// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

//A basic erc20 token with minting and burning functionality
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract PinkyToken is ERC20, Ownable {
    address public pinkyNFTAddress;

    constructor() ERC20("PinkyToken", "PINKY") Ownable(msg.sender) {

    }
    function setPinkyNFTAddress(address _pinkyNFTAddress) external onlyOwner {
        pinkyNFTAddress = _pinkyNFTAddress;
    }
    function mintToPinkyNFT(uint256 _amount) external onlyOwner {
        _mint(pinkyNFTAddress, _amount);
    }
    function adminMint(address _to, uint256 _amount) external onlyOwner {
        _mint(_to, _amount);
    }
}