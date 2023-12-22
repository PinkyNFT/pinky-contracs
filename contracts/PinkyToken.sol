// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;


import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract PinkyToken is ERC20, AccessControl {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant AIRDROPPER_ROLE = keccak256("AIRDROPPER_ROLE");
    
    constructor() ERC20("PinkyToken", "PINKY") {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    function airDropSingle(address _to, uint256 _amount) external onlyRole(AIRDROPPER_ROLE) {
        // transfer _amount to _to
        transfer(_to, _amount);
    }

    function airDropBulk(
        address[] memory _to,
        uint256[] memory _amount
    ) external onlyRole(AIRDROPPER_ROLE) {
        require(_to.length == _amount.length, "Invalid input");
        for (uint256 i = 0; i < _to.length; i++) {
            transfer(_to[i], _amount[i]);
        }
    }
    function mint(address _to, uint256 _amount) external onlyRole(MINTER_ROLE) {
        _mint(_to, _amount);
    }
}
