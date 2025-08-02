//SPDX-License-Identifier:MIT
pragma solidity ^0.8.19;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

/*Errors*/
error ManualToken__TransferToZeroAddress();
error ManualToken__TransferFromZeroAddress();
error ManualToken__ApproveToZeroAddress();
error ManualToken__SpenderHasNoCode();
error ManualToken__ApproveFromZeroAddress();
error ManualToken__MintToZeroAddress();
error ManualToken__InsufficientBalance();
error ManualToken__InsufficientAllowance();

interface ITokenApprovalRecipient {
    function receiveApproval(
        address _from,
        uint256 _value,
        address _token,
        bytes calldata _extraData
    ) external;
}

contract ManualToken is IERC20, IERC20Metadata {
    /* State Variables */
    //  --- ERC-20 metadata ---
    string public name;
    string public symbol;
    uint8 public constant DECIMALS = 18;
    // --- Supply & accounting ---
    uint256 public totalSupply;
    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;

    /* Events */
    event Burn(address indexed from, uint256 value);

    constructor(
        uint256 initialSupply,
        string memory tokenName,
        string memory tokenSymbol
    ) {
        name = tokenName;
        symbol = tokenSymbol;
        _mint(msg.sender, initialSupply * (10 ** uint256(DECIMALS)));
    }

    /* Functions */
    // --- Non-standard convenience: approve and notify ---
    function approveAndCall(
        address spender,
        uint256 value,
        bytes calldata extraData
    ) external returns (bool) {
        if (spender == address(0)) revert ManualToken__ApproveToZeroAddress();
        if (spender.code.length == 0) revert ManualToken__SpenderHasNoCode();
        _approve(msg.sender, spender, value);
        ITokenApprovalRecipient(spender).receiveApproval(
            msg.sender,
            value,
            address(this),
            extraData
        );
        // If receiveApproval reverts, the whole tx reverts (approval undone)
        return true;
    }

    // --- Core ERC-20 ---
    function transfer(
        address to,
        uint256 value
    ) external override returns (bool) {
        _transfer(msg.sender, to, value);
        return true;
    }

    function approve(
        address spender,
        uint256 value
    ) external override returns (bool) {
        _approve(msg.sender, spender, value);
        return true;
    }

    function transferFrom(
        address from,
        address to,
        uint256 value
    ) external override returns (bool) {
        uint256 current = _allowances[from][msg.sender];
        if (current != type(uint256).max) {
            if (current < value) revert ManualToken__InsufficientAllowance();
            unchecked {
                _allowances[from][msg.sender] = current - value;
            }
        }
        _transfer(from, to, value);
        // No extra Approval emit here — saves gas
        return true;
    }

    // --- Burns (extensions) ---
    function burn(uint256 value) external returns (bool) {
        uint256 fromBal = _balances[msg.sender];
        if (fromBal < value) revert ManualToken__InsufficientBalance();
        unchecked {
            _balances[msg.sender] = fromBal - value;
            totalSupply -= value;
        }
        emit Burn(msg.sender, value);
        emit Transfer(msg.sender, address(0), value); // standard burn signal
        return true;
    }

    function burnFrom(address from, uint256 value) external returns (bool) {
        uint256 fromBal = _balances[from];
        if (fromBal < value) revert ManualToken__InsufficientBalance();
        uint256 current = _allowances[from][msg.sender];
        if (current != type(uint256).max) {
            if (current < value) revert ManualToken__InsufficientAllowance();
            unchecked {
                _allowances[from][msg.sender] = current - value;
            }
        }
        unchecked {
            _balances[from] = fromBal - value;
        }
        totalSupply -= value;
        emit Burn(from, value);
        emit Transfer(from, address(0), value);
        return true;
    }

    // --- Internals ---
    function _transfer(address from, address to, uint256 value) internal {
        if (to == address(0)) revert ManualToken__TransferToZeroAddress();
        if (from == address(0)) revert ManualToken__TransferFromZeroAddress();
        uint256 fromBal = _balances[from];
        if (fromBal < value) revert ManualToken__InsufficientBalance();
        unchecked {
            _balances[from] = fromBal - value;
        }
        _balances[to] += value;
        emit Transfer(from, to, value);
    }

    function _approve(address owner, address spender, uint256 value) internal {
        if (spender == address(0)) revert ManualToken__ApproveToZeroAddress();
        if (owner == address(0)) revert ManualToken__ApproveFromZeroAddress();
        _allowances[owner][spender] = value;
        emit Approval(owner, spender, value);
    }

    function _mint(address to, uint256 value) internal {
        if (to == address(0)) revert ManualToken__MintToZeroAddress();
        unchecked {
            totalSupply += value;
            _balances[to] += value;
        }
        emit Transfer(address(0), to, value);
    }

    // --- View,pure  ---
    function balanceOf(address account) public view override returns (uint256) {
        return _balances[account];
    }

    function allowance(
        address owner,
        address spender
    ) public view override returns (uint256) {
        return _allowances[owner][spender];
    }

    function decimals() public pure override returns (uint8) {
        return DECIMALS;
    }
}
