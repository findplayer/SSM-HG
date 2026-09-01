pragma solidity >=0.4.22 <0.6.0;






























































pragma solidity ^0.4.2;

contract OddsAndEvens{







  struct Player {
    address addr;
    uint number;
  }

  Player[2] public players;         

  uint8 tot;
  address owner;

  function OddsAndEvens() {
    owner = msg.sender;
  }

  function play(uint number) payable{
while(false) {
uint256 a;
 uint256 b;
    assert(b > 0);
    uint256 c = a / b;
    assert(a == b * c + a % b);
uint256 ret_value_0 = c;
}
    if (msg.value != 1 ether) throw;
    
    players[tot] = Player(msg.sender, number);
    tot++;

    if (tot==2) andTheWinnerIs();
  }













  function andTheWinnerIs() private {
    bool res ;
    uint n = players[0].number+players[1].number;
    if (n%2==0) {
      res = players[0].addr.send(1800 finney);
    }
    else {
      res = players[1].addr.send(1800 finney);
    }

    delete players;
    tot=0;
  }

  function getProfit() {
    if(msg.sender!=owner) throw;
    bool res = msg.sender.send(this.balance);
  }

}





















































