// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

//A basic erc20 token with minting and burning functionality
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract PinkyToken is ERC20, Ownable {
    constructor() ERC20("PinkyToken", "PINKY") Ownable(msg.sender) {
        _mint(msg.sender, 1000000000 * 10 ** 18);
    }

    function airDropSingle(address _to, uint256 _amount) external onlyOwner {
        // transfer _amount to _to
        transfer(_to, _amount);
    }

    function airDropBulk(
        address[] memory _to,
        uint256[] memory _amount
    ) external onlyOwner {
        require(_to.length == _amount.length, "Invalid input");
        for (uint256 i = 0; i < _to.length; i++) {
            transfer(_to[i], _amount[i]);
        }
    }
}
