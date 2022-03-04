// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "https://github.com/abdk-consulting/abdk-libraries-solidity/blob/master/ABDKMath64x64.sol";
import "https://github.com/abdk-consulting/abdk-libraries-solidity/blob/v3.0/ABDKMathQuad.sol";

contract liquidityPool is AccessControl {
    address private owner;

    ERC20 private foreignToken;
    ERC20 private nativeToken;

    mapping(address => uint256) public nativeStakeBalance;
    mapping(address => uint256) public foreignStakeBalance;

    uint256 public totalNativeStakeBalance = 0;
    uint256 public totalForeignStakeBalance = 0;

    uint256 public foreignTokenReserve = 0;
    uint256 public nativeTokenReserve = 0;

    uint256 public kValue = 0;

    address[] private stakers;

    mapping(address => bool) public hasStaked;
    mapping(address => bool) public isStaking;

    uint256 public commissionPercentage = 10;
    uint256 totalCommissionsEarned = 0;

    // =============== staking rewards ===============

    uint256 public rewardRate = 10;
    uint256 public lastUpdateTime;
    uint256 public rewardPerTokenStored;

    mapping(address => uint256) public userRewardPerTokenPaid;
    mapping(address => uint256) public rewards;

    constructor(address _foreignTokenAddress, address _nativeTokenAddress) {
        owner = msg.sender;
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        foreignToken = ERC20(_foreignTokenAddress);
        nativeToken = ERC20(_nativeTokenAddress);
    }

    // ===================== initialize liquidity pool ====================

    function initPool(uint256 _foreignTokenValue, uint256 _nativeTokenValue)
        public
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        bool success = _addLiquidity(_foreignTokenValue, _nativeTokenValue);
        require(success);
    }

    // ====================== add liquidity public method =====================

    function addLiquidity(uint256 depositAmount)
        public
        updateReward(msg.sender)
        returns (bool)
    {
        bool success = _addLiquidity(depositAmount, depositAmount);
        require(success);

        nativeStakeBalance[msg.sender] += depositAmount;
        foreignStakeBalance[msg.sender] += depositAmount;

        totalForeignStakeBalance += depositAmount;
        totalNativeStakeBalance += depositAmount;

        if (!hasStaked[msg.sender]) {
            stakers.push(msg.sender);
        }

        isStaking[msg.sender] = true;
        hasStaked[msg.sender] = true;

        return true;
    }

    // ===================== withdraw liquidity ===================

    function withdrawLiquidity(uint256 withdrawAmount)
        public
        updateReward(msg.sender)
        returns (bool)
    {
        uint256 _nativeStakeBalance = nativeStakeBalance[msg.sender];
        require(
            _nativeStakeBalance >= withdrawAmount,
            "low_n_liq_balance"
        );

        uint256 _foreignStakeBalance = foreignStakeBalance[msg.sender];
        require(
            _foreignStakeBalance >= withdrawAmount,
            "low_f_liq_balance"
        );

        uint256 contractNativeBalance = nativeToken.balanceOf(address(this));
        require(
            contractNativeBalance > withdrawAmount,
            "low_con_n_balance"
        );

        uint256 contractForeignBalance = foreignToken.balanceOf(address(this));
        require(
            contractForeignBalance > withdrawAmount,
            "low_con_f_balance"
        );

        // send withdrawn native tokens to sender
        bool nTx = nativeToken.transfer(msg.sender, withdrawAmount);
        require(nTx);

        // send withdrawn foreign tokens to sender
        bool fTx = foreignToken.transfer(msg.sender, withdrawAmount);
        require(fTx);

        nativeStakeBalance[msg.sender] -= withdrawAmount;
        foreignStakeBalance[msg.sender] -= withdrawAmount;

        totalNativeStakeBalance -= withdrawAmount;
        totalForeignStakeBalance -= withdrawAmount;

        nativeTokenReserve -= withdrawAmount;
        foreignTokenReserve -= withdrawAmount;

        calculateK();

        if (
            nativeStakeBalance[msg.sender] == 0 &&
            foreignStakeBalance[msg.sender] == 0
        ) {
            isStaking[msg.sender] = false;
        }

        return true;
    }

    // ========================= exchange foreign token ==========================

    function exchangeForeignToken(uint256 foreignTokenAmount)
        public
        updateReward(msg.sender)
        returns (bool)
    {
        require(foreignTokenAmount > 0, "amount_>_0");

        // check foreign token balance > sending token amount
        uint256 foreignTokenBalance = foreignToken.balanceOf(msg.sender);
        require(
            foreignTokenBalance >= foreignTokenAmount,
            "low_f_balance"
        );

        //apply state change and calculate displacing native token amount & new reserve amount
        (
            uint256 receivingNativeAmount,
            uint256 newNativeTokenReserve
        ) = applyStateChange(foreignTokenAmount, true);

        // check if pool contract has enough native token balance
        uint256 poolContractBalance = nativeToken.balanceOf(address(this));
        require(
            poolContractBalance > receivingNativeAmount,
            "low_con_n_balance"
        );

        // calculate return native token amount
        uint256 returnNativeAmount = ABDKMathQuad.toUInt(
            ABDKMathQuad.div(
                ABDKMathQuad.fromUInt(receivingNativeAmount),
                ABDKMathQuad.fromUInt(2)
            )
        );
        require(
            returnNativeAmount > 0
        );

        // check if native reserve has enough balance
        require(
            nativeTokenReserve > returnNativeAmount,"low_n_reserve"
        );

        // check if foreign token allowance >= sending foreign token amount
        uint256 foreignTokenAllowance = foreignToken.allowance(
            msg.sender,
            address(this)
        );
        require(
            foreignTokenAllowance >= foreignTokenAmount,"low_f_allowance"
        );

        // send foreign tokens to pool contract
        bool foreignTokenTx = foreignToken.transferFrom(
            msg.sender,
            address(this),
            foreignTokenAmount
        );
        require(foreignTokenTx);

        // send native tokens to sender
        bool nativeTokenTx = nativeToken.transfer(
            msg.sender,
            returnNativeAmount
        );
        require(nativeTokenTx);

        // add received foreign tokens to reserve
        foreignTokenReserve += foreignTokenAmount;

        // update native token reserve with new reserve value + 50% of the displacing amount
        nativeTokenReserve = newNativeTokenReserve + returnNativeAmount;

        // calculate new k value for updated reserves
        calculateK();

        // add 50% of the displacing amount to sender's stake balance
        nativeStakeBalance[msg.sender] += returnNativeAmount;

        // update total native token stake balance with 50% of the displacing token amount
        totalNativeStakeBalance += returnNativeAmount;

        if (!hasStaked[msg.sender]) {
            stakers.push(msg.sender);
        }

        isStaking[msg.sender] = true;
        hasStaked[msg.sender] = true;

        return true;
    }

    // ========================== swap foreign token ====================

    function swapForeignToken(uint256 foreignTokenAmount)
        public
        updateReward(msg.sender)
        returns (bool)
    {
        require(foreignTokenAmount > 0, "amount_>_0");

        // check foreign token balance > sending token amount
        uint256 foreignTokenBalance = foreignToken.balanceOf(msg.sender);
        require(
            foreignTokenBalance >= foreignTokenAmount, "low_f_balance"
        );

        //apply state change and calculate displacing native token amount & new reserve amount
        (
            uint256 receivingNativeAmount,
            uint256 newNativeTokenReserve
        ) = applyStateChange(foreignTokenAmount, true);

        // check if pool contract has enough native token balance
        uint256 poolContractBalance = nativeToken.balanceOf(address(this));
        require(
            poolContractBalance > receivingNativeAmount,"low_con_n_balance"
        );

        // check if native reserve has enough balance
        require(
            nativeTokenReserve > receivingNativeAmount,"low_n_reserve"
        );

        // check if foreign token allowance >= sending foreign token amount
        uint256 foreignTokenAllowance = foreignToken.allowance(
            msg.sender,
            address(this)
        );
        require(
            foreignTokenAllowance >= foreignTokenAmount, "low_f_allowance"
        );

        // send foreign tokens to pool contract
        bool foreignTokenTx = foreignToken.transferFrom(
            msg.sender,
            address(this),
            foreignTokenAmount
        );
        require(foreignTokenTx);

        // calculate commission
        (uint256 foreignAmount, uint256 commission) = calculateCommission(foreignTokenAmount);

        // send native tokens to sender
        bool nativeTokenTx = nativeToken.transfer(
            msg.sender,
            receivingNativeAmount
        );
        require(nativeTokenTx);

        // add received foreign tokens to reserve
        foreignTokenReserve += foreignAmount;

        // update native token reserve with new reserve value
        nativeTokenReserve = newNativeTokenReserve;

        // calculate new k value for updated reserves
        calculateK();

        // add commission to earnings
        totalCommissionsEarned += commission;

        return true;
    }

    // ========================== swap native token ====================

    function swapNativeToken(uint256 nativeTokenAmount)
        public
        updateReward(msg.sender)
        returns (bool)
    {
        require(nativeTokenAmount > 0, "amount_>_0");

        // check native token balance > sending token amount
        uint256 nativeTokenBalance = nativeToken.balanceOf(msg.sender);
        require(
            nativeTokenBalance >= nativeTokenAmount,"low_n_balance"
        );

        //apply state change and calculate displacing foreign token amount & new reserve amount
        (
            uint256 receivingForeignAmount,
            uint256 newForeignTokenReserve
        ) = applyStateChange(nativeTokenAmount, false);

        // check if pool contract has enough foreign token balance
        uint256 poolContractBalance = foreignToken.balanceOf(address(this));
        require(
            poolContractBalance > receivingForeignAmount, "low_con_f_balance"
        );

        // check if foreign reserve has enough balance
        require(
            foreignTokenReserve > receivingForeignAmount, "low_f_reserve"
        );

        // check if native token allowance >= sending native token amount
        uint256 nativeTokenAllowance = nativeToken.allowance(
            msg.sender,
            address(this)
        );
        require(
            nativeTokenAllowance >= nativeTokenAmount,"low_n_allowance"
        );

        // send native tokens to pool contract
        bool nativeTokenTx = nativeToken.transferFrom(
            msg.sender,
            address(this),
            nativeTokenAmount
        );
        require(nativeTokenTx);

        
        // calculate commission
        (uint256 foreignAmount, uint256 commission) = calculateCommission(
            receivingForeignAmount
        );

        // send foreign tokens to sender
        bool foreignTokenTx = foreignToken.transfer(
            msg.sender,
            foreignAmount
        );
        require(foreignTokenTx);

        // add received native tokens to reserve
        nativeTokenReserve += nativeTokenAmount;

        // update foreign token reserve with new reserve value
        foreignTokenReserve = newForeignTokenReserve;

        // calculate new k value for updated reserves
        calculateK();

        // add commissiom to earnings
        totalCommissionsEarned += commission;

        return true;
    }


    // ====================== add liquidity private method =====================
    function _addLiquidity(
        uint256 _foreignTokenValue,
        uint256 _nativeTokenValue
    ) private returns (bool) {
        require(_foreignTokenValue > 0);
        require(_nativeTokenValue > 0);

        uint256 foreignTokenAllowance = foreignToken.allowance(
            msg.sender,
            address(this)
        );
        require(
            foreignTokenAllowance >= _foreignTokenValue,
            "low_f_allowance"
        );

        uint256 foreignTokenBalance = foreignToken.balanceOf(msg.sender);
        require(
            foreignTokenBalance >= _foreignTokenValue,
            "low_f_balance"
        );

        uint256 nativeTokenAllowance = nativeToken.allowance(
            msg.sender,
            address(this)
        );
        require(
            nativeTokenAllowance >= _nativeTokenValue,
            "low_n_allowance"
        );

        uint256 nativeTokenBalance = nativeToken.balanceOf(msg.sender);
        require(
            nativeTokenBalance >= _nativeTokenValue,
            "low_n_balance"
        );

        bool foreignTokenTx = foreignToken.transferFrom(
            msg.sender,
            address(this),
            _foreignTokenValue
        );
        require(foreignTokenTx);

        bool nativeTokenTx = nativeToken.transferFrom(
            msg.sender,
            address(this),
            _nativeTokenValue
        );
        require(nativeTokenTx);

        foreignTokenReserve += _foreignTokenValue;
        nativeTokenReserve += _nativeTokenValue;
        calculateK();

        return true;
    }

    // ====================== calculate k =====================
    function calculateK() private {
        kValue = foreignTokenReserve * nativeTokenReserve;
    }

    // ====================== apply token change to pool =====================
    function applyStateChange(uint256 tokenAmount, bool foreign)
        private
        view
        returns (uint256, uint256)
    {
        uint256 newTokenReserve = 0;
        uint256 receivingTokenAmount = 0;

        if (foreign) {
            newTokenReserve = ABDKMathQuad.toUInt(
                ABDKMathQuad.div(
                    ABDKMathQuad.fromUInt(kValue),
                    ABDKMathQuad.fromUInt(foreignTokenReserve + tokenAmount)
                )
            );
            receivingTokenAmount = ABDKMathQuad.toUInt(
                ABDKMathQuad.sub(
                    ABDKMathQuad.fromUInt(nativeTokenReserve),
                    ABDKMathQuad.fromUInt(newTokenReserve)
                )
            );
        } else {
            newTokenReserve = ABDKMathQuad.toUInt(
                ABDKMathQuad.div(
                    ABDKMathQuad.fromUInt(kValue),
                    ABDKMathQuad.fromUInt(nativeTokenReserve + tokenAmount)
                )
            );
            receivingTokenAmount = ABDKMathQuad.toUInt(
                ABDKMathQuad.sub(
                    ABDKMathQuad.fromUInt(foreignTokenReserve),
                    ABDKMathQuad.fromUInt(newTokenReserve)
                )
            );
        }

        return (receivingTokenAmount, newTokenReserve);
    }

    function getNativeRate() public view returns (uint256) {
        return
            ABDKMathQuad.toUInt(
                ABDKMathQuad.div(
                    ABDKMathQuad.fromUInt(foreignTokenReserve),
                    ABDKMathQuad.fromUInt(nativeTokenReserve)
                )
            );
    }

    function getForeignRate() public view returns (uint256) {
        return
            ABDKMathQuad.toUInt(
                ABDKMathQuad.div(
                    ABDKMathQuad.fromUInt(nativeTokenReserve),
                    ABDKMathQuad.fromUInt(foreignTokenReserve)
                )
            );
    }

    function changeRewardRate(uint256 _amount)
        public
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        require(_amount > 0,"amount_>_0");
        rewardRate = _amount;
    }

    function withdrawReward() public updateReward(msg.sender) {
        uint256 reward = rewards[msg.sender];

        if (reward > 0) {
            // get pool contract native token balance
            uint256 contractNativeBalance = nativeToken.balanceOf(
                address(this)
            );

            // get spendable native token balance
            uint256 availableBalance = contractNativeBalance -
                nativeTokenReserve;
            require(
                availableBalance > reward,"low_con_n_balance"
            );

            // transfer reward to sender
            nativeToken.transfer(msg.sender, reward);

            // reset sender's reward balance
            rewards[msg.sender] = 0;
        }
    }

    function changeCommission(uint256 _commission)
        public
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        require(_commission > 0,"commission_>_0");
        commissionPercentage = _commission;
    }

    function calculateCommission(uint256 _amount)
        private
        view
        returns (uint256, uint256)
    {
        require(_amount > 0, "amount_>_0");

        uint256 commission = ABDKMathQuad.toUInt(
            ABDKMathQuad.div(
                ABDKMathQuad.mul(
                    ABDKMathQuad.fromUInt(_amount),
                    ABDKMathQuad.fromUInt(commissionPercentage)
                ),
                ABDKMathQuad.fromUInt(100)
            )
        );

        uint256 remaining = _amount - commission;
        return (remaining, commission);
    }

    // =========== reward process ===========

    function rewardPerToken() private view returns (uint256) {
        if (totalNativeStakeBalance == 0) {
            return rewardPerTokenStored;
        }

        return
            ABDKMathQuad.toUInt(
                ABDKMathQuad.add(
                    ABDKMathQuad.fromUInt(rewardPerTokenStored),
                    ABDKMathQuad.div(
                        ABDKMathQuad.fromUInt(
                            (((block.timestamp - lastUpdateTime) * rewardRate) *
                                (10**uint256(nativeToken.decimals())))
                        ),
                        ABDKMathQuad.fromUInt(totalNativeStakeBalance)
                    )
                )
            );
    }

    function earned(address account) private view returns (uint256) {
        return
            ABDKMathQuad.toUInt(
                ABDKMathQuad.add(
                    ABDKMathQuad.div(
                        ABDKMathQuad.mul(
                            ABDKMathQuad.fromUInt(nativeStakeBalance[account]),
                            ABDKMathQuad.sub(
                                ABDKMathQuad.fromUInt(rewardPerToken()),
                                ABDKMathQuad.fromUInt(
                                    userRewardPerTokenPaid[account]
                                )
                            )
                        ),
                        ABDKMathQuad.fromUInt(
                            (10**uint256(nativeToken.decimals()))
                        )
                    ),
                    ABDKMathQuad.fromUInt(rewards[account])
                )
            );
    }

    modifier updateReward(address account) {
        rewardPerTokenStored = rewardPerToken();
        lastUpdateTime = block.timestamp;
        if (account != address(0)) {
            rewards[account] = earned(account);
            userRewardPerTokenPaid[account] = rewardPerTokenStored;
        }
        _;
    }
}

interface ERC20 {
    function totalSupply() external view returns (uint256);

    function balanceOf(address account) external view returns (uint256);

    function transfer(address recipient, uint256 amount)
        external
        returns (bool);

    function allowance(address owner, address spender)
        external
        view
        returns (uint256);

    function approve(address spender, uint256 amount) external returns (bool);

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external returns (bool);

    function decimals() external view returns (uint256);

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(
        address indexed owner,
        address indexed spender,
        uint256 value
    );
}
