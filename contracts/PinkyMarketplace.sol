// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// ██████╗ ██╗███╗   ██╗██╗  ██╗██╗   ██╗
// ██╔══██╗██║████╗  ██║██║ ██╔╝╚██╗ ██╔╝
// ██████╔╝██║██╔██╗ ██║█████╔╝  ╚████╔╝
// ██╔═══╝ ██║██║╚██╗██║██╔═██╗   ╚██╔╝
// ██║     ██║██║ ╚████║██║  ██╗   ██║
// ╚═╝     ╚═╝╚═╝  ╚═══╝╚═╝  ╚═╝   ╚═╝

import "./DirectListing.sol";
import "./EnglishAuction.sol";
import { ERC165 } from "@openzeppelin/contracts/utils/introspection/ERC165.sol";

import { ERC721Holder, IERC721Receiver } from "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import { ERC1155Holder, IERC1155Receiver } from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";

// contract PinkyMarketplace is DirectListing, EnglishAuction {
//     constructor(address _nativeTokenWrapper, address _defaultAdmin) BaseMarketplace(_nativeTokenWrapper) {
//         _grantRole(DEFAULT_ADMIN_ROLE, _defaultAdmin);
//         _grantRole(LISTER_ROLE, address(0));
//         _grantRole(ASSET_ROLE, address(0));
//     }

//     receive() external payable {
//         assert(msg.sender == nativeTokenWrapper); // only accept ETH via fallback from the native token wrapper contract
//     }

//     /*///////////////////////////////////////////////////////////////
//                         ERC 165 / 721 / 1155 logic
//     //////////////////////////////////////////////////////////////*/

//     function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
//         return
//             interfaceId == type(IERC1155Receiver).interfaceId ||
//             interfaceId == type(IERC721Receiver).interfaceId ||
//             super.supportsInterface(interfaceId);
//     }
// }
