// SPDX-License-Identifier: MIT

/**
website: https://www.thesecret.club/
twitter: https://twitter.com/MLM_token
telegram: @MLM_contract

We are excited to introduce MLM Token  - a ERC20 meme token with a unique referral marketing program.
Our goal is to create an engaging and mutually beneficial community for all participants.

To take advantage of the exclusive trading opportunity with $MLM, we are offering the first 30 invitations from the developer with the invite code FIRST30.


Maximum Purchase per Transaction: 2% of Total Supply.

Purchase and sale tax: 2% / 2% (Buy / Sell) for activated wallets, and 3% / 3% for non-activated wallets.
1% of the tax is refunded upon wallet activation.

Referral Marketing Program:
1st level: 0.6% - For Novice (To achieve Novice rank, invite one referral. Novice rank allows earning rewards from 1st level referrals.)
2nd level: 0.5% - For Apprentice (To achieve Apprentice rank, invite five referrals with Novice rank. Apprentice rank allows earning rewards from 2nd level referrals.)
3rd level: 0.4% - For Expert (To achieve Expert rank, invite five referrals with Apprentice rank. Expert rank allows earning rewards from 3rd level referrals.)
4th level: 0.3% - For Master (To achieve Master rank, invite five referrals with Expert rank. Master rank allows earning rewards from 4th level referrals.)
5th level: 0.2% - For Legend (To achieve Legend rank, invite five referrals with Master rank. Legend rank allows earning rewards from 5th level referrals.)

* Referral is counted as an address that has made at least one token purchase.
** Immediately after reaching the next rank, you receive all accumulated bonuses of the corresponding level.



**/


pragma solidity 0.8.24;

interface IERC20 {
    function totalSupply() external view returns (uint256);

    function balanceOf(address account) external view returns (uint256);

    function allowance(address owner, address spender) external view returns (uint256);

    function transfer(address recipient, uint256 amount) external returns (bool);

    function approve(address spender, uint256 amount) external returns (bool);

    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
}


contract Context {
    // Empty internal constructor, to prevent people from mistakenly deploying
    // an instance of this contract, which should be used via inheritance.
    constructor () { }

    function _msgSender() internal view returns (address payable) {
        return payable(msg.sender);
    }


}

contract ReentrancyGuard {
    bool private locked;

    constructor() {
        locked = false;
    }

    modifier nonReentrant() {
        require(!locked, "Reentrant call");
        locked = true;
        _;
        locked = false;
    }
}

contract Ownable is Context {
    address private _owner;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    constructor () {
        address msgSender = _msgSender();
        _owner = msgSender;
        emit OwnershipTransferred(address(0), msgSender);
    }

    function owner() public view returns (address) {
        return _owner;
    }

    modifier onlyOwner() {
        require(_owner == _msgSender(), "onlyOwner");
        _;
    }

    function renounceOwnership() external onlyOwner {
        emit OwnershipTransferred(_owner, address(0));
        _owner = address(0);
    }

}

contract SwapBlock is Ownable {
    mapping(address => bool) public addressesLiquidity;
    event PercentsWalletLimitSet(uint256 _percentWalletLimit);
    event AddressLiquidityAdded(address indexed _addressLiquidity);
    event AddressLiquidityRemoved(address indexed _addressLiquidity);

    function checkAddressLiquidity(address _addressLiquidity) external view returns (bool) {
        return addressesLiquidity[_addressLiquidity];
    }

    function addAddressLiquidity(address _addressLiquidity) external onlyOwner {
        addressesLiquidity[_addressLiquidity] = true;
        emit AddressLiquidityAdded(_addressLiquidity);
    }

    function removeAddressLiquidity(address _addressLiquidity) external onlyOwner {
        addressesLiquidity[_addressLiquidity] = false;
        emit AddressLiquidityRemoved(_addressLiquidity);
    }
    uint256 private _percentWalletLimits = 2;

    function getPercentsWalletLimit() public view returns (uint256) {
        return _percentWalletLimits;
    }

    function setPercentsWalletLimit(uint256 _percentWalletLimit) external onlyOwner {
        require(_percentWalletLimit <= 100, "PercentsWalletLimit > 100");

        _percentWalletLimits = _percentWalletLimit;
        emit PercentsWalletLimitSet(_percentWalletLimit);
    }
}


