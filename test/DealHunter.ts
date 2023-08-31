import {
  time,
  loadFixture,
} from "@nomicfoundation/hardhat-toolbox/network-helpers";
import { anyValue } from "@nomicfoundation/hardhat-chai-matchers/withArgs";
import { expect } from "chai";
import { ethers } from "hardhat";
import { createSignedFlashloanParams } from "./helper/opensea";

const abiCoder = ethers.AbiCoder.defaultAbiCoder();

const WETHAddress = '0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2';
const DownPaymentAddress = '0x3710D54de90324C8BA4B534D1e3F0fCEDc679ca4';
const DbetWETHAddress = '0x87ddE3A3f4b629E389ce5894c9A1F34A7eeC5648';
const DownPaymentRatio = 4200;
const paymentCases = {
  opensea: {
    orderInput: {
      "considerationToken": "0x0000000000000000000000000000000000000000",
      "considerationIdentifier": "0",
      "considerationAmount": "47500000000000000000",
      "offerer": "0x66dd2e46331219d1046b8452a04806eb6ba07ef3",
      "zone": "0x004c00500000ad104d7dbd00e3ae0a5c00560c00",
      "offerToken": "0xbc4ca0eda7647a8ab7c2061c2e118a18a936f13d",
      "offerIdentifier": "4758",
      "offerAmount": "1",
      "basicOrderType": 0,
      "startTime": "1692380340",
      "endTime": "1695058740",
      "zoneHash": "0x0000000000000000000000000000000000000000000000000000000000000000",
      "salt": "24446860302761739304752683030156737591518664810215442929809170743478567736856",
      "offererConduitKey": "0x0000007b02230091a7ed01230072f7006a004d60a8d4e71d599b8104250f0000",
      "fulfillerConduitKey": "0x0000007b02230091a7ed01230072f7006a004d60a8d4e71d599b8104250f0000",
      "totalOriginalAdditionalRecipients": "2",
      "additionalRecipients": [
        {
          "amount": "1250000000000000000",
          "recipient": "0x0000a26b00c1f0df003000390027140000faa719"
        },
        {
          "amount": "1250000000000000000",
          "recipient": "0xa858ddc0445d8131dac4d1de01f834ffcba52ef1"
        }
      ],
      "signature": "0x199a1dec0ee32862553572ae7d947660dbbf6227545dd8011cf72c3465f3751fd32e7a0b471dcfcae62c675fc61711bac4f4921da7484cb0da65931860418467",
    },
    tokenId: '4758',
    price: '50',
    nftContract: {
      address: '0xbc4ca0eda7647a8ab7c2061c2e118a18a936f13d',
      name: "BAYC"
    },
    adapterFullPayment: '',
    adapterDownPayment: '0x8B5ABF01b87f87Fb8e0FfC60D32ed7DD29b1f06b',
  }
}

