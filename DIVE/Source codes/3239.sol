//SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface Token {
    function transfer(address to, uint tokens) external returns (bool success);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool) ;
      function balanceOf(address account) external view returns (uint256);
    function allowance(address owner, address spender) external view returns (uint256);

    }

contract NailsTech_Stake
    {
       
        address  public owner;

        address public Staking_token = 0xbb1e43733D4632955422f92F603F34429ECc8d4c; 

        uint public totalusers;

        uint public per_day_divider= 1 days;
        uint public minimum_investment=100*10**18;
        uint public penalty=10*10**18;

        uint public referral_percentage=5*10**18;

        uint public totalbusiness; 

        struct allInvestments{

            uint investedAmount;
            uint withdrawnTime;
            uint DepositTime;
            uint investmentNum;
            uint unstakeTime;
            bool unstake;
            uint reward;
            uint pending_rew;
            uint apr;
            uint timeframe;


        }



        struct Data{

            mapping(uint=>allInvestments) investment;
            uint noOfInvestment;
            uint totalInvestment;
            uint totalWithdraw_reward;
            bool investBefore;
            uint TotalReferrals_earning;
            address referralFrom;  
            mapping(uint=>ref_data) referralLevel;
            uint totalDirects;
        }

        struct ref_data{
            uint reward;
            uint count;  
        }

        struct time_Apy
        {
            uint timeframe;
            uint APR;
        }

        struct history
        {
            uint events;
            uint amount;
            uint time;


        }
        mapping(address=>Data) public user;
        mapping(uint=>time_Apy) public details;

        mapping(address=>mapping(uint=>allInvestments)) public user_investments;

        constructor(){
            
            owner=msg.sender;              

            details[0].timeframe=90 days;
            details[1].timeframe=30 days;
            details[2].timeframe=7 days;




            details[0].APR=170;
            details[1].APR=50;
            details[2].APR=10;




        }


        modifier onlyOwner() 
        {
            require(msg.sender == owner, "Only owner is allowed to perform this action");
            _;
        }      

        function Stake(uint _investedamount,uint choose_val,address _ref) external returns(bool success)
        {
            require(details[choose_val].APR > 0," apr iss");
            require(_investedamount >= minimum_investment,"value is not greater than minimum investment");     

            require(Token(Staking_token).allowance(msg.sender,address(this))>=_investedamount,"allowance");
            

            if(user[msg.sender].investBefore == false)
            { 

                if(_ref!=address(0) && _ref!=msg.sender) 
                {

                    user[msg.sender].referralFrom=_ref;
                    user[_ref].totalDirects++;

                    uint earning= _investedamount*referral_percentage/100 ether;
                    user[_ref].TotalReferrals_earning+=earning;

                    Token(Staking_token).transfer(_ref,earning);

                }

                totalusers++;                                     
            }

            uint num = user[msg.sender].noOfInvestment;
            user[msg.sender].investment[num].investedAmount =_investedamount;
            user[msg.sender].investment[num].DepositTime=block.timestamp;
            user[msg.sender].investment[num].withdrawnTime=block.timestamp + details[choose_val].timeframe ;  
            
            user[msg.sender].investment[num].investmentNum=num;
            user[msg.sender].investment[num].apr=details[choose_val].APR;
             user[msg.sender].investment[num].timeframe=(details[choose_val].timeframe/per_day_divider) ;  


            user[msg.sender].totalInvestment+=_investedamount;
            user[msg.sender].noOfInvestment++;
            totalbusiness+=_investedamount;



            Token(Staking_token).transferFrom(msg.sender,address(this),_investedamount);
            user_investments[msg.sender][num] = user[msg.sender].investment[num];



            return true;
            
        }

       function get_TotalReward(address userAddress) view public returns(uint){ 
            uint totalReward;
            uint depTime;
            uint rew;
            uint temp = user[userAddress].noOfInvestment;
            for( uint i = 0;i < temp;i++)
            {   
                if(!user[userAddress].investment[i].unstake)
                {
                    if(block.timestamp < user[userAddress].investment[i].withdrawnTime)
                    {
                        depTime =block.timestamp - user[userAddress].investment[i].DepositTime;
                    }
                    else
                    {    
                        depTime =user[userAddress].investment[i].withdrawnTime - user[userAddress].investment[i].DepositTime;
                    }                
                }
                else
                {
                    if(user[userAddress].investment[i].unstakeTime <= user[userAddress].investment[i].withdrawnTime)
                    {
                        depTime =user[userAddress].investment[i].unstakeTime - user[userAddress].investment[i].DepositTime;

                    }
                    else
                    {
                        depTime =user[userAddress].investment[i].withdrawnTime - user[userAddress].investment[i].DepositTime;

                    }                }
                depTime=depTime/per_day_divider; //1 day
                if(depTime>0)
                {
                     rew  =  (((user[userAddress].investment[i].investedAmount * ((user[userAddress].investment[i].apr) *10**18) )/ (100*10**18) )/(user[userAddress].investment[i].timeframe));


                    totalReward += depTime * rew;
                }
            }
            totalReward -= user[userAddress].totalWithdraw_reward;

            return totalReward;
        }

        function getReward_perInv(uint i, address userAddress) view public returns(uint){ 
            uint totalReward;
            uint depTime;
            uint rew;

                if(!user[userAddress].investment[i].unstake)
                {
                    if(block.timestamp < user[userAddress].investment[i].withdrawnTime)
                    {
                        if(block.timestamp < user[userAddress].investment[i].withdrawnTime)
                        {
                            depTime =block.timestamp - user[userAddress].investment[i].DepositTime;
                        }
                        else
                        {    
                            depTime =user[userAddress].investment[i].withdrawnTime - user[userAddress].investment[i].DepositTime;
                        }                        
                    }
                    else
                    {    
                        depTime =user[userAddress].investment[i].withdrawnTime - user[userAddress].investment[i].DepositTime;
                    }     
                }
                else
                {
                    if(user[userAddress].investment[i].unstakeTime <= user[userAddress].investment[i].withdrawnTime)
                    {
                        depTime =user[userAddress].investment[i].unstakeTime - user[userAddress].investment[i].DepositTime;

                    }
                    else
                    {
                        depTime =user[userAddress].investment[i].withdrawnTime - user[userAddress].investment[i].DepositTime;

                    }
                }
                depTime=depTime/per_day_divider; //1 day
                if(depTime>0)
                {
                     rew  =  (((user[userAddress].investment[i].investedAmount * ((user[userAddress].investment[i].apr) *10**18) )/ (100*10**18) )/(user[userAddress].investment[i].timeframe));


                    totalReward += depTime * rew;
                }
            

            return totalReward;
        }

        function get_totalEarning(address add) public view returns(uint) {   

            return ( get_TotalReward(add));

        }


        function withdrawReward() public returns (bool success)
        {
            uint Total_reward = get_TotalReward(msg.sender);
            require(Total_reward>0,"you dont have rewards to withdrawn");         
        
            Token(Staking_token).transfer(msg.sender,Total_reward);             
                         
            user[msg.sender].totalWithdraw_reward+=Total_reward;

            return true;

        }


        function unStake(uint num) external  returns (bool success)
        {


            require(user[msg.sender].investment[num].investedAmount>0,"you dont have investment to withdrawn");            
            require(!user[msg.sender].investment[num].unstake ,"you have withdrawn");
            uint amount=user[msg.sender].investment[num].investedAmount;


            if(user[msg.sender].investment[num].withdrawnTime > block.timestamp)
            {
                uint penalty_fee=(amount*(penalty))/(100*10**18);
                Token(Staking_token).transfer(owner,penalty_fee);            
                amount=amount-penalty_fee;
            }
            Token(Staking_token).transfer(msg.sender,amount);             
            user[msg.sender].investment[num].unstake =true;    
            user[msg.sender].investment[num].unstakeTime =block.timestamp;    

            user[msg.sender].totalInvestment-=user[msg.sender].investment[num].investedAmount;
            user_investments[msg.sender][num] = user[msg.sender].investment[num];

            return true;

        }

        function getTotalInvestment() public view returns(uint) {   
            
            return user[msg.sender].totalInvestment;

        }

        function getAll_investments() public view returns (allInvestments[] memory Invested)
        { 
            uint num = user[msg.sender].noOfInvestment;
            uint temp;
            uint currentIndex;
            
            for(uint i=0;i<num;i++)
            {
               if(!user[msg.sender].investment[i].unstake )
               {
                   temp++;
               }

            }
         
            allInvestments[] memory temp_arr =  new allInvestments[](temp) ;
            Invested =  new allInvestments[](temp) ;

            for(uint i=0;i<num;i++)
            {
               if( !user[msg.sender].investment[i].unstake )
               {

                    temp_arr[currentIndex]=user[msg.sender].investment[i];
                    temp_arr[currentIndex].reward=getReward_perInv(i,msg.sender);

                    currentIndex++;
               }

            }

            uint count=temp;
            for(uint i=0;i<temp;i++)
            {
                count--;
                Invested[i]=temp_arr[count];

            }

            return Invested;

        }

        function getAll_investments_ForReward() public view returns (allInvestments[] memory Invested) { //this function will return the all investments of the investor and withware date
            uint num = user[msg.sender].noOfInvestment;
            uint currentIndex;

         
            allInvestments[] memory temp_arr =  new allInvestments[](num) ;
            Invested =  new allInvestments[](num) ;

            for(uint i=0;i<num;i++)
            {

                temp_arr[currentIndex]=user[msg.sender].investment[i];
                temp_arr[currentIndex].reward=getReward_perInv(i,msg.sender);

                currentIndex++;

            }

            uint count=num;
            for(uint i=0;i<num;i++)
            {
                count--;
                Invested[i]=temp_arr[count];

            }

            return Invested;

        }

        function get_upliner(address inv) public view returns(address)
        {
            return user[inv].referralFrom;
        }


        function get_TotalDirects(address inv) public view returns(uint){  
            return user[inv].totalDirects;
        }
         
        function total_withdraw_reaward() view public returns(uint){


            uint Temp = user[msg.sender].totalWithdraw_reward;

            return Temp;
            

        }

        function withdrawFunds(uint _amount)  public
        {
            require(msg.sender==owner);

            uint bal = Token(Staking_token).balanceOf(address(this));
            require(bal>=_amount);

            Token(Staking_token).transfer(owner,_amount); 
        }
  

 
        function get_currTime() public view returns(uint)
        {
            return block.timestamp;
        }
        
        function get_withdrawnTime(uint num) public view returns(uint)
        {
            return user[msg.sender].investment[num].withdrawnTime;
        }

        
        //setters


        function transferOwnership(address _owner) onlyOwner public
        {
            owner = _owner;
        }

        function update_min_inv(uint _val) onlyOwner public
        {
            minimum_investment = _val;
        }

        function update_referral_percentage(uint _val) onlyOwner public
        {
            referral_percentage = _val;
        }

        function update_7days_apr(uint _val) onlyOwner public
        {
            details[2].APR = _val;
        }

        function update_30days_apr(uint _val) onlyOwner public
        {
            details[1].APR = _val;
        }

        function update_90days_apr(uint _val) onlyOwner public
        {
            details[0].APR = _val;
        }
        
        function update_unstake_penalty(uint _val) onlyOwner public
        {
            penalty = _val;
        }

    }