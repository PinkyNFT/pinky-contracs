// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { IERC165 } from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import { Status, TokenType } from "./interfaces/IMarketPlace.sol";
import { IERC1155 } from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "./DirectListingsStorage.sol";
import "./EnglishAuctionStorage.sol";
import { PinkyMarketplaceProxy } from "./PinkyMarketplaceProxy.sol";

import { PlatformFee } from "./PlatformFee.sol";
import { CurrencyTransferLib } from "./lib/CurrencyTransferLib.sol";

abstract contract BaseMarketplace is PlatformFee, ReentrancyGuard, AccessControl {
    /// @dev Only lister role holders can create listings, when listings are restricted by lister address.
    bytes32 constant LISTER_ROLE = keccak256("LISTER_ROLE");
    /// @dev Only assets from NFT contracts with asset role can be listed, when listings are restricted by asset address.
    bytes32 constant ASSET_ROLE = keccak256("ASSET_ROLE");

    /// @dev The max bps of the contract. So, 10_000 == 100 %
    uint64 constant MAX_BPS = 10_000;

    /// @dev The address of the native token wrapper contract.
    address immutable nativeTokenWrapper;
    PinkyMarketplaceProxy pinkyMarketplaceProxy;

    /// @dev Checks whether the caller has LISTER_ROLE.
    modifier onlyListerRole() {
        require(hasRole(LISTER_ROLE, address(0)) || hasRole(LISTER_ROLE, _msgSender()), "!LISTER_ROLE");
        _;
    }

    /// @dev Checks whether the caller has ASSET_ROLE.
    modifier onlyAssetRole(address _asset) {
        require(hasRole(LISTER_ROLE, address(0)) || hasRole(ASSET_ROLE, _asset), "!ASSET_ROLE");
        _;
    }

    /// @dev Checks whether caller is a listing creator.
    modifier onlyListingCreator(uint256 _listingId) {
        require(
            _directListingsStorage().listings[_listingId].listingCreator == _msgSender(),
            "Marketplace: not listing creator."
        );
        _;
    }

    /// @dev Checks whether a listing exists.
    modifier onlyExistingListing(uint256 _listingId) {
        require(
            _directListingsStorage().listings[_listingId].status == Status.CREATED,
            "Marketplace: invalid listing."
        );
        _;
    }
    /// @dev Checks whether caller is a auction creator.
    modifier onlyAuctionCreator(uint256 _auctionId) {
        require(
            _englishAuctionsStorage().auctions[_auctionId].auctionCreator == _msgSender(),
            "Marketplace: not auction creator."
        );
        _;
    }

    /// @dev Checks whether an auction exists.
    modifier onlyExistingAuction(uint256 _auctionId) {
        require(
            _englishAuctionsStorage().auctions[_auctionId].status == Status.CREATED,
            "Marketplace: invalid auction."
        );
        _;
    }

    constructor(address _nativeTokenWrapper, address _pinkyMarketplaceProxyAddress) {
        nativeTokenWrapper = _nativeTokenWrapper;
        pinkyMarketplaceProxy = PinkyMarketplaceProxy(_pinkyMarketplaceProxyAddress);
    }

    /// @dev Returns the DirectListings storage.
    function _directListingsStorage() internal pure returns (DirectListingsStorage.Data storage data) {
        data = DirectListingsStorage.data();
    }

    /// @dev Returns the EnglishAuctions storage.
    function _englishAuctionsStorage() internal pure returns (EnglishAuctionsStorage.Data storage data) {
        data = EnglishAuctionsStorage.data();
    }

    /// @dev Checks whether platform fee info can be set in the given execution context.
    function _canSetPlatformFeeInfo() internal view override returns (bool) {
        return hasRole(DEFAULT_ADMIN_ROLE, _msgSender());
    }

    /// @dev Returns the interface supported by a contract.
    function _getTokenType(address _assetContract) internal view returns (TokenType tokenType) {
        if (IERC165(_assetContract).supportsInterface(type(IERC1155).interfaceId)) {
            tokenType = TokenType.ERC1155;
        } else if (IERC165(_assetContract).supportsInterface(type(IERC721).interfaceId)) {
            tokenType = TokenType.ERC721;
        } else {
            revert("Marketplace: auctioned token must be ERC1155 or ERC721.");
        }
    }

    /// @dev Pays out stakeholders in auction.
    function _payout(address _payer, address _payee, address _currencyToUse, uint256 _totalPayoutAmount) internal {
        address _nativeTokenWrapper = nativeTokenWrapper;
        uint256 amountRemaining;
        // Payout platform fee
        {
            (address platformFeeRecipient, uint16 platformFeeBps) = getPlatformFeeInfo();
            uint256 platformFeeCut = (_totalPayoutAmount * platformFeeBps) / MAX_BPS;

            // Transfer platform fee
            CurrencyTransferLib.transferCurrencyWithWrapper(
                _currencyToUse,
                _payer,
                platformFeeRecipient,
                platformFeeCut,
                _nativeTokenWrapper
            );

            amountRemaining = _totalPayoutAmount - platformFeeCut;
        }

        // Distribute price to token owner
        CurrencyTransferLib.transferCurrencyWithWrapper(
            _currencyToUse,
            _payer,
            _payee,
            amountRemaining,
            _nativeTokenWrapper
        );
    }

    /// @dev Transfers tokens for auction.
    function _transferTokens(
        address _from,
        address _to,
        TokenType tokenType,
        address assetContract,
        uint256 tokenId,
        uint256 quantity
    ) internal {
        if (tokenType == TokenType.ERC1155) {
            IERC1155(assetContract).safeTransferFrom(_from, _to, tokenId, quantity, "");
        } else if (tokenType == TokenType.ERC721) {
            IERC721(assetContract).safeTransferFrom(_from, _to, tokenId, "");
        }
    }

    /// @dev Validates that `_tokenOwner` owns and has approved Marketplace to transfer NFTs.
    function _validateOwnershipAndApproval(
        address _tokenOwner,
        address _assetContract,
        uint256 _tokenId,
        uint256 _quantity,
        TokenType _tokenType
    ) internal view returns (bool isValid) {
        address market = address(this);

        if (_tokenType == TokenType.ERC1155) {
            isValid =
                IERC1155(_assetContract).balanceOf(_tokenOwner, _tokenId) >= _quantity &&
                IERC1155(_assetContract).isApprovedForAll(_tokenOwner, market);
        } else if (_tokenType == TokenType.ERC721) {
            address owner;
            address operator;

            // failsafe for reverts in case of non-existent tokens
            try IERC721(_assetContract).ownerOf(_tokenId) returns (address _owner) {
                owner = _owner;

                // Nesting the approval check inside this try block, to run only if owner check doesn't revert.
                // If the previous check for owner fails, then the return value will always evaluate to false.
                try IERC721(_assetContract).getApproved(_tokenId) returns (address _operator) {
                    operator = _operator;
                } catch {}
            } catch {}

            isValid =
                owner == _tokenOwner &&
                (operator == market || IERC721(_assetContract).isApprovedForAll(_tokenOwner, market));
        }
    }

    /// @dev Validates that `_tokenOwner` owns and has approved Markeplace to transfer the appropriate amount of currency
    function _validateERC20BalAndAllowance(address _tokenOwner, address _currency, uint256 _amount) internal view {
        require(
            IERC20(_currency).balanceOf(_tokenOwner) >= _amount &&
                IERC20(_currency).allowance(_tokenOwner, address(this)) >= _amount,
            "!BAL20"
        );
    }
}
