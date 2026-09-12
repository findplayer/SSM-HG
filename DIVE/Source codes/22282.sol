pragma solidity >=0.4.22 <0.9.0;

contract SendMessageToSomeone {
    event Message(address indexed sender, address indexed receiver, string message);

    function sendMessage(address payable receiver, string memory message) public payable {
        // Require the sent value to be no more than 0.01 Ether
        require(msg.value <= 0.01 ether, "You can send up to 0.01 Ether.");

        // Transfer the Ether to the receiver
        receiver.transfer(msg.value);

        // Emit the message event
        emit Message(msg.sender, receiver, message);
    }
}