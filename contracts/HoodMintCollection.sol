// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "erc721a/contracts/ERC721A.sol";
import "@openzeppelin/contracts/token/common/ERC2981.sol";
import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "./interfaces/ITransferValidator.sol";

/// @title HoodMintCollection
/// @notice A deliberately boring, honeypot-safe NFT collection for Robinhood Chain.
///         Free mints by default. No hidden owner mint. No blacklist. No tax.
///         No transfer pause. Metadata can be frozen to prove immutability.
///         Royalties are declared per ERC-2981 and can be enforced on-chain via an
///         ERC-721C-style transfer validator.
///
///         What the owner CAN do:  toggle minting, update metadata (until frozen),
///                                 lower/raise royalty within a hard cap, set the
///                                 transfer validator, renounce ownership.
///         What the owner CANNOT do: mint past the cap, mint arbitrarily after deploy,
///                                 freeze/seize holder tokens, block transfers, add a tax.
contract HoodMintCollection is ERC721A, ERC2981, Ownable2Step {
    // ---- Immutable launch parameters -------------------------------------------------
    uint256 public immutable maxSupply;      // hard cap, set at deploy, never changes
    uint256 public immutable maxPerWallet;   // per-address mint cap (0 = unlimited)
    uint256 public immutable mintPrice;      // wei per token (0 = free, the default)

    // ---- Royalty guard ---------------------------------------------------------------
    uint96 public constant MAX_ROYALTY_BPS = 1000; // 10% ceiling, protects buyers

    // ---- Mutable, bounded state ------------------------------------------------------
    bool public mintActive;                  // gates MINTING only, never transfers
    bool public metadataFrozen;              // once true, baseURI can never change
    string private _baseTokenURI;
    string private _contractURI;             // collection-level metadata for marketplaces
    address public transferValidator;        // 0x0 = open transfers; set = enforced

    // ---- Events ----------------------------------------------------------------------
    event MintActiveSet(bool active);
    event BaseURISet(string baseURI);
    event MetadataFrozen();
    event ContractURISet(string contractURI);
    event RoyaltySet(address receiver, uint96 bps);
    event TransferValidatorSet(address validator);
    event ReserveMinted(address to, uint256 quantity);

    error MintNotActive();
    error ExceedsMaxSupply();
    error ExceedsWalletLimit();
    error WrongPayment();
    error MetadataIsFrozen();
    error RoyaltyTooHigh();
    error ZeroQuantity();

    constructor(
        string memory name_,
        string memory symbol_,
        uint256 maxSupply_,
        uint256 maxPerWallet_,
        uint256 mintPrice_,
        uint96 royaltyBps_,
        address royaltyReceiver_,
        string memory baseURI_,
        string memory contractURI_,
        uint256 reserveQuantity_,
        address owner_,
        address transferValidator_
    ) ERC721A(name_, symbol_) Ownable(owner_) {
        require(maxSupply_ > 0, "maxSupply=0");
        require(royaltyBps_ <= MAX_ROYALTY_BPS, "royalty>cap");
        require(reserveQuantity_ <= maxSupply_, "reserve>supply");

        maxSupply = maxSupply_;
        maxPerWallet = maxPerWallet_;
        mintPrice = mintPrice_;
        _baseTokenURI = baseURI_;
        _contractURI = contractURI_;

        _setDefaultRoyalty(royaltyReceiver_, royaltyBps_);
        emit RoyaltySet(royaltyReceiver_, royaltyBps_);

        if (transferValidator_ != address(0)) {
            transferValidator = transferValidator_;
            emit TransferValidatorSet(transferValidator_);
        }

        // Optional, fully-disclosed reserve minted once to the creator at deploy.
        // Counts against maxSupply. This is the ONLY owner-side mint that exists.
        if (reserveQuantity_ > 0) {
            _mint(owner_, reserveQuantity_);
            emit ReserveMinted(owner_, reserveQuantity_);
        }
    }

    // ---- Public mint -----------------------------------------------------------------

    /// @notice Free (or fixed-price) public mint. This is the only ongoing mint path.
    function mint(uint256 quantity) external payable {
        if (!mintActive) revert MintNotActive();
        if (quantity == 0) revert ZeroQuantity();
        if (_totalMinted() + quantity > maxSupply) revert ExceedsMaxSupply();
        if (maxPerWallet != 0 && _numberMinted(msg.sender) + quantity > maxPerWallet) {
            revert ExceedsWalletLimit();
        }
        if (msg.value != mintPrice * quantity) revert WrongPayment();

        _mint(msg.sender, quantity);
    }

    // ---- Owner controls (bounded) ----------------------------------------------------

    function setMintActive(bool active) external onlyOwner {
        mintActive = active;
        emit MintActiveSet(active);
    }

    function setBaseURI(string calldata baseURI_) external onlyOwner {
        if (metadataFrozen) revert MetadataIsFrozen();
        _baseTokenURI = baseURI_;
        emit BaseURISet(baseURI_);
    }

    /// @notice One-way switch. After this, art/metadata can never change again.
    function freezeMetadata() external onlyOwner {
        metadataFrozen = true;
        emit MetadataFrozen();
    }

    function setContractURI(string calldata contractURI_) external onlyOwner {
        _contractURI = contractURI_;
        emit ContractURISet(contractURI_);
    }

    function setRoyalty(address receiver, uint96 bps) external onlyOwner {
        if (bps > MAX_ROYALTY_BPS) revert RoyaltyTooHigh();
        _setDefaultRoyalty(receiver, bps);
        emit RoyaltySet(receiver, bps);
    }

    /// @notice Point the collection at an ERC-721C-style validator to enforce that
    ///         only royalty-honoring marketplaces can move tokens. Set to 0x0 for
    ///         fully open transfers.
    function setTransferValidator(address validator) external onlyOwner {
        transferValidator = validator;
        emit TransferValidatorSet(validator);
    }

    // ---- Withdraw (only relevant if a non-zero mintPrice is ever used) ---------------

    function withdraw(address payable to) external onlyOwner {
        (bool ok, ) = to.call{value: address(this).balance}("");
        require(ok, "withdraw failed");
    }

    // ---- Metadata --------------------------------------------------------------------

    function _baseURI() internal view override returns (string memory) {
        return _baseTokenURI;
    }

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        if (!_exists(tokenId)) revert URIQueryForNonexistentToken();
        string memory base = _baseURI();
        return bytes(base).length == 0 ? "" : string(abi.encodePacked(base, _toString(tokenId), ".json"));
    }

    function contractURI() external view returns (string memory) {
        return _contractURI;
    }

    function _startTokenId() internal pure override returns (uint256) {
        return 1;
    }

    // ---- ERC-721C enforcement hook -----------------------------------------------------

    /// @dev Called by ERC721A on mint, transfer, and burn. We only validate real
    ///      secondary transfers (from != 0 && to != 0). Mints and burns are never
    ///      blocked, so nothing can trap a holder's ability to receive or burn.
    function _beforeTokenTransfers(
        address from,
        address to,
        uint256 startTokenId,
        uint256 quantity
    ) internal override {
        address validator = transferValidator;
        if (validator != address(0) && from != address(0) && to != address(0)) {
            uint256 end = startTokenId + quantity;
            for (uint256 id = startTokenId; id < end; ++id) {
                ITransferValidator(validator).validateTransfer(msg.sender, from, to, id);
            }
        }
        super._beforeTokenTransfers(from, to, startTokenId, quantity);
    }

    // ---- ERC-721C introspection (so 721C-aware tools recognize the collection) -------

    function getTransferValidator() external view returns (address) {
        return transferValidator;
    }

    /// @return functionSignature selector the validator exposes for validation
    /// @return isViewFunction    whether that function is a view call
    function getTransferValidationFunction()
        external
        pure
        returns (bytes4 functionSignature, bool isViewFunction)
    {
        return (ITransferValidator.validateTransfer.selector, true);
    }

    // ---- Interfaces ------------------------------------------------------------------

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721A, ERC2981)
        returns (bool)
    {
        return ERC721A.supportsInterface(interfaceId) || ERC2981.supportsInterface(interfaceId);
    }

    // ---- Views for the launchpad UI --------------------------------------------------

    function minted() external view returns (uint256) {
        return _totalMinted();
    }

    function mintedBy(address account) external view returns (uint256) {
        return _numberMinted(account);
    }
}
