// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import { IERC1155 } from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import { IERC165 } from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import { CurrencyTransferLib } from "./lib/CurrencyTransferLib.sol";
import "./EnglishAuctionStorage.sol";
import "./interfaces/IMarketPlace.sol";
import "./BaseMarketplace.sol";

contract EnglishAuction is BaseMarketplace, IEnglishAuctions {
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

    constructor(address _pinkyMarketplaceProxyAddress) BaseMarketplace(_pinkyMarketplaceProxyAddress) {}

    /*///////////////////////////////////////////////////////////////
                External functions of Auction
    //////////////////////////////////////////////////////////////*/

    /// @notice Auction ERC721 or ERC1155 NFTs.
    function createAuction(AuctionParameters calldata _params) external nonReentrant returns (uint256 auctionId) {
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

        pinkyMarketplaceProxy.transferTokens(
            auctionCreator,
            address(pinkyMarketplaceProxy),
            auction.tokenType,
            auction.assetContract,
            auction.tokenId,
            auction.quantity
        );

        emit NewAuction(auctionCreator, auctionId, _params.assetContract, auction);
    }

    /// @dev Cancels an auction.
    function cancelAuction(
        uint256 _auctionId
    ) external onlyExistingAuction(_auctionId) onlyAuctionCreator(_auctionId) nonReentrant {
        Auction memory _targetAuction = _englishAuctionsStorage().auctions[_auctionId];
        Bid memory _winningBid = _englishAuctionsStorage().winningBid[_auctionId];

        require(_winningBid.bidder == address(0), "Marketplace: bids already made.");

        _englishAuctionsStorage().auctions[_auctionId].status = Status.CANCELLED;

        pinkyMarketplaceProxy.transferTokens(
            address(pinkyMarketplaceProxy),
            _targetAuction.auctionCreator,
            _targetAuction.tokenType,
            _targetAuction.assetContract,
            _targetAuction.tokenId,
            _targetAuction.quantity
        );

        emit CancelledAuction(_targetAuction.auctionCreator, _auctionId);
    }

    function collectAuctionPayout(uint256 _auctionId) external override {
        require(
            !_englishAuctionsStorage().payoutStatus[_auctionId].paidOutBidAmount,
            "Marketplace: payout already completed."
        );
        _englishAuctionsStorage().payoutStatus[_auctionId].paidOutBidAmount = true;

        Auction memory _targetAuction = _englishAuctionsStorage().auctions[_auctionId];
        Bid memory _winningBid = _englishAuctionsStorage().winningBid[_auctionId];

        require(_targetAuction.status != Status.CANCELLED, "Marketplace: invalid auction.");
        require(_targetAuction.endTimestamp <= block.timestamp, "Marketplace: auction still active.");
        require(_winningBid.bidder != address(0), "Marketplace: no bids were made.");

        _closeAuctionForAuctionCreator(_targetAuction, _winningBid);

        if (_targetAuction.status != Status.COMPLETED) {
            _englishAuctionsStorage().auctions[_auctionId].status = Status.COMPLETED;
        }
    }

    function collectAuctionTokens(uint256 _auctionId) external override {
        Auction memory _targetAuction = _englishAuctionsStorage().auctions[_auctionId];
        Bid memory _winningBid = _englishAuctionsStorage().winningBid[_auctionId];

        require(_targetAuction.status != Status.CANCELLED, "Marketplace: invalid auction.");
        require(_targetAuction.endTimestamp <= block.timestamp, "Marketplace: auction still active.");
        require(_winningBid.bidder != address(0), "Marketplace: no bids were made.");

        _closeAuctionForBidder(_targetAuction, _winningBid);

        if (_targetAuction.status != Status.COMPLETED) {
            _englishAuctionsStorage().auctions[_auctionId].status = Status.COMPLETED;
        }
    }

    function bidInAuction(uint256 _auctionId, uint256 _bidAmount) external payable override {
        Auction memory _targetAuction = _englishAuctionsStorage().auctions[_auctionId];

        require(
            _targetAuction.endTimestamp > block.timestamp && _targetAuction.startTimestamp <= block.timestamp,
            "Marketplace: inactive auction."
        );
        require(_bidAmount != 0, "Marketplace: Bidding with zero amount.");
        require(
            _targetAuction.currency == CurrencyTransferLib.NATIVE_TOKEN || msg.value == 0,
            "Marketplace: invalid native tokens sent."
        );
        require(
            _bidAmount <= _targetAuction.buyoutBidAmount || _targetAuction.buyoutBidAmount == 0,
            "Marketplace: Bidding above buyout price."
        );

        Bid memory newBid = Bid({ auctionId: _auctionId, bidder: _msgSender(), bidAmount: _bidAmount });

        _handleBid(_targetAuction, newBid);
    }

    /*///////////////////////////////////////////////////////////////
                View functions of Auction
    //////////////////////////////////////////////////////////////*/

    function isNewWinningBid(uint256 _auctionId, uint256 _bidAmount) external view override returns (bool) {
        Auction memory _targetAuction = _englishAuctionsStorage().auctions[_auctionId];
        Bid memory _currentWinningBid = _englishAuctionsStorage().winningBid[_auctionId];

        return
            _isNewWinningBid(
                _targetAuction.minimumBidAmount,
                _currentWinningBid.bidAmount,
                _bidAmount,
                _targetAuction.bidBufferBps
            );
    }

    function getAuction(uint256 _auctionId) external view override returns (Auction memory auction) {
        auction = _englishAuctionsStorage().auctions[_auctionId];
    }

    function getAllAuctions(
        uint256 _startId,
        uint256 _endId
    ) external view override returns (Auction[] memory _allAuctions) {
        require(_startId <= _endId && _endId < _englishAuctionsStorage().totalAuctions, "invalid range");

        _allAuctions = new Auction[](_endId - _startId + 1);

        for (uint256 i = _startId; i <= _endId; i += 1) {
            _allAuctions[i - _startId] = _englishAuctionsStorage().auctions[i];
        }
    }

    function getAllValidAuctions(
        uint256 _startId,
        uint256 _endId
    ) external view override returns (Auction[] memory _validAuctions) {
        require(_startId <= _endId && _endId < _englishAuctionsStorage().totalAuctions, "invalid range");

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
    ) external view override returns (address bidder, address currency, uint256 bidAmount) {
        Auction memory _targetAuction = _englishAuctionsStorage().auctions[_auctionId];
        Bid memory _currentWinningBid = _englishAuctionsStorage().winningBid[_auctionId];

        bidder = _currentWinningBid.bidder;
        currency = _targetAuction.currency;
        bidAmount = _currentWinningBid.bidAmount;
    }

    function isAuctionExpired(uint256 _auctionId) external view override returns (bool) {
        return _englishAuctionsStorage().auctions[_auctionId].endTimestamp >= block.timestamp;
    }

    /*///////////////////////////////////////////////////////////////
                Internal functions of Auction
    //////////////////////////////////////////////////////////////*/

    /// @dev Returns the next auction Id.
    function _getNextAuctionId() internal returns (uint256 id) {
        id = _englishAuctionsStorage().totalAuctions;
        _englishAuctionsStorage().totalAuctions += 1;
    }

    /// @dev Checks whether the auction creator owns and has approved marketplace to transfer auctioned tokens.
    function _validateNewAuction(AuctionParameters memory _params, TokenType _tokenType) internal view {
        require(_params.quantity > 0, "Marketplace: auctioning zero quantity.");
        require(_params.quantity == 1 || _tokenType == TokenType.ERC1155, "Marketplace: auctioning invalid quantity.");
        require(_params.timeBufferInSeconds > 0, "Marketplace: no time-buffer.");
        require(_params.bidBufferBps > 0, "Marketplace: no bid-buffer.");
        require(
            _params.startTimestamp + 60 minutes >= block.timestamp && _params.startTimestamp < _params.endTimestamp,
            "Marketplace: invalid timestamps."
        );
        require(
            _params.buyoutBidAmount == 0 || _params.buyoutBidAmount >= _params.minimumBidAmount,
            "Marketplace: invalid bid amounts."
        );
    }

    /// @dev Processes an incoming bid in an auction.
    function _handleBid(Auction memory _targetAuction, Bid memory _incomingBid) internal {
        Bid memory currentWinningBid = _englishAuctionsStorage().winningBid[_targetAuction.auctionId];
        uint256 currentBidAmount = currentWinningBid.bidAmount;
        uint256 incomingBidAmount = _incomingBid.bidAmount;

        // Close auction and execute sale if there's a buyout price and incoming bid amount is buyout price.
        if (_targetAuction.buyoutBidAmount > 0 && incomingBidAmount >= _targetAuction.buyoutBidAmount) {
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
            _englishAuctionsStorage().winningBid[_targetAuction.auctionId] = _incomingBid;

            if (_targetAuction.endTimestamp - block.timestamp <= _targetAuction.timeBufferInSeconds) {
                _targetAuction.endTimestamp += _targetAuction.timeBufferInSeconds;
                _englishAuctionsStorage().auctions[_targetAuction.auctionId] = _targetAuction;
            }
        }

        // Payout previous highest bid.
        if (currentWinningBid.bidder != address(0) && currentBidAmount > 0) {
            pinkyMarketplaceProxy.sendCurrencyWithWrapper(
                _targetAuction.currency,
                currentWinningBid.bidder,
                currentBidAmount
            );
        }

        pinkyMarketplaceProxy.receiveCurrencyWithWrapper(
            _targetAuction.currency,
            _incomingBid.bidder,
            incomingBidAmount
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
                ((_incomingBidAmount - _currentWinningBidAmount) * MAX_BPS) / _currentWinningBidAmount >=
                _bidBufferBps);
        }
    }

    /// @dev Closes an auction for the winning bidder; distributes auction items to the winning bidder.
    function _closeAuctionForBidder(Auction memory _targetAuction, Bid memory _winningBid) internal {
        require(
            !_englishAuctionsStorage().payoutStatus[_targetAuction.auctionId].paidOutAuctionTokens,
            "Marketplace: payout already completed."
        );
        _englishAuctionsStorage().payoutStatus[_targetAuction.auctionId].paidOutAuctionTokens = true;

        _targetAuction.endTimestamp = uint64(block.timestamp);

        _englishAuctionsStorage().winningBid[_targetAuction.auctionId] = _winningBid;
        _englishAuctionsStorage().auctions[_targetAuction.auctionId] = _targetAuction;

        pinkyMarketplaceProxy.transferTokens(
            address(pinkyMarketplaceProxy),
            _winningBid.bidder,
            _targetAuction.tokenType,
            _targetAuction.assetContract,
            _targetAuction.tokenId,
            _targetAuction.quantity
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
    function _closeAuctionForAuctionCreator(Auction memory _targetAuction, Bid memory _winningBid) internal {
        uint256 payoutAmount = _winningBid.bidAmount;
        pinkyMarketplaceProxy.payout(
            address(pinkyMarketplaceProxy),
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

    /// @dev Returns the EnglishAuctions storage.
    function _englishAuctionsStorage() internal pure returns (EnglishAuctionsStorage.Data storage data) {
        data = EnglishAuctionsStorage.data();
    }
}
