// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

// Uncomment this line to use console.log
// import "hardhat/console.sol";
import "@uniswap/v3-core/contracts/libraries/LowGasSafeMath.sol";

interface IWETH {
    function allowance(
        address owner,
        address spender
    ) external view returns (uint);

    function transferFrom(
        address src,
        address dst,
        uint wad
    ) external returns (bool);

    function withdraw(uint wad) external;
}

interface IMarketAdapter {
    function purchaseNFT(
        address collection,
        uint256 tokenId,
        bytes calldata data
    ) external;
}

interface IDownPayment {
    function buy(
        address adapter,
        uint256 borrowAmount,
        bytes calldata data,
        Sig calldata sig
    ) external payable;
}

contract DealHunter {
    using LowGasSafeMath for uint256;

    address public wethAddress;
    uint256 public downpaymentRate;

    constructor(address _wethAddress, uint256 _downpaymentRate) {
        wethAddress = _wethAddress;
        downpaymentRate = _downpaymentRate;
    }

    function fire(
        address marketAdapter,
        address collection,
        uint256 tokenId,
        address buyer,
        uint256 price,
        bool downpayment,
        bytes calldata data
    ) external {
        uint256 _requiredBalence = price;
        if (downpayment) {
            _requiredBalence = LowGasSafeMath.mul(price, downpaymentRate) / 100;
        }
        require(
            buyer.balance >= _requiredBalence,
            "buyer's balance is too low"
        );
        require(
            IWETH(wethAddress).allowance(buyer, address(this)) >=
                _requiredBalence,
            "the balance allowed from buyer is too low"
        );
        require(
            IWETH(wethAddress).transferFrom(
                buyer,
                address(this),
                _requiredBalence
            ),
            "failed to transfer enough amount of WETH from buyer"
        );

        IWETH(wethAddress).withdraw(price);

        if (!downpayment) {
            IMarketAdapter(marketAdapter).purchaseNFT(
                collection,
                tokenId,
                data
            );

            // TODO: transfer to buyer below or has been done by above purchaseNFT
        } else {
            IDownPayment(marketAdapter).buy(
                marketAdapter,
                LowGasSafeMath.sub(price, _requiredBalence),
                data,
                sig
            );
        }
    }
}
