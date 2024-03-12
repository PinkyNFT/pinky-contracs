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

import { PlatformFee } from "./PlatformFee.sol";
import { CurrencyTransferLib } from "./lib/CurrencyTransferLib.sol";

/*receives token and sends token */
contract PinkyMarketplaceProxy is ReentrancyGuard, AccessControl {
    bytes32 constant MARKET_PLACE_ROLE = keccak256("MARKET_PLACE_ROLE");
    address immutable nativeTokenWrapper;

    constructor(address _nativeTokenWrapper,
        address _defaultAdmin
    ) {
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
    function addMarketplaceContract(address _marketplaceContract) onlyRole(DEFAULT_ADMIN_ROLE) external {
        _grantRole(MARKET_PLACE_ROLE, _marketplaceContract);
    }
    function removeMarketplaceContract(address _marketplaceContract) onlyRole(DEFAULT_ADMIN_ROLE) external {
        _revokeRole(MARKET_PLACE_ROLE, _marketplaceContract);
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
}
