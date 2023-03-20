// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

/**
 * @title CollateralizedStablecoin
 * @author Hareem Saad
 * @notice Implementation of collateralized stable coin
 * 
 * depositCollateral -- mints tokens against the aomunt of USD you provide
 * withdrawCollateral -- gives USD against stable coin tokens
 * 
 * Added PAX controls for under collateralization (rejecting trasactions when treasury empty)
 */
contract CollateralizedStablecoin is ERC20, Ownable {

    uint8 public ratio;
    uint8 public tax;
    uint8 public fee;
    uint256 private taxAmount;
    uint256 private wethTaxAmount;
    uint256 public supplyCap;
    AggregatorV3Interface internal priceFeed;
    
    constructor () ERC20 ("Neon", "NEO") {
        ratio = 1;
        tax = 1;
        fee = 150;
        supplyCap = 1000000 * 10 ** 18;
        priceFeed = AggregatorV3Interface(0xD4a33860578De61DBAbDc8BFdb98FD742fA7028e);
    }

    event newDeposit (address indexed from, uint256 amount, uint256 exchange);
    event newRedeem (address indexed from, uint256 amount, uint256 exchange);
    event withdrawn(address from, address to, uint amount, uint time);

    /**
     * @notice gives stable coin in return for ETH
     * @param _amount of dollars (USD) you want to stake
     */
    function depositCollateral(uint256 _amount) public payable {
        //calculate tokens
        uint256 tokensToMint = _amount * 10 ** 18 * ratio;
        
        //check cap of tokens
        require(_amount > 0 && tokensToMint <= supplyCap, "Amount must be greater than 0 and lower and equal to supplyCap");
        
        //calculate price
        uint256 exchangeRate = uint256(getLatestPrice());
        uint256 price = _getExchangeRate(_amount, exchangeRate);
        
        //see if msg.value is enough
        require(price <= msg.value, "Value not enough");
        
        //mint
        _mint(msg.sender, tokensToMint);

        emit newDeposit(msg.sender, _amount, exchangeRate);

        //transfer leftover
        (bool sent,) = payable(msg.sender).call{value: msg.value - price}("");
        require(sent, "Failed to send Ether");
    }

    /**
     * @notice gives the latest exchange rate for 1 ETH to USD
     * @param _amount of dollars (USD) you want to stake
     */
    function _getExchangeRate(uint256 _amount, uint256 exchangeRate) internal pure returns (uint256) {
        return _amount * (10 ** 18) / exchangeRate;
    }

    /**
     * @notice gives the latest exchange rate for 1 ETH to USD
     * @param _amount of dollars (USD) you want to stake
     */
    function getExchangeRate(uint256 _amount) public view returns (uint256) {
        uint256 exchangeRate = uint256(getLatestPrice());
        return _amount * (10 ** 18) / exchangeRate;
    }

    /**
     * @notice gives taxed ether in return for withdrawn collateral
     * @param _amount of tokens you want to redeem
     */
    function withdrawCollateral(uint256 _amount) public {
        //check if amount is not zero
        require(_amount > 0, "Amount must be greater than 0");

        //check if have have collateral to redeem
        //owner's tax amount does not count as collateral
        require(address(this).balance > taxAmount, "No ETH in reserve");

        //check balance of sender
        require(balanceOf(msg.sender) >= _amount, "Amount must be greater than 0");

        //calculations
        uint256 exchangeRate = uint256(getLatestPrice());

        (uint256 RedeemedAmount, uint256 Tax) = _calculatePriceForSale(_amount, exchangeRate);

        //update tax
        taxAmount += Tax;

        // _burn(msg.sender, _amount * 10 ** 18 / ratio);
        _burn(msg.sender, _amount * 10 ** 18);

        emit newRedeem(msg.sender, _amount, exchangeRate);

        //transfer money
        (bool sent,) = payable(msg.sender).call{value: RedeemedAmount}("");
        require(sent, "Failed to send Ether");
    }

    /**
     * @notice gives amount of ether to redeem and tax value
     * @param _amount of tokens you want to redeem
     */
    function _calculatePriceForSale(uint256 _amount, uint256 exchangeRate) internal view returns (uint256 RedeemedAmount, uint256 Tax) {
        uint256 dollars = _amount * 10 ** 18 / ratio;

        uint256 price = dollars / exchangeRate;

        uint256 _tax = tax * price / 100;
        return (price - _tax, _tax);
    }

    /**
     * @notice gives amount of ether to redeem and tax value
     * @param _amount of tokens you want to redeem
     */
    function calculatePriceForSale(uint256 _amount) public view returns (uint256 RedeemedAmount, uint256 Tax) {
        uint256 dollars = _amount * 10 ** 18 / ratio;

        uint256 exchangeRate = uint256(getLatestPrice());

        uint256 price = dollars / exchangeRate;

        uint256 _tax = tax * price / 100;
        return (price - _tax, _tax);
    }

    /**
     * @notice allows owner to withdraw tax
     */
    function withdrawTax() public onlyOwner {
        require(taxAmount > 0, "tax must be greater than 0");

        uint256 _tax = taxAmount;

        taxAmount = 0;

        (bool sent,) = payable(msg.sender).call{value: _tax}("");
        require(sent, "Failed to send Ether");

        emit withdrawn (address(this), msg.sender, _tax, block.timestamp);
    }

    function viewTax() public view onlyOwner returns (uint256) {
        return taxAmount;
    }

    function getUsdExchangeRate() public view returns (uint256) {
        return uint256(getLatestPrice());
    }

    //------------------------------------------------------------------------

    address wethAddress = 0xB4FBF271143F4FBf7B91A5ded31805e42b2208d6;

    /**
     * @notice gives stable coin in return for ETH
     * @param _amount of dollars (USD) you want to stake
     */
    function depositCollateralWithWeth(uint256 _amount) public {

        //calculuate tokens to mint
        uint256 tokensToMint = _amount * 10 ** 18 * ratio;

        //check token supply cap
        require(_amount > 0 && tokensToMint <= supplyCap, "Amount must be greater than 0 and lower and equal to supplyCap");
        
        //weth instance
        IERC20 wethToken = IERC20(wethAddress);
        
        //calculate price
        uint256 exchangeRate = uint256(getLatestPrice());
        uint256 price = _getExchangeRate(_amount, exchangeRate);
        
        //check if approved for price
        require(wethToken.allowance(msg.sender, address(this)) >= price, "contract not approved for price amount");

        //check if msg.sender has balance equal to or greater than price
        require(price <= wethToken.balanceOf(msg.sender), "Value not enough");
        
        //transfer price
        wethToken.transferFrom(msg.sender, address(this), price);
        
        _mint(msg.sender, tokensToMint);

        emit newDeposit(msg.sender, _amount, exchangeRate);
    }

    /**
     * @notice gives taxed ether in return for withdrawn collateral
     * @param _amount of CollateralizedStablecoin tokens you want to redeem
     */
    function withdrawCollateralWithWeth(uint256 _amount) public {
        
        //check if collateral in reserve, should be greater than owner's earned tax
        require(balanceOf(address(this)) > wethTaxAmount, "No ETH in reserve");
        
        //weth instance
        IERC20 wethToken = IERC20(wethAddress);
        
        //checks
        require(_amount > 0, "Amount must be greater than 0");
        require(balanceOf(msg.sender) >= _amount, "balance of stablecoin lower than amount");

        //calculate Price For Sale
        uint256 exchangeRate = uint256(getLatestPrice());

        (uint256 RedeemedAmount, uint256 Tax) = _calculatePriceForSale(_amount, exchangeRate);

        //update tax
        wethTaxAmount += Tax;

        //burn
        _burn(msg.sender, _amount * 10 ** 18);

        emit newRedeem(msg.sender, _amount, exchangeRate);

        //transfer weth
        wethToken.transfer(msg.sender, RedeemedAmount);
    }

    /**
     * @notice allows owner to withdraw tax
     */
    function withdrawTaxInWeth() public onlyOwner {
        require(wethTaxAmount > 0, "tax must be greater than 0");

        uint256 _tax = wethTaxAmount;

        wethTaxAmount = 0;

        IERC20 wethToken = IERC20(wethAddress);

        wethToken.transfer(owner(), _tax);

        emit withdrawn (address(this), msg.sender, _tax, block.timestamp);
    }

    function getLatestPrice() public view returns (int256) {
        (, int256 price, , , ) = priceFeed.latestRoundData();
        return price;
    }

    function viewWethTax() public view onlyOwner returns (uint256) {
        return wethTaxAmount;
    }

    //misc
    function _getExchangeRateMisc(uint256 _amount, uint256 exchangeRate) internal pure returns (uint256) {
        uint256 price = _amount * (10 ** 18) / exchangeRate;

        uint _fee = price * 150 / 10000;

        uint newPrice = price + _fee;
        
        return newPrice;
    }

}