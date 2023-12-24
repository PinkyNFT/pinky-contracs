// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract PinkyToken is ERC20, AccessControl {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant AIRDROPPER_ROLE = keccak256("AIRDROPPER_ROLE");
    uint256 public MAX_SUPPLY_IN_ETH;
    uint256 public MAX_SUPPLY_IN_WEI;
    uint256 public AIRDROP_CAP_IN_ETH;
    uint256 public AIRDROP_CAP_IN_WEI;

    constructor(uint256 _maxSupply, uint256 _airDropCap) ERC20("PinkyToken", "PINKY") {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        MAX_SUPPLY_IN_ETH = _maxSupply;
        MAX_SUPPLY_IN_WEI = _maxSupply * 10**18;
        AIRDROP_CAP_IN_ETH = _airDropCap;
        AIRDROP_CAP_IN_WEI = _airDropCap * 10**18;
    }
    function airDropSingle(
        address _to,
        uint256 _amount
    ) external onlyRole(AIRDROPPER_ROLE){
        // transfer _amount to _to
        imint(_to, _amount);
    }

    function airDropBulk(
        address[] memory _to,
        uint256[] memory _amount
    ) external onlyRole(AIRDROPPER_ROLE) {
        require(_to.length == _amount.length, "Invalid input");

        for (uint256 i = 0; i < _to.length; i++) {
            imint(_to[i], _amount[i]);
        }
    }

    function imint(address _to, uint256 _amount) internal {
        require(totalSupply() + _amount <= MAX_SUPPLY_IN_WEI, "Max supply reached");
        require(_amount <= AIRDROP_CAP_IN_WEI, "Airdrop cap reached");
        _mint(_to, _amount);
    }

    function mint(address _to, uint256 _amount) external onlyRole(MINTER_ROLE) {
        _mint(_to, _amount);
    }

    function setMaxSupply(uint256 _maxSupply) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_maxSupply > totalSupply(), "Invalid input");
        MAX_SUPPLY_IN_ETH = _maxSupply;
        MAX_SUPPLY_IN_WEI = _maxSupply * 10**18;
    }

    function setAirDropCap(uint256 _airDropCap) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_airDropCap <= MAX_SUPPLY_IN_ETH, "Invalid input");
        AIRDROP_CAP_IN_ETH = _airDropCap;
        AIRDROP_CAP_IN_WEI = _airDropCap * 10**18;
    }
}
