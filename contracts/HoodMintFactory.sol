// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./HoodMintCollection.sol";
import "@openzeppelin/contracts/access/Ownable2Step.sol";

/// @title HoodMintFactory
/// @notice One-call launcher for HoodMintCollection. Anyone can deploy a collection;
///         the caller becomes its owner. On Robinhood Chain a full deploy costs a few
///         cents, so we deploy real standalone contracts (no proxies) for maximum
///         auditability. Mints are always free by default; the factory never takes a
///         cut of mints.
contract HoodMintFactory is Ownable2Step {
    /// @notice Optional protocol fee to CREATE a collection (not to mint). Default 0.
    uint256 public creationFee;

    /// @notice Default validator new collections inherit. Lets enforcement be switched
    ///         on chain-wide once a validator is live, without touching this contract.
    address public defaultTransferValidator;

    address[] public allCollections;
    mapping(address => address[]) public collectionsByCreator;

    event CollectionCreated(
        address indexed collection,
        address indexed creator,
        string name,
        string symbol,
        uint256 maxSupply,
        uint256 maxPerWallet,
        uint256 mintPrice,
        uint96 royaltyBps,
        address royaltyReceiver,
        uint256 reserveQuantity,
        uint256 index
    );
    event CreationFeeSet(uint256 fee);
    event DefaultTransferValidatorSet(address validator);
    event FeesWithdrawn(address to, uint256 amount);

    error InsufficientFee();
    error EmptyName();
    error EmptySymbol();

    constructor(address owner_) Ownable(owner_) {}

    struct LaunchParams {
        string name;
        string symbol;
        uint256 maxSupply;
        uint256 maxPerWallet;   // 0 = unlimited
        uint256 mintPrice;      // 0 = free (default and encouraged)
        uint96 royaltyBps;      // <= 1000 (10%)
        address royaltyReceiver;
        string baseURI;         // e.g. ipfs://CID/  (tokenURI = baseURI + id + ".json")
        string contractURI;     // collection-level metadata JSON
        uint256 reserveQuantity;// minted to creator at deploy, counts vs maxSupply
    }

    /// @notice Deploy a new collection. Caller becomes owner. Send `creationFee` if set.
    function createCollection(LaunchParams calldata p) external payable returns (address collection) {
        if (msg.value < creationFee) revert InsufficientFee();
        if (bytes(p.name).length == 0) revert EmptyName();
        if (bytes(p.symbol).length == 0) revert EmptySymbol();

        address receiver = p.royaltyReceiver == address(0) ? msg.sender : p.royaltyReceiver;

        HoodMintCollection c = new HoodMintCollection(
            p.name,
            p.symbol,
            p.maxSupply,
            p.maxPerWallet,
            p.mintPrice,
            p.royaltyBps,
            receiver,
            p.baseURI,
            p.contractURI,
            p.reserveQuantity,
            msg.sender,                 // creator owns the collection
            defaultTransferValidator    // inherit chain-wide validator (0x0 = open)
        );

        collection = address(c);
        uint256 index = allCollections.length;
        allCollections.push(collection);
        collectionsByCreator[msg.sender].push(collection);

        emit CollectionCreated(
            collection,
            msg.sender,
            p.name,
            p.symbol,
            p.maxSupply,
            p.maxPerWallet,
            p.mintPrice,
            p.royaltyBps,
            receiver,
            p.reserveQuantity,
            index
        );
    }

    // ---- Views -----------------------------------------------------------------------

    function totalCollections() external view returns (uint256) {
        return allCollections.length;
    }

    function creatorCollections(address creator) external view returns (address[] memory) {
        return collectionsByCreator[creator];
    }

    /// @notice Cheap pagination for the "explore" grid without an external indexer.
    function collectionsPaged(uint256 start, uint256 count)
        external
        view
        returns (address[] memory page)
    {
        uint256 len = allCollections.length;
        if (start >= len) return new address[](0);
        uint256 end = start + count;
        if (end > len) end = len;
        page = new address[](end - start);
        for (uint256 i = start; i < end; ++i) {
            page[i - start] = allCollections[i];
        }
    }

    // ---- Admin (bounded) -------------------------------------------------------------

    function setCreationFee(uint256 fee) external onlyOwner {
        creationFee = fee;
        emit CreationFeeSet(fee);
    }

    function setDefaultTransferValidator(address validator) external onlyOwner {
        defaultTransferValidator = validator;
        emit DefaultTransferValidatorSet(validator);
    }

    function withdrawFees(address payable to) external onlyOwner {
        uint256 amount = address(this).balance;
        (bool ok, ) = to.call{value: amount}("");
        require(ok, "withdraw failed");
        emit FeesWithdrawn(to, amount);
    }
}