contract MLM is Context, IERC20, SwapBlock, ReentrancyGuard {

    struct AddressData {
        bool registered;
        address referrers;
        uint256 unregisteredRewards;
        uint256[5] balancelevels;
        uint32[5] count_levels;
        bool counted;
    }
    struct InviteData {
        bool usedInvite;
        address referral;
    }
    event usedInvitesChanged(bytes signature);
    event DataChanged(address indexed userAddress);
    mapping(address => AddressData) private _address_data;
    mapping(bytes32 => InviteData) private _invites_data;
    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;
    uint256 private _totalSupply;
    uint8 public immutable _decimals;
    uint8[5] private _REWARDS;
    uint8[5] private _requiredReferralsCount;
    string public _symbol;
    string public _name;
    constructor() {
        _name = "TheSecret.club";
        _symbol = "MLM";
        _REWARDS=[60,50,40,30,20];
        _requiredReferralsCount=[1, 5, 5, 5, 5];
        _decimals = 18;
        _totalSupply = 420e6 * 1e18;
        _balances[msg.sender] = _totalSupply;
        _address_data[msg.sender].registered = true; 
        emit Transfer(address(0), msg.sender, _totalSupply);
    }    

    function getAddressData(address user) public view returns (AddressData memory) {
        return _address_data[user];
    }
    function getUsedInvite(bytes32 inviteId) public view returns (bool) {
        bool usedInvite = _invites_data[inviteId].usedInvite;
        return usedInvite;
    }
    function getInviteReferral(bytes32 inviteId) public view returns (address) {
        address invitereferral = _invites_data[inviteId].referral;
        return invitereferral;
    }
    function getRewards() public view returns (uint8[5] memory) {
        return (_REWARDS);
    }
    function getrequiredReferralsCount() public view returns (uint8[5] memory) {
        return (_requiredReferralsCount);
    }
    function getOwner() external view returns (address) {
        return owner();
    }

    function decimals() external view returns (uint8) {
        return _decimals;
    }

    function symbol() external view returns (string memory) {
        return _symbol;
    }

    function name() external view returns (string memory) {
        return _name;
    }

    function totalSupply() external view returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) external view returns (uint256) {
        return _balances[account];
    }

    function transfer(address recipient, uint256 amount) external returns (bool) {
        _transfer(msg.sender, recipient, amount);
        return true;
    }

    function allowance(address addressOwner, address spender) external view returns (uint256) {
        return _allowances[addressOwner][spender];
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        _approve(msg.sender, spender, amount);
        return true;
    }

    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool) {
        _transfer(sender, recipient, amount);
        _approve(sender, msg.sender, _allowances[sender][msg.sender] - amount);
        return true;
    }

    function increaseAllowance(address spender, uint256 addedValue) external returns (bool) {
        _approve(msg.sender, spender, _allowances[msg.sender][spender]+addedValue);
        return true;
    }

    function decreaseAllowance(address spender, uint256 subtractedValue) external returns (bool) {
        _approve(msg.sender, spender, _allowances[msg.sender][spender]-subtractedValue);
        return true;
    }

    function _mint(address account, uint256 amount) internal {
        require(account != address(0), "Mint to the zero address");
        _totalSupply = _totalSupply+amount;
        _balances[account] = _balances[account]+amount;
        emit Transfer(address(0), account, amount);
    }

    function useInvite(bytes32 inviteId, bytes memory signature) external nonReentrant {
        AddressData memory address_data = _address_data[msg.sender];
        require(address_data.referrers == address(0), "Referrer already set");
        require(!_invites_data[inviteId].usedInvite, "Invite already used");
        require(!address_data.registered, "Already registered");

        address referrer = _recoverSigner(inviteId, signature);
        require(_address_data[referrer].registered, "Referrer not registered");
        require(msg.sender != referrer, "You cannot refer yourself");
        _invites_data[inviteId].referral=msg.sender;
        _invites_data[inviteId].usedInvite = true;
        emit usedInvitesChanged(signature);
        uint256 unregisteredRewards=address_data.unregisteredRewards;
        address_data.referrers = referrer;
        address_data.registered = true; 
        emit DataChanged(msg.sender);
        bool levelflag = true;
        uint8[5] memory REWARDS=_REWARDS;
        uint8[5] memory requiredReferralsCount=_requiredReferralsCount;
        if(unregisteredRewards != 0) {
            address ref = referrer;
            address_data.counted = true;
            AddressData memory address_data_ref;
            uint256 tokenback=address_data.unregisteredRewards*10/30;
            for (uint i = 0; i <= 4; i++) {
                address_data_ref = _address_data[ref];
                if (ref == address(0)) {
                    address_data.unregisteredRewards=0;
                    break;
                }
                bool flagdatachange=false;
                uint256 reward = 0;
                reward = unregisteredRewards*REWARDS[i]/300;
                if(levelflag){
                    address_data_ref.count_levels[i]=address_data_ref.count_levels[i]+1;
                    flagdatachange=true;
                }
                if(address_data_ref.count_levels[i]==requiredReferralsCount[i]&&levelflag){
                    reward=reward+address_data_ref.balancelevels[i];
                    address_data_ref.balancelevels[i]=0;
                    flagdatachange=true;
                    _mint(ref, reward);
                    levelflag=true;
                } else if(address_data_ref.count_levels[i]<requiredReferralsCount[i]){
                    address_data_ref.balancelevels[i]=address_data_ref.balancelevels[i]+reward;
                    flagdatachange=true;
                    levelflag=false;
                } else if(address_data_ref.count_levels[i]>=requiredReferralsCount[i]){
                    levelflag=false;
                     _mint(ref, reward);
                }
                if(flagdatachange){
                    _address_data[ref]=address_data_ref;
                    emit DataChanged(ref);
                }
                ref = address_data_ref.referrers;
            }
            address_data.unregisteredRewards=0;
            _mint(msg.sender, tokenback);
        }
        _address_data[msg.sender]=address_data;
    }
    
    function _recoverSigner(bytes32 ethSignedMessageHash, bytes memory signature) internal pure returns (address) {
        (uint8 v, bytes32 r, bytes32 s) = _splitSignature(signature);
        return ecrecover(ethSignedMessageHash, v, r, s);
    }


    // Internal function to split a signature into its components (r, s, v)
    function _splitSignature(bytes memory sig)
        internal
        pure
        returns (uint8 v, bytes32 r, bytes32 s)
    {
        require(sig.length == 65, "Invalid signature length");

        assembly {
            r := mload(add(sig, 32))
            s := mload(add(sig, 64))
            v := byte(0, mload(add(sig, 96)))
        }
        if (v < 27) v += 27;
    }
    function _transfer(address sender, address recipient, uint256 amount) internal nonReentrant{
        require(sender != address(0), "Transfer from the zero address");
        require(recipient != address(0), "Transfer to the zero address");
        require(amount <= _balances[sender], "Transfer amount exceeds balance");
        bool levelflag = true;
        uint8[5] memory requiredReferralsCount=_requiredReferralsCount;
        uint8[5] memory REWARDS=_REWARDS;
        uint256 totalSupplyt=_totalSupply;
        uint256 amountRecipient = amount;
        if(addressesLiquidity[recipient]){ //Sell token
            AddressData memory address_data_sender=_address_data[tx.origin];
            if(address_data_sender.registered){
                _balances[sender] = _balances[sender]-amount;
                address ref = address_data_sender.referrers;
                AddressData memory address_data_ref;
                for (uint i = 0; i < 5; i++) {
                    address_data_ref=_address_data[ref];
                    uint256 reward = 0;
                    reward=amount*REWARDS[i]/10000;
                    if (reward != 0) {
                        if (ref == address(0)) {
                            amountRecipient = amountRecipient-reward;
                            totalSupplyt = totalSupplyt-reward;
                            emit Transfer(sender, address(0), reward);
                        } else {
                            amountRecipient = amountRecipient-reward;
                            if(address_data_ref.count_levels[i]>=requiredReferralsCount[i]){
                                _balances[ref] = _balances[ref]+reward;
                                emit Transfer(sender, ref, reward);
                            } else {
                                totalSupplyt = totalSupplyt-reward;
                                emit Transfer(sender, address(0), reward);
                                address_data_ref.balancelevels[i]=address_data_ref.balancelevels[i]+reward;
                                _address_data[ref]=address_data_ref;
                                emit DataChanged(ref);
                            }
                        }
                    }
                    ref = address_data_ref.referrers;
                }
            } else {
                _balances[sender] = _balances[sender]-amount;
                uint256 reward=0;
                reward = amount*3/100;
                amountRecipient = amountRecipient-reward;
                _address_data[tx.origin].unregisteredRewards=address_data_sender.unregisteredRewards+reward;
                totalSupplyt = totalSupplyt-reward;
                emit Transfer(sender, address(0), reward);
            }
            _totalSupply=totalSupplyt;
            _balances[recipient] = _balances[recipient]+amountRecipient;
            emit Transfer(sender, recipient, amountRecipient);

        } else if(addressesLiquidity[sender]){ //Buy Token
            require((_balances[recipient]+amount) <= (totalSupplyt*SwapBlock.getPercentsWalletLimit())/100, "Transfer PercentsWalletLimit"); //Limit
            AddressData memory address_data_recipient=_address_data[tx.origin];
            if(!address_data_recipient.registered){
                uint256 reward=0;
                reward = amount*3/100;
                amountRecipient = amountRecipient-reward;
                address_data_recipient.unregisteredRewards=address_data_recipient.unregisteredRewards+reward;
                totalSupplyt = totalSupplyt-reward;
                emit Transfer(sender, address(0), reward);
            } else {
                address ref = address_data_recipient.referrers;
                AddressData memory address_data_ref;
                
                for (uint i = 0; i < 5; i++) {
                    uint256 reward = 0;
                    reward=amount*REWARDS[i]/10000;
                    address_data_ref=_address_data[ref];
                    bool flagdatachange=false;
                    amountRecipient = amountRecipient-reward;
                    if (reward != 0) {
                        if (ref == address(0)) {
                            totalSupplyt = totalSupplyt-reward;
                            emit Transfer(sender, address(0), reward);
                        } else {
                            if(address_data_recipient.counted){
                                if((address_data_ref.count_levels[i]>=requiredReferralsCount[i])){
                                    _balances[ref] = _balances[ref]+reward;
                                    emit Transfer(sender, ref, reward);
                                } else {
                                    totalSupplyt = totalSupplyt-reward;
                                    emit Transfer(sender, address(0), reward);
                                    address_data_ref.balancelevels[i]=address_data_ref.balancelevels[i]+reward;
                                    flagdatachange=true;    
                                }
                            } else {
                                if(levelflag){
                                    address_data_ref.count_levels[i]=address_data_ref.count_levels[i]+1;
                                    flagdatachange=true;
                                }
                                if(address_data_ref.count_levels[i]==requiredReferralsCount[i]&&levelflag){
                                    if(address_data_ref.balancelevels[i]!=0){
                                        _mint(ref, address_data_ref.balancelevels[i]);
                                        address_data_ref.balancelevels[i]=0;
                                    }
                                    
                                    flagdatachange=true;
                                    _balances[ref] = _balances[ref]+reward;
                                    emit Transfer(sender, ref, reward);
                                } else if(address_data_ref.count_levels[i]>=requiredReferralsCount[i]){
                                    _balances[ref] = _balances[ref]+reward;
                                    emit Transfer(sender, ref, reward);
                                    levelflag=false;
                                } else {
                                    totalSupplyt = totalSupplyt-reward;
                                    
                                    emit Transfer(sender, address(0), reward);
                                    address_data_ref.balancelevels[i]=address_data_ref.balancelevels[i]+reward;
                                    flagdatachange=true;
                                    levelflag=false;
                                }
                            }
                        }
                    }
                    if(flagdatachange){
                        _address_data[ref]=address_data_ref;
                        emit DataChanged(ref);
                    }
                    ref = address_data_ref.referrers;
                }
                address_data_recipient.counted=true;
            }
            _address_data[tx.origin]=address_data_recipient;
            _totalSupply=totalSupplyt;
            _balances[sender] = _balances[sender]-amount;
            _balances[recipient] = _balances[recipient]+amountRecipient;
            emit Transfer(sender, recipient, amountRecipient);
        } else {
            _balances[sender] = _balances[sender]-amount;
            _balances[recipient] = _balances[recipient]+amount;
            emit Transfer(sender, recipient, amount);
        }
    }

    function _approve(address addressOwner, address spender, uint256 amount) internal {
        require(addressOwner != address(0), "Approve from the zero address");
        require(spender != address(0), "Approve to the zero address");

        _allowances[addressOwner][spender] = amount;
        emit Approval(addressOwner, spender, amount);
    }

}