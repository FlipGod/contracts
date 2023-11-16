// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

// Uncomment this line to use console.log
import "hardhat/console.sol";
import "@benddao/bend-downpayment/contracts/interfaces/IDownpayment.sol";
import "@benddao/bend-downpayment/contracts/interfaces/IDebtToken.sol";
import "@benddao/bend-downpayment/contracts/interfaces/IWETH.sol";
import "@benddao/bend-downpayment/contracts/interfaces/ILendPoolAddressesProvider.sol";
import "@benddao/bend-downpayment/contracts/interfaces/ILendPool.sol";
import "@benddao/bend-downpayment/contracts/libraries/PercentageMath.sol";
import "@openzeppelin/contracts/interfaces/IERC1271.sol";
import "@openzeppelin/contracts/interfaces/IERC721.sol";
import "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {IERC20Upgradeable, SafeERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

struct Sig {
    uint8 v;
    bytes32 r;
    bytes32 s;
}

interface IMarketAdapter {
    function purchaseNFT(
        address collection,
        uint256 tokenId,
        bytes calldata data,
        Sig calldata sig
    ) external;
}

contract DealHunter is IERC1271, OwnableUpgradeable, IERC721Receiver {
    using PercentageMath for uint256;
    using SafeERC20Upgradeable for IERC20Upgradeable;

    event FullPaymentSuccessful(
        address collection,
        uint256 tokenId,
        address buyer,
        uint256 purchaseAmount
    );

    event DownPaymentSuccessful(
        address collection,
        uint256 tokenId,
        address buyer,
        uint256 purchaseAmount,
        uint256 borrowAmount
    );

    event TokenReclaimed(
        address collection,
        uint256 tokenId,
        address buyer,
        uint256 paybackAmount
    );

    event LoanPartialRepaied(
        address collection,
        uint256 tokenId,
        address buyer,
        uint256 paybackAmount,
        bool loanClosed
    );

    event ERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes data
    );

    bytes4 internal constant MAGICVALUE = 0x1626ba7e;
    IWETH public weth;
    IDebtToken public debtWeth;
    IDownpayment public lender;
    ILendPoolAddressesProvider public lendPoolProvider;
    uint256 public downPaymentFeeRetio;

    function initialize(
        address _wethAddress,
        address _debtWethAddress,
        address _lenderAddress,
        address _lendPoolProviderAddress,
        uint256 _downPaymentFeeRetio
    ) external initializer {
        __Ownable_init();
        weth = IWETH(_wethAddress);
        debtWeth = IDebtToken(_debtWethAddress);
        lender = IDownpayment(_lenderAddress);
        lendPoolProvider = ILendPoolAddressesProvider(_lendPoolProviderAddress);
        downPaymentFeeRetio = _downPaymentFeeRetio;
    }

    function setDebtWethAddress(address _debtWethAddress) external onlyOwner {
        debtWeth = IDebtToken(_debtWethAddress);
    }

    function setLenderAddress(address _lenderAddress) external onlyOwner {
        lender = IDownpayment(_lenderAddress);
    }

    function setLendPoolProviderAddress(
        address _lendPoolProviderAddress
    ) external onlyOwner {
        lendPoolProvider = ILendPoolAddressesProvider(_lendPoolProviderAddress);
    }

    function setDownPaymentFee(uint256 _downPaymentFee) external onlyOwner {
        downPaymentFeeRetio = _downPaymentFee;
    }

    function fire(
        address marketAdapter,
        address collection,
        uint256 tokenId,
        address payable buyer,
        uint256 price,
        bool payDown,
        bytes calldata data,
        Sig calldata sig
    ) external payable onlyOwner {
        uint256 _requiredBalence = price;
        uint256 _borrowAmount = 0;
        if (payDown) {
            (, , , _borrowAmount, , , ) = ILendPool(
                lendPoolProvider.getLendPool()
            ).getNftCollateralData(collection, address(weth));
            _requiredBalence =
                _requiredBalence -
                _borrowAmount +
                _requiredBalence.percentMul(downPaymentFeeRetio);

            console.log("from contract(_requiredBalence):", _requiredBalence);
            console.log("from contract(_borrowAmount):", _borrowAmount);
        }

        console.log("from contract balance of buyer :", weth.balanceOf(buyer));

        require(
            weth.balanceOf(buyer) >= _requiredBalence,
            "buyer's balance is insufficient"
        );
        require(
            weth.allowance(buyer, address(this)) >= _requiredBalence,
            "the WETH allowance is insufficient"
        );

        weth.transferFrom(buyer, address(this), _requiredBalence);

        console.log("from contract: transfer successed");
        console.log(
            "from contract(contract owned weth):",
            weth.balanceOf(address(this))
        );
        // IWETH(wethAddress).withdraw(_requiredBalence);
        console.log("from contract: withdraw successed");

        if (!payDown) {
            IMarketAdapter(marketAdapter).purchaseNFT(
                collection,
                tokenId,
                data,
                sig
            );

            IERC721(collection).safeTransferFrom(address(this), buyer, tokenId);
            emit FullPaymentSuccessful(
                collection,
                tokenId,
                buyer,
                _requiredBalence
            );
        } else {
            weth.approve(marketAdapter, _requiredBalence);
            debtWeth.approveDelegation(marketAdapter, _borrowAmount);
            lender.buy(
                marketAdapter,
                _borrowAmount,
                data,
                IDownpayment.Sig(sig.v, sig.r, sig.s)
            );
            emit DownPaymentSuccessful(
                collection,
                tokenId,
                buyer,
                _requiredBalence,
                _borrowAmount
            );
        }
    }

    function repay(
        address collection,
        uint256 tokenId,
        uint256 paybackAmount
    ) external payable {
        address receiver = msg.sender;

        if (msg.value > 0) {
            weth.deposit{value: msg.value}();
            IERC20Upgradeable(address(weth)).safeTransfer(receiver, msg.value);
        }

        require(
            weth.balanceOf(receiver) >= paybackAmount,
            "buyer's balance is insufficient"
        );
        require(
            weth.allowance(receiver, address(this)) >= paybackAmount,
            "the WETH allowance is insufficient"
        );

        address lendPoolAddress = lendPoolProvider.getLendPool();

        weth.transferFrom(receiver, address(this), paybackAmount);
        weth.approve(lendPoolAddress, paybackAmount);

        (uint256 realPaybackAmount, bool loanClosed) = ILendPool(
            lendPoolAddress
        ).repay(collection, tokenId, paybackAmount);
        if (loanClosed) {
            IERC721(collection).safeTransferFrom(
                address(this),
                receiver,
                tokenId
            );

            emit TokenReclaimed(
                collection,
                tokenId,
                receiver,
                realPaybackAmount
            );
        }
        emit LoanPartialRepaied(
            collection,
            tokenId,
            receiver,
            realPaybackAmount,
            loanClosed
        );
    }

    receive() external payable {}

    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes calldata data
    ) external override returns (bytes4) {
        emit ERC721Received(operator, from, tokenId, data);
        return IERC721Receiver.onERC721Received.selector;
    }

    function isValidSignature(
        bytes32 hash,
        bytes memory signature
    ) external view override returns (bytes4 magicValue) {
        // console.log("from contract(isValidSignature):", owner());
        // console.logBytes32(hash);
        // console.logBytes(signature);
        if (SignatureChecker.isValidSignatureNow(owner(), hash, signature))
            return MAGICVALUE;
        else return 0xffffffff;
    }
}
