//SPDX-License-Identifier:MIT

pragma solidity ^0.8.19;
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title A sample Token contract
 * @author web3pavlou
 * @notice This is a sample contract for creating a token based on OZ library standards,not intended for production purposes
 */

contract OurToken is ERC20 {
    constructor(uint256 initialSupply) ERC20("OurToken", "OT") {
        _mint(msg.sender, initialSupply);
    }
}
