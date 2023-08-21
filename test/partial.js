const { expect, use, util } = require("chai");

const { ethers } = require("hardhat");
const { utils } = require("ethers");



describe("Escrow Contract", function () {
  let escrow;
  let WETH = "0xB4FBF271143F4FBf7B91A5ded31805e42b2208d6";
  let DAI;

  before(async () => {
    [user0, user1,user2,user3,user4,user5,user6,user7,owner] = await ethers.getSigners();
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
    const amountToDeposit = ethers.utils.parseEther("20000");
    await DAI.mint(user0.address,amountToDeposit);
    await DAI.mint(user1.address,amountToDeposit);
    await DAI.mint(user2.address,amountToDeposit);
    await DAI.mint(user3.address,amountToDeposit);
    await DAI.mint(user4.address,amountToDeposit);
    await DAI.mint(user5.address,amountToDeposit);
    await DAI.mint(user6.address,amountToDeposit);
    await DAI.mint(user7.address,amountToDeposit);
    await DAI.approve(escrow.address, amountToDeposit);
    await DAI.connect(user1).approve(escrow.address, amountToDeposit);
    await DAI.connect(user2).approve(escrow.address, amountToDeposit);
    await DAI.connect(user3).approve(escrow.address, amountToDeposit);
    await DAI.connect(user4).approve(escrow.address, amountToDeposit);
    await DAI.connect(user5).approve(escrow.address, amountToDeposit);
    await DAI.connect(user6).approve(escrow.address, amountToDeposit);
    await DAI.connect(user7).approve(escrow.address, amountToDeposit);
    await escrow.connect(user0).depositToken(tokenAddress, amountToDeposit,{value:0});
    await escrow.connect(user0).depositToken(WETH, ethers.utils.parseEther("20"),{value:ethers.utils.parseEther("20")});
    await escrow.connect(user1).depositToken(tokenAddress, amountToDeposit,{value:0});
    await escrow.connect(user1).depositToken(WETH, ethers.utils.parseEther("20"),{value:ethers.utils.parseEther("20")});
    await escrow.connect(user2).depositToken(tokenAddress, amountToDeposit,{value:0});
    await escrow.connect(user2).depositToken(WETH, ethers.utils.parseEther("20"),{value:ethers.utils.parseEther("20")});
    await escrow.connect(user3).depositToken(tokenAddress, amountToDeposit,{value:0});
    await escrow.connect(user3).depositToken(WETH, ethers.utils.parseEther("20"),{value:ethers.utils.parseEther("20")});
    await escrow.connect(user4).depositToken(tokenAddress, amountToDeposit,{value:0});
    await escrow.connect(user4).depositToken(WETH, ethers.utils.parseEther("20"),{value:ethers.utils.parseEther("20")});
    await escrow.connect(user5).depositToken(tokenAddress, amountToDeposit,{value:0});
    await escrow.connect(user5).depositToken(WETH, ethers.utils.parseEther("20"),{value:ethers.utils.parseEther("20")});
    await escrow.connect(user6).depositToken(tokenAddress, amountToDeposit,{value:0});
    await escrow.connect(user6).depositToken(WETH, ethers.utils.parseEther("20"),{value:ethers.utils.parseEther("20")});
    await escrow.connect(user7).depositToken(tokenAddress, amountToDeposit,{value:0});
    await escrow.connect(user7).depositToken(WETH, ethers.utils.parseEther("20"),{value:ethers.utils.parseEther("20")});
  });

  it("Should test order with surplus", async function (){
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
    sellAmount = ethers.utils.parseEther("1.1");
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
    await escrow.settleOrders([Order1data,Order0data],[signature1,signature0]);
     
  });

  it("complete the unFilled State of order", async function (){
    let sellToken = DAI.address;
    let buyToken = WETH;
    let receiver = user0.address;
    let sellAmount = ethers.utils.parseEther("2000");
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
    sellAmount = ethers.utils.parseEther("0.25");
    buyAmount = ethers.utils.parseEther("500");
    validTo = Math.floor(Date.now() / 1000) + 3600; // Valid for 1 hour
    partiallyFillable = false;
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

    sellToken = WETH;
    buyToken = DAI.address;
    receiver = user2.address;
    sellAmount = ethers.utils.parseEther("0.25");
    buyAmount = ethers.utils.parseEther("500");
    validTo = Math.floor(Date.now() / 1000) + 3600; // Valid for 1 hour
    partiallyFillable = false;
    feeAmount = ethers.utils.parseEther("0.01");
    let Order2data = {
      sellToken,
      buyToken,
      receiver,
      sellAmount,
      buyAmount,
      validTo,
      partiallyFillable,
      feeAmount,
    };
    let signature2 = await signOrder(user2,Order2data);
    sellToken = WETH;
    buyToken = DAI.address;
    receiver = user1.address;
    sellAmount = ethers.utils.parseEther("0.75");
    buyAmount = ethers.utils.parseEther("1500");
    validTo = Math.floor(Date.now() / 1000) + 3600; // Valid for 1 hour
    partiallyFillable = true;
    feeAmount = ethers.utils.parseEther("0.01");
    let Order3data = {
      sellToken,
      buyToken,
      receiver,
      sellAmount,
      buyAmount,
      validTo,
      partiallyFillable,
      feeAmount,
    };
    let signature3 = await signOrder(user3,Order3data);
    await escrow.settleOrders([Order0data,Order1data],[signature0,signature1]);
    await escrow.settleOrders([Order0data,Order2data],[signature0,signature2]);
    await escrow.settleOrders([Order3data,Order0data],[signature3,signature0]);
  });

  it("complete order with surplus and last partially filled", async function (){
    let sellToken = DAI.address;
    let buyToken = WETH;
    let receiver = user0.address;
    let sellAmount = ethers.utils.parseEther("2000");
    let buyAmount = ethers.utils.parseEther("1");
    let validTo = Math.floor(Date.now() / 1000) + 3600; // Valid for 1 hour
    let partiallyFillable = false;
    let feeAmount = ethers.utils.parseEther("0.01");
    let Order4data = {
      sellToken,
      buyToken,
      receiver,
      sellAmount,
      buyAmount,
      validTo,
      partiallyFillable,
      feeAmount,
    };
    let signature4 = await signOrder(user4,Order4data);
    sellToken = WETH;
    buyToken = DAI.address;
    receiver = user1.address;
    sellAmount = ethers.utils.parseEther("0.5");
    buyAmount = ethers.utils.parseEther("950");
    validTo = Math.floor(Date.now() / 1000) + 3600; // Valid for 1 hour
    partiallyFillable = true;
    feeAmount = ethers.utils.parseEther("0.01");
    let Order5data = {
      sellToken,
      buyToken,
      receiver,
      sellAmount,
      buyAmount,
      validTo,
      partiallyFillable,
      feeAmount,
    };
    let signature5 = await signOrder(user5,Order5data);

    sellToken = WETH;
    buyToken = DAI.address;
    receiver = user2.address;
    sellAmount = ethers.utils.parseEther("0.75");
    buyAmount = ethers.utils.parseEther("1500");
    validTo = Math.floor(Date.now() / 1000) + 3600; // Valid for 1 hour
    partiallyFillable = true;
    feeAmount = ethers.utils.parseEther("0.01");
    let Order6data = {
      sellToken,
      buyToken,
      receiver,
      sellAmount,
      buyAmount,
      validTo,
      partiallyFillable,
      feeAmount,
    };
    let signature6 = await signOrder(user6,Order6data);

    sellToken = DAI.address;
    buyToken = WETH;
    receiver = user0.address;
    sellAmount = ethers.utils.parseEther("500");
    buyAmount = ethers.utils.parseEther("0.25");
    validTo = Math.floor(Date.now() / 1000) + 3600; // Valid for 1 hour
    partiallyFillable = true;
    feeAmount = ethers.utils.parseEther("0.01");
    Order7data = {
      sellToken,
      buyToken,
      receiver,
      sellAmount,
      buyAmount,
      validTo,
      partiallyFillable,
      feeAmount,
    };
    let signature7 = await signOrder(user7,Order7data);
    await escrow.settleOrders([Order4data,Order5data,Order6data],[signature4,signature5,signature6]);
    await escrow.settleOrders([Order6data,Order7data],[signature6,signature7]);
    
    // await escrow.settleOrders([Order0data,Order2data],[signature0,signature2]);
    // await escrow.settleOrders([Order3data,Order0data],[signature3,signature0]);
  });

  
});