describe("DealHunter", function () {
  // We define a fixture to reuse the same setup in every test.
  // We use loadFixture to run this setup once, snapshot that state,
  // and reset Hardhat Network to that snapshot in every test.
  async function deployDHFixture() {
    // Contracts are deployed using the first signer/account by default
    const [owner, otherAccount, buyer] = await ethers.getSigners();
    const wethProvider = await ethers.getImpersonatedSigner('0x2fEb1512183545f48f6b9C5b4EbfCaF49CfCa6F3')
    const addressPlaceholder = await ethers.Wallet.createRandom().getAddress();
    const calldataPlaceholder = abiCoder.encode(['uint256'], [0]);

    const DH = await ethers.getContractFactory("DealHunter");
    const dh = await DH.deploy(WETHAddress, DbetWETHAddress, DownPaymentAddress, DownPaymentRatio);
    const weth = await ethers.getContractAt('IWETH', WETHAddress);
    const dp = await ethers.getContractAt('IDownpayment', DownPaymentAddress);
    const bendAddressesProvider = await ethers.getContractAt("ILendPoolAddressesProvider", "0x24451f47caf13b24f4b5034e1df6c0e401ec0e46");
    const bendLendPool = await ethers.getContractAt("ILendPool", await bendAddressesProvider.getLendPool());

    await weth.connect(wethProvider).transfer(buyer, await weth.balanceOf(wethProvider));

    console.log(`WETH Buyer balance ${buyer.address}: ${await weth.balanceOf(buyer)}`);

    return { dh, weth, dp, bendLendPool, owner, otherAccount, buyer, addressPlaceholder, calldataPlaceholder };
  }

  describe("Deployment", function () {
    it("Should set the right WETH contract address", async function () {
      const { dh } = await loadFixture(deployDHFixture);

      expect(await dh.wethAddress()).to.equal(WETHAddress);
    });

    it("Should set the right DownPayment contract address", async function () {
      const { dh } = await loadFixture(deployDHFixture);

      expect(await dh.lenderAddress()).to.equal(DownPaymentAddress);
    });

    it("Should set the right DownPaymentRate ", async function () {
      const { dh } = await loadFixture(deployDHFixture);

      expect(await dh.downPaymentRatio()).to.equal(DownPaymentRatio);
    });
  });

  describe("Setters", function () {
    it("Should set the right DownPaymentRate", async function () {
      const { dh } = await loadFixture(deployDHFixture);
      const newRate = 50;
      await dh.setDownPaymentRate(newRate);
      expect(await dh.downPaymentRatio()).to.equal(newRate);
    });


    it("Should set the right LenderAddress", async function () {
      const { dh, otherAccount } = await loadFixture(deployDHFixture);

      const newAddress = otherAccount.address;
      await dh.setLenderAddress(newAddress);
      expect(await dh.lenderAddress()).to.equal(newAddress);
    });
  })

  describe("Fire", function () {
    describe("Validations", function () {
      it("Should revert with the right error if balance is low when full payment", async function () {
        const { dh, owner, addressPlaceholder, calldataPlaceholder } = await loadFixture(deployDHFixture);

        const emptyAccount = await ethers.getSigner(ethers.Wallet.createRandom().address);
        await expect(
          dh.connect(owner).fire(
            addressPlaceholder,
            addressPlaceholder,
            BigInt(0),
            await emptyAccount.getAddress(),
            ethers.parseEther('50'),
            false,
            calldataPlaceholder,
            { v: BigInt(0), r: calldataPlaceholder, s: calldataPlaceholder, }
          )
        ).to.be.revertedWith(
          "buyer's balance is too low"
        );
      });

      it("Should revert with the right error if balance is low when down payment", async function () {
        const { dh, owner, addressPlaceholder, calldataPlaceholder } = await loadFixture(deployDHFixture);

        const emptyAccount = await ethers.getSigner(ethers.Wallet.createRandom().address);
        await expect(
          dh.connect(owner).fire(
            addressPlaceholder,
            addressPlaceholder,
            BigInt(0),
            await emptyAccount.getAddress(),
            ethers.parseEther('50'),
            true,
            calldataPlaceholder,
            { v: BigInt(0), r: calldataPlaceholder, s: calldataPlaceholder, }
          )
        ).to.be.revertedWith(
          "buyer's balance is too low"
        );
      });

      it("Should revert with the right error if balance is not engouth when down payment", async function () {
        const { dh, weth, owner, buyer, addressPlaceholder, calldataPlaceholder } = await loadFixture(deployDHFixture);
        const sellPrice = 50;
        const amountShouldTransfer = BigInt("13813826751282430350873") - ethers.parseEther((sellPrice * 0.42 - 0.1).toString());

        await weth.connect(buyer).transfer(owner.address, amountShouldTransfer);
        await weth.connect(buyer).approve(await dh.getAddress(), ethers.parseEther('50'));

        await expect(
          dh.connect(owner).fire(
            addressPlaceholder,
            addressPlaceholder,
            BigInt(0),
            buyer.address,
            ethers.parseEther(sellPrice.toString()),
            true,
            calldataPlaceholder,
            { v: BigInt(0), r: calldataPlaceholder, s: calldataPlaceholder, }
          )
        ).to.be.revertedWith(
          "buyer's balance is too low"
        );
      });

      it("Should revert with the right error if WETH allowance is not enough", async function () {
        const { dh, owner, buyer, addressPlaceholder, calldataPlaceholder } = await loadFixture(deployDHFixture);

        await expect(
          dh.connect(owner).fire(
            addressPlaceholder,
            addressPlaceholder,
            BigInt(0),
            buyer.address,
            ethers.parseEther('50'),
            true,
            calldataPlaceholder,
            { v: BigInt(0), r: calldataPlaceholder, s: calldataPlaceholder, }
          )
        ).to.be.revertedWith(
          "the balance allowed from buyer is too low"
        );
      });

      it("Should revert with the right error if  WETH allowance is not engouth when down payment", async function () {
        const { dh, weth, owner, buyer, addressPlaceholder, calldataPlaceholder } = await loadFixture(deployDHFixture);
        const sellPrice = 50;

        await weth.connect(buyer).approve(await dh.getAddress(), ethers.parseEther('20.9'));

        await expect(
          dh.connect(owner).fire(
            addressPlaceholder,
            addressPlaceholder,
            BigInt(0),
            buyer.address,
            ethers.parseEther(sellPrice.toString()),
            true,
            calldataPlaceholder,
            { v: BigInt(0), r: calldataPlaceholder, s: calldataPlaceholder, }
          )
        ).to.be.revertedWith(
          "the balance allowed from buyer is too low"
        );
      });
    });

    describe("Full Payment", function () {
    });

    describe("Down Payment", function () {
      it("Should buyer reveiced NFT that they bought with 42% down payment", async function () {
        const { dh, weth, dp, bendLendPool, owner, buyer } = await loadFixture(deployDHFixture);

        await weth.connect(buyer).approve(
          await paymentCases.opensea.adapterDownPayment,
          // ethers.parseEther((Number(paymentCases.opensea.price) * 0.42).toString())
          await weth.balanceOf(buyer.address)
        );

        const signedParams = await createSignedFlashloanParams(
          1,
          buyer,
          paymentCases.opensea.adapterDownPayment,
          paymentCases.opensea.orderInput,
          await dp.nonces(buyer.address),
        );
        const borrowAmount = await bendLendPool.getNftCollateralData(
          paymentCases.opensea.nftContract.address,
          WETHAddress,
        );

        console.log(signedParams, borrowAmount.availableBorrowsInReserve);

        await dp.connect(buyer).buy(
          paymentCases.opensea.adapterDownPayment,
          borrowAmount.availableBorrowsInReserve,
          signedParams.data,
          signedParams.sig
        )

        // await dh.connect(owner).fire(
        //   paymentCases.opensea.adapterDownPayment,
        //   paymentCases.opensea.nftContract.address,
        //   BigInt(paymentCases.opensea.tokenId),
        //   buyer.address,
        //   ethers.parseEther('100'),
        //   borrowAmount.availableBorrowsInReserve,
        //   true,
        //   signedParams.data,
        //   signedParams.sig
        // );
      });
    });

    describe("Events", function () {
      it("Should emit an event on withdrawals", async function () {
        const { lock, unlockTime, lockedAmount } = await loadFixture(
          deployDHFixture
        );

        await time.increaseTo(unlockTime);

        await expect(lock.withdraw())
          .to.emit(lock, "Withdrawal")
          .withArgs(lockedAmount, anyValue); // We accept any value as `when` arg
      });
    });

    describe("Transfers", function () {
      it("Should transfer the funds to the owner", async function () {
        const { lock, unlockTime, lockedAmount, owner } = await loadFixture(
          deployDHFixture
        );

        await time.increaseTo(unlockTime);

        await expect(lock.withdraw()).to.changeEtherBalances(
          [owner, lock],
          [lockedAmount, -lockedAmount]
        );
      });
    });
  });
});
