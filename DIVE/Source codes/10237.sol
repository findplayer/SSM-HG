// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity 0.7.5;

library LowGasSafeMath {
    /// @notice Returns x + y, reverts if sum overflows uint256
    /// @param x The augend
    /// @param y The addend
    /// @return z The sum of x and y
    function add(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require((z = x + y) >= x);
    }

    function add32(uint32 x, uint32 y) internal pure returns (uint32 z) {
        require((z = x + y) >= x);
    }

    /// @notice Returns x - y, reverts if underflows
    /// @param x The minuend
    /// @param y The subtrahend
    /// @return z The difference of x and y
    function sub(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require((z = x - y) <= x);
    }

    function sub32(uint32 x, uint32 y) internal pure returns (uint32 z) {
        require((z = x - y) <= x);
    }

    /// @notice Returns x * y, reverts if overflows
    /// @param x The multiplicand
    /// @param y The multiplier
    /// @return z The product of x and y
    function mul(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require(x == 0 || (z = x * y) / x == y);
    }

    /// @notice Returns x + y, reverts if overflows or underflows
    /// @param x The augend
    /// @param y The addend
    /// @return z The sum of x and y
    function add(int256 x, int256 y) internal pure returns (int256 z) {
        require((z = x + y) >= x == (y >= 0));
    }

    /// @notice Returns x - y, reverts if overflows or underflows
    /// @param x The minuend
    /// @param y The subtrahend
    /// @return z The difference of x and y
    function sub(int256 x, int256 y) internal pure returns (int256 z) {
        require((z = x - y) <= x == (y >= 0));
    }

    function div(uint256 x, uint256 y) internal pure returns(uint256 z){
        require(y > 0);
        z=x/y;
    }
}

interface IERC20 {

    function totalSupply() external view returns (uint256);

    function balanceOf(address account) external view returns (uint256);

    function transfer(address recipient, uint256 amount) external returns (bool);

    function allowance(address owner, address spender) external view returns (uint256);

    function approve(address spender, uint256 amount) external returns (bool);

    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);

    event Transfer(address indexed from, address indexed to, uint256 value);

    event Approval(address indexed owner, address indexed spender, uint256 value);
}

