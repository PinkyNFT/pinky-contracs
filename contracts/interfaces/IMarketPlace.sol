// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.11;

/**
 *
 *  The `DirectListings` extension smart contract lets you buy and sell NFTs (ERC-721 or ERC-1155) for a fixed price.
 */
enum Status {
    UNSET,
    CREATED,
    COMPLETED,
    CANCELLED
}
enum TokenType {
    ERC721,
    ERC1155
}

interface IDirectListings {
    /**
     *  @notice The parameters a seller sets when creating or updating a listing.
     *
     *  @param assetContract The address of the smart contract of the NFTs being listed.
     *  @param tokenId The tokenId of the NFTs being listed.
     *  @param quantity The quantity of NFTs being listed. This must be non-zero, and is expected to
     *                  be `1` for ERC-721 NFTs.
     *  @param currency The currency in which the price must be paid when buying the listed NFTs.
     *  @param pricePerToken The price to pay per unit of NFTs listed.
     *  @param startTimestamp The UNIX timestamp at and after which NFTs can be bought from the listing.
     *  @param endTimestamp The UNIX timestamp at and after which NFTs cannot be bought from the listing.
     *  @param reserved Whether the listing is reserved to be bought from a specific set of buyers.
     */
    struct ListingParameters {
        address assetContract;
        uint256 tokenId;
        uint256 quantity;
        address currency;
        uint256 pricePerToken;
        uint128 startTimestamp;
        uint128 endTimestamp;
        bool reserved;
    }

    /**
     *  @notice The information stored for a listing.
     *
     *  @param listingId The unique ID of the listing.
     *  @param listingCreator The creator of the listing.
     *  @param assetContract The address of the smart contract of the NFTs being listed.
     *  @param tokenId The tokenId of the NFTs being listed.
     *  @param quantity The quantity of NFTs being listed. This must be non-zero, and is expected to
     *                  be `1` for ERC-721 NFTs.
     *  @param currency The currency in which the price must be paid when buying the listed NFTs.
     *  @param pricePerToken The price to pay per unit of NFTs listed.
     *  @param startTimestamp The UNIX timestamp at and after which NFTs can be bought from the listing.
     *  @param endTimestamp The UNIX timestamp at and after which NFTs cannot be bought from the listing.
     *  @param reserved Whether the listing is reserved to be bought from a specific set of buyers.
     *  @param status The status of the listing (created, completed, or cancelled).
     *  @param tokenType The type of token listed (ERC-721 or ERC-1155)
     */
    struct Listing {
        uint256 listingId;
        uint256 tokenId;
        uint256 quantity;
        uint256 pricePerToken;
        uint128 startTimestamp;
        uint128 endTimestamp;
        address listingCreator;
        address assetContract;
        address currency;
        TokenType tokenType;
        Status status;
        bool reserved;
    }

    /// @notice Emitted when a new listing is created.
    event NewListing(
        address indexed listingCreator,
        uint256 indexed listingId,
        address indexed assetContract,
        Listing listing
    );

    /// @notice Emitted when a listing is updated.
    event UpdatedListing(
        address indexed listingCreator,
        uint256 indexed listingId,
        address indexed assetContract,
        Listing listing
    );

    /// @notice Emitted when a listing is cancelled.
    event CancelledListing(address indexed listingCreator, uint256 indexed listingId);

    /// @notice Emitted when a buyer is approved to buy from a reserved listing.
    event BuyerApprovedForListing(uint256 indexed listingId, address indexed buyer, bool approved);

    /// @notice Emitted when a currency is approved as a form of payment for the listing.
    event CurrencyApprovedForListing(uint256 indexed listingId, address indexed currency, uint256 pricePerToken);

    /// @notice Emitted when NFTs are bought from a listing.
    event NewSale(
        address indexed listingCreator,
        uint256 indexed listingId,
        address indexed assetContract,
        uint256 tokenId,
        address buyer,
        uint256 quantityBought,
        uint256 totalPricePaid
    );

    /**
     *  @notice List NFTs (ERC721 or ERC1155) for sale at a fixed price.
     *
     *  @param _params The parameters of a listing a seller sets when creating a listing.
     *
     *  @return listingId The unique integer ID of the listing.
     */
    function createListing(ListingParameters memory _params) external returns (uint256 listingId);

    /**
     *  @notice Update parameters of a listing of NFTs.
     *
     *  @param _listingId The ID of the listing to update.
     *  @param _params The parameters of a listing a seller sets when updating a listing.
     */
    function updateListing(uint256 _listingId, ListingParameters memory _params) external;

    /**
     *  @notice Cancel a listing.
     *
     *  @param _listingId The ID of the listing to cancel.
     */
    function cancelListing(uint256 _listingId) external;

