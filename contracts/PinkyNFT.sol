// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// ██████╗ ██╗███╗   ██╗██╗  ██╗██╗   ██╗
// ██╔══██╗██║████╗  ██║██║ ██╔╝╚██╗ ██╔╝
// ██████╔╝██║██╔██╗ ██║█████╔╝  ╚████╔╝
// ██╔═══╝ ██║██║╚██╗██║██╔═██╗   ╚██╔╝
// ██║     ██║██║ ╚████║██║  ██╗   ██║
// ╚═╝     ╚═╝╚═╝  ╚═══╝╚═╝  ╚═╝   ╚═╝

import { ERC721 } from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";

contract PinkyNFT is ERC721, Ownable, Pausable, ReentrancyGuard, AccessControl {
    uint256 private tokenIdCounter = 0;
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    address public openseaProxyRegistryAddress;
    address public pinkyProxyRegistryAddress;

    IERC20 public pinkyToken;

    uint256 public mintFeeInCoin;
    uint256 public mintFeeInToken;

    bool public mintingInCoinEnabled;
    bool public mintingInTokenEnabled;
    bool public freeMintingEnabled;

    uint256 accountMintingFrequency = 4 minutes;

    mapping(address => uint256) public nextNFTMintTime;
    mapping(uint => uint256) private _parentNFTs;
    mapping(uint => string) private _tokenURIs;
    mapping(string => bool) private _mintedHashes;
    mapping(uint => uint256) public revealDate; //mapping of tokenId to reveal date
    // Optional base URI
    string public baseTokenURI;
    string public prerevealMetadata;
    event NFTMinted(address indexed owner, uint256 indexed tokenId);
    // event NFTListingChanged(address indexed owner, uint256 indexed tokenId);

    constructor(
        address _openseaProxyRegistryAddress,
        address _pinkyProxyRegistryAddress,
        uint256 _mintFeeInCoin,
        uint256 _mintFeeInToken,
        bool _mintingInCoinEnabled,
        bool _mintingInTokenEnabled,
        bool _freeMintingEnabled,
        string memory _baseTokenURI,
        string memory _prerevealMetadata
    ) ERC721("PinkyNFT", "PNFT") Ownable(msg.sender) {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        openseaProxyRegistryAddress = _openseaProxyRegistryAddress;
        pinkyProxyRegistryAddress = _pinkyProxyRegistryAddress;

        mintFeeInCoin = _mintFeeInCoin;
        mintFeeInToken = _mintFeeInToken;

        mintingInCoinEnabled = _mintingInCoinEnabled;
        freeMintingEnabled = _freeMintingEnabled;
        mintingInTokenEnabled = _mintingInTokenEnabled;

        baseTokenURI = _baseTokenURI;
        prerevealMetadata = _prerevealMetadata;
    }

    function mintNFTInCoin(
        string memory jsonHash,
        uint256 _parentNFT,
        uint256 _revealDate
    ) external payable whenNotPaused nonReentrant {
        require(mintingInCoinEnabled, "Minting in coin is disabled");
        require(msg.value >= mintFeeInCoin, "Insufficient funds to mint.");
        require(!_mintedHashes[jsonHash], "This hash has already been minted");
        // Mint the NFT
        _mintNFT(msg.sender, jsonHash, _parentNFT, _revealDate);
        emit NFTMinted(msg.sender, tokenIdCounter);
        tokenIdCounter++;
    }

    function mintNFTInToken(
        string memory jsonHash,
        uint256 _parentNFT,
        uint256 _revealDate
    ) external whenNotPaused nonReentrant {
        require(mintingInTokenEnabled, "Minting in token is disabled");
        require(!_mintedHashes[jsonHash], "This hash has already been minted");
        require(pinkyToken.balanceOf(msg.sender) >= mintFeeInToken, "Insufficient funds to mint.");
        require(pinkyToken.allowance(msg.sender, address(this)) >= mintFeeInToken, "Insufficient allowance to mint.");
        require(pinkyToken.transferFrom(msg.sender, address(this), mintFeeInToken), "Transfer failed");

        // Mint the NFT
        _mintNFT(msg.sender, jsonHash, _parentNFT, _revealDate);
        emit NFTMinted(msg.sender, tokenIdCounter);
        tokenIdCounter++;
    }

    function freeMintNFT(
        address _to,
        string memory jsonHash,
        uint256 _parentNFT,
        uint256 _revealDate
    ) external whenNotPaused nonReentrant onlyRole(MINTER_ROLE) {
        require(freeMintingEnabled, "Free minting is disabled");
        require(!_mintedHashes[jsonHash], "This hash has already been minted");
        require(nextNFTMintTime[_to] < block.timestamp, "Please wait for the next minting window.");
        nextNFTMintTime[_to] = block.timestamp + accountMintingFrequency;
        // Mint the NFT
        _mintNFT(_to, jsonHash, _parentNFT, _revealDate);
        emit NFTMinted(_to, tokenIdCounter);
        tokenIdCounter++;
    }

    function _mintNFT(address _to, string memory jsonHash, uint256 _parentNFT, uint256 _revealDate) internal {
        _safeMint(_to, tokenIdCounter);

        _parentNFTs[tokenIdCounter] = _parentNFT == 0 ? tokenIdCounter : _parentNFT;
        revealDate[tokenIdCounter] = _revealDate;
        _tokenURIs[tokenIdCounter] = jsonHash;
        _mintedHashes[jsonHash] = true;
    }

    /**
     * Override isApprovedForAll to auto-approve OS's proxy contract
     */
    function isApprovedForAll(address _owner, address _operator) public view override returns (bool isOperator) {
        // if OpenSea's ERC721 Proxy Address is detected, auto-return true
        if (
            (openseaProxyRegistryAddress != address(0) && _operator == openseaProxyRegistryAddress) ||
            (pinkyProxyRegistryAddress != address(0) && _operator == pinkyProxyRegistryAddress)
        ) {
            return true;
        }

        // otherwise, use the default ERC721.isApprovedForAll()
        return super.isApprovedForAll(_owner, _operator);
    }

    function setMinMintingFrequency(uint256 _accountMintingFrequency) external onlyOwner {
        accountMintingFrequency = _accountMintingFrequency;
    }

    function setOpenseaProxyRegistryAddress(address _openseaProxyRegistryAddress) external onlyOwner {
        openseaProxyRegistryAddress = _openseaProxyRegistryAddress;
    }

    function setPinkyProxyRegistryAddress(address _pinkyProxyRegistryAddress) external onlyOwner {
        pinkyProxyRegistryAddress = _pinkyProxyRegistryAddress;
    }

    // Allow the contract owner to update the mint fee
    function setMintFeeInCoin(uint256 _newFee) external onlyOwner {
        mintFeeInCoin = _newFee;
    }

    function setMintingInCoinEnabled(bool _enabled) external onlyOwner {
        mintingInCoinEnabled = _enabled;
    }

    function setFreeMintingEnabled(bool _enabled) external onlyOwner {
        freeMintingEnabled = _enabled;
    }

    function setMintingInTokenEnabled(bool _enabled) external onlyOwner {
        mintingInTokenEnabled = _enabled;
    }

    function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
        //string cat with tokenURI
        string memory _tokenURI = _tokenURIs[tokenId];

        if (revealDate[tokenId] > 0 && revealDate[tokenId] < block.timestamp) {
            return prerevealMetadata;
        }
        // If token URI is set, concatenate base URI and tokenURI (via string.concat).
        return bytes(_tokenURI).length > 0 ? string.concat(baseTokenURI, _tokenURI) : super.tokenURI(tokenId);
    }

    function setPinkToken(address _pinkyTokenAddress, uint256 _mintFeeInToken) external onlyOwner {
        pinkyToken = IERC20(_pinkyTokenAddress);
        mintFeeInToken = _mintFeeInToken;
    }

    function setPreRevealMetadata(string memory _prerevealMetadata) external onlyOwner {
        prerevealMetadata = _prerevealMetadata;
    }

    function withdraw() external onlyOwner {
        (bool sent, ) = msg.sender.call{ value: address(this).balance }("");
        require(sent, "Failed to send Ether");
    }

    function withdrawToken(address _tokenAddress) external onlyOwner {
        IERC20 token = IERC20(_tokenAddress);
        token.transfer(msg.sender, token.balanceOf(address(this)));
    }

    function setBaseURI(string memory baseURI) public onlyOwner {
        baseTokenURI = baseURI;
    }

    struct NFT {
        uint256 tokenId;
        string tokenURI;
    }

    function getNFTByAddress(address _address) public view returns (NFT[] memory) {
        uint256 count = 0;

        for (uint256 i = 0; i <= tokenIdCounter; i++) {
            if (_ownerOf(i) == _address) {
                count++;
            }
        }
        NFT[] memory result = new NFT[](count);
        count = 0;
        for (uint256 i = 0; i <= tokenIdCounter; i++) {
            if (_ownerOf(i) == _address) {
                result[count] = NFT(i, tokenURI(i));
                count++;
            }
        }
        return result;
    }

    function getFamilyTree(uint256 _tokenId) public view returns (uint256[] memory) {
        uint256 count = 0;
        uint256 tokenID = _tokenId;

        while (true) {
            count++;
            if (_parentNFTs[tokenID] == 0 || _parentNFTs[tokenID] == tokenID) {
                break;
            }
            tokenID = _parentNFTs[tokenID];
        }
        uint256[] memory result = new uint256[](count);
        count = 0;
        tokenID = _tokenId;
        while (true) {
            result[count] = tokenID;
            count++;
            if (_parentNFTs[tokenID] == 0 || _parentNFTs[tokenID] == tokenID) {
                break;
            }
            tokenID = _parentNFTs[tokenID];
        }
        return result;
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC721, AccessControl) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    function transferOwnership(address newOwner) public virtual override onlyOwner {
        if (newOwner == address(0)) {
            revert OwnableInvalidOwner(address(0));
        }
        //make sure the old owner is not the new owner
        revokeRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(DEFAULT_ADMIN_ROLE, newOwner);
        _transferOwnership(newOwner);
    }
}