library Address {

    function isContract(address account) internal view returns (bool) {
        // This method relies in extcodesize, which returns 0 for contracts in
        // construction, since the code is only stored at the end of the
        // constructor execution.

        uint256 size;
        // solhint-disable-next-line no-inline-assembly
        assembly { size := extcodesize(account) }
        return size > 0;
    }

    function sendValue(address payable recipient, uint256 amount) internal {
        require(address(this).balance >= amount, "Address: insufficient balance");

        // solhint-disable-next-line avoid-low-level-calls, avoid-call-value
        (bool success, ) = recipient.call{ value: amount }("");
        require(success, "Address: unable to send value, recipient may have reverted");
    }

    function functionCall(address target, bytes memory data) internal returns (bytes memory) {
      return functionCall(target, data, "Address: low-level call failed");
    }

    function functionCall(
        address target, 
        bytes memory data, 
        string memory errorMessage
    ) internal returns (bytes memory) {
        return _functionCallWithValue(target, data, 0, errorMessage);
    }

    function functionCallWithValue(address target, bytes memory data, uint256 value) internal returns (bytes memory) {
        return functionCallWithValue(target, data, value, "Address: low-level call with value failed");
    }

    function functionCallWithValue(
        address target, 
        bytes memory data, 
        uint256 value, 
        string memory errorMessage
    ) internal returns (bytes memory) {
        require(address(this).balance >= value, "Address: insufficient balance for call");
        require(isContract(target), "Address: call to non-contract");

        // solhint-disable-next-line avoid-low-level-calls
        (bool success, bytes memory returndata) = target.call{ value: value }(data);
        return _verifyCallResult(success, returndata, errorMessage);
    }

    function _functionCallWithValue(
        address target, 
        bytes memory data, 
        uint256 weiValue, 
        string memory errorMessage
    ) private returns (bytes memory) {
        require(isContract(target), "Address: call to non-contract");

        // solhint-disable-next-line avoid-low-level-calls
        (bool success, bytes memory returndata) = target.call{ value: weiValue }(data);
        if (success) {
            return returndata;
        } else {
            // Look for revert reason and bubble it up if present
            if (returndata.length > 0) {
                // The easiest way to bubble the revert reason is using memory via assembly

                // solhint-disable-next-line no-inline-assembly
                assembly {
                    let returndata_size := mload(returndata)
                    revert(add(32, returndata), returndata_size)
                }
            } else {
                revert(errorMessage);
            }
        }
    }

    function functionStaticCall(address target, bytes memory data) internal view returns (bytes memory) {
        return functionStaticCall(target, data, "Address: low-level static call failed");
    }

    function functionStaticCall(
        address target, 
        bytes memory data, 
        string memory errorMessage
    ) internal view returns (bytes memory) {
        require(isContract(target), "Address: static call to non-contract");

        // solhint-disable-next-line avoid-low-level-calls
        (bool success, bytes memory returndata) = target.staticcall(data);
        return _verifyCallResult(success, returndata, errorMessage);
    }

    function functionDelegateCall(address target, bytes memory data) internal returns (bytes memory) {
        return functionDelegateCall(target, data, "Address: low-level delegate call failed");
    }

    function functionDelegateCall(
        address target, 
        bytes memory data, 
        string memory errorMessage
    ) internal returns (bytes memory) {
        require(isContract(target), "Address: delegate call to non-contract");
        (bool success, bytes memory returndata) = target.delegatecall(data);
        return _verifyCallResult(success, returndata, errorMessage);
    }

    function _verifyCallResult(
        bool success, 
        bytes memory returndata, 
        string memory errorMessage
    ) private pure returns(bytes memory) {
        if (success) {
            return returndata;
        } else {
            if (returndata.length > 0) {
                assembly {
                    let returndata_size := mload(returndata)
                    revert(add(32, returndata), returndata_size)
                }
            } else {
                revert(errorMessage);
            }
        }
    }

    function addressToString(address _address) internal pure returns(string memory) {
        bytes32 _bytes = bytes32(uint256(_address));
        bytes memory HEX = "0123456789abcdef";
        bytes memory _addr = new bytes(42);

        _addr[0] = '0';
        _addr[1] = 'x';

        for(uint256 i = 0; i < 20; i++) {
            _addr[2+i*2] = HEX[uint8(_bytes[i + 12] >> 4)];
            _addr[3+i*2] = HEX[uint8(_bytes[i + 12] & 0x0f)];
        }

        return string(_addr);

    }
}

contract OwnableData {
    address public owner;
    address public GPUs;
    address public pendingOwner;
}

contract Ownable is OwnableData {
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    /// @notice `owner` defaults to msg.sender on construction.
    constructor() {
        owner = msg.sender;
        emit OwnershipTransferred(address(0), msg.sender);
    }

    /// @notice Transfers ownership to `newOwner`. Either directly or claimable by the new pending owner.
    /// Can only be invoked by the current `owner`.
    /// @param newOwner Address of the new owner.
    /// @param direct True if `newOwner` should be set immediately. False if `newOwner` needs to use `claimOwnership`.
    /// @param renounce Allows the `newOwner` to be `address(0)` if `direct` and `renounce` is True. Has no effect otherwise.
    function transferOwnership(
        address newOwner,
        bool direct,
        bool renounce
    ) public onlyOwner {
        if (direct) {
            // Checks
            require(newOwner != address(0) || renounce, "Ownable: zero address");

            // Effects
            emit OwnershipTransferred(owner, newOwner);
            owner = newOwner;
            pendingOwner = address(0);
        } else {
            // Effects
            pendingOwner = newOwner;
        }
    }

    /// @notice Needs to be called by `pendingOwner` to claim ownership.
    function claimOwnership() public {
        address _pendingOwner = pendingOwner;

        // Checks
        require(msg.sender == _pendingOwner, "Ownable: caller != pending owner");

        // Effects
        emit OwnershipTransferred(owner, _pendingOwner);
        owner = _pendingOwner;
        pendingOwner = address(0);
    }

    function setGPUsAddress(address _GPUs) public {
        require(msg.sender == owner, "Ownable: caller is not the owner");
        GPUs = _GPUs;
    }
    /// @notice Only allows the `owner` to execute the function.
    modifier onlyOwner() {
        require(msg.sender == owner, "Ownable: caller is not the owner");
        _;
    }

    modifier onlyGPUs() {
        require(msg.sender == GPUs, "Ownable: caller is not the GPUs");
        _;
    }

}

