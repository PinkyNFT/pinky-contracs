// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { IERC165 } from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import { Status, TokenType } from "./interfaces/IMarketPlace.sol";
import { IERC1155 } from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import { CurrencyTransferLib } from "./lib/CurrencyTransferLib.sol";
import { PlatformFee } from "./PlatformFee.sol";
import { ERC721Holder, IERC721Receiver } from "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import { ERC1155Holder, IERC1155Receiver } from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";

/*receives token and sends token */
contract PinkyMarketplaceProxy is PlatformFee, ReentrancyGuard, AccessControl, ERC721Holder, ERC1155Holder {
    bytes32 constant MARKET_PLACE_ROLE = keccak256("MARKET_PLACE_ROLE");
    address immutable nativeTokenWrapper;
    /// @dev The max bps of the contract. So, 10_000 == 100 %
    uint64 constant MAX_BPS = 10_000;

    constructor(address _nativeTokenWrapper, address _defaultAdmin) {
        _grantRole(DEFAULT_ADMIN_ROLE, _defaultAdmin);
        nativeTokenWrapper = _nativeTokenWrapper;
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

    function addMarketplaceContract(address _marketplaceContract) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _grantRole(MARKET_PLACE_ROLE, _marketplaceContract);
    }

    function removeMarketplaceContract(address _marketplaceContract) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _revokeRole(MARKET_PLACE_ROLE, _marketplaceContract);
    }

    /// @dev Transfers tokens for auction.
    function transferTokens(
        address _from,
        address _to,
        TokenType tokenType,
        address assetContract,
        uint256 tokenId,
        uint256 quantity
    ) external nonReentrant onlyRole(MARKET_PLACE_ROLE) {
        if (tokenType == TokenType.ERC1155) {
            IERC1155(assetContract).safeTransferFrom(_from, _to, tokenId, quantity, "");
        } else if (tokenType == TokenType.ERC721) {
            IERC721(assetContract).safeTransferFrom(_from, _to, tokenId, "");
        }
    }

    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual override(AccessControl, ERC1155Holder) returns (bool) {
        return
            interfaceId == type(IERC1155Receiver).interfaceId ||
            interfaceId == type(IERC721Receiver).interfaceId ||
            super.supportsInterface(interfaceId);
    }

    function receiveCurrencyWithWrapper(
        address _currency,
        address _from,
        uint256 _amount
    ) external nonReentrant onlyRole(MARKET_PLACE_ROLE) {
        CurrencyTransferLib.transferCurrencyWithWrapper(_currency, _from, address(this), _amount, nativeTokenWrapper);
    }

    function sendCurrencyWithWrapper(
        address _currency,
        address _to,
        uint256 _amount
    ) external nonReentrant onlyRole(MARKET_PLACE_ROLE) {
        CurrencyTransferLib.transferCurrencyWithWrapper(_currency, address(this), _to, _amount, nativeTokenWrapper);
    }

    /// @dev Pays out stakeholders in auction.
    function payout(
        address _payer,
        address _payee,
        address _currencyToUse,
        uint256 _totalPayoutAmount
    ) external nonReentrant onlyRole(MARKET_PLACE_ROLE) {
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
                nativeTokenWrapper
            );

            amountRemaining = _totalPayoutAmount - platformFeeCut;
        }

        // Distribute price to token owner
        CurrencyTransferLib.transferCurrencyWithWrapper(
            _currencyToUse,
            _payer,
            _payee,
            amountRemaining,
            nativeTokenWrapper
        );
    }

    /// @dev Checks whether platform fee info can be set in the given execution context.
    function _canSetPlatformFeeInfo() internal view override returns (bool) {
        return hasRole(DEFAULT_ADMIN_ROLE, _msgSender());
    }
}
