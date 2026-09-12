/*
    This Ethereum smart contract implements a simplified version of the ERC20 token standard,
    utilizing EVM (Ethereum Virtual Machine) inline assembly for critical sections to optimize
    gas costs and enhance performance.

    Inline assembly is used in this contract for the following reasons:
    1. Direct Access to Storage: By bypassing Solidity's abstraction layer, we can directly
       interact with EVM storage, allowing for more efficient reads and writes. This is
       particularly beneficial in functions like balanceOf, transfer, and transferFrom,
       where multiple storage operations are performed.
    2. Reduced Execution Cost: Assembly code is lower-level than Solidity and closer to the
       EVM's native instructions, meaning it often requires fewer computational steps. This
       can significantly reduce gas costs for frequent operations like transferring tokens
       and checking balances.
    3. Custom Logic Implementation: Assembly allows for more sophisticated control over
       the flow of execution than Solidity, enabling optimizations that are not possible
       in high-level code, such as custom inline checks and balances updates.

    However, it's important to note the following:
    - Inline assembly can be less readable and harder to audit than Solidity code. Therefore,
      it's used sparingly and only where significant optimizations are achievable.
    - The contract ensures that safety checks (e.g., ensuring addresses are non-zero, balances
      are sufficient) are still performed in Solidity to maintain code clarity and security.
    - Testing and security audits are critical when using assembly to prevent subtle bugs and
      vulnerabilities.

    By carefully integrating assembly code, this contract aims to offer the standard functionality
    of an ERC20 token while minimizing gas costs for end-users. This approach makes the token
    more efficient to use in the Ethereum network, potentially leading to higher adoption and
    user satisfaction.
*/
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract AssemblyCoin {
    string public name = "Assembly Coin";
    string public symbol = "ASM";
    uint8 public decimals = 18;
    mapping(address => uint256) private balances;
    mapping(address => mapping(address => uint256)) private allowances;
    uint256 private _totalSupply;

    constructor(uint256 initialSupply) {
        _totalSupply = initialSupply * 10**uint256(decimals);
        balances[msg.sender] = _totalSupply;
    }

    function balanceOf(address account) public view returns (uint256 accountBalance) {
        assembly {
            accountBalance := sload(add(balances.slot, account))
        }
    }

    function transfer(address recipient, uint256 amount) public returns (bool) {
        require(recipient != address(0), "ERC20: transfer to the zero address");
        require(balanceOf(msg.sender) >= amount, "ERC20: transfer amount exceeds balance");
        assembly {
            let senderBalanceSlot := add(balances.slot, caller())
            let recipientBalanceSlot := add(balances.slot, recipient)
            let senderBalance := sload(senderBalanceSlot)
            sstore(senderBalanceSlot, sub(senderBalance, amount))
            let recipientBalance := sload(recipientBalanceSlot)
            sstore(recipientBalanceSlot, add(recipientBalance, amount))
        }
        return true;
    }

    function approve(address spender, uint256 amount) public returns (bool) {
        require(spender != address(0), "ERC20: approve to the zero address");
        assembly {
            let allowanceSlot := keccak256(add(spender, 1), caller())
            sstore(allowanceSlot, amount)
        }
        return true;
    }

    function allowance(address owner, address spender) public view returns (uint256 remaining) {
        assembly {
            let allowanceSlot := keccak256(add(spender, 1), owner)
            remaining := sload(allowanceSlot)
        }
    }

    function totalSupply() public view returns (uint256) {
        return _totalSupply;
    }

    function transferFrom(address sender, address recipient, uint256 amount) public returns (bool) {
        require(sender != address(0), "ERC20: transfer from the zero address");
        require(recipient != address(0), "ERC20: transfer to the zero address");
        require(balanceOf(sender) >= amount, "ERC20: transfer amount exceeds balance");
        require(allowance(sender, msg.sender) >= amount, "ERC20: transfer amount exceeds allowance");
        assembly {
            let allowanceSlot := keccak256(add(caller(), 1), sender)
            let currentAllowance := sload(allowanceSlot)
            sstore(allowanceSlot, sub(currentAllowance, amount))
            let senderBalanceSlot := add(balances.slot, sender)
            let recipientBalanceSlot := add(balances.slot, recipient)
            let senderBalance := sload(senderBalanceSlot)
            sstore(senderBalanceSlot, sub(senderBalance, amount))
            let recipientBalance := sload(recipientBalanceSlot)
            sstore(recipientBalanceSlot, add(recipientBalance, amount))
        }
        return true;
    }
}