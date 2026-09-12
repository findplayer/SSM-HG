// SPDX-License-Identifier: MIT

pragma solidity 0.8.18;

/* 
    @title	SecureKey 2FA Token for Untracer V. 3.0  
    @author	The Architect - bd36584a2ffb45a50d94c97e708e9f8307329a0a0394936e49b0de7eb00916da
    @notice This contract cannot be paused for end user security
    @dev	Service token. Untracer contract will verify the presence of this token in destination wallet preventing MEV action
            and increasing security of the mixing procedure. Only the contract can call the minting function of this token. 
*/

contract SecureKEY {

    /* ERC20 standard */
    string public name;
    string public symbol;
    uint8 public decimals;
    address private owner;

    /* Authorized caller for minting is stored here */
    address private untracerContractAddress;        

    /* Event declaration */
    event tokenMinted(uint256 amount); 
    event changedUntracerContractAddress(address newAddress);
    event renounced(address deadAddress);

    /* Keep balance of addresses */
    mapping(address => uint256) private balances;

     /*
        @dev	Modifier for checking the authorized caller
    */
    modifier onlyAuthorizedCaller() {
        require(msg.sender == untracerContractAddress, "Ownable: caller is not the untracer contract");
        _;
    }
     
    /*
        @dev	Modifier for checking ownership.
    */
    modifier onlyOwner() {
        require(msg.sender == owner, "Ownable: caller is not the owner");
        _;
    }
    
   /*
        @dev	Modifier for address verification. 
    */
    modifier validAddress(address _addr) {
        require(_addr != address(0), "Not valid address");
        _;
    }

    constructor() {
        /* Standard ERC20 interface data for this token */
        name = "SecureKEY";
        symbol = "SKey";
        decimals = 18;

        /* The owner is registered*/
        owner = msg.sender;
    }

    /*
        @dev	Standard ERC20 interface balanceOf/transfer/allowance methods
    */

    function balanceOf(address _owner) public view returns (uint256 balance) {
        return balances[_owner];
    }

    function transfer(address _to, uint256 _value) public returns (bool success) {
        require(balances[msg.sender] >= _value, "Insufficient balance");
        balances[msg.sender] -= _value;
        balances[_to] += _value;
        return true;
    }
   
     /*
        @dev	Mint the token to the caller's address. Only the contract (as caller) can activate this function
        @param	Address of the authorized to mint contract
        @return	returns TRUE (ERC20 interface) in any case. A TokenMinted event is triggered
    */
    function mint(address _to, uint256 _value) public onlyAuthorizedCaller() returns (bool success) {
        uint256 realAmount = _value * 10 ** 18;
        balances[_to] += realAmount;
        emit tokenMinted(realAmount);
        return true;
    }

    /*
        @dev	Reset the wallet setting balance to zero
        @param	Address of the wallet to make empty. Only the contract of untracer can call this method.
    */
    function resetWallet(address walletToReset) public onlyAuthorizedCaller validAddress(walletToReset)  {
        balances[walletToReset] = 0;
    }
    
    /*
        @dev	Set the address of the Untracer contract. Only this address will be able to mint token
        @param	Address of the authorized to mint contract. The validAddress modifier is added to perform valid address check
        @return	return types of an function
    */
    function setUntracerContractAddress(address addressOfUntracerContract) public onlyOwner validAddress(addressOfUntracerContract) {

        /* Set the new contract address for untracer authorized to mint token */
        untracerContractAddress = addressOfUntracerContract;
        
        /* Emit an event for this operation */
        emit changedUntracerContractAddress(addressOfUntracerContract);
    }

    /*
        @dev	Returns the address that created this contract, to inform user.
        @param	none.
        @return	returns an address
    */
    function getOwner() public view returns (address)    {
        return owner;
    }

    /*
        @dev	Function to renounce ownership of the contract
        @param	none.
        @return	none. But emits an event for this operation
    */

    function renounceOwnership() public onlyOwner   {
        address deadAddress = 0x000000000000000000000000000000000000dEaD;
        
        /* Change ownership to a dead wallet */
        owner = deadAddress;

        /* Emit an event */
        emit renounced(deadAddress);
    }
}