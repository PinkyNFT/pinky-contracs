// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// ██████╗ ██╗███╗   ██╗██╗  ██╗██╗   ██╗
// ██╔══██╗██║████╗  ██║██║ ██╔╝╚██╗ ██╔╝
// ██████╔╝██║██╔██╗ ██║█████╔╝  ╚████╔╝
// ██╔═══╝ ██║██║╚██╗██║██╔═██╗   ╚██╔╝
// ██║     ██║██║ ╚████║██║  ██╗   ██║
// ╚═╝     ╚═╝╚═╝  ╚═══╝╚═╝  ╚═╝   ╚═╝
import "./DirectListingsStorage.sol";

import {IDirectListings} from "../interfaces/IMarketPlace.sol";
import {IPlatformFee} from "../interfaces/IPlatformFee.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {CurrencyTransferLib} from "../lib/CurrencyTransferLib.sol";

contract DirectListingsLogic is
    IDirectListings,
    ReentrancyGuard,
    AccessControl
{
    /// @dev Only lister role holders can create listings, when listings are restricted by lister address.
    bytes32 private constant LISTER_ROLE = keccak256("LISTER_ROLE");
    /// @dev Only assets from NFT contracts with asset role can be listed, when listings are restricted by asset address.
    bytes32 private constant ASSET_ROLE = keccak256("ASSET_ROLE");

    /// @dev The max bps of the contract. So, 10_000 == 100 %
    uint64 private constant MAX_BPS = 10_000;

    /// @dev The address of the native token wrapper contract.
    address private immutable nativeTokenWrapper;

    /// @dev Checks whether the caller has LISTER_ROLE.
    modifier onlyListerRole() {
        require(
            hasRole(LISTER_ROLE, address(0)) ||
                hasRole(LISTER_ROLE, _msgSender()),
            "!LISTER_ROLE"
        );
        _;
    }

    /// @dev Checks whether the caller has ASSET_ROLE.
    modifier onlyAssetRole(address _asset) {
        require(
            hasRole(LISTER_ROLE, address(0)) || hasRole(ASSET_ROLE, _asset),
            "!ASSET_ROLE"
        );
        _;
    }

    /// @dev Checks whether caller is a listing creator.
    modifier onlyListingCreator(uint256 _listingId) {
        require(
            _directListingsStorage().listings[_listingId].listingCreator ==
                _msgSender(),
            "Marketplace: not listing creator."
        );
        _;
    }

    /// @dev Checks whether a listing exists.
    modifier onlyExistingListing(uint256 _listingId) {
        require(
            _directListingsStorage().listings[_listingId].status ==
                IDirectListings.Status.CREATED,
            "Marketplace: invalid listing."
        );
        _;
    }

    constructor(address _nativeTokenWrapper) {
        nativeTokenWrapper = _nativeTokenWrapper;
    }

    function createListing(
        ListingParameters memory _params,
        address listerAddress
    )
        external
        onlyListerRole
        onlyAssetRole(_params.assetContract)
        returns (uint256 listingId)
    {
        listingId = _getNextListingId();
        address listingCreator = listerAddress == address(0)
            ? _msgSender()
            : listerAddress;
        TokenType tokenType = _getTokenType(_params.assetContract);

        uint128 startTime = _params.startTimestamp;
        uint128 endTime = _params.endTimestamp;
        require(
            startTime < endTime,
            "Marketplace: endTimestamp not greater than startTimestamp."
        );
        if (startTime < block.timestamp) {
            require(
                startTime + 60 minutes >= block.timestamp,
                "Marketplace: invalid startTimestamp."
            );

            startTime = uint128(block.timestamp);
            endTime = endTime == type(uint128).max
                ? endTime
                : startTime + (_params.endTimestamp - _params.startTimestamp);
        }
        _validateNewListing(_params, tokenType);
        Listing memory listing = Listing({
            listingId: listingId,
            listingCreator: listingCreator,
            assetContract: _params.assetContract,
            tokenId: _params.tokenId,
            quantity: _params.quantity,
            currency: _params.currency,
            pricePerToken: _params.pricePerToken,
            startTimestamp: startTime,
            endTimestamp: endTime,
            reserved: _params.reserved,
            tokenType: tokenType,
            status: IDirectListings.Status.CREATED
        });
        _directListingsStorage().listings[listingId] = listing;

        emit NewListing(
            listingCreator,
            listingId,
            _params.assetContract,
            listing
        );
    }

    function updateListing(
        uint256 _listingId,
        ListingParameters memory _params
    )
        external
        onlyExistingListing(_listingId)
        onlyAssetRole(_params.assetContract)
        onlyListingCreator(_listingId)
    {
        address listingCreator = _msgSender();
        Listing memory listing = _directListingsStorage().listings[_listingId];
        TokenType tokenType = _getTokenType(_params.assetContract);

        require(
            listing.endTimestamp > block.timestamp,
            "Marketplace: listing expired."
        );

        require(
            listing.assetContract == _params.assetContract &&
                listing.tokenId == _params.tokenId,
            "Marketplace: cannot update what token is listed."
        );

        uint128 startTime = _params.startTimestamp;
        uint128 endTime = _params.endTimestamp;
        require(
            startTime < endTime,
            "Marketplace: endTimestamp not greater than startTimestamp."
        );
        require(
            listing.startTimestamp > block.timestamp ||
                (startTime == listing.startTimestamp &&
                    endTime > block.timestamp),
            "Marketplace: listing already active."
        );

        if (
            startTime != listing.startTimestamp && startTime < block.timestamp
        ) {
            require(
                startTime + 60 minutes >= block.timestamp,
                "Marketplace: invalid startTimestamp."
            );

            startTime = uint128(block.timestamp);

            endTime = endTime == listing.endTimestamp ||
                endTime == type(uint128).max
                ? endTime
                : startTime + (_params.endTimestamp - _params.startTimestamp);
        }

        {
            uint256 _approvedCurrencyPrice = _directListingsStorage()
                .currencyPriceForListing[_listingId][_params.currency];
            require(
                _approvedCurrencyPrice == 0 ||
                    _params.pricePerToken == _approvedCurrencyPrice,
                "Marketplace: price different from approved price"
            );
        }

        _validateNewListing(_params, tokenType);

        listing = Listing({
            listingId: _listingId,
            listingCreator: listingCreator,
            assetContract: _params.assetContract,
            tokenId: _params.tokenId,
            quantity: _params.quantity,
            currency: _params.currency,
            pricePerToken: _params.pricePerToken,
            startTimestamp: startTime,
            endTimestamp: endTime,
            reserved: _params.reserved,
            tokenType: tokenType,
            status: IDirectListings.Status.CREATED
        });

        _directListingsStorage().listings[_listingId] = listing;

        emit UpdatedListing(
            listingCreator,
            _listingId,
            _params.assetContract,
            listing
        );
    }

    function cancelListing(
        uint256 _listingId
    )
        external
        override
        onlyExistingListing(_listingId)
        onlyListingCreator(_listingId)
    {
        _directListingsStorage().listings[_listingId].status = IDirectListings
            .Status
            .CANCELLED;
        emit CancelledListing(_msgSender(), _listingId);
    }

    function approveBuyerForListing(
        uint256 _listingId,
        address _buyer,
        bool _toApprove
    ) external onlyExistingListing(_listingId) onlyListingCreator(_listingId) {
        require(
            _directListingsStorage().listings[_listingId].reserved,
            "Marketplace: listing not reserved."
        );

        _directListingsStorage().isBuyerApprovedForListing[_listingId][
                _buyer
            ] = _toApprove;

        emit BuyerApprovedForListing(_listingId, _buyer, _toApprove);
    }

    function approveCurrencyForListing(
        uint256 _listingId,
        address _currency,
        uint256 _pricePerTokenInCurrency
    ) external onlyExistingListing(_listingId) onlyListingCreator(_listingId) {
        Listing memory listing = _directListingsStorage().listings[_listingId];
        require(
            _currency != listing.currency ||
                _pricePerTokenInCurrency == listing.pricePerToken,
            "Marketplace: approving listing currency with different price."
        );
        require(
            _directListingsStorage().currencyPriceForListing[_listingId][
                _currency
            ] != _pricePerTokenInCurrency,
            "Marketplace: price unchanged."
        );

        _directListingsStorage().currencyPriceForListing[_listingId][
                _currency
            ] = _pricePerTokenInCurrency;

        emit CurrencyApprovedForListing(
            _listingId,
            _currency,
            _pricePerTokenInCurrency
        );
    }

    function buyFromListing(
        uint256 _listingId,
        address _buyFor,
        uint256 _quantity,
        address _currency,
        uint256 _expectedTotalPrice
    ) external payable nonReentrant onlyExistingListing(_listingId) {
        Listing memory listing = _directListingsStorage().listings[_listingId];
        address buyer = _msgSender();

        require(
            !listing.reserved ||
                _directListingsStorage().isBuyerApprovedForListing[_listingId][
                    buyer
                ],
            "buyer not approved"
        );
        require(
            _quantity > 0 && _quantity <= listing.quantity,
            "Buying invalid quantity"
        );
        require(
            block.timestamp < listing.endTimestamp &&
                block.timestamp >= listing.startTimestamp,
            "not within sale window."
        );

        require(
            _validateOwnershipAndApproval(
                listing.listingCreator,
                listing.assetContract,
                listing.tokenId,
                _quantity,
                listing.tokenType
            ),
            "Marketplace: not owner or approved tokens."
        );

        uint256 targetTotalPrice;

        if (
            _directListingsStorage().currencyPriceForListing[_listingId][
                _currency
            ] > 0
        ) {
            targetTotalPrice =
                _quantity *
                _directListingsStorage().currencyPriceForListing[_listingId][
                    _currency
                ];
        } else {
            require(
                _currency == listing.currency,
                "Paying in invalid currency."
            );
            targetTotalPrice = _quantity * listing.pricePerToken;
        }

        require(
            targetTotalPrice == _expectedTotalPrice,
            "Unexpected total price"
        );

        // Check: buyer owns and has approved sufficient currency for sale.
        if (_currency == CurrencyTransferLib.NATIVE_TOKEN) {
            require(
                msg.value == targetTotalPrice,
                "Marketplace: msg.value must exactly be the total price."
            );
        } else {
            require(msg.value == 0, "Marketplace: invalid native tokens sent.");
            _validateERC20BalAndAllowance(buyer, _currency, targetTotalPrice);
        }

        if (listing.quantity == _quantity) {
            _directListingsStorage()
                .listings[_listingId]
                .status = IDirectListings.Status.COMPLETED;
        }
        _directListingsStorage().listings[_listingId].quantity -= _quantity;

        _payout(buyer, listing.listingCreator, _currency, targetTotalPrice);
        _transferListingTokens(
            listing.listingCreator,
            _buyFor,
            _quantity,
            listing
        );

        emit NewSale(
            listing.listingCreator,
            listing.listingId,
            listing.assetContract,
            listing.tokenId,
            buyer,
            _quantity,
            targetTotalPrice
        );
    }

    function totalListings() external view returns (uint256) {
        return _directListingsStorage().totalListings;
    }

    function getAllListings(
        uint256 _startId,
        uint256 _endId
    ) external view returns (Listing[] memory _allListings) {
        require(
            _startId <= _endId &&
                _endId < _directListingsStorage().totalListings,
            "invalid range"
        );

        _allListings = new Listing[](_endId - _startId + 1);

        for (uint256 i = _startId; i <= _endId; i += 1) {
            _allListings[i - _startId] = _directListingsStorage().listings[i];
        }
    }

    function getAllValidListings(
        uint256 _startId,
        uint256 _endId
    ) external view returns (Listing[] memory _validListings) {
        require(
            _startId <= _endId &&
                _endId < _directListingsStorage().totalListings,
            "invalid range"
        );

        Listing[] memory _listings = new Listing[](_endId - _startId + 1);
        uint256 _listingCount;

        for (uint256 i = _startId; i <= _endId; i += 1) {
            _listings[i - _startId] = _directListingsStorage().listings[i];
            if (_validateExistingListing(_listings[i - _startId])) {
                _listingCount += 1;
            }
        }

        _validListings = new Listing[](_listingCount);
        uint256 index = 0;
        uint256 count = _listings.length;
        for (uint256 i = 0; i < count; i += 1) {
            if (_validateExistingListing(_listings[i])) {
                _validListings[index++] = _listings[i];
            }
        }
    }

    function getListing(
        uint256 _listingId
    ) external view override returns (Listing memory listing) {
        listing = _directListingsStorage().listings[_listingId];
    }

    /*///////////////////////////////////////////////////////////////
                            Internal functions
    //////////////////////////////////////////////////////////////*/

    /// @dev Returns the next listing Id.
    function _getNextListingId() internal returns (uint256 id) {
        id = _directListingsStorage().totalListings;
        _directListingsStorage().totalListings += 1;
    }

    /// @dev Returns the interface supported by a contract.
    function _getTokenType(
        address _assetContract
    ) internal view returns (TokenType tokenType) {
        if (
            IERC165(_assetContract).supportsInterface(
                type(IERC1155).interfaceId
            )
        ) {
            tokenType = TokenType.ERC1155;
        } else if (
            IERC165(_assetContract).supportsInterface(type(IERC721).interfaceId)
        ) {
            tokenType = TokenType.ERC721;
        } else {
            revert("Marketplace: listed token must be ERC1155 or ERC721.");
        }
    }

    /// @dev Checks whether the listing creator owns and has approved marketplace to transfer listed tokens.
    function _validateNewListing(
        ListingParameters memory _params,
        TokenType _tokenType
    ) internal view {
        require(_params.quantity > 0, "Marketplace: listing zero quantity.");
        require(
            _params.quantity == 1 || _tokenType == TokenType.ERC1155,
            "Marketplace: listing invalid quantity."
        );

        require(
            _validateOwnershipAndApproval(
                _msgSender(),
                _params.assetContract,
                _params.tokenId,
                _params.quantity,
                _tokenType
            ),
            "Marketplace: not owner or approved tokens."
        );
    }

    /// @dev Checks whether the listing exists, is active, and if the lister has sufficient balance.
    function _validateExistingListing(
        Listing memory _targetListing
    ) internal view returns (bool isValid) {
        isValid =
            _targetListing.startTimestamp <= block.timestamp &&
            _targetListing.endTimestamp > block.timestamp &&
            _targetListing.status == IDirectListings.Status.CREATED &&
            _validateOwnershipAndApproval(
                _targetListing.listingCreator,
                _targetListing.assetContract,
                _targetListing.tokenId,
                _targetListing.quantity,
                _targetListing.tokenType
            );
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
                IERC1155(_assetContract).balanceOf(_tokenOwner, _tokenId) >=
                _quantity &&
                IERC1155(_assetContract).isApprovedForAll(_tokenOwner, market);
        } else if (_tokenType == TokenType.ERC721) {
            address owner;
            address operator;

            // failsafe for reverts in case of non-existent tokens
            try IERC721(_assetContract).ownerOf(_tokenId) returns (
                address _owner
            ) {
                owner = _owner;

                // Nesting the approval check inside this try block, to run only if owner check doesn't revert.
                // If the previous check for owner fails, then the return value will always evaluate to false.
                try IERC721(_assetContract).getApproved(_tokenId) returns (
                    address _operator
                ) {
                    operator = _operator;
                } catch {}
            } catch {}

            isValid =
                owner == _tokenOwner &&
                (operator == market ||
                    IERC721(_assetContract).isApprovedForAll(
                        _tokenOwner,
                        market
                    ));
        }
    }

    /// @dev Validates that `_tokenOwner` owns and has approved Markeplace to transfer the appropriate amount of currency
    function _validateERC20BalAndAllowance(
        address _tokenOwner,
        address _currency,
        uint256 _amount
    ) internal view {
        require(
            IERC20(_currency).balanceOf(_tokenOwner) >= _amount &&
                IERC20(_currency).allowance(_tokenOwner, address(this)) >=
                _amount,
            "!BAL20"
        );
    }

    /// @dev Transfers tokens listed for sale in a direct or auction listing.
    function _transferListingTokens(
        address _from,
        address _to,
        uint256 _quantity,
        Listing memory _listing
    ) internal {
        if (_listing.tokenType == TokenType.ERC1155) {
            IERC1155(_listing.assetContract).safeTransferFrom(
                _from,
                _to,
                _listing.tokenId,
                _quantity,
                ""
            );
        } else if (_listing.tokenType == TokenType.ERC721) {
            IERC721(_listing.assetContract).safeTransferFrom(
                _from,
                _to,
                _listing.tokenId,
                ""
            );
        }
    }

    /// @dev Pays out stakeholders in a sale.
    function _payout(
        address _payer,
        address _payee,
        address _currencyToUse,
        uint256 _totalPayoutAmount
    ) internal {
        address _nativeTokenWrapper = nativeTokenWrapper;
        uint256 amountRemaining;

        // Payout platform fee
        {
            (
                address platformFeeRecipient,
                uint16 platformFeeBps
            ) = IPlatformFee(address(this)).getPlatformFeeInfo();
            uint256 platformFeeCut = (_totalPayoutAmount * platformFeeBps) /
                MAX_BPS;

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

    /// @dev Returns the DirectListings storage.
    function _directListingsStorage()
        internal
        pure
        returns (DirectListingsStorage.Data storage data)
    {
        data = DirectListingsStorage.data();
    }
}
