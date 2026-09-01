pragma solidity ^0.5.9;





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














library SafeMath {









    function add(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c = a + b;
        require(c >= a, "SafeMath: addition overflow");

        return c;
    }










    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b <= a, "SafeMath: subtraction overflow");
        uint256 c = a - b;

        return c;
    }










    function mul(uint256 a, uint256 b) internal pure returns (uint256) {
        
        
        
        if (a == 0) {
            return 0;
        }

        uint256 c = a * b;
        require(c / a == b, "SafeMath: multiplication overflow");

        return c;
    }












    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        
        require(b > 0, "SafeMath: division by zero");
        uint256 c = a / b;
        

        return c;
    }












    function mod(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b != 0, "SafeMath: modulo by zero");
        return a % b;
    }
}

pragma experimental ABIEncoderV2;








































contract ReverseRegistrar {
    function setName(string memory name) public returns (bytes32);
}

contract Etherclear {
    

    
    
    
    
    
    event PaymentOpened(
        uint txnId,
        uint holdTime,
        uint openTime,
        uint closeTime,
        address token,
        uint sendAmount,
        address indexed sender,
        address indexed recipient,
        bytes codeHash
    );
    event PaymentClosed(
        uint txnId,
        uint holdTime,
        uint openTime,
        uint closeTime,
        address token,
        uint sendAmount,
        address indexed sender,
        address indexed recipient,
        bytes codeHash,
        uint state
    );

    
    
    enum PaymentState {OPEN, COMPLETED, CANCELLED}
    
    
    enum CompletePaymentRequestType {CANCEL, RETRIEVE}

    
    
    struct Payment {
        
        uint holdTime;
        uint paymentOpenTime;
        uint paymentCloseTime;
        
        address token;
        uint sendAmount;
        address payable sender;
        address payable recipient;
        bytes codeHash;
        PaymentState state;
    }

    ReverseRegistrar reverseRegistrar;

    
    
    
    
    
    struct CompletePaymentRequest {
        uint txnId;
        address sender;
        address recipient;
        
        string passphrase;
        
        uint requestType;
    }

    
    mapping(uint => Payment) openPayments;

    
    address payable public owner;
    
    
    
    uint public baseFee;
    uint public paymentFee;
    
    mapping(address => mapping(address => uint)) public tokens;

    
    
    
    bool public createPaymentEnabled;
    
    bool public retrieveFundsEnabled;

    address constant verifyingContract = 0x1C56346CD2A2Bf3202F771f50d3D14a367B48070;
    bytes32 constant salt = 0xf2d857f4a3edcb9b78b4d503bfe733db1e3f6cdc2b7971ee739626c97e86a558;
    string private constant COMPLETE_PAYMENT_REQUEST_TYPE = "CompletePaymentRequest(uint256 txnId,address sender,address recipient,string passphrase,uint256 requestType)";
    string private constant EIP712_DOMAIN_TYPE = "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract,bytes32 salt)";
    bytes32 private constant EIP712_DOMAIN_TYPEHASH = keccak256(
        abi.encodePacked(EIP712_DOMAIN_TYPE)
    );
    bytes32 private constant COMPLETE_PAYMENT_REQUEST_TYPEHASH = keccak256(
        abi.encodePacked(COMPLETE_PAYMENT_REQUEST_TYPE)
    );
    bytes32 private DOMAIN_SEPARATOR;
    
    
    uint256 public chainId;

    function hashCompletePaymentRequest(CompletePaymentRequest memory request)
        private
        view
        returns (bytes32 hash)
    {
        return keccak256(
            abi.encodePacked(
                "\x19\x01",
                DOMAIN_SEPARATOR,
                keccak256(
                    abi.encode(
                        COMPLETE_PAYMENT_REQUEST_TYPEHASH,
                        request.txnId,
                        request.sender,
                        request.recipient,
                        keccak256(bytes(request.passphrase)),
                        request.requestType
                    )
                )
            )
        );
    }

    
    function getSignerForPaymentCompleteRequest(
        uint256 txnId,
        address sender,
        address recipient,
        string memory passphrase,
        uint requestType,
        bytes32 sigR,
        bytes32 sigS,
        uint8 sigV
    ) public view returns (address result) {
        CompletePaymentRequest memory request = CompletePaymentRequest(
            txnId,
            sender,
            recipient,
            passphrase,
            requestType
        );
        address signer = ecrecover(
            hashCompletePaymentRequest(request),
            sigV,
            sigR,
            sigS
        );
        return signer;
    }

    constructor(uint256 _chainId) public {
        owner = msg.sender;
        baseFee = 0.001 ether;
        paymentFee = 0.005 ether;
        createPaymentEnabled = true;
        retrieveFundsEnabled = true;
        chainId = _chainId;
        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                EIP712_DOMAIN_TYPEHASH,
                keccak256("Etherclear"),
                keccak256("1"),
                chainId,
                verifyingContract,
                salt
            )
        );
    }

    modifier onlyOwner {
        require(
            msg.sender == owner,
            "Only the contract owner is allowed to use this function."
        );
        _;
    }




    function setENS(address reverseRegistrarAddr, string memory name)
        public
        onlyOwner
    {
        reverseRegistrar = ReverseRegistrar(reverseRegistrarAddr);
        reverseRegistrar.setName(name);

    }

    function withdrawFees(address token) external onlyOwner {
        
        uint total = tokens[token][owner];
        tokens[token][owner] = 0;
        if (token == address(0)) {
            owner.transfer(total);
        } else {
            require(
                IERC20(token).transfer(owner, total),
                "Could not successfully withdraw token"
            );
        }
    }

    function viewBalance(address token, address user)
        external
        view
        returns (uint balance)
    {
        return tokens[token][user];
    }

    
    
    function changeBaseFee(uint newFee) external onlyOwner {
        baseFee = newFee;
    }
    function changePaymentFee(uint newFee) external onlyOwner {
        paymentFee = newFee;
    }

    function disableRetrieveFunds(bool disabled) public onlyOwner {
        retrieveFundsEnabled = !disabled;
    }

    function disableCreatePayment(bool disabled) public onlyOwner {
        createPaymentEnabled = !disabled;
    }

    function getPaymentInfo(uint paymentID)
        external
        view
        returns (
            uint holdTime,
            uint paymentOpenTime,
            uint paymentCloseTime,
            address token,
            uint sendAmount,
            address sender,
            address recipient,
            bytes memory codeHash,
            uint state
        )
    {
        Payment memory txn = openPayments[paymentID];
        return (
            txn.holdTime,
            txn.paymentOpenTime,
            txn.paymentCloseTime,
            txn.token,
            txn.sendAmount,
            txn.sender,
            txn.recipient,
            txn.codeHash,
            uint(txn.state)
        );
    }

    function cancelPaymentAsSender(uint txnId) external {
        
        Payment memory txn = openPayments[txnId];
        require(
            txn.sender == msg.sender,
            "Payment sender does not match message sender."
        );
        require(
            txn.state == PaymentState.OPEN,
            "Payment must be open to cancel."
        );
        cancelPayment(txnId);
    }

    
    
    function cancelPayment(uint txnId) private {
        
        Payment memory txn = openPayments[txnId];

        
        txn.paymentCloseTime = now;
        txn.state = PaymentState.CANCELLED;

        delete openPayments[txnId];

        
        if (txn.token == address(0)) {
            tokens[address(0)][txn.sender] = SafeMath.sub(
                tokens[address(0)][txn.sender],
                txn.sendAmount
            );
            txn.sender.transfer(txn.sendAmount);
        } else {
            withdrawToken(txn.token, txn.sender, txn.sender, txn.sendAmount);
        }

        emit PaymentClosed(
            txnId,
            txn.holdTime,
            txn.paymentOpenTime,
            txn.paymentCloseTime,
            txn.token,
            txn.sendAmount,
            txn.sender,
            txn.recipient,
            txn.codeHash,
            uint(txn.state)
        );
    }











    
    
    function transferToken(
        address token,
        address user,
        uint originalAmount,
        uint feeAmount
    ) internal {
        require(token != address(0));
        
        
        require(
            IERC20(token).transferFrom(
                user,
                address(this),
                SafeMath.add(originalAmount, feeAmount)
            )
        );
        
        tokens[token][user] = SafeMath.add(
            tokens[token][msg.sender],
            originalAmount
        );
        tokens[token][owner] = SafeMath.add(tokens[token][owner], feeAmount);
    }

    
    
    
    function withdrawToken(
        address token,
        address userFrom,
        address userTo,
        uint amount
    ) internal {
        require(token != address(0));
        require(IERC20(token).transfer(userTo, amount));
        tokens[token][userFrom] = SafeMath.sub(tokens[token][userFrom], amount);
    }

    
    
    function createPayment(
        uint amount,
        address payable recipient,
        uint holdTime,
        bytes calldata codeHash
    ) external payable {
        return createTokenPayment(
            address(0),
            amount,
            recipient,
            holdTime,
            codeHash
        );

    }

    
    
    
    
    
    
    function getBalance(address token) external view returns (uint amt) {
        return tokens[token][msg.sender];
    }

    function getPaymentId(address recipient, bytes memory codeHash)
        public
        pure
        returns (uint result)
    {
        bytes memory txnIdBytes = abi.encodePacked(
            keccak256(abi.encodePacked(codeHash, recipient))
        );
        uint txnId = sliceUint(txnIdBytes);
        return txnId;
    }
    
    
    
    
    
    
    function createTokenPayment(
        address token,
        uint amount,
        address payable recipient,
        uint holdTime,
        bytes memory codeHash
    ) public payable {
        
        require(
            createPaymentEnabled,
            "The create payments functionality is currently disabled"
        );
        uint paymentFeeTotal = uint(
            SafeMath.mul(paymentFee, amount) / (1 ether)
        );
        if (token == address(0)) {
            require(
                msg.value >= (
                    SafeMath.add(SafeMath.add(amount, baseFee), paymentFeeTotal)
                ),
                "Message value is not enough to cover amount and fees"
            );
        } else {
            require(
                msg.value >= baseFee,
                "Message value is not enough to cover base fee"
            );
            
            
            
        }

        
        
        
        
        uint txnId = getPaymentId(recipient, codeHash);
        
        require(
            openPayments[txnId].sender == address(0),
            "Payment ID must be unique. Use a different passphrase hash."
        );

        
        Payment memory txn = Payment(
            holdTime,
            now,
            0,
            token,
            amount,
            msg.sender,
            recipient,
            codeHash,
            PaymentState.OPEN
        );

        openPayments[txnId] = txn;

        
        if (token == address(0)) {
            
            tokens[address(0)][msg.sender] = SafeMath.add(
                tokens[address(0)][msg.sender],
                amount
            );

            
            tokens[address(0)][owner] = SafeMath.add(
                tokens[address(0)][owner],
                SafeMath.sub(msg.value, amount)
            );

        } else {
            
            tokens[address(0)][owner] = SafeMath.add(
                tokens[address(0)][owner],
                msg.value
            );
            
            transferToken(token, msg.sender, amount, paymentFeeTotal);
        }

        
        emit PaymentOpened(
            txnId,
            txn.holdTime,
            txn.paymentOpenTime,
            txn.paymentCloseTime,
            txn.token,
            txn.sendAmount,
            txn.sender,
            txn.recipient,
            txn.codeHash
        );

    }

    
    
    
    
    function completePaymentAsProxy(
        uint256 txnId,
        address sender,
        address recipient,
        string memory passphrase,
        uint requestType,
        bytes32 sigR,
        bytes32 sigS,
        uint8 sigV
    ) public {
        CompletePaymentRequest memory request = CompletePaymentRequest(
            txnId,
            sender,
            recipient,
            passphrase,
            requestType
        );
        address signer = ecrecover(
            hashCompletePaymentRequest(request),
            sigV,
            sigR,
            sigS
        );

        require(
            requestType == uint(
                CompletePaymentRequestType.CANCEL
            ) || requestType == uint(CompletePaymentRequestType.RETRIEVE),
            "requestType must be 0 (CANCEL) or 1 (RETRIEVE)"
        );

        if (requestType == uint(CompletePaymentRequestType.RETRIEVE)) {
            require(
                recipient == signer,
                "The message recipient must be the same as the signer of the message"
            );
            Payment memory txn = openPayments[txnId];
            require(
                txn.recipient == recipient,
                "The payment's recipient must be the same as signer of the message"
            );
            retrieveFunds(txn, txnId, passphrase);
        } else {
            require(
                sender == signer,
                "The message sender must be the same as the signer of the message"
            );
            Payment memory txn = openPayments[txnId];
            require(
                txn.sender == sender,
                "The payment's sender must be the same as signer of the message"
            );
            cancelPayment(txnId);
        }
    }

    
    function retrieveFundsAsRecipient(uint txnId, string memory code) public {
        Payment memory txn = openPayments[txnId];

        
        require(
            txn.recipient == msg.sender,
            "Message sender must match payment recipient"
        );
        retrieveFunds(txn, txnId, code);
    }

    
    
    
    
    function retrieveFunds(Payment memory txn, uint txnId, string memory code)
        private
    {
        require(
            retrieveFundsEnabled,
            "The retrieve funds functionality is currently disabled."
        );
        require(
            txn.state == PaymentState.OPEN,
            "Payment must be open to retrieve funds"
        );
        
        bytes memory actualHash = abi.encodePacked(
            keccak256(abi.encodePacked(code, txn.recipient))
        );
        
        require(
            sliceUint(actualHash) == sliceUint(txn.codeHash),
            "Passphrase is not correct"
        );

        
        require(
            (txn.paymentOpenTime + txn.holdTime) > now,
            "Hold time has already expired"
        );

        
        txn.paymentCloseTime = now;
        txn.state = PaymentState.COMPLETED;

        delete openPayments[txnId];

        
        if (txn.token == address(0)) {
            
            
            txn.recipient.transfer(txn.sendAmount);
            tokens[address(0)][txn.sender] = SafeMath.sub(
                tokens[address(0)][txn.sender],
                txn.sendAmount
            );

        } else {
            withdrawToken(txn.token, txn.sender, txn.recipient, txn.sendAmount);
        }

        emit PaymentClosed(
            txnId,
            txn.holdTime,
            txn.paymentOpenTime,
            txn.paymentCloseTime,
            txn.token,
            txn.sendAmount,
            txn.sender,
            txn.recipient,
            txn.codeHash,
            uint(txn.state)
        );

    }

    
    
    function sliceUint(bytes memory bs) public pure returns (uint) {
        uint start = 0;
        if (bs.length < start + 32) {
            return 0;
        }
        uint x;
        assembly {
            x := mload(add(bs, add(0x20, start)))
        }
        return x;
    }

}