    /**
     *  @notice Approve a buyer to buy from a reserved listing.
     *
     *  @param _listingId The ID of the listing to update.
     *  @param _buyer The address of the buyer to approve to buy from the listing.
     *  @param _toApprove Whether to approve the buyer to buy from the listing.
     */
    function approveBuyerForListing(uint256 _listingId, address _buyer, bool _toApprove) external;

    /**
     *  @notice Approve a currency as a form of payment for the listing.
     *
     *  @param _listingId The ID of the listing to update.
     *  @param _currency The address of the currency to approve as a form of payment for the listing.
     *  @param _pricePerTokenInCurrency The price per token for the currency to approve.
     */
    function approveCurrencyForListing(
        uint256 _listingId,
        address _currency,
        uint256 _pricePerTokenInCurrency
    ) external;

    /**
     *  @notice Buy NFTs from a listing.
     *
     *  @param _listingId The ID of the listing to update.
     *  @param _buyFor The recipient of the NFTs being bought.
     *  @param _quantity The quantity of NFTs to buy from the listing.
     *  @param _currency The currency to use to pay for NFTs.
     *  @param _expectedTotalPrice The expected total price to pay for the NFTs being bought.
     */
    function buyFromListing(
        uint256 _listingId,
        address _buyFor,
        uint256 _quantity,
        address _currency,
        uint256 _expectedTotalPrice
    ) external payable;

    /**
     *  @notice Returns the total number of listings created.
     *  @dev At any point, the return value is the ID of the next listing created.
     */
    function totalListings() external view returns (uint256);

    /// @notice Returns all listings between the start and end Id (both inclusive) provided.
    function getAllListings(uint256 _startId, uint256 _endId) external view returns (Listing[] memory listings);

    /**
     *  @notice Returns all valid listings between the start and end Id (both inclusive) provided.
     *          A valid listing is where the listing creator still owns and has approved Marketplace
     *          to transfer the listed NFTs.
     */
    function getAllValidListings(uint256 _startId, uint256 _endId) external view returns (Listing[] memory listings);

    /**
     *  @notice Returns a listing at the provided listing ID.
     *
     *  @param _listingId The ID of the listing to fetch.
     */
    function getListing(uint256 _listingId) external view returns (Listing memory listing);
}

/**
 *  The `EnglishAuctions` extension smart contract lets you sell NFTs (ERC-721 or ERC-1155) in an english auction.
 */

interface IEnglishAuctions {
    /**
     *  @notice The parameters a seller sets when creating an auction listing.
     *
     *  @param assetContract The address of the smart contract of the NFTs being auctioned.
     *  @param tokenId The tokenId of the NFTs being auctioned.
     *  @param quantity The quantity of NFTs being auctioned. This must be non-zero, and is expected to
     *                  be `1` for ERC-721 NFTs.
     *  @param currency The currency in which the bid must be made when bidding for the auctioned NFTs.
     *  @param minimumBidAmount The minimum bid amount for the auction.
     *  @param buyoutBidAmount The total bid amount for which the bidder can directly purchase the auctioned items and close the auction as a result.
     *  @param timeBufferInSeconds This is a buffer e.g. x seconds. If a new winning bid is made less than x seconds before expirationTimestamp, the
     *                             expirationTimestamp is increased by x seconds.
     *  @param bidBufferBps This is a buffer in basis points e.g. x%. To be considered as a new winning bid, a bid must be at least x% greater than
     *                      the current winning bid.
     *  @param startTimestamp The timestamp at and after which bids can be made to the auction
     *  @param endTimestamp The timestamp at and after which bids cannot be made to the auction.
     */
    struct AuctionParameters {
        address assetContract;
        uint256 tokenId;
        uint256 quantity;
        address currency;
        uint256 minimumBidAmount;
        uint256 buyoutBidAmount;
        uint64 timeBufferInSeconds;
        uint64 bidBufferBps;
        uint64 startTimestamp;
        uint64 endTimestamp;
    }

