// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "https://github.com/abdk-consulting/abdk-libraries-solidity/blob/master/ABDKMath64x64.sol";
import "./testToken.sol";


contract FarmContract {
    address public owner;
    NativeToken private token;
    address[] public stakers;
    uint totalStakedAmount = 0;
    mapping(address => uint) public stakingBalance;
    mapping(address => bool) public hasStaked;
    mapping(address => bool) public isStaking;

    event StakeTokens(address indexed from, uint256 value);
    event UnstakeTokens(address indexed from, uint256 value);

    constructor(address tokenAddress) {
        token = NativeToken(tokenAddress);
        owner = msg.sender;
    }

    function stakeTokens(uint _amount) public {
        require(_amount > 0, "Amount cannot be 0");

        uint tokenBalance = token.balanceOf(msg.sender);
        require(tokenBalance >= _amount, "Insufficient balance");

        token.transferFrom(msg.sender, address(this), _amount);

        stakingBalance[msg.sender] = stakingBalance[msg.sender] + _amount;
        totalStakedAmount += _amount;

        if(!hasStaked[msg.sender]) {
            stakers.push(msg.sender);
        }

        isStaking[msg.sender] = true;
        hasStaked[msg.sender] = true;

        emit StakeTokens(msg.sender, _amount);
    }


    function unstakeTokens(uint _amount) public {
        require(_amount > 0, "Amount cannot be 0");

        uint balance = stakingBalance[msg.sender];

        require(balance > 0, "No staked tokens");
        require(balance >= _amount, "Insufficient staked token amount");

        token.transfer(msg.sender, _amount);

        uint remaining = balance - _amount;

        stakingBalance[msg.sender] = remaining;
        totalStakedAmount -= _amount;

        if(remaining > 0){
            isStaking[msg.sender] = true;
        }else{
            isStaking[msg.sender] = false;
        }

        emit UnstakeTokens(msg.sender, _amount);

    }




    function mulDiv (uint x, uint y, uint z) private pure returns (uint) {
        return
            ABDKMath64x64.toUInt (
                ABDKMath64x64.div (
                    ABDKMath64x64.mul (
                    ABDKMath64x64.fromUInt (x),
                    ABDKMath64x64.fromUInt (y)
                    ),
                    ABDKMath64x64.fromUInt (z)
                )
            );
    }


    function issueRewards(uint _rewardAmount) public {
        require(msg.sender == owner || msg.sender == address(token), "Issueing rewards only callable by owner or token contract");
        
        uint tokenBalance = token.balanceOf(address(this));
        uint rewardBalance = tokenBalance - totalStakedAmount;
        require(rewardBalance >= _rewardAmount, "Insufficient balance to issue rewards");

        uint length = stakers.length;

        for (uint i=0; i<length; i++) {
            address recipient = stakers[i];
            uint balance = stakingBalance[recipient];
            if(balance > 0) {
                uint transferAmount = mulDiv(_rewardAmount, balance, totalStakedAmount);
                token.transfer(recipient, transferAmount);
            }
        }
    } 


    function changeTokenSupply(uint _burnAmount, uint _mintAmount) public {
        require(msg.sender == owner, "Change token supply only callable by owner");

        require(_burnAmount > 0, "Burn amount must be larger than 0");
        require(_mintAmount > 0, "Mint amount must be larger than 0");

        token.changeTotalSupply(_burnAmount, _mintAmount);

       // issueRewards(_mintAmount);

    }

    function changeTokenAddress(address addr) public virtual returns (bool) {
        require(msg.sender == owner, "Change token address only callable by owner");
        token = NativeToken(addr);
        return true;
    }
}