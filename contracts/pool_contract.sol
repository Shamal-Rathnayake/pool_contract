// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "@openzeppelin/contracts/access/AccessControl.sol";
import "https://github.com/abdk-consulting/abdk-libraries-solidity/blob/master/ABDKMath64x64.sol";
import "./testToken.sol";


interface ERC20 {

    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
}

contract poolContract  is  AccessControl {
    address public owner;

    ERC20 public ethToken;
    TestToken public bscToken;

    address[] public stakers;

    uint public ethTokenRatio;
    uint public bscTokenRatio;

    mapping(address => uint) public stakeBalance;
    mapping(address => bool) public hasStaked;
    mapping(address => bool) public isStaking;

    uint public totalStakeBalance = 0;

    

    constructor(address _ethToken, address _bscToken, uint _ethTokenRatio, uint _bscTokenRatio) {
        owner = msg.sender;
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        ethToken = ERC20(_ethToken);
        bscToken = TestToken(_bscToken);
        changeTokenRatio(_ethTokenRatio, _bscTokenRatio);
    }

    function changeTokenRatio(uint _ethTokenRatio, uint _bscTokenRatio) public onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_ethTokenRatio > 0 && _bscTokenRatio > 0, "Token ratios must be larger than 0");
        ethTokenRatio = _ethTokenRatio;
        bscTokenRatio = _bscTokenRatio;
    }


    function exchangeToken(uint _amount) public {
        require(_amount > 0, "Amount cannot be 0");

        uint ethTokenBalance = ethToken.balanceOf(msg.sender);
        require(ethTokenBalance >= _amount, "Insufficient balance");

        uint bscTokenHalfAmount = calculateBscTokenHalfAmount(_amount, bscTokenRatio, ethTokenRatio);
        require(bscTokenHalfAmount > 0 , "Half amount must be larger than 0");

        uint poolContractBalance = bscToken.balanceOf(address(this));
        require(poolContractBalance > bscTokenHalfAmount * 2, "Insufficient pool contract balance");

        uint ethTokenAllowance = ethToken.allowance(msg.sender, address(this));
        require(ethTokenAllowance >= _amount, "Token allowance too low");

        bool ethTtx = ethToken.transferFrom(msg.sender, address(this), _amount);
        require(ethTtx, "Token transfer to pool contract failed");

        bool ttx = bscToken.transfer(msg.sender, bscTokenHalfAmount);
        require(ttx, "Token transfer to sender failed");

        stakeBalance[msg.sender] += bscTokenHalfAmount;
        totalStakeBalance += bscTokenHalfAmount;

        if(!hasStaked[msg.sender]) {
            stakers.push(msg.sender);
        }

        isStaking[msg.sender] = true;
        hasStaked[msg.sender] = true;

    }

    function stakeTokens(uint _amount) public {
        require(_amount > 0, "Amount cannot be 0");

        uint tokenBalance = bscToken.balanceOf(msg.sender);
        require(tokenBalance >= _amount, "Insufficient balance");

        uint bscTokenAllowance = bscToken.allowance(msg.sender, address(this));
        require(bscTokenAllowance >= _amount, "Token allowance too low");

        bscToken.transferFrom(msg.sender, address(this), _amount);

        stakeBalance[msg.sender] += _amount;
        totalStakeBalance += _amount;

        if(!hasStaked[msg.sender]) {
            stakers.push(msg.sender);
        }

        isStaking[msg.sender] = true;
        hasStaked[msg.sender] = true;

    }

    function unstakeTokens(uint _amount) public {
        require(_amount > 0, "Amount cannot be 0");

        uint balance = stakeBalance[msg.sender];

        require(balance > 0, "No staked tokens");
        require(balance >= _amount, "Insufficient staked token amount");

        bscToken.transfer(msg.sender, _amount);

        uint remaining = balance - _amount;

        stakeBalance[msg.sender] = remaining;
        totalStakeBalance -= _amount;

        if(remaining > 0){
            isStaking[msg.sender] = true;
        }else{
            isStaking[msg.sender] = false;
        }

    }

    function calculateBscTokenHalfAmount(uint _ethTokenAmount, uint _bscTokenRatio, uint _ethTokenRatio) private pure returns (uint){
        uint halfAmount =  ABDKMath64x64.toUInt( ABDKMath64x64.div(ABDKMath64x64.fromUInt (_ethTokenAmount), ABDKMath64x64.fromUInt (2)));
        uint bscTokenAmount = ABDKMath64x64.toUInt (
                ABDKMath64x64.div (
                    ABDKMath64x64.mul (
                    ABDKMath64x64.fromUInt (halfAmount),
                    ABDKMath64x64.fromUInt (_bscTokenRatio)
                    ),
                    ABDKMath64x64.fromUInt (_ethTokenRatio)
                )
            );
        return bscTokenAmount;
    }

}