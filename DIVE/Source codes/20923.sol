pragma solidity >=0.4.22 <0.9.0;

    contract SendMessage {
        event Message(string indexed message);

        function Comment(string memory message) public {
            emit Message(message);
        }
    }