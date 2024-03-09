// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// ██████╗ ██╗███╗   ██╗██╗  ██╗██╗   ██╗
// ██╔══██╗██║████╗  ██║██║ ██╔╝╚██╗ ██╔╝
// ██████╔╝██║██╔██╗ ██║█████╔╝  ╚████╔╝
// ██╔═══╝ ██║██║╚██╗██║██╔═██╗   ╚██╔╝
// ██║     ██║██║ ╚████║██║  ██╗   ██║
// ╚═╝     ╚═╝╚═╝  ╚═══╝╚═╝  ╚═╝   ╚═╝

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {CurrencyTransferLib} from "./lib/CurrencyTransferLib.sol";

import "./interfaces/IMarketPlace.sol";
import "./DirectListingsStorage.sol";
import "./EnglishAuctionStorage.sol";
import "./PlatformFee.sol";

contract PinkyMarketplace is
    IDirectListings,
    IEnglishAuctions,
    PlatformFee,
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
                Status.CREATED,
            "Marketplace: invalid listing."
        );
        _;
    }
    /// @dev Checks whether caller is a auction creator.
    modifier onlyAuctionCreator(uint256 _auctionId) {
        require(
            _englishAuctionsStorage().auctions[_auctionId].auctionCreator ==
                _msgSender(),
            "Marketplace: not auction creator."
        );
        _;
    }

    /// @dev Checks whether an auction exists.
    modifier onlyExistingAuction(uint256 _auctionId) {
        require(
            _englishAuctionsStorage().auctions[_auctionId].status ==
                Status.CREATED,
            "Marketplace: invalid auction."
        );
        _;
    }

    constructor(address _nativeTokenWrapper) {
        nativeTokenWrapper = _nativeTokenWrapper;
    }

    function createListing(
        ListingParameters memory _params
    )
        external
        onlyListerRole
        onlyAssetRole(_params.assetContract)
        returns (uint256 listingId)
    {
        listingId = _getNextListingId();
        address listingCreator = _msgSender();
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
            status: Status.CREATED
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
            status: Status.CREATED
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
        _directListingsStorage().listings[_listingId].status = Status.CANCELLED;
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
            _directListingsStorage().listings[_listingId].status = Status
                .COMPLETED;
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

    /// @notice Auction ERC721 or ERC1155 NFTs.
    function createAuction(
        AuctionParameters calldata _params
    )
        external
        onlyListerRole
        onlyAssetRole(_params.assetContract)
        nonReentrant
        returns (uint256 auctionId)
    {
        auctionId = _getNextAuctionId();
        address auctionCreator = _msgSender();
        TokenType tokenType = _getTokenType(_params.assetContract);

        _validateNewAuction(_params, tokenType);

        Auction memory auction = Auction({
            auctionId: auctionId,
            auctionCreator: auctionCreator,
            assetContract: _params.assetContract,
            tokenId: _params.tokenId,
            quantity: _params.quantity,
            currency: _params.currency,
            minimumBidAmount: _params.minimumBidAmount,
            buyoutBidAmount: _params.buyoutBidAmount,
            timeBufferInSeconds: _params.timeBufferInSeconds,
            bidBufferBps: _params.bidBufferBps,
            startTimestamp: _params.startTimestamp,
            endTimestamp: _params.endTimestamp,
            tokenType: tokenType,
            status: Status.CREATED
        });

        _englishAuctionsStorage().auctions[auctionId] = auction;

        _transferAuctionTokens(auctionCreator, address(this), auction);

        emit NewAuction(
            auctionCreator,
            auctionId,
            _params.assetContract,
            auction
        );
    }

    function cancelAuction(uint256 _auctionId) external override {}

    function collectAuctionPayout(uint256 _auctionId) external override {
        require(
            !_englishAuctionsStorage()
                .payoutStatus[_auctionId]
                .paidOutBidAmount,
            "Marketplace: payout already completed."
        );
        _englishAuctionsStorage()
            .payoutStatus[_auctionId]
            .paidOutBidAmount = true;

        Auction memory _targetAuction = _englishAuctionsStorage().auctions[
            _auctionId
        ];
        Bid memory _winningBid = _englishAuctionsStorage().winningBid[
            _auctionId
        ];

        require(
            _targetAuction.status != Status.CANCELLED,
            "Marketplace: invalid auction."
        );
        require(
            _targetAuction.endTimestamp <= block.timestamp,
            "Marketplace: auction still active."
        );
        require(
            _winningBid.bidder != address(0),
            "Marketplace: no bids were made."
        );

        _closeAuctionForAuctionCreator(_targetAuction, _winningBid);

        if (_targetAuction.status != Status.COMPLETED) {
            _englishAuctionsStorage().auctions[_auctionId].status = Status
                .COMPLETED;
        }
    }

    function collectAuctionTokens(uint256 _auctionId) external override {
        Auction memory _targetAuction = _englishAuctionsStorage().auctions[
            _auctionId
        ];
        Bid memory _winningBid = _englishAuctionsStorage().winningBid[
            _auctionId
        ];

        require(
            _targetAuction.status != Status.CANCELLED,
            "Marketplace: invalid auction."
        );
        require(
            _targetAuction.endTimestamp <= block.timestamp,
            "Marketplace: auction still active."
        );
        require(
            _winningBid.bidder != address(0),
            "Marketplace: no bids were made."
        );

        _closeAuctionForBidder(_targetAuction, _winningBid);

        if (_targetAuction.status != Status.COMPLETED) {
            _englishAuctionsStorage().auctions[_auctionId].status = Status
                .COMPLETED;
        }
    }

    function bidInAuction(
        uint256 _auctionId,
        uint256 _bidAmount
    ) external payable override {
        Auction memory _targetAuction = _englishAuctionsStorage().auctions[
            _auctionId
        ];

        require(
            _targetAuction.endTimestamp > block.timestamp &&
                _targetAuction.startTimestamp <= block.timestamp,
            "Marketplace: inactive auction."
        );
        require(_bidAmount != 0, "Marketplace: Bidding with zero amount.");
        require(
            _targetAuction.currency == CurrencyTransferLib.NATIVE_TOKEN ||
                msg.value == 0,
            "Marketplace: invalid native tokens sent."
        );
        require(
            _bidAmount <= _targetAuction.buyoutBidAmount ||
                _targetAuction.buyoutBidAmount == 0,
            "Marketplace: Bidding above buyout price."
        );

        Bid memory newBid = Bid({
            auctionId: _auctionId,
            bidder: _msgSender(),
            bidAmount: _bidAmount
        });

        _handleBid(_targetAuction, newBid);
    }

    function isNewWinningBid(
        uint256 _auctionId,
        uint256 _bidAmount
    ) external view override returns (bool) {
        Auction memory _targetAuction = _englishAuctionsStorage().auctions[
            _auctionId
        ];
        Bid memory _currentWinningBid = _englishAuctionsStorage().winningBid[
            _auctionId
        ];

        return
            _isNewWinningBid(
                _targetAuction.minimumBidAmount,
                _currentWinningBid.bidAmount,
                _bidAmount,
                _targetAuction.bidBufferBps
            );
    }

    function getAuction(
        uint256 _auctionId
    ) external view override returns (Auction memory auction) {
        auction = _englishAuctionsStorage().auctions[_auctionId];
    }

    function getAllAuctions(
        uint256 _startId,
        uint256 _endId
    ) external view override returns (Auction[] memory _allAuctions) {
        require(
            _startId <= _endId &&
                _endId < _englishAuctionsStorage().totalAuctions,
            "invalid range"
        );

        _allAuctions = new Auction[](_endId - _startId + 1);

        for (uint256 i = _startId; i <= _endId; i += 1) {
            _allAuctions[i - _startId] = _englishAuctionsStorage().auctions[i];
        }
    }

    function getAllValidAuctions(
        uint256 _startId,
        uint256 _endId
    ) external view override returns (Auction[] memory _validAuctions) {
        require(
            _startId <= _endId &&
                _endId < _englishAuctionsStorage().totalAuctions,
            "invalid range"
        );

        Auction[] memory _auctions = new Auction[](_endId - _startId + 1);
        uint256 _auctionCount;

        for (uint256 i = _startId; i <= _endId; i += 1) {
            uint256 j = i - _startId;
            _auctions[j] = _englishAuctionsStorage().auctions[i];
            if (
                _auctions[j].startTimestamp <= block.timestamp &&
                _auctions[j].endTimestamp > block.timestamp &&
                _auctions[j].status == Status.CREATED &&
                _auctions[j].assetContract != address(0)
            ) {
                _auctionCount += 1;
            }
        }

        _validAuctions = new Auction[](_auctionCount);
        uint256 index = 0;
        uint256 count = _auctions.length;
        for (uint256 i = 0; i < count; i += 1) {
            if (
                _auctions[i].startTimestamp <= block.timestamp &&
                _auctions[i].endTimestamp > block.timestamp &&
                _auctions[i].status == Status.CREATED &&
                _auctions[i].assetContract != address(0)
            ) {
                _validAuctions[index++] = _auctions[i];
            }
        }
    }

    function getWinningBid(
        uint256 _auctionId
    )
        external
        view
        override
        returns (address bidder, address currency, uint256 bidAmount)
    {
        Auction memory _targetAuction = _englishAuctionsStorage().auctions[
            _auctionId
        ];
        Bid memory _currentWinningBid = _englishAuctionsStorage().winningBid[
            _auctionId
        ];

        bidder = _currentWinningBid.bidder;
        currency = _targetAuction.currency;
        bidAmount = _currentWinningBid.bidAmount;
    }

    function isAuctionExpired(
        uint256 _auctionId
    ) external view override returns (bool) {
        return
            _englishAuctionsStorage().auctions[_auctionId].endTimestamp >=
            block.timestamp;
    }

    /*///////////////////////////////////////////////////////////////
                            Internal functions
    //////////////////////////////////////////////////////////////*/

    /// @dev Returns the next listing Id.
    function _getNextListingId() internal returns (uint256 id) {
        id = _directListingsStorage().totalListings;
        _directListingsStorage().totalListings += 1;
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
            _targetListing.status == Status.CREATED &&
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

    /// @dev Returns the DirectListings storage.
    function _directListingsStorage()
        internal
        pure
        returns (DirectListingsStorage.Data storage data)
    {
        data = DirectListingsStorage.data();
    }

    // auction internal functions
    /*///////////////////////////////////////////////////////////////
                            Internal functions
    //////////////////////////////////////////////////////////////*/

    /// @dev Returns the next auction Id.
    function _getNextAuctionId() internal returns (uint256 id) {
        id = _englishAuctionsStorage().totalAuctions;
        _englishAuctionsStorage().totalAuctions += 1;
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
            revert("Marketplace: auctioned token must be ERC1155 or ERC721.");
        }
    }

    /// @dev Checks whether the auction creator owns and has approved marketplace to transfer auctioned tokens.
    function _validateNewAuction(
        AuctionParameters memory _params,
        TokenType _tokenType
    ) internal view {
        require(_params.quantity > 0, "Marketplace: auctioning zero quantity.");
        require(
            _params.quantity == 1 || _tokenType == TokenType.ERC1155,
            "Marketplace: auctioning invalid quantity."
        );
        require(
            _params.timeBufferInSeconds > 0,
            "Marketplace: no time-buffer."
        );
        require(_params.bidBufferBps > 0, "Marketplace: no bid-buffer.");
        require(
            _params.startTimestamp + 60 minutes >= block.timestamp &&
                _params.startTimestamp < _params.endTimestamp,
            "Marketplace: invalid timestamps."
        );
        require(
            _params.buyoutBidAmount == 0 ||
                _params.buyoutBidAmount >= _params.minimumBidAmount,
            "Marketplace: invalid bid amounts."
        );
    }

    /// @dev Processes an incoming bid in an auction.
    function _handleBid(
        Auction memory _targetAuction,
        Bid memory _incomingBid
    ) internal {
        Bid memory currentWinningBid = _englishAuctionsStorage().winningBid[
            _targetAuction.auctionId
        ];
        uint256 currentBidAmount = currentWinningBid.bidAmount;
        uint256 incomingBidAmount = _incomingBid.bidAmount;
        address _nativeTokenWrapper = nativeTokenWrapper;

        // Close auction and execute sale if there's a buyout price and incoming bid amount is buyout price.
        if (
            _targetAuction.buyoutBidAmount > 0 &&
            incomingBidAmount >= _targetAuction.buyoutBidAmount
        ) {
            incomingBidAmount = _targetAuction.buyoutBidAmount;
            _incomingBid.bidAmount = _targetAuction.buyoutBidAmount;

            _closeAuctionForBidder(_targetAuction, _incomingBid);
        } else {
            /**
             *      If there's an exisitng winning bid, incoming bid amount must be bid buffer % greater.
             *      Else, bid amount must be at least as great as minimum bid amount
             */
            require(
                _isNewWinningBid(
                    _targetAuction.minimumBidAmount,
                    currentBidAmount,
                    incomingBidAmount,
                    _targetAuction.bidBufferBps
                ),
                "Marketplace: not winning bid."
            );

            // Update the winning bid and auction's end time before external contract calls.
            _englishAuctionsStorage().winningBid[
                _targetAuction.auctionId
            ] = _incomingBid;

            if (
                _targetAuction.endTimestamp - block.timestamp <=
                _targetAuction.timeBufferInSeconds
            ) {
                _targetAuction.endTimestamp += _targetAuction
                    .timeBufferInSeconds;
                _englishAuctionsStorage().auctions[
                    _targetAuction.auctionId
                ] = _targetAuction;
            }
        }

        // Payout previous highest bid.
        if (currentWinningBid.bidder != address(0) && currentBidAmount > 0) {
            CurrencyTransferLib.transferCurrencyWithWrapper(
                _targetAuction.currency,
                address(this),
                currentWinningBid.bidder,
                currentBidAmount,
                _nativeTokenWrapper
            );
        }

        // Collect incoming bid
        CurrencyTransferLib.transferCurrencyWithWrapper(
            _targetAuction.currency,
            _incomingBid.bidder,
            address(this),
            incomingBidAmount,
            _nativeTokenWrapper
        );

        emit NewBid(
            _targetAuction.auctionId,
            _incomingBid.bidder,
            _targetAuction.assetContract,
            _incomingBid.bidAmount,
            _targetAuction
        );
    }

    /// @dev Checks whether an incoming bid is the new current highest bid.
    function _isNewWinningBid(
        uint256 _minimumBidAmount,
        uint256 _currentWinningBidAmount,
        uint256 _incomingBidAmount,
        uint256 _bidBufferBps
    ) internal pure returns (bool isValidNewBid) {
        if (_currentWinningBidAmount == 0) {
            isValidNewBid = _incomingBidAmount >= _minimumBidAmount;
        } else {
            isValidNewBid = (_incomingBidAmount > _currentWinningBidAmount &&
                ((_incomingBidAmount - _currentWinningBidAmount) * MAX_BPS) /
                    _currentWinningBidAmount >=
                _bidBufferBps);
        }
    }

    /// @dev Closes an auction for the winning bidder; distributes auction items to the winning bidder.
    function _closeAuctionForBidder(
        Auction memory _targetAuction,
        Bid memory _winningBid
    ) internal {
        require(
            !_englishAuctionsStorage()
                .payoutStatus[_targetAuction.auctionId]
                .paidOutAuctionTokens,
            "Marketplace: payout already completed."
        );
        _englishAuctionsStorage()
            .payoutStatus[_targetAuction.auctionId]
            .paidOutAuctionTokens = true;

        _targetAuction.endTimestamp = uint64(block.timestamp);

        _englishAuctionsStorage().winningBid[
            _targetAuction.auctionId
        ] = _winningBid;
        _englishAuctionsStorage().auctions[
            _targetAuction.auctionId
        ] = _targetAuction;

        _transferAuctionTokens(
            address(this),
            _winningBid.bidder,
            _targetAuction
        );

        emit AuctionClosed(
            _targetAuction.auctionId,
            _targetAuction.assetContract,
            _msgSender(),
            _targetAuction.tokenId,
            _targetAuction.auctionCreator,
            _winningBid.bidder
        );
    }

    /// @dev Closes an auction for an auction creator; distributes winning bid amount to auction creator.
    function _closeAuctionForAuctionCreator(
        Auction memory _targetAuction,
        Bid memory _winningBid
    ) internal {
        uint256 payoutAmount = _winningBid.bidAmount;
        _payout(
            address(this),
            _targetAuction.auctionCreator,
            _targetAuction.currency,
            payoutAmount
        );

        emit AuctionClosed(
            _targetAuction.auctionId,
            _targetAuction.assetContract,
            _msgSender(),
            _targetAuction.tokenId,
            _targetAuction.auctionCreator,
            _winningBid.bidder
        );
    }

    /// @dev Transfers tokens for auction.
    function _transferAuctionTokens(
        address _from,
        address _to,
        Auction memory _auction
    ) internal {
        if (_auction.tokenType == TokenType.ERC1155) {
            IERC1155(_auction.assetContract).safeTransferFrom(
                _from,
                _to,
                _auction.tokenId,
                _auction.quantity,
                ""
            );
        } else if (_auction.tokenType == TokenType.ERC721) {
            IERC721(_auction.assetContract).safeTransferFrom(
                _from,
                _to,
                _auction.tokenId,
                ""
            );
        }
    }

    /// @dev Pays out stakeholders in auction.
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

    /// @dev Returns the EnglishAuctions storage.
    function _englishAuctionsStorage()
        internal
        pure
        returns (EnglishAuctionsStorage.Data storage data)
    {
        data = EnglishAuctionsStorage.data();
    }

    /// @dev Checks whether platform fee info can be set in the given execution context.
    function _canSetPlatformFeeInfo() internal view override returns (bool) {
        return hasRole(DEFAULT_ADMIN_ROLE, _msgSender());
    }
}
