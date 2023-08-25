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

interface IERC721 {
    function safeTransferFrom(
        address _from,
        address _to,
        uint256 _tokenId
    ) external payable;
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

    event FullPaymentSuccessful(
        address collection,
        uint256 tokenId,
        address buyer,
        uint256 price
    );

    event DownPaymentSuccessful(
        address collection,
        uint256 tokenId,
        address buyer,
        uint256 price
    );

    address public wethAddress;
    address public lenderAddress;
    uint256 public downPaymentRate;

    constructor(
        address _wethAddress,
        address _lenderAddress,
        uint256 _downPaymentRate
    ) {
        wethAddress = _wethAddress;
        lenderAddress = lenderAddress;
        downPaymentRate = _downPaymentRate;
    }

    function setDownpaymentRate(uint256 rate) external {
        downPaymentRate = rate;
    }

    function setLenderAddress(address _lenderAddress) external {
        lenderAddress = _lenderAddress;
    }

    function fire(
        address marketAdapter,
        address collection,
        uint256 tokenId,
        address buyer,
        uint256 price,
        bool downPayment,
        bytes calldata data
    ) external {
        uint256 _requiredBalence = price;
        if (downPayment) {
            _requiredBalence = LowGasSafeMath.mul(price, downPaymentRate) / 100;
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

        if (!downPayment) {
            IMarketAdapter(marketAdapter).purchaseNFT(
                collection,
                tokenId,
                data
            );

            IERC721(collection).safeTransferFrom(address(this), buyer, tokenId);
            emit FullPaymentSuccessful(collection, tokenId, buyer, price);
        } else {
            IDownPayment(lenderAddress).buy(
                marketAdapter,
                LowGasSafeMath.sub(price, _requiredBalence),
                data,
                sig
            );
            emit DownPaymentSuccessful(collection, tokenId, buyer, price);
        }
    }
}
