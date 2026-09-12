// PAYPHONE dialer extension for SOUND MACHINES session
// by 0xDEAFBEEF
// March 2024

//SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

abstract contract extPhoneCard  {
  function balanceOf(address owner) external virtual view returns (uint256);
  function tokenOfOwnerByIndex(address owner, uint256 i) external virtual view returns (uint256);
}

contract PayPhoneMoMA  {
  extPhoneCard public phonecard;

  uint256 public last_dial_ts;
  uint256 public dial_index;
  uint256 public callsRemaining;

  uint256 public phonecard_range_lo;
  uint256 public phonecard_range_hi;    
  address _owner;

  uint256 public callRateLimit;
  uint256 public callRateLimit_phonecard;
  bool public inTheOffice;
  uint256 _dialCost1;
  uint256 _dialCost2;
  uint256 _dialCostMode;
  uint256 _dialCostBegin;  
  uint256 _dialCostLen;

  uint256 public maxMsgLength;
  event DialEvent(address from, string m,uint256 dial_id);

  struct dialStruct {
    address from;
    uint256 ts;
    string m; //optionally store the message in contract storage
  }
   
  mapping (uint256 => dialStruct) public dials;
  mapping (address => uint256) public last_dial_ts_phonecard;

  modifier onlyOwner() {
    require(_owner == msg.sender, "only owner");
    _;
  }

  constructor() {
    address _phonecard_contract_address = 0x1D9787369B1DCf709f92Da1d8743c2A4b6028a83;
    phonecard = extPhoneCard(_phonecard_contract_address);
    _owner = msg.sender;

    dial_index = 1000000; 
    inTheOffice = false;
    callsRemaining = 0;
    callRateLimit = 10; //communal rate limit for public
    callRateLimit_phonecard = 60*1; // individual rate limits for phone card holders
    _dialCost1 = 25000000000; //calls cost 25 Gwei, unless you have a prepaid phonecard
    maxMsgLength=2000;

    phonecard_range_lo = 339348595130070749814751437599411258966098496;
    phonecard_range_hi = 339348595130070749814751437599411258966098525;
  }

  function hasPhoneCard() public view returns (bool) {
    if (address(phonecard)==0x0000000000000000000000000000000000000000) return false;
    uint256 n = phonecard.balanceOf(msg.sender);
    if (n==0) return false;
    for (uint256 i=0;i<n;i++) {
      uint256 tid = phonecard.tokenOfOwnerByIndex(msg.sender,i);
      if (tid >= phonecard_range_lo && tid <= phonecard_range_hi) {
	return true;
      }
    }
    return false;
  }

  function dial(string calldata m) payable public {
    require(inTheOffice==true,"Please call back during business hours.");
    require(callsRemaining > 0,"Order book is full for now. Call back later.");
    require(bytes(m).length < maxMsgLength, "Message too long");
        
    if (hasPhoneCard()) {
      //no cost for prepaid phonecard holders.

      //rate limit is on individual basis. only one call every 3 minutes.
      require(block.timestamp - last_dial_ts_phonecard[msg.sender] > callRateLimit_phonecard,"Phone card holders have priority, but are limited to 1 call per minute. Wait [callRateLimit_phoneCard] seconds before calling back.");

      last_dial_ts_phonecard[msg.sender] = block.timestamp;
    } else {
      // 
      require(msg.value>=dialCost(), "Must send [dialCost] to dial");
      require(block.timestamp - last_dial_ts > callRateLimit,"Busy signal. Wait [callRateLimit] seconds before calling back.");

      last_dial_ts = block.timestamp;
    }
        
    dial_index++;
    callsRemaining--;
    emit DialEvent(msg.sender,m,dial_index-1);    
  }

  //seconds remaining in rate limiting
  function timeRemaining() public view returns (uint256) { 
    uint256 a = block.timestamp - last_dial_ts;
    if (a > callRateLimit) {
      return 0;
    }  else {
      return callRateLimit - a;
    }
  }

  //seconds remaining in phonecard holder rate limiting (on per user basis)
  function timeRemaining_phonecard() public view returns (uint256) { 
    if (!hasPhoneCard()) return 999999; //if not phonecard holder, time remaining is infinite

    uint256 a = block.timestamp - last_dial_ts_phonecard[msg.sender];
    if (a > callRateLimit_phonecard) {
      return 0;
    }  else {
      return callRateLimit_phonecard - a;
    }
  }

  function setMaxMsgLength(uint256 a) public onlyOwner {
    maxMsgLength=a;
  }
  
  function setDialCost(uint256 mode, uint256 t, uint256 a, uint256 b) public onlyOwner {
    _dialCost1 = a;
    _dialCost2 = b;
    _dialCostMode = mode;
    _dialCostBegin = block.timestamp;
    if (t <= 0) t = 1;
    
    _dialCostLen = t;
  }

  function dialCost() public view returns (uint256) {
    //in mode 0, fixed dialCost equal to _dialCost1
    if (_dialCostMode ==0) return _dialCost1;

    //in mode 1, linearly descending cost from _dialCost1 to _dialCost2 over time _dialCostLen 
    uint256 am = ((block.timestamp - _dialCostBegin)*1000) / _dialCostLen;
    if (am > 1000 ) am = 1000; //clamp to 1000;
    if (am < 0) am = 0;
    uint256 cost = _dialCost2*am + _dialCost1 * (1000-am);
    cost /= 1000;
    return cost;
  }

    // all calls get event logged as DialEvent, but for prompts that interpreted, also manually
    // permanently store details, including the message, in contract storage

    function storeDialMessage(uint256 dialId, address from, uint256 ts, string calldata m) public onlyOwner {
        require(dialId < dial_index, "Dial Index out of range.");
        dials[dialId].m = m;
        dials[dialId].ts = ts;
        dials[dialId].from = from;
    }

  //enable
  function setInTheOffice(bool a) public onlyOwner {
    inTheOffice = a;
  }

  //set the number of calls allowed during a shift
  function setCallsRemaining(uint256 a) public onlyOwner {
    callsRemaining = a;
  }
    
  function withdraw() public onlyOwner {
    payable(msg.sender).transfer(address(this).balance);
  }

  //set the allowable minimum number of seconds between calls
  function setCallRateLimit(uint256 a) public onlyOwner {
    callRateLimit = a;
  }

  //set the allowable minimum number of seconds between calls
  function setCallRateLimit_phonecard(uint256 a) public onlyOwner {
    callRateLimit_phonecard = a;
  }
  
  function setPhoneCardContractAddress(address _phonecard_contract_address) public onlyOwner {
    phonecard = extPhoneCard(_phonecard_contract_address);
  }

  //Set inclusive token ID range
  function setPhoneCardTokenRange(uint256 lo, uint256 hi) public onlyOwner {
    phonecard_range_lo = lo;
    phonecard_range_hi = hi;
  }
  
}