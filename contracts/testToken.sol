// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/IERC20.sol";
import "./farm.sol";

contract NativeToken is  AccessControl, IERC20  {

    event TransferToken(address indexed from, address indexed to, uint256 value, uint256 commission);
    event TokenSupplyChange( uint256 burnValue, uint256 mintValue);
 
    mapping(address => uint256) private _balances;

    mapping(address => mapping(address => uint256)) private _allowances;

    uint256 private _totalSupply;
    string private _name = "TEST TOKEN";
    string private _symbol = "TSTSKR";

    address tokenOwner;
    address private FARMING_CONTRACT_ROLE;
    uint public commissionPercentage;
    FarmContract private farmContract;




    constructor(uint256 initialSupply, uint _commissionPercentage) {
        _mint(msg.sender, initialSupply * 10 ** uint(decimals()));
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        tokenOwner = msg.sender;
        commissionPercentage = _commissionPercentage;
    }

    function mint(address to, uint256 amount) public onlyRole(DEFAULT_ADMIN_ROLE) {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) public onlyRole(DEFAULT_ADMIN_ROLE) {
        _burn(from, amount);
    }

    function setFarmingRole(address _farmingContract) public  onlyRole(DEFAULT_ADMIN_ROLE) {
        FARMING_CONTRACT_ROLE = _farmingContract;
        farmContract = FarmContract(_farmingContract);
    }

    function changeTotalSupply(uint _burnAmount, uint _mintAmount) public{
        require(FARMING_CONTRACT_ROLE == msg.sender, "Only farming contract is allowed");
        require(_burnAmount > 0, "Burn amount must be larger than 0");
        require( tokenOwner.balance >= _burnAmount, "Burn amount cannot be larger than existing balance");
        require(_mintAmount > 0, "Mint amount must be larger than 0");

        _burn(tokenOwner, _burnAmount);
        _mint(msg.sender, _mintAmount);

        emit TokenSupplyChange(_burnAmount, _mintAmount);
    }

    function changeCommission(uint _commissionPercentage) public onlyRole(DEFAULT_ADMIN_ROLE) {
        commissionPercentage = _commissionPercentage;
    }

    function transferTokens(address to, uint256 amount, uint commission) public virtual  returns (bool) {
        address from = _msgSender();

        uint256 fromBalance = _balances[from];
        require(fromBalance >= (amount + commission), "ERC20: transfer amount exceeds balance");
        
        _transfer(from, to, amount);
        _transfer(from, FARMING_CONTRACT_ROLE, commission);

        emit TransferToken(from, to, amount, commission);

        return true;
    }


    function name() public view virtual returns (string memory) {
        return _name;
    }

    function symbol() public view virtual  returns (string memory) {
        return _symbol;
    }

    function decimals() public view virtual  returns (uint8) {
        return 18;
    }

    function totalSupply() public view virtual override returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) public view virtual override returns (uint256) {
        return _balances[account];
    }

    function transfer(address to, uint256 amount) public virtual override returns (bool) {
        address owner = _msgSender();
        _transfer(owner, to, amount);
        return true;
    }

    function allowance(address owner, address spender) public view virtual override returns (uint256) {
        return _allowances[owner][spender];
    }


    function approve(address spender, uint256 amount) public virtual override returns (bool) {
        address owner = _msgSender();
        _approve(owner, spender, amount);
        return true;
    }

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) public virtual override returns (bool) {
        address spender = _msgSender();
        _spendAllowance(from, spender, amount);
        _transfer(from, to, amount);
        return true;
    }

    function increaseAllowance(address spender, uint256 addedValue) public virtual returns (bool) {
        address owner = _msgSender();
        _approve(owner, spender, _allowances[owner][spender] + addedValue);
        return true;
    }

    function decreaseAllowance(address spender, uint256 subtractedValue) public virtual returns (bool) {
        address owner = _msgSender();
        uint256 currentAllowance = _allowances[owner][spender];
        require(currentAllowance >= subtractedValue, "ERC20: decreased allowance below zero");
        unchecked {
            _approve(owner, spender, currentAllowance - subtractedValue);
        }

        return true;
    }


    function _transfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual {
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");

        _beforeTokenTransfer(from, to, amount);

        uint256 fromBalance = _balances[from];
        require(fromBalance >= amount, "ERC20: transfer amount exceeds balance");
        unchecked {
            _balances[from] = fromBalance - amount;
        }
        _balances[to] += amount;

        emit Transfer(from, to, amount);

        _afterTokenTransfer(from, to, amount);
    }

    function _mint(address account, uint256 amount) internal virtual {
        require(account != address(0), "ERC20: mint to the zero address");

        _beforeTokenTransfer(address(0), account, amount);

        _totalSupply += amount;
        _balances[account] += amount;
        emit Transfer(address(0), account, amount);

        _afterTokenTransfer(address(0), account, amount);
    }


    function _burn(address account, uint256 amount) internal virtual {
        require(account != address(0), "ERC20: burn from the zero address");

        _beforeTokenTransfer(account, address(0), amount);

        uint256 accountBalance = _balances[account];
        require(accountBalance >= amount, "ERC20: burn amount exceeds balance");
        unchecked {
            _balances[account] = accountBalance - amount;
        }
        _totalSupply -= amount;

        emit Transfer(account, address(0), amount);

        _afterTokenTransfer(account, address(0), amount);
    }

 
    function _approve(
        address owner,
        address spender,
        uint256 amount
    ) internal virtual {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");

        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

 
    function _spendAllowance(
        address owner,
        address spender,
        uint256 amount
    ) internal virtual {
        uint256 currentAllowance = allowance(owner, spender);
        if (currentAllowance != type(uint256).max) {
            require(currentAllowance >= amount, "ERC20: insufficient allowance");
            unchecked {
                _approve(owner, spender, currentAllowance - amount);
            }
        }
    }

   
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual {}

    
    function _afterTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual {}
}