// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

contract MockLaunchERC20 is ERC20 {
    constructor(string memory name_, string memory symbol_, uint256 initialSupply, address to)
        ERC20(name_, symbol_)
    {
        _mint(to, initialSupply);
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}
