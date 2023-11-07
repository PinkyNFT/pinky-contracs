// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

// TODO: Please remove Counters.sol
// ref: https://github.com/OpenZeppelin/openzeppelin-contracts/issues/4720#issuecomment-1795345899
// import "@openzeppelin/contracts/utils/Counters.sol";


contract PinkyNFT is ERC721, Ownable, Pausable, ReentrancyGuard {
    uint256 private tokenIdCounter;
    address public openseaProxyRegistryAddress =
        0x1E0049783F008A0085193E00003D00cd54003c71;// open access to opensea

    IERC20 public pinkyToken; // PINKY COIN token contract

    uint256 public mintFeeInCoin = 1 ether; // 1 MATIC
    uint256 public mintFeeInToken = 10 * 10 ** 18; // 10 PINKY
    uint256 public mintReward = 10 * 10 ** 18; // 10 PINKY
    bool public mintingInCoinEnabled = true;
    bool public mintingInTokenEnabled = false;

    mapping(uint => string) private _tokenURIs;
    mapping(string => bool) private _mintedHashes;
    mapping(uint => uint256) public revealDate; //mapping of tokenId to reveal date
    // Optional base URI
    string private baseTokenURI = "https://gateway.pinata.cloud/ipfs/";
    string prerevealMetadata =
        "https://ipfs.io/ipfs/bafyreicwi7sbomz7lu5jozgeghclhptilbvvltpxt3hbpyazz5zxvqh62m/metadata.json";
    event NFTMinted(address indexed owner, uint256 indexed tokenId);
    event NFTListingChanged(address indexed owner, uint256 indexed tokenId);

    constructor(address pinkyTokenAddress) ERC721("PinkyNFT", "PNFT") {
        pinkyToken = IERC20(pinkyTokenAddress);
    }

    function mintNFTInCoin(
        string memory jsonHash,
        uint256 _revealDate
    ) external payable whenNotPaused nonReentrant {
        require(mintingInCoinEnabled, "Minting in coin is disabled");
        require(msg.value >= mintFeeInCoin, "Insufficient funds to mint.");
        require(!_mintedHashes[jsonHash], "This hash has already been minted");
        // Mint the NFT
        _mintNFT(jsonHash, _revealDate);
        emit NFTMinted(msg.sender, tokenIdCounter);
    }

    function mintNFTInToken(
        string memory jsonHash,
        uint256 _revealDate
    ) external payable whenNotPaused nonReentrant {
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
        _mintNFT(jsonHash, _revealDate);
        emit NFTMinted(msg.sender, tokenIdCounter);
    }

    function _mintNFT(string memory jsonHash, uint256 _revealDate) internal {
        uint256 tokenId = tokenIdCounter;
        // _mint(msg.sender, tokenId, 1, "");
        _safeMint(msg.sender, tokenId);

        revealDate[tokenId] = _revealDate;
        _tokenURIs[tokenId] = jsonHash;
        _mintedHashes[jsonHash] = true;
        //give 10 PINKY to the user

        pinkyToken.transfer(msg.sender, mintReward);
        tokenIdCounter++;
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
    ) external onlyOwner {
        openseaProxyRegistryAddress = _openseaProxyRegistryAddress;
    }

    function setMintReward(uint256 _newReward) external onlyOwner {
        mintReward = _newReward;
    }

    // Allow the contract owner to update the mint fee
    function setMintFeeInCoin(uint256 _newFee) external onlyOwner {
        mintFeeInCoin = _newFee;
    }

    function setMintFeeInToken(uint256 _newFee) external onlyOwner {
        mintFeeInToken = _newFee;
    }
    function setMintingInCoinEnabled(bool _enabled) external onlyOwner {
        mintingInCoinEnabled = _enabled;
    }
    function setMintingInTokenEnabled(bool _enabled) external onlyOwner {
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
    ) external onlyOwner {
        pinkyToken = IERC20(_pinkyTokenAddress);
    }

    function setPreRevealMetadata(
        string memory _prerevealMetadata
    ) external onlyOwner {
        prerevealMetadata = _prerevealMetadata;
    }

    function withdraw() external onlyOwner {
        (bool sent, ) = msg.sender.call{value: address(this).balance}("");
        require(sent, "Failed to send Ether");
    }

    /**
     * @dev Sets `baseURI` as the `baseTokenURI` for all tokens
     */
    function setBaseURI(string memory baseURI) public onlyOwner {
        baseTokenURI = baseURI;
    }

    struct NFT {
        uint256 tokenId;
        string tokenURI;
    }

    function getNFTByAddress(
        address _address
    ) public view returns (NFT[] memory) {
        uint256 tokenIdLimit = tokenIdCounter;
        uint256 count = 0;

        for (uint256 i = 0; i < tokenIdLimit; i++) {
            // TODO: replace _isApprovedOrOwner
            if (_isApprovedOrOwner(_address, i)) {
                count++;
            }
        }
        NFT[] memory result = new NFT[](count);
        count = 0;
        for (uint256 i = 0; i < tokenIdLimit; i++) {
            // TODO: replace _isApprovedOrOwner
            if (_isApprovedOrOwner(_address, i)) {
                result[count] = NFT(i, tokenURI(i));
                count++;
            }
        }
        return result;
    }
}
