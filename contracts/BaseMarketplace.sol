// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IERC165 } from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import { Status, TokenType } from "./interfaces/IMarketPlace.sol";
import { IERC1155 } from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { PinkyMarketplaceProxy } from "./PinkyMarketplaceProxy.sol";

abstract contract BaseMarketplace is ReentrancyGuard, Ownable {
    uint64 constant MAX_BPS = 10_000;
    address public pinkyNFT;
    PinkyMarketplaceProxy pinkyMarketplaceProxy;

    constructor(address _pinkyMarketplaceProxyAddress, address _pinkyNFT) Ownable(msg.sender) {
        pinkyMarketplaceProxy = PinkyMarketplaceProxy(_pinkyMarketplaceProxyAddress);
        pinkyNFT = _pinkyNFT;
    }

    /// @dev Returns the interface supported by a contract.
    // function _getTokenType(address _assetContract) internal view returns (TokenType tokenType) {
    //     if (IERC165(_assetContract).supportsInterface(type(IERC1155).interfaceId)) {
    //         tokenType = TokenType.ERC1155;
    //     } else if (IERC165(_assetContract).supportsInterface(type(IERC721).interfaceId)) {
    //         tokenType = TokenType.ERC721;
    //     } else {
    //         revert("Marketplace: auctioned token must be ERC1155 or ERC721.");
    //     }
    // }

    /// @dev Validates that `_tokenOwner` owns and has approved Marketplace to transfer NFTs.
    function _validateOwnershipAndApproval(address _tokenOwner, uint256 _tokenId) internal view returns (bool isValid) {
        address market = address(pinkyMarketplaceProxy);
        address owner;
        address operator;

        // failsafe for reverts in case of non-existent tokens
        try IERC721(pinkyNFT).ownerOf(_tokenId) returns (address _owner) {
            owner = _owner;

            // Nesting the approval check inside this try block, to run only if owner check doesn't revert.
            // If the previous check for owner fails, then the return value will always evaluate to false.
            try IERC721(pinkyNFT).getApproved(_tokenId) returns (address _operator) {
                operator = _operator;
            } catch {}
        } catch {}

        isValid =
            owner == _tokenOwner &&
            (operator == market || IERC721(pinkyNFT).isApprovedForAll(_tokenOwner, market));
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
