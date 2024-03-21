// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import { IERC1155 } from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import { IERC165 } from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import { CurrencyTransferLib } from "./lib/CurrencyTransferLib.sol";
import "./DirectListingsStorage.sol";
import "./interfaces/IMarketPlace.sol";
import "./BaseMarketplace.sol";

contract DirectListing is BaseMarketplace, IDirectListings {
    /// @dev Checks whether caller is a listing creator.
    modifier onlyListingCreator(uint256 _listingId) {
        require(
            _directListingsStorage().listings[_listingId].listingCreator == msg.sender,
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

    constructor(address _pinkyMarketplaceProxyAddress) BaseMarketplace(_pinkyMarketplaceProxyAddress) {}

    /*///////////////////////////////////////////////////////////////
                External functions of Direct Listings
    //////////////////////////////////////////////////////////////*/

    function createListing(ListingParameters memory _params) external returns (uint256 listingId) {
        listingId = _getNextListingId();
        address listingCreator = _msgSender();
        TokenType tokenType = _getTokenType(_params.assetContract);

        uint128 startTime = _params.startTimestamp;
        uint128 endTime = _params.endTimestamp;
        require(startTime < endTime, "Marketplace: endTimestamp not greater than startTimestamp.");
        if (startTime < block.timestamp) {
            require(startTime + 60 minutes >= block.timestamp, "Marketplace: invalid startTimestamp.");

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
            status: Status.CREATED
        });
        _directListingsStorage().listings[listingId] = listing;

        emit NewListing(listingCreator, listingId, _params.assetContract, listing);
    }

    function updateListing(uint256 _listingId, ListingParameters memory _params) external onlyExistingListing(_listingId) onlyListingCreator(_listingId) {
        address listingCreator = _msgSender();
        Listing memory listing = _directListingsStorage().listings[_listingId];
        TokenType tokenType = _getTokenType(_params.assetContract);

        require(listing.endTimestamp > block.timestamp, "Marketplace: listing expired.");

        require(
            listing.assetContract == _params.assetContract && listing.tokenId == _params.tokenId,
            "Marketplace: cannot update what token is listed."
        );

        uint128 startTime = _params.startTimestamp;
        uint128 endTime = _params.endTimestamp;
        require(startTime < endTime, "Marketplace: endTimestamp not greater than startTimestamp.");
        require(
            listing.startTimestamp > block.timestamp ||
                (startTime == listing.startTimestamp && endTime > block.timestamp),
            "Marketplace: listing already active."
        );

        if (startTime != listing.startTimestamp && startTime < block.timestamp) {
            require(startTime + 60 minutes >= block.timestamp, "Marketplace: invalid startTimestamp.");

            startTime = uint128(block.timestamp);

            endTime = endTime == listing.endTimestamp || endTime == type(uint128).max
                ? endTime
                : startTime + (_params.endTimestamp - _params.startTimestamp);
        }

        {
            uint256 _approvedCurrencyPrice = _directListingsStorage().currencyPriceForListing[_listingId][
                _params.currency
            ];
            require(
                _approvedCurrencyPrice == 0 || _params.pricePerToken == _approvedCurrencyPrice,
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
            status: Status.CREATED
        });

        _directListingsStorage().listings[_listingId] = listing;

        emit UpdatedListing(listingCreator, _listingId, _params.assetContract, listing);
    }

    function cancelListing(uint256 _listingId) external override onlyExistingListing(_listingId) onlyListingCreator(_listingId) {
        _directListingsStorage().listings[_listingId].status = Status.CANCELLED;
        emit CancelledListing(_msgSender(), _listingId);
    }

    function approveBuyerForListing(
        uint256 _listingId,
        address _buyer,
        bool _toApprove
    ) external onlyExistingListing(_listingId) onlyListingCreator(_listingId) {
        require(_directListingsStorage().listings[_listingId].reserved, "Marketplace: listing not reserved.");

        _directListingsStorage().isBuyerApprovedForListing[_listingId][_buyer] = _toApprove;

        emit BuyerApprovedForListing(_listingId, _buyer, _toApprove);
    }

    function approveCurrencyForListing(
        uint256 _listingId,
        address _currency,
        uint256 _pricePerTokenInCurrency
    ) external onlyExistingListing(_listingId) onlyListingCreator(_listingId) {
        Listing memory listing = _directListingsStorage().listings[_listingId];
        require(
            _currency != listing.currency || _pricePerTokenInCurrency == listing.pricePerToken,
            "Marketplace: approving listing currency with different price."
        );
        require(
            _directListingsStorage().currencyPriceForListing[_listingId][_currency] != _pricePerTokenInCurrency,
            "Marketplace: price unchanged."
        );

        _directListingsStorage().currencyPriceForListing[_listingId][_currency] = _pricePerTokenInCurrency;

        emit CurrencyApprovedForListing(_listingId, _currency, _pricePerTokenInCurrency);
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
            !listing.reserved || _directListingsStorage().isBuyerApprovedForListing[_listingId][buyer],
            "buyer not approved"
        );
        require(_quantity > 0 && _quantity <= listing.quantity, "Buying invalid quantity");
        require(
            block.timestamp < listing.endTimestamp && block.timestamp >= listing.startTimestamp,
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

        if (_directListingsStorage().currencyPriceForListing[_listingId][_currency] > 0) {
            targetTotalPrice = _quantity * _directListingsStorage().currencyPriceForListing[_listingId][_currency];
        } else {
            require(_currency == listing.currency, "Paying in invalid currency.");
            targetTotalPrice = _quantity * listing.pricePerToken;
        }

        require(targetTotalPrice == _expectedTotalPrice, "Unexpected total price");

        // Check: buyer owns and has approved sufficient currency for sale.
        if (_currency == CurrencyTransferLib.NATIVE_TOKEN) {
            require(msg.value == targetTotalPrice, "Marketplace: msg.value must exactly be the total price.");
        } else {
            require(msg.value == 0, "Marketplace: invalid native tokens sent.");
            _validateERC20BalAndAllowance(buyer, _currency, targetTotalPrice);
        }

        if (listing.quantity == _quantity) {
            _directListingsStorage().listings[_listingId].status = Status.COMPLETED;
        }
        _directListingsStorage().listings[_listingId].quantity -= _quantity;

        pinkyMarketplaceProxy.payout(buyer, listing.listingCreator, _currency, targetTotalPrice);
        pinkyMarketplaceProxy.transferTokens(
            listing.listingCreator,
            _buyFor,
            listing.tokenType,
            listing.assetContract,
            listing.tokenId,
            _quantity
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

    /*///////////////////////////////////////////////////////////////
                View functions of Direct Listings
    //////////////////////////////////////////////////////////////*/

    /**
     *  @notice Returns the total number of listings created.
     *  @dev At any point, the return value is the ID of the next listing created.
     */
    function totalListings() external view returns (uint256) {
        return _directListingsStorage().totalListings;
    }

    /// @notice Returns whether a buyer is approved for a listing.
    function isBuyerApprovedForListing(uint256 _listingId, address _buyer) external view returns (bool) {
        return _directListingsStorage().isBuyerApprovedForListing[_listingId][_buyer];
    }

    /// @notice Returns whether a currency is approved for a listing.
    function isCurrencyApprovedForListing(uint256 _listingId, address _currency) external view returns (bool) {
        return _directListingsStorage().currencyPriceForListing[_listingId][_currency] > 0;
    }

    /// @notice Returns the price per token for a listing, in the given currency.
    function currencyPriceForListing(uint256 _listingId, address _currency) external view returns (uint256) {
        if (_directListingsStorage().currencyPriceForListing[_listingId][_currency] == 0) {
            revert("Currency not approved for listing");
        }

        return _directListingsStorage().currencyPriceForListing[_listingId][_currency];
    }

    function getAllListings(uint256 _startId, uint256 _endId) external view returns (Listing[] memory _allListings) {
        require(_startId <= _endId && _endId < _directListingsStorage().totalListings, "invalid range");

        _allListings = new Listing[](_endId - _startId + 1);

        for (uint256 i = _startId; i <= _endId; i += 1) {
            _allListings[i - _startId] = _directListingsStorage().listings[i];
        }
    }

    function getAllValidListings(
        uint256 _startId,
        uint256 _endId
    ) external view returns (Listing[] memory _validListings) {
        require(_startId <= _endId && _endId < _directListingsStorage().totalListings, "invalid range");

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

    function getAllListingOfNFT(
        address nftAddress,
        uint256 tokenId
    ) external view returns (Listing[] memory _validListings) {
        
        uint256 _endId = _directListingsStorage().totalListings;

        uint256 _listingCount;
        Listing memory _listingNow;
        
        for (uint256 i = 0; i <= _endId; i += 1) {
            _listingNow =  _directListingsStorage().listings[i];
            if (_listingNow.assetContract == nftAddress && _listingNow.tokenId == tokenId) {
                _listingCount += 1;
            }
        }

        _validListings = new Listing[](_listingCount);
        uint256 index = 0;
        for (uint256 i = 0; i < _endId; i += 1) {
            _listingNow =  _directListingsStorage().listings[i];
            if (_listingNow.assetContract == nftAddress && _listingNow.tokenId == tokenId) {
                 _validListings[index++] = _listingNow;
            }
        }
    }
    function getListing(uint256 _listingId) external view override returns (Listing memory listing) {
        listing = _directListingsStorage().listings[_listingId];
    }

    /*///////////////////////////////////////////////////////////////
                Internal functions of Direct Listings
    //////////////////////////////////////////////////////////////*/

    function _getNextListingId() internal returns (uint256 id) {
        id = _directListingsStorage().totalListings;
        _directListingsStorage().totalListings += 1;
    }

    /// @dev Checks whether the listing creator owns and has approved marketplace to transfer listed tokens.
    function _validateNewListing(ListingParameters memory _params, TokenType _tokenType) internal view {
        require(_params.quantity > 0, "Marketplace: listing zero quantity.");
        require(_params.quantity == 1 || _tokenType == TokenType.ERC1155, "Marketplace: listing invalid quantity.");

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
    function _validateExistingListing(Listing memory _targetListing) internal view returns (bool isValid) {
        isValid =
            _targetListing.startTimestamp <= block.timestamp &&
            _targetListing.endTimestamp > block.timestamp &&
            _targetListing.status == Status.CREATED &&
            _validateOwnershipAndApproval(
                _targetListing.listingCreator,
                _targetListing.assetContract,
                _targetListing.tokenId,
                _targetListing.quantity,
                _targetListing.tokenType
            );
    }

    /// @dev Returns the DirectListings storage.
    function _directListingsStorage() internal pure returns (DirectListingsStorage.Data storage data) {
        data = DirectListingsStorage.data();
    }
}
