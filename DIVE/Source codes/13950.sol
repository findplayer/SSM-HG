/**
 *                                                        
 *   TTTTTTTTTTTTTTTTTTTTTTTRRRRRRRRRRRRRRRRR   IIIIIIIIII     
 *   T:::::::::::::::::::::TR::::::::::::::::R  I::::::::I     
 *   T:::::::::::::::::::::TR::::::RRRRRR:::::R I::::::::I     
 *   T:::::TT:::::::TT:::::TRR:::::R     R:::::RII::::::II     
 *   TTTTTT  T:::::T  TTTTTT  R::::R     R:::::R  I::::I       
 *           T:::::T          R::::R     R:::::R  I::::I       
 *           T:::::T          R::::RRRRRR:::::R   I::::I       
 *           T:::::T          R:::::::::::::RR    I::::I       
 *           T:::::T          R::::RRRRRR:::::R   I::::I       
 *           T:::::T          R::::R     R:::::R  I::::I       
 *           T:::::T          R::::R     R:::::R  I::::I       
 *           T:::::T          R::::R     R:::::R  I::::I       
 *         TT:::::::TT      RR:::::R     R:::::RON::::::II     
 *         T:::::::::T      R::::::R     R:::::RI::::::::I     
 *         T:::::::::T      R::::::R     R:::::RI::::::::I     
 *         TTTTTTTTTTT      RRRRRRRR     RRRRRRRIIIIIIIIII
 *                                         DeFiance.app
 */

// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

/// @custom:security-contact security@defiance.app
contract DeFianceTRI {

    string public constant name = "DeFiance TRI";
    string public constant symbol = "TRI";
    uint8 public constant decimals = 18;

    uint256 constant UINT256_MAX = type(uint256).max;

    uint256 immutable public totalSupply;

    mapping(address => uint) public nonces;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    bytes32 public immutable DOMAIN_SEPARATOR;
    bytes32 public constant PERMIT_TYPEHASH = keccak256(
        "Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"
    );

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    constructor() {
        totalSupply = 1000000000 * 10 ** decimals;
        
        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes(name)),
                keccak256(bytes("1")),
                block.chainid,
                address(this)
            )
        );

        unchecked {
            balanceOf[address(msg.sender)] = balanceOf[address(msg.sender)] + totalSupply;
        }

        emit Transfer(address(0), address(msg.sender), totalSupply);
    }

    function approve(address spender, uint256 value) external returns (bool) {
        _approve(msg.sender, spender, value);

        return true;
    }

    function increaseAllowance(address spender, uint256 addedValue) external returns (bool) {
        _approve(msg.sender, spender, allowance[msg.sender][spender] + addedValue);

        return true;
    }

    function decreaseAllowance(address spender, uint256 subtractedValue) external returns (bool) {
        _approve(msg.sender, spender, allowance[msg.sender][spender] - subtractedValue);

        return true;
    }

    function transfer(address to, uint256 value) external returns (bool) {
        _transfer(msg.sender, to, value);

        return true;
    }

    function transferFrom(address from, address to, uint256 value) external returns (bool) {
        if (allowance[from][msg.sender] != UINT256_MAX) {
            allowance[from][msg.sender] -= value;
        }

        _transfer(from, to, value);

        return true;
    }

    function permit(address owner, address spender, uint256 value, uint256 deadline, uint8 v, bytes32 r, bytes32 s) external {
        require(deadline >= block.timestamp, "DeFianceTRI: PERMIT_CALL_EXPIRED");

        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                DOMAIN_SEPARATOR,
                keccak256(
                    abi.encode(
                        PERMIT_TYPEHASH,
                        owner,
                        spender,
                        value,
                        nonces[owner]++,
                        deadline
                    )
                )
            )
        );

        if (uint256(s) > 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A0) {
            revert("DeFianceTRI: INVALID_SIGNATURE");
        }

        address signer = ecrecover(digest, v, r, s);

        require(signer != address(0) && signer == owner, "DeFianceTRI: INVALID_SIGNATURE");

        _approve(owner, spender, value);
    }
    
    function _approve(address owner, address spender, uint256 value) private {
        allowance[owner][spender] = value;

        emit Approval(owner, spender, value);
    }

    function _transfer(address from, address to, uint256 value) private {
        balanceOf[from] = balanceOf[from] - value;

        unchecked {
            balanceOf[to] = balanceOf[to] + value;
        }

        allowance[from][to] = 0;

        emit Transfer(from, to, value);
    }
}