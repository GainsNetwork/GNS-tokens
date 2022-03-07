pragma solidity 0.6.6;
import {ERC20, ERC20Capped} from "@openzeppelin/contracts/token/ERC20/ERC20Capped.sol";
import {AccessControlMixin} from "./polygon/common/AccessControlMixin.sol";
import {IChildToken} from "./polygon/child/ChildToken/IChildToken.sol";
import {NativeMetaTransaction} from "./polygon/common/NativeMetaTransaction.sol";
import {ContextMixin} from "./polygon/common/ContextMixin.sol";


contract GainsNetworkToken is
    ERC20Capped,
    IChildToken,
    AccessControlMixin,
    NativeMetaTransaction,
    ContextMixin
{
    bytes32 public constant DEPOSITOR_ROLE = keccak256("DEPOSITOR_ROLE");
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant BURNER_ROLE = keccak256("BURNER_ROLE");

    struct GrantRequest {
        bytes32[] roles;
        uint initiated;
    }
    mapping(address => GrantRequest) grantRequests;
    uint constant public MIN_GRANT_REQUEST_DELAY = 45000; // 1 day

    event GrantRequestInitiated(bytes32[] indexed roles, address indexed account, uint indexed block);
    event GrantRequestCanceled(address indexed account, uint indexed canceled);

    constructor(
        address tradingStorage,
        address trading,
        address callbacks,
        address vault,
        address pool,
        address tokenMigration
    ) public ERC20Capped(100*(10**6)*(10**18)) ERC20("Gains Network", "GNS") {

        // Token init
        _setupContractId("ChildMintableERC20");
        _setupDecimals(18);
        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
        _setupRole(DEPOSITOR_ROLE, 0xA6FA4fB5f76172d178d61B04b0ecd319C5d1C0aa);
        _initializeEIP712("Gains Network");

        // Trading roles
        _setupRole(MINTER_ROLE, tradingStorage);
        _setupRole(BURNER_ROLE, tradingStorage);
        _setupRole(MINTER_ROLE, trading);
        _setupRole(MINTER_ROLE, callbacks);
        _setupRole(MINTER_ROLE, vault);
        _setupRole(MINTER_ROLE, pool);
        _setupRole(MINTER_ROLE, tokenMigration);
    }

    // This is to support Native meta transactions
    // never use msg.sender directly, use _msgSender() instead
    function _msgSender()
        internal
        override
        view
        returns (address payable sender)
    {
        return ContextMixin.msgSender();
    }

    // Disable grantRole AccessControl function (can only be done after timelock)
    function grantRole(bytes32 role, address account) public override {
        require(false, "DISABLED (TIMELOCK)");
    }

    // Returns true if a grant request was initiated for this account.
    function grantRequestInitiated(address account) public view returns(bool){
        GrantRequest memory r = grantRequests[account];
        return r.roles.length > 0 && r.initiated > 0;
    }

    // Initiates a request to grant `role` to `account` at current block number.
    function initiateGrantRequest(bytes32[] calldata roles, address account) external only(DEFAULT_ADMIN_ROLE){
        require(!grantRequestInitiated(account), "Grant request already initiated for this account.");
        grantRequests[account] = GrantRequest(roles, block.number);
        emit GrantRequestInitiated(roles, account, block.number);
    }

    // Cancels a request to grant `role` to `account` 
    function cancelGrantRequest(address account) external only(DEFAULT_ADMIN_ROLE){
        require(grantRequestInitiated(account), "You must first initiate a grant request for this role and account.");
        delete grantRequests[account];
        emit GrantRequestCanceled(account, block.number);
    }

    // Grant the roles precised in the request to account (must wait for the timelock)
    function executeGrantRequest(address account) public only(DEFAULT_ADMIN_ROLE){
        require(grantRequestInitiated(account), "You must first initiate a grant request for this role and account.");
        
        GrantRequest memory r = grantRequests[account];
        require(block.number >= r.initiated + MIN_GRANT_REQUEST_DELAY, "You must wait for the minimum delay after initiating a request.");

        for(uint i = 0; i < r.roles.length; i++){
            _setupRole(r.roles[i], account);
        }

        delete grantRequests[account];
    }

    // Mint tokens (called by our ecosystem contracts)
    function mint(address to, uint amount) external only(MINTER_ROLE){
        _mint(to, amount);
    }

    // Burn tokens (called by our ecosystem contracts)
    function burn(address from, uint amount) external only(BURNER_ROLE){
        _burn(from, amount);
    }

    /**
     * @notice called when token is deposited on root chain
     * @dev Should be callable only by ChildChainManager
     * Should handle deposit by minting the required amount for user
     * Make sure minting is done only by this function
     * @param user user address for whom deposit is being done
     * @param depositData abi encoded amount
     */
    function deposit(address user, bytes calldata depositData)
        external
        override
        only(DEPOSITOR_ROLE)
    {
        uint256 amount = abi.decode(depositData, (uint256));
        _mint(user, amount);
    }

    /**
     * @notice called when user wants to withdraw tokens back to root chain
     * @dev Should burn user's tokens. This transaction will be verified when exiting on root chain
     * @param amount amount of tokens to withdraw
     */
    function withdraw(uint256 amount) external {
        _burn(_msgSender(), amount);
    }

}