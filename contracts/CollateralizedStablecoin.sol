// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract CollateralizedStablecoin is ERC20 {

    uint8 public ratio;
    uint8 public tax;
    
    constructor () ERC20 ("Neon", "NEO") {
        ratio = 2;
        tax = 1;
    }

    /**
     * @notice gives stable coin in return for ETH
     * @param _amount amount of stable coins you want
     */
    depositCollateral(uint256 _amount) public payable {
        require(_amount > 0, "Amount must be greater than 0");
        require(_amount * ratio <= msg.value, "Value not enough");
        _mint(msg.sender, _amount);
    }

    function decimals() public view override returns (uint8) {
        return 1;
    }

    //so i can run it on localhost
    function getLatestPrice() public view returns (int256) {
        return 100;
    }

}