const { expect, use, util } = require("chai");

const { ethers } = require("hardhat");
const { utils } = require("ethers");



describe("Escrow Contract", function () {
  let escrow;
  let WETH = "0xB4FBF271143F4FBf7B91A5ded31805e42b2208d6";
  let DAI;
  let user0;
  let user1;
  let owner;

  beforeEach(async () => {
    [user0, user1,owner] = await ethers.getSigners();
    const ERC20Factory = await ethers.getContractFactory("TestERC20");
    DAI = await ERC20Factory.deploy();
    await DAI.deployed();
    const EscrowFactory = await ethers.getContractFactory("Escrow");
    escrow = await EscrowFactory.deploy(owner.address);
    await escrow.deployed();
  });

  async function signOrder(signer, data) {
    const domain = {  
      name:"Dafi-Protocol" ,
      version:"V1" ,
      chainId: 31337, // Replace with the Hardhat's chain ID
      verifyingContract: escrow.address,
    };
    const types = {
      Data: [
        { name: "sellToken", type: "address" },
        { name: "buyToken", type: "address" },
        { name: "receiver", type: "address" },
        { name: "sellAmount", type: "uint256" },
        { name: "buyAmount", type: "uint256" },
        { name: "validTo", type: "uint32" },
        { name: "partiallyFillable", type: "bool" },
        { name: "feeAmount", type: "uint256" },
      ],
    };

    const value = {
      sellToken: data.sellToken,
      buyToken: data.buyToken,
      receiver: data.receiver,
      sellAmount: data.sellAmount,
      buyAmount: data.buyAmount,
      validTo: data.validTo,
      partiallyFillable: data.partiallyFillable,
      feeAmount: data.feeAmount,
    };
    const signature = await signer._signTypedData(domain, types, value);
    const recoverAddress = ethers.utils.verifyTypedData(domain, types, value, signature);
    return signature;
}





  it("Should deposit and withdraw tokens", async function () {
    const tokenAddress = DAI.address;
    const amountToDeposit = ethers.utils.parseEther("1");
    await DAI.mint(user0.address,amountToDeposit);
    await DAI.mint(user1.address,amountToDeposit);
    await DAI.approve(escrow.address, amountToDeposit);
    await DAI.connect(user1).approve(escrow.address, amountToDeposit);
    await escrow.connect(user0).depositToken(tokenAddress, amountToDeposit,{value:0});
    await escrow.connect(user0).depositToken(WETH, amountToDeposit,{value:ethers.utils.parseEther("1")});
    await escrow.connect(user1).depositToken(tokenAddress, amountToDeposit,{value:0});
    await escrow.connect(user1).depositToken(WETH, amountToDeposit,{value:ethers.utils.parseEther("1")});
    await escrow.connect(user0).withdraw(tokenAddress, amountToDeposit);
    await escrow.connect(user1).withdraw(tokenAddress, amountToDeposit);
    await escrow.connect(user0).withdraw(WETH, amountToDeposit);
    await escrow.connect(user1).withdraw(WETH, amountToDeposit);
  });

  it("Should settle full order", async function (){
    const tokenAddress = DAI.address;
    const amountToDeposit = ethers.utils.parseEther("1801");
    await DAI.mint(user0.address,amountToDeposit);
    await DAI.approve(escrow.address, amountToDeposit);
    await escrow.connect(user0).depositToken(tokenAddress, amountToDeposit,{value:0});
    await escrow.connect(user1).depositToken(WETH, ethers.utils.parseEther("1.01"),{value:ethers.utils.parseEther("1.01")});
    let sellToken = DAI.address;
    let buyToken = WETH;
    let receiver = user0.address;
    let sellAmount = ethers.utils.parseEther("1800");
    let buyAmount = ethers.utils.parseEther("1");
    let validTo = Math.floor(Date.now() / 1000) + 3600; // Valid for 1 hour
    let partiallyFillable = true;
    let feeAmount = ethers.utils.parseEther("0.01");

    let Order0data = {
      sellToken,
      buyToken,
      receiver,
      sellAmount,
      buyAmount,
      validTo,
      partiallyFillable,
      feeAmount,
    };
    let signature0 = await signOrder(user0,Order0data);

    sellToken = WETH;
    buyToken = DAI.address;
    receiver = user1.address;
    sellAmount = ethers.utils.parseEther("1");
    buyAmount = ethers.utils.parseEther("1800");
    validTo = Math.floor(Date.now() / 1000) + 3600; // Valid for 1 hour
    partiallyFillable = true;
    feeAmount = ethers.utils.parseEther("0.01");
    let Order1data = {
      sellToken,
      buyToken,
      receiver,
      sellAmount,
      buyAmount,
      validTo,
      partiallyFillable,
      feeAmount,
    };
    let signature1 = await signOrder(user1,Order1data);
    await escrow.settleOrders([Order0data,Order1data],[signature0,signature1]);
     
  });

  it("Should settle order partilly filled", async function (){
    const tokenAddress = DAI.address;
    const amountToDeposit = ethers.utils.parseEther("1801");
    await DAI.mint(user0.address,amountToDeposit);
    await DAI.approve(escrow.address, amountToDeposit);
    await escrow.connect(user0).depositToken(tokenAddress, amountToDeposit,{value:0});
    await escrow.connect(user1).depositToken(WETH, ethers.utils.parseEther("1.01"),{value:ethers.utils.parseEther("1.01")});
    let sellToken = DAI.address;
    let buyToken = WETH;
    let receiver = user0.address;
    let sellAmount = ethers.utils.parseEther("1800");
    let buyAmount = ethers.utils.parseEther("1");
    let validTo = Math.floor(Date.now() / 1000) + 3600; // Valid for 1 hour
    let partiallyFillable = true;
    let feeAmount = ethers.utils.parseEther("0.01");

    let Order0data = {
      sellToken,
      buyToken,
      receiver,
      sellAmount,
      buyAmount,
      validTo,
      partiallyFillable,
      feeAmount,
    };

    let signature0 = await signOrder(user0,Order0data);
    sellToken = WETH;
    buyToken = DAI.address;
    receiver = user1.address;
    sellAmount = ethers.utils.parseEther("0.5");
    buyAmount = ethers.utils.parseEther("900");
    validTo = Math.floor(Date.now() / 1000) + 3600; // Valid for 1 hour
    partiallyFillable = true;
    feeAmount = ethers.utils.parseEther("0.01");

    let Order1data = {
      sellToken,
      buyToken,
      receiver,
      sellAmount,
      buyAmount,
      validTo,
      partiallyFillable,
      feeAmount,
    };
    let signature1 = await signOrder(user1,Order1data); 
    
    await escrow.settleOrders([Order0data,Order1data],[signature0,signature1]);
    await escrow.connect(owner).withdraw(DAI.address,ethers.utils.parseEther("0.01"));
    await escrow.connect(user0).cancelOrder(signature0,Order0data);
    await escrow.connect(user0).withdraw(DAI.address,ethers.utils.parseEther("900"));
  });

  it("Should revert settle order", async function (){
    const tokenAddress = DAI.address;
    const amountToDeposit = ethers.utils.parseEther("1801");
    await DAI.mint(user0.address,amountToDeposit);
    await DAI.approve(escrow.address, amountToDeposit);
    await escrow.connect(user0).depositToken(tokenAddress, amountToDeposit,{value:0});
    await escrow.connect(user1).depositToken(WETH, ethers.utils.parseEther("1.01"),{value:ethers.utils.parseEther("1.01")});
    let sellToken = DAI.address;
    let buyToken = WETH;
    let receiver = user0.address;
    let sellAmount = ethers.utils.parseEther("1800");
    let buyAmount = ethers.utils.parseEther("1");
    let validTo = Math.floor(Date.now() / 1000) + 3600; // Valid for 1 hour
    let partiallyFillable = false;
    let feeAmount = ethers.utils.parseEther("0.01");

    let Order0data = {
      sellToken,
      buyToken,
      receiver,
      sellAmount,
      buyAmount,
      validTo,
      partiallyFillable,
      feeAmount,
    };

    let signature0 = await signOrder(user0,Order0data);
    sellToken = WETH;
    buyToken = DAI.address;
    receiver = user1.address;
    sellAmount = ethers.utils.parseEther("0.5");
    buyAmount = ethers.utils.parseEther("900");
    validTo = Math.floor(Date.now() / 1000) + 3600; // Valid for 1 hour
    partiallyFillable = true;
    feeAmount = ethers.utils.parseEther("0.01");

    let Order1data = {
      sellToken,
      buyToken,
      receiver,
      sellAmount,
      buyAmount,
      validTo,
      partiallyFillable,
      feeAmount,
    };
    let signature1 = await signOrder(user1,Order1data);  
    await expect ( escrow.settleOrders([Order0data,Order1data],[signature0,signature1])).to.be.revertedWith("!partiallyfillable");
  });


  it("should get GPV2 hash for cowswap", async function(){
    const tokenAddress = DAI.address;
    const amountToDeposit = ethers.utils.parseEther("1801");
    await DAI.mint(user0.address,amountToDeposit);
    await DAI.approve(escrow.address, amountToDeposit);
    await escrow.connect(user0).depositToken(tokenAddress, amountToDeposit,{value:0});
    await escrow.connect(user1).depositToken(WETH, ethers.utils.parseEther("1.01"),{value:ethers.utils.parseEther("1.01")});
    let sellToken = DAI.address;
    let buyToken = WETH;
    let receiver = user0.address;
    let sellAmount = ethers.utils.parseEther("1800");
    let buyAmount = ethers.utils.parseEther("1");
    let validTo = Math.floor(Date.now() / 1000) + 3600; // Valid for 1 hour
    let partiallyFillable = false;
    let feeAmount = ethers.utils.parseEther("0.01");

    let Orderdata = {
      sellToken,
      buyToken,
      receiver,
      sellAmount,
      buyAmount,
      validTo,
      partiallyFillable,
      feeAmount,
    };

    let signature = await signOrder(user0,Orderdata);
    await escrow.getHashGPV2(Orderdata,signature);
  });

  it("Should settle order partilly filled and check mappings and IsValidSig", async function (){
    const tokenAddress = DAI.address;
    const amountToDeposit = ethers.utils.parseEther("1801");
    await DAI.mint(user0.address,amountToDeposit);
    await DAI.approve(escrow.address, amountToDeposit);
    await escrow.connect(user0).depositToken(tokenAddress, amountToDeposit,{value:0});
    await escrow.connect(user1).depositToken(WETH, ethers.utils.parseEther("1.01"),{value:ethers.utils.parseEther("1.01")});
    let sellToken = DAI.address;
    let buyToken = WETH;
    let receiver = user0.address;
    let sellAmount = ethers.utils.parseEther("1800");
    let buyAmount = ethers.utils.parseEther("1");
    let validTo = Math.floor(Date.now() / 1000) + 3600; // Valid for 1 hour
    let partiallyFillable = true;
    let feeAmount = ethers.utils.parseEther("0.01");

    let Order0data = {
      sellToken,
      buyToken,
      receiver,
      sellAmount,
      buyAmount,
      validTo,
      partiallyFillable,
      feeAmount,
    };

    let signature0 = await signOrder(user0,Order0data);
    sellToken = WETH;
    buyToken = DAI.address;
    receiver = user1.address;
    sellAmount = ethers.utils.parseEther("0.5");
    buyAmount = ethers.utils.parseEther("900");
    validTo = Math.floor(Date.now() / 1000) + 3600; // Valid for 1 hour
    partiallyFillable = true;
    feeAmount = ethers.utils.parseEther("0.01");

    let Order1data = {
      sellToken,
      buyToken,
      receiver,
      sellAmount,
      buyAmount,
      validTo,
      partiallyFillable,
      feeAmount,
    };
    let signature1 = await signOrder(user1,Order1data); 
    await escrow.settleOrders([Order0data,Order1data],[signature0,signature1]);
    let tx0 = await escrow.unfilledOrderInfo(signature0); 
    await escrow.unfilledOrderInfo(signature1);
    await escrow.isValidSignature(tx0.orderHash,signature0);

  });


  it("Should settle order partilly filled and check mappings and IsValidSig", async function (){
    const tokenAddress = DAI.address;
    const amountToDeposit = ethers.utils.parseEther("1801");
    await DAI.mint(user0.address,amountToDeposit);
    await DAI.approve(escrow.address, amountToDeposit);
    await escrow.connect(user0).depositToken(tokenAddress, amountToDeposit,{value:0});
    await escrow.connect(user1).depositToken(WETH, ethers.utils.parseEther("1.01"),{value:ethers.utils.parseEther("1.01")});
    let sellToken = DAI.address;
    let buyToken = WETH;
    let receiver = user0.address;
    let sellAmount = ethers.utils.parseEther("1800");
    let buyAmount = ethers.utils.parseEther("1");
    let validTo = Math.floor(Date.now() / 1000) + 3600; // Valid for 1 hour
    let partiallyFillable = true;
    let feeAmount = ethers.utils.parseEther("0.01");

    let Order0data = {
      sellToken,
      buyToken,
      receiver,
      sellAmount,
      buyAmount,
      validTo,
      partiallyFillable,
      feeAmount,
    };

    let signature0 = await signOrder(user0,Order0data);
    sellToken = WETH;
    buyToken = DAI.address;
    receiver = user1.address;
    sellAmount = ethers.utils.parseEther("0.5");
    buyAmount = ethers.utils.parseEther("900");
    validTo = Math.floor(Date.now() / 1000) + 3600; // Valid for 1 hour
    partiallyFillable = true;
    feeAmount = ethers.utils.parseEther("0.01");

    let Order1data = {
      sellToken,
      buyToken,
      receiver,
      sellAmount,
      buyAmount,
      validTo,
      partiallyFillable,
      feeAmount,
    };
    let signature1 = await signOrder(user1,Order1data); 
    await escrow.settleOrders([Order0data,Order1data],[signature0,signature1]);
    let tx0 = await escrow.unfilledOrderInfo(signature0); 
    await escrow.unfilledOrderInfo(signature1);
    await escrow.isValidSignature(tx0.orderHash,signature0);
  });
});
