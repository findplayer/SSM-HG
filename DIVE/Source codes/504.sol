//SPDX-License-Identifier: MIT

pragma solidity 0.8.24;


interface IToken {

    function transferFrom(address from, address to, uint256 amount) external;
}


contract CryptoCadetRouter {

    address owner;
    uint8 fee;

    modifier onlyOwner {
        require(msg.sender == owner, "Not the owner");
        _;
    }

    event NativeTransfer(address indexed sender, uint256 amount, uint256 timestamp, bool received);
    event TokenTransfer(address indexed sender, uint256 amount, uint256 timestamp, bool received);
    event ReferralEarned(address indexed sender, address indexed referrer, uint256 commission, uint256 timestamp);


    constructor(address _owner, uint8 _fee){
        owner = _owner;
        fee = _fee;

    }

    function payWithNative(address _payee) external payable returns (bool){
        require(msg.value > 0, "nonzero amount required");
        uint256 amount = msg.value;
        uint256 tax = (amount * fee)/ 100;
        uint256 remainder = amount - tax;
         (bool success, ) = payable(owner).call{value: tax}("");
        require(success);
        (bool os, ) = payable(_payee).call{value: remainder}("");
        require(os);

        emit NativeTransfer(msg.sender, remainder, block.timestamp, true);

        return true;

    } 
    function payWithNative(address _payee, address _referrer, uint8 _refPercent) external payable returns (bool){
        require(msg.value > 0, "nonzero amount required");
        require(_refPercent <= 100, "referral commission cannot exceed 100 percent");
        uint256 amount = msg.value;
        uint256 tax = (amount * fee)/ 100;
        uint256 commission = ((amount - tax) * _refPercent)/100;
        uint256 remainder = amount - tax - commission;
         (bool success, ) = payable(owner).call{value: tax}("");
        require(success);
        (bool os, ) = payable(_payee).call{value: remainder}("");
        require(os);
        (bool ref, ) = payable(_referrer).call{value: commission}("");
        require(ref);

        emit NativeTransfer(msg.sender, remainder, block.timestamp, true);
        emit ReferralEarned(msg.sender, _referrer, commission, block.timestamp);

        return true;

    } 

    function payWithToken(address _payee, address _token, uint256 _amount) external returns (bool){
        require(_amount > 0, "nonzero amount required");
        IToken token = IToken(_token);
        uint256 tax = (_amount * fee)/ 100;
        uint256 remainder = _amount - tax;
        token.transferFrom(msg.sender, owner, tax);
        token.transferFrom(msg.sender, _payee, remainder);

        emit TokenTransfer(msg.sender, remainder, block.timestamp, true);

        return true;


    }
    function payWithToken(address _payee, address _token, uint256 _amount, address _referrer, uint8 _refPercent) external returns (bool){
        require(_amount > 0, "nonzero amount required");
        require(_refPercent <= 100, "referral commission cannot exceed 100 percent");
        IToken token = IToken(_token);
        uint256 tax = (_amount * fee)/ 100;
        uint256 commission = ((_amount - tax) * _refPercent)/100;
        uint256 remainder = _amount - tax - commission;
        token.transferFrom(msg.sender, owner, tax);
        token.transferFrom(msg.sender, _referrer, commission);
        token.transferFrom(msg.sender, _payee, remainder);

        emit TokenTransfer(msg.sender, remainder, block.timestamp, true);
        emit ReferralEarned(msg.sender, _referrer, block.timestamp, commission);


        return true;


    }


    function setOwner(address _owner) public onlyOwner {
        owner = _owner;
    }

    function setFee(uint8 _fee) public onlyOwner {
        fee = _fee;
    }
}