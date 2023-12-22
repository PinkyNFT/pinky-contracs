// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

contract PinkyNFT is ERC721, AccessControl, Pausable, ReentrancyGuard {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    uint256 private tokenIdCounter = 0;
    address public openseaProxyRegistryAddress; // open access to opensea 0x1E0049783F008A0085193E00003D00cd54003c71

    IERC20 public pinkyToken;

    uint256 public mintFeeInCoin; // = 0.001 ether;
    uint256 public mintFeeInToken; //= 10 * 10 ** 18; // 10 PINKY

    bool public mintingInCoinEnabled; // = true;
    bool public mintingInTokenEnabled; // = false;

    mapping(uint => uint256) private _parentNFTs;
    mapping(uint => string) private _tokenURIs;
    mapping(string => bool) private _mintedHashes;
    mapping(uint => uint256) public revealDate; //mapping of tokenId to reveal date
    // Optional base URI
    string private baseTokenURI; // = "https://gateway.pinata.cloud/ipfs/";
    string prerevealMetadata; // ="https://ipfs.io/ipfs/bafyreicwi7sbomz7lu5jozgeghclhptilbvvltpxt3hbpyazz5zxvqh62m/metadata.json";
    event NFTMinted(address indexed owner, uint256 indexed tokenId);
    event NFTListingChanged(address indexed owner, uint256 indexed tokenId);

    constructor(
        address _openseaProxyRegistryAddress,
        uint256 _mintFeeInCoin,
        uint256 _mintFeeInToken,
        bool _mintingInCoinEnabled,
        bool _mintingInTokenEnabled,
        string memory _baseTokenURI,
        string memory _prerevealMetadata
    ) ERC721("PinkyNFT", "PNFT") {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        openseaProxyRegistryAddress = _openseaProxyRegistryAddress;
        mintFeeInCoin = _mintFeeInCoin;
        mintFeeInToken = _mintFeeInToken;

        mintingInCoinEnabled = _mintingInCoinEnabled;
        mintingInTokenEnabled = _mintingInTokenEnabled;
        baseTokenURI = _baseTokenURI;
        prerevealMetadata = _prerevealMetadata;
    }

    function mintNFTInCoin(
        string memory jsonHash,
        uint256 _parentNFT,
        uint256 _revealDate
    ) external payable onlyRole(MINTER_ROLE) whenNotPaused nonReentrant {
        require(mintingInCoinEnabled, "Minting in coin is disabled");
        require(msg.value >= mintFeeInCoin, "Insufficient funds to mint.");
        require(!_mintedHashes[jsonHash], "This hash has already been minted");
        // Mint the NFT
        _mintNFT(jsonHash, _parentNFT, _revealDate);
        emit NFTMinted(msg.sender, tokenIdCounter);
        tokenIdCounter++;
    }

    function mintNFTInToken(
        string memory jsonHash,
        uint256 _parentNFT,
        uint256 _revealDate
    ) external payable onlyRole(MINTER_ROLE) whenNotPaused nonReentrant {
        require(mintingInTokenEnabled, "Minting in token is disabled");
        require(
            pinkyToken.balanceOf(msg.sender) >= mintFeeInToken,
            "Insufficient funds to mint."
        );
        require(
            pinkyToken.allowance(msg.sender, address(this)) >= mintFeeInToken,
            "Insufficient allowance to mint."
        );
        require(!_mintedHashes[jsonHash], "This hash has already been minted");

        require(
            pinkyToken.transferFrom(msg.sender, address(this), mintFeeInToken),
            "Transfer failed"
        );
        // Mint the NFT
        _mintNFT(jsonHash, _parentNFT, _revealDate);
        emit NFTMinted(msg.sender, tokenIdCounter);
        tokenIdCounter++;
    }

    function _mintNFT(
        string memory jsonHash,
        uint256 _parentNFT,
        uint256 _revealDate
    ) internal {
        _safeMint(msg.sender, tokenIdCounter);

        _parentNFTs[tokenIdCounter] = _parentNFT == 0
            ? tokenIdCounter
            : _parentNFT;
        revealDate[tokenIdCounter] = _revealDate;
        _tokenURIs[tokenIdCounter] = jsonHash;
        _mintedHashes[jsonHash] = true;
    }

    /**
     * Override isApprovedForAll to auto-approve OS's proxy contract
     */
    function isApprovedForAll(
        address _owner,
        address _operator
    ) public view override returns (bool isOperator) {
        // if OpenSea's ERC721 Proxy Address is detected, auto-return true
        if (_operator == openseaProxyRegistryAddress) {
            return true;
        }

        // otherwise, use the default ERC721.isApprovedForAll()
        return super.isApprovedForAll(_owner, _operator);
    }

    function setOpenseaProxyRegistryAddress(
        address _openseaProxyRegistryAddress
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        openseaProxyRegistryAddress = _openseaProxyRegistryAddress;
    }

    // Allow the contract owner to update the mint fee
    function setMintFeeInCoin(uint256 _newFee) external onlyRole(DEFAULT_ADMIN_ROLE) {
        mintFeeInCoin = _newFee;
    }

    function setMintFeeInToken(uint256 _newFee) external onlyRole(DEFAULT_ADMIN_ROLE) {
        mintFeeInToken = _newFee;
    }

    function setMintingInCoinEnabled(bool _enabled) external onlyRole(DEFAULT_ADMIN_ROLE) {
        mintingInCoinEnabled = _enabled;
    }

    function setMintingInTokenEnabled(bool _enabled) external onlyRole(DEFAULT_ADMIN_ROLE) {
        mintingInTokenEnabled = _enabled;
    }

    function tokenURI(
        uint256 tokenId
    ) public view virtual override returns (string memory) {
        //string cat with tokenURI
        string memory _tokenURI = _tokenURIs[tokenId];

        if (revealDate[tokenId] > 0 && revealDate[tokenId] < block.timestamp) {
            return prerevealMetadata;
        }
        // If token URI is set, concatenate base URI and tokenURI (via string.concat).
        return
            bytes(_tokenURI).length > 0
                ? string.concat(baseTokenURI, _tokenURI)
                : super.tokenURI(tokenId);
    }

    function setPinkTokenAddress(
        address _pinkyTokenAddress
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        pinkyToken = IERC20(_pinkyTokenAddress);
    }

    function setPreRevealMetadata(
        string memory _prerevealMetadata
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        prerevealMetadata = _prerevealMetadata;
    }

    function withdraw() external onlyRole(DEFAULT_ADMIN_ROLE) {
        (bool sent, ) = msg.sender.call{value: address(this).balance}("");
        require(sent, "Failed to send Ether");
    }


    function setBaseURI(string memory baseURI) public onlyRole(DEFAULT_ADMIN_ROLE) {
        baseTokenURI = baseURI;
    }

    struct NFT {
        uint256 tokenId;
        string tokenURI;
    }

    function getNFTByAddress(
        address _address
    ) public view returns (NFT[] memory) {
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

    function getFamilyTree(
        uint256 _tokenId
    ) public view returns (uint256[] memory) {
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
}
