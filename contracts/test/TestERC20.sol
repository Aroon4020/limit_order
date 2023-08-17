// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

//import { IERC20 } from "../interfaces/IERC20.sol";

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract TestERC20 is ERC20 {
    constructor()ERC20("TEST","TEST"){

    }

    function mint(address to, uint256 amount) external{
        _mint(to,amount);
    }
    
}