    /**
     *  @notice The information stored for an auction.
     *
     *  @param auctionId The unique ID of the auction.
     *  @param auctionCreator The creator of the auction.
     *  @param assetContract The address of the smart contract of the NFTs being auctioned.
     *  @param tokenId The tokenId of the NFTs being auctioned.
     *  @param quantity The quantity of NFTs being auctioned. This must be non-zero, and is expected to
     *                  be `1` for ERC-721 NFTs.
     *  @param currency The currency in which the bid must be made when bidding for the auctioned NFTs.
     *  @param minimumBidAmount The minimum bid amount for the auction.
     *  @param buyoutBidAmount The total bid amount for which the bidder can directly purchase the auctioned items and close the auction as a result.
     *  @param timeBufferInSeconds This is a buffer e.g. x seconds. If a new winning bid is made less than x seconds before expirationTimestamp, the
     *                             expirationTimestamp is increased by x seconds.
     *  @param bidBufferBps This is a buffer in basis points e.g. x%. To be considered as a new winning bid, a bid must be at least x% greater than
     *                      the current winning bid.
     *  @param startTimestamp The timestamp at and after which bids can be made to the auction
     *  @param endTimestamp The timestamp at and after which bids cannot be made to the auction.
     *  @param status The status of the auction (created, completed, or cancelled).
     *  @param tokenType The type of NFTs auctioned (ERC-721 or ERC-1155)
     */
    struct Auction {
        uint256 auctionId;
        uint256 tokenId;
        uint256 quantity;
        uint256 minimumBidAmount;
        uint256 buyoutBidAmount;
        uint64 timeBufferInSeconds;
        uint64 bidBufferBps;
        uint64 startTimestamp;
        uint64 endTimestamp;
        address auctionCreator;
        address assetContract;
        address currency;
        TokenType tokenType;
        Status status;
    }

    /**
     *  @notice The information stored for a bid made in an auction.
     *
     *  @param auctionId The unique ID of the auction.
     *  @param bidder The address of the bidder.
     *  @param bidAmount The total bid amount (in the currency specified by the auction).
     */
    struct Bid {
        uint256 auctionId;
        address bidder;
        uint256 bidAmount;
    }

    struct AuctionPayoutStatus {
        bool paidOutAuctionTokens;
        bool paidOutBidAmount;
    }

    /// @dev Emitted when a new auction is created.
    event NewAuction(
        address indexed auctionCreator,
        uint256 indexed auctionId,
        address indexed assetContract,
        Auction auction
    );

    /// @dev Emitted when a new bid is made in an auction.
    event NewBid(
        uint256 indexed auctionId,
        address indexed bidder,
        address indexed assetContract,
        uint256 bidAmount,
        Auction auction
    );

    /// @notice Emitted when a auction is cancelled.
    event CancelledAuction(address indexed auctionCreator, uint256 indexed auctionId);

    /// @dev Emitted when an auction is closed.
    event AuctionClosed(
        uint256 indexed auctionId,
        address indexed assetContract,
        address indexed closer,
        uint256 tokenId,
        address auctionCreator,
        address winningBidder
    );

    /**
     *  @notice Put up NFTs (ERC721 or ERC1155) for an english auction.
     *
     *  @param _params The parameters of an auction a seller sets when creating an auction.
     *
     *  @return auctionId The unique integer ID of the auction.
     */
    function createAuction(AuctionParameters memory _params) external returns (uint256 auctionId);

    /**
     *  @notice Cancel an auction.
     *
     *  @param _auctionId The ID of the auction to cancel.
     */
    function cancelAuction(uint256 _auctionId) external;

    /**
     *  @notice Distribute the winning bid amount to the auction creator.
     *
     *  @param _auctionId The ID of an auction.
     */
    function collectAuctionPayout(uint256 _auctionId) external;

    /**
     *  @notice Distribute the auctioned NFTs to the winning bidder.
     *
     *  @param _auctionId The ID of an auction.
     */
    function collectAuctionTokens(uint256 _auctionId) external;

    /**
     *  @notice Bid in an active auction.
     *
     *  @param _auctionId The ID of the auction to bid in.
     *  @param _bidAmount The bid amount in the currency specified by the auction.
     */
    function bidInAuction(uint256 _auctionId, uint256 _bidAmount) external payable;

    /**
     *  @notice Returns whether a given bid amount would make for a winning bid in an auction.
     *
     *  @param _auctionId The ID of an auction.
     *  @param _bidAmount The bid amount to check.
     */
    function isNewWinningBid(uint256 _auctionId, uint256 _bidAmount) external view returns (bool);

    /// @notice Returns the auction of the provided auction ID.
    function getAuction(uint256 _auctionId) external view returns (Auction memory auction);

    /// @notice Returns all non-cancelled auctions.
    function getAllAuctions(uint256 _startId, uint256 _endId) external view returns (Auction[] memory auctions);

    /// @notice Returns all active auctions.
    function getAllValidAuctions(uint256 _startId, uint256 _endId) external view returns (Auction[] memory auctions);

    /// @notice Returns the winning bid of an active auction.
    function getWinningBid(
        uint256 _auctionId
    ) external view returns (address bidder, address currency, uint256 bidAmount);

    /// @notice Returns whether an auction is active.
    function isAuctionExpired(uint256 _auctionId) external view returns (bool);
}