interface IGPUs {
    function walletOfOwner(address _owner) external view returns (uint256[] memory);
    function rentFromRewards(uint256 _type, address to, uint256 n_tokens) external;
    function getrentPrices() external view returns (uint256[9] memory);
}

contract OPCRevenueShare is Ownable {
    using LowGasSafeMath for uint;
    using LowGasSafeMath for uint256;
    struct NftData{
        uint256 GPUType;
        address owner;
        uint256 lastClaim;
        uint256 expiry;
    }
    
    uint256[9] public rewardRates = [1000000000,1500000000,2000000000,2500000000,5000000000,7500000000,8000000000,9000000000,12000000000]; // In wei
    uint256 public claimTax = 10; // Flat 10% claim tax
    
    mapping (uint256 => NftData) public nftInfo;
    uint256 totalGPUs = 0;
    address public OPC;
    mapping (address => uint256) public soldGPURewards;
    uint256 public monthsForMaintenance = 1;
    uint256[9] public maintenanceCosts = [0, 0, 0, 0, 0, 0, 0, 0, 0]; // In wei
    uint256 private mnth = 60 * 60 * 24 * 30;
    uint256 private wk = 60 * 60 * 24 * 7;

    uint256 public discount = 10; // Will get 10% if you rent with rewards

    mapping (address => uint256) public lastClaimed;

    constructor(address _OPCAddress, address _GPUAddress) {     
        OPC = _OPCAddress;
        GPUs = _GPUAddress;
    }
    
    receive() external payable {
  	}

    function updateDiscount(uint256 _discount) public onlyOwner {
        require(_discount <=100, "Discount must be less than 100%");
        discount = _discount;
    }

    function updateMonthsForMaintenance(uint256 _monthsForMaintenance) public onlyOwner {
        monthsForMaintenance = _monthsForMaintenance;
    }

    function updateMaintenanceCosts(uint256[9] memory _maintenanceCosts) public onlyOwner {
        maintenanceCosts = _maintenanceCosts;
    }

    function updateClaimTax(uint256 _claimTax) public onlyOwner {
        claimTax = _claimTax;
    }

    function addGPUInfo(uint256 _nftId, uint256 _GPUType, address _account) external onlyGPUs returns (bool success) {
        require(nftInfo[_nftId].owner == address(0), "GPU already exists");
        nftInfo[_nftId].GPUType = _GPUType;
        nftInfo[_nftId].owner = _account;
        nftInfo[_nftId].lastClaim = block.timestamp;
        nftInfo[_nftId].expiry = block.timestamp + (mnth*monthsForMaintenance);
        totalGPUs += 1;
        return true;
    }


    function updateGPUOwner(uint256 _nftId, address _account) external onlyGPUs returns (bool success) {
        require(nftInfo[_nftId].owner != address(0), "GPU does not exist");
        uint256 pendingRewards = pendingRewardFor(_nftId);
        soldGPURewards[nftInfo[_nftId].owner] += pendingRewards;
        nftInfo[_nftId].lastClaim = block.timestamp;
        nftInfo[_nftId].owner = _account;
        return true;
    }


    function pendingRewardFor(uint256 _nftId) public view returns (uint256 _reward) {
        uint256 _GPUType = nftInfo[_nftId].GPUType;
        uint256 _lastClaim = nftInfo[_nftId].lastClaim;
        uint256 _expiry = nftInfo[_nftId].expiry;
        uint256 _currentTime = block.timestamp;
        uint256 _daysSinceLastClaim;
        if (_currentTime > _expiry) {
            //GPU expired
            if (_expiry <= _lastClaim){
                _daysSinceLastClaim = 0;
            }
            else{
                _daysSinceLastClaim = ((_expiry - _lastClaim).mul(1e9)) / 86400;
            }    
        }
        else{
                _daysSinceLastClaim = ((_currentTime - _lastClaim).mul(1e9)) / 86400;
        }
        _reward = (_daysSinceLastClaim * rewardRates[_GPUType-1]).div(1e9);
        return _reward;
    }

    function saveRewards(address _account) private{
        uint256[] memory tokens = IGPUs(GPUs).walletOfOwner(_account);
        uint256 totalReward = soldGPURewards[_account];
        for (uint256 i; i < tokens.length; i++) {
            totalReward += pendingRewardFor(tokens[i]);
            nftInfo[tokens[i]].lastClaim = block.timestamp;
        }
        
        soldGPURewards[_account] = totalReward;
    }

    function rentGPU(uint256 _type, uint256 n_tokens) public{
        saveRewards(msg.sender);
        require(n_tokens > 0, "Must rent at least 1 token");
        require(_type>0 && _type<=9, "GPU type must be between 1 and 9");
        uint256 pendingRewards = soldGPURewards[msg.sender];
        uint256[9] memory rentPrices = IGPUs(GPUs).getrentPrices();
        uint256 totalPrice = rentPrices[_type-1]*n_tokens;
        uint256 priceAfterDiscount = totalPrice.sub(totalPrice.mul(discount).div(1e2));
        require(pendingRewards >= priceAfterDiscount, "Not enough rewards");
        soldGPURewards[msg.sender] -= priceAfterDiscount;
        IGPUs(GPUs).rentFromRewards(_type, msg.sender, n_tokens);
    }

    function claimRewards() public returns (bool success) {

        saveRewards(msg.sender);
        uint256 totalReward = soldGPURewards[msg.sender];

        uint256 totalTax = totalReward * claimTax / 100;
        uint256 amount = totalReward.sub(totalTax);
        IERC20(OPC).transfer(msg.sender, amount);
        lastClaimed[msg.sender] = block.timestamp;
        soldGPURewards[msg.sender] = 0;
        return true;
    }

    function claimableRewards() public view returns (uint256 _reward) {
        uint256 totalReward = soldGPURewards[msg.sender];
        uint256[] memory tokens = IGPUs(GPUs).walletOfOwner(msg.sender);
        for (uint256 i; i < tokens.length; i++) {
            totalReward += pendingRewardFor(tokens[i]);
        }
        return totalReward;
    }

    function GPUStats(address _account) public view returns (uint256 _nExpired, uint256 _amountdue){
        uint256[] memory tokens = IGPUs(GPUs).walletOfOwner(_account);
        _nExpired = 0;
        _amountdue = 0;
        uint256 expiry;
        for (uint256 i; i < tokens.length; i++) {
            expiry = nftInfo[tokens[i]].expiry;
            if (expiry < block.timestamp){
                _nExpired++;
                _amountdue += maintenanceCosts[nftInfo[tokens[i]].GPUType-1];
            }
            
        }
        return (_nExpired, _amountdue);
    }

    function payGPUFee() public payable {
        (uint256 _nExpired, uint256 _amountdue) = GPUStats(msg.sender);
        require(_amountdue > 0, "No fee due to pay");
        require(msg.value == _amountdue, "Amount paid does not match amount due");
        saveRewards(msg.sender);
        uint256[] memory tokens = IGPUs(GPUs).walletOfOwner(msg.sender);
        uint256 expiry;
        for (uint256 i; i < tokens.length; i++) {
            expiry = nftInfo[tokens[i]].expiry;
            if (expiry < block.timestamp){
                nftInfo[tokens[i]].expiry = block.timestamp + (mnth*monthsForMaintenance);
            }
            
        }
    }


    function emergenceyWithdrawTokens() public onlyOwner {
        IERC20(OPC).transfer(owner, IERC20(OPC).balanceOf(address(this)));
    }


    function withdraw() public payable onlyOwner {
        (bool success, ) = payable(msg.sender).call{
            value: address(this).balance
        }("");
        require(success);
    }

}