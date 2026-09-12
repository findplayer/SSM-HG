// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

interface ERC721 {
    function safeTransferFrom(address from,address to,uint256 tokenId) external payable;
    function ownerOf(uint256 tokenId) external view returns (address owner);
}

contract NononSlideV0 {

    error MustGas();
    error MustOwn();
    error NotLong();
    error MustAlt();
    error GasSet();

    uint256[] public ids;
    address[] public players;
    uint16 public length;
    uint256 public gas;
    uint8 public gasSet;
    bool public ready;

    ERC721 nonon = ERC721(0xD3607bc8c7927B348bac50dc224C28E3ce933ca6);

    function signUp(uint256 nononId) public payable {
        //cache for gas save
        uint16 _length = length;
        //must provide gas for slide
        if(msg.value < gas){revert MustGas();}
        //cant slide to yourself
        if(_length > 0){
            if(players[_length - 1] == msg.sender){revert MustAlt();}
        }
        //must own nonon
        //OR it is the previous signup id
        if(nonon.ownerOf(nononId) != msg.sender){
            if(_length > 0 && ids[_length-1] != nononId) {
                revert MustOwn();
            }        
        }
        //load slide
        ids[_length] = nononId;
        players[_length] = msg.sender;
        unchecked{
            ++length;
        }
        //if greater than 2 people, ready to slide
        if(_length+1 > 2){ready = true;}
    }

    function slide() public {
        //cache for gas save
        address[] memory _players = players;
        uint256[] memory _ids = ids;
        uint16 _length = length;
        //must have greater than 2 ppl
        if(!ready){revert NotLong();}
        //WEEEEEE!!!!!!!!
        for(uint8 i; i<_length-1;){
            nonon.safeTransferFrom(_players[i], _players[i+1], _ids[i]);
            unchecked{
                ++i;
            }
        }
        //loop back to first player
        nonon.safeTransferFrom(_players[_length-1], _players[0], _ids[_length-1]);
        //person who pays the gas for the slide, gets the gas pot
        payable(msg.sender).transfer(address(this).balance);
        //reload for next slide
        reset();
    }

    function setGas(uint256 newGas) external {
        //set this once you figure out how much gas it costs per head
        if(gasSet > 2){revert GasSet();}
        gas = newGas;
        ++gasSet;
    }

    //in case someone messes up
    function resetSlide() external {
        //cache to save gas
        uint256 _gas = gas;
        address[] memory _players = players;
        //return gas mony
        for(uint8 i; i<length;){
            payable(_players[i]).transfer(_gas);
            unchecked{
                ++i;
            }
        }
        //reset slide
        reset();
    }

    function reset() internal {
        //reset slide
        for(uint8 i; i<length;){
            players[i] = address(0);
            ids[i] = 0;
            unchecked{
                ++i;
            }
        }
        length = 0;
        ready = false;
    }
   
}