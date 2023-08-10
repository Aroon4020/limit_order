// // SPDX-License-Identifier: MIT
// pragma solidity ^0.8.17;

// import {ICoWSwapSettlement} from "./interfaces/ICoWSwapSettlement.sol";
// import {ERC1271_MAGIC_VALUE, IERC1271} from "./interfaces/IERC1271.sol";
// import {IERC20} from "./interfaces/IERC20.sol";
// import {IWETH} from "./interfaces/IWETH.sol";
// import {GPv2Order} from "./vendored/GPv2Order.sol";
// import {ICoWSwapOnchainOrders} from "./vendored/ICoWSwapOnchainOrders.sol";
// import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
// import "hardhat/console.sol";

// contract Escrow {
//     using GPv2Order for *;
//     bytes32 public constant APP_DATA = keccak256("ABC");
//     address WETH;

//     struct usersOrderOperations {
//         // IERC20 sellToken0;
//         // IERC20 buyToken0;
//         // uint256 amountToSell0;
//         // uint256 amountToBuy0;
//         // IERC20 sellToken1;
//         // IERC20 buyToken1;
//         // uint256 amountToSell1;
//         // uint256 amountToBuy1;
//         // uint256 clearingPrice;
//         uint256 remAmountToSell0;
//         uint256 remAmountToBuy0;
//         uint256 remAmountToSell1;
//         uint256 remAmountToBuy1;
//         //uint256 feeAmount;
//         Data order0;
//         bytes signature0;
//         address signer0;
//         Data order1;
//         bytes signature1;
//         address signer1;
//     }
//     struct Data {
//         IERC20 sellToken;
//         IERC20 buyToken;
//         address receiver;
//         uint256 sellAmount;
//         uint256 buyAmount;
//         uint32 validTo;
//         bool partiallyFillable;
//         uint256 feeAmount;
//     }

//     struct unFilledOrder {
//         IERC20 sellToken;
//         uint256 amountToSell;
//         IERC20 buyToken;
//         uint256 amountToBuy;
//     }

//     address owner;

//     mapping(address => mapping(address => uint256)) public depositInfo;
//     mapping(bytes => unFilledOrder) public unFilledOrderInfo; //should not be against msg.sender!
//     mapping(bytes32 => bool) public unFilledOrderHash;

//     ICoWSwapSettlement public immutable settlement;
//     bytes32 public immutable domainSeparator;

//     constructor(ICoWSwapSettlement settlement_) {
//         settlement = settlement_;
//         domainSeparator = settlement_.domainSeparator();
//     }

//     receive() external payable {}

//     function depositToken(address token, uint256 amount) external payable {
//         _pay(token, amount);
//         depositInfo[msg.sender][token] =
//             depositInfo[msg.sender][token] +
//             amount;
//     }

//     //The 'taker' is someone who decides to place an order that is instantly matched with an existing order on the order book. Maker.
//     //You become a “maker” when you place an order and it does not trade immediately, so your order stays

//     //1 ETH - 2000 USDT
//     //1000 USDT - 1 ETH
//     //500 USDT - 0.25

//     function settleOrders(
//         Data[] calldata data,
//         bytes[] calldata signature
//     ) external {
//         usersOrderOperations memory userOps;
//         userOps.order0 = data[0];
//         userOps.signer0 = verifySigner(userOps.order0, signature[0]);//not in case of partial
//         (
//             userOps.order0.sellToken0,
//             userOps.buyToken0,
//             userOps.amountToSell0,
//             userOps.amountToBuy0,
//             userOps.order0.feeAmount
//         ) = extractOrderData(userOps.order0,signature[0]);
//         userOps.remAmountToBuy0 = userOps.amountToBuy0;
//         userOps.remAmountToSell0 = userOps.amountToSell0;
//         require(
//             depositInfo[userOps.signer0][address(userOps.sellToken0)] >=
//                 userOps.amountToSell0 + userOps.feeAmount
//         );
//         //deduct % of amount of trade filled
//         userOps.order0.sellToken.transfer(owner, userOps.feeAmount);
//         for (uint256 i = 1; i < data.length; ) {
//             userOps.order1 = data[i];
//             userOps.signer1 = verifySigner(userOps.order1, signature[i]);
//             (
//                 userOps.sellToken1,
//                 userOps.buyToken1,
//                 userOps.amountToSell1,
//                 userOps.amountToBuy1,
//                 userOps.feeAmount    
//             ) = extractOrderData(data[i],signature[i]);
//             executeTrade(userOps);
//             unchecked {
//                 ++i;
//             }
//         }
//         checkAndUpdatePartialOrder(userOps);
//     }

//     function executeTrade(usersOrderOperations memory userOps) internal {
//             require(userOps.buyToken0 == userOps.sellToken1);
//             require(userOps.sellToken0 == userOps.buyToken1);
//             require(
//                 depositInfo[userOps.signer1][address(userOps.sellToken1)] >=
//                     userOps.amountToSell1 + userOps.feeAmount
//             );
//             userOps.remAmountToSell1 = userOps.amountToSell1; //1000,250
//             userOps.remAmountToBuy1 = userOps.amountToBuy1; //0.5,0.125
//             userOps.sellToken1.transfer(owner, userOps.feeAmount);
//             userOps.clearingPrice =
//                 (userOps.amountToSell0 * userOps.amountToSell1) /
//                 userOps.amountToBuy0; //0.5
//             require(userOps.clearingPrice <= userOps.amountToBuy1);
        
//         if (userOps.clearingPrice > userOps.remAmountToSell0) {
//                 if(userOps.order0.receiver==address(this)){

//                 }

//                 userOps.sellToken1.transfer(
//                     userOps.order0.receiver,
//                     userOps.remAmountToBuy0
//                 ); //750
//                 userOps.buyToken1.transfer(
//                     userOps.order1.receiver,
//                     userOps.remAmountToSell0
//                 ); //0.375
//                 depositInfo[userOps.signer1][address(userOps.sellToken1)] =
//                     depositInfo[userOps.signer1][address(userOps.sellToken1)] -
//                     userOps.remAmountToBuy0;
//                 depositInfo[userOps.signer0][address(userOps.sellToken0)] =
//                     depositInfo[userOps.signer0][address(userOps.sellToken0)] -
//                     userOps.remAmountToSell0;
//                 userOps.remAmountToSell1 =
//                     userOps.remAmountToSell1 -
//                     userOps.remAmountToBuy0; //1000-750 250
//                 userOps.remAmountToBuy1 =
//                     userOps.remAmountToBuy1 -
//                     userOps.remAmountToSell0; //0.5-0.375
//                 userOps.remAmountToSell0 = 0; //
//                 userOps.remAmountToBuy0 = 0;
//             } else {
//                 require(userOps.clearingPrice >= userOps.amountToBuy1); // not need I think!
//                 userOps.sellToken1.transfer(
//                     userOps.order0.receiver,
//                     userOps.amountToSell1
//                 ); //1000,250
//                 userOps.buyToken1.transfer(
//                     userOps.order1.receiver,
//                     userOps.clearingPrice
//                 ); //0.5, 0.125
//                 depositInfo[userOps.signer1][address(userOps.sellToken1)] =
//                     depositInfo[userOps.signer1][address(userOps.sellToken1)] -
//                     userOps.amountToSell1;
//                 depositInfo[userOps.signer0][address(userOps.sellToken0)] =
//                     depositInfo[userOps.signer0][address(userOps.sellToken0)] -
//                     userOps.clearingPrice;
//                 userOps.remAmountToSell1 = 0;
//                 userOps.remAmountToBuy1 = 0;
//                 userOps.remAmountToSell0 =
//                     userOps.remAmountToSell0 -
//                     userOps.clearingPrice; //1-0.5 = 0.5, 0.5-0.125 = 0.375
//                 userOps.remAmountToBuy0 =
//                     userOps.remAmountToBuy0 -
//                     userOps.amountToSell1; //2000-1000, 1000-250 = 750
//             }
//     }

//     function checkAndUpdatePartialOrder(
//         usersOrderOperations memory userOps
//     ) internal {
//         if (userOps.clearingPrice > userOps.remAmountToSell0) {
//             require(userOps.order1.partiallyFillable);
//             unFilledOrder memory unFilled;
//             unFilled.sellToken = userOps.order1.sellToken;
//             unFilled.buyToken = userOps.order1.buyToken;
//             unFilled.amountToSell = userOps.remAmountToSell1;
//             unFilled.amountToBuy = userOps.remAmountToBuy1;
//             getUnfilledHashGPV2(
//                 unFilled,
//                 userOps.order1.receiver,
//                 userOps.order1.validTo,
//                 userOps.signature0
//             );
//             //last partillyFilled
//         } else if (
//             userOps.remAmountToSell0 > 0 && userOps.remAmountToBuy0 > 0
//         ) {
//             require(userOps.order0.partiallyFillable);
//             unFilledOrder memory unFilled;
//             unFilled.sellToken = userOps.order0.sellToken;
//             unFilled.buyToken = userOps.order0.buyToken;
//             unFilled.amountToSell = userOps.remAmountToSell0;
//             unFilled.amountToBuy = userOps.remAmountToBuy0;
//             getUnfilledHashGPV2(
//                 unFilled,
//                 userOps.order0.receiver,
//                 userOps.order0.validTo,
//                 userOps.signature0
//             );
//             //first is partially filled
//         }
//     }

//     function getUnfilledHashGPV2(
//         unFilledOrder memory data,
//         address receiver,
//         uint32 validTo,
//         bytes memory signature
//     ) internal {
//         GPv2Order.Data memory order = GPv2Order.Data({
//             sellToken: data.sellToken,
//             buyToken: data.buyToken,
//             receiver: receiver,
//             sellAmount: data.amountToSell,
//             buyAmount: data.amountToBuy,
//             validTo: validTo,
//             appData: APP_DATA,
//             feeAmount: 0,
//             kind: GPv2Order.KIND_SELL,
//             partiallyFillable: false,
//             sellTokenBalance: GPv2Order.BALANCE_ERC20,
//             buyTokenBalance: GPv2Order.BALANCE_ERC20
//         });
//         bytes32 orderHash = order.hash(domainSeparator);
//         unFilledOrderHash[orderHash] = true;
//         unFilledOrderInfo[signature] = data;
//     }

//     function getHashGPV2(Data memory data, bytes calldata signature) public {
//         address signer = verifySigner(data, signature);
//         IERC20 sellToken = data.sellToken;
//         uint256 amountToSell = data.sellAmount + data.feeAmount;
//         uint256 total = depositInfo[signer][address(sellToken)];
//         require(amountToSell <= total);
//         require(
//             depositInfo[signer][address(data.sellToken)] >=
//                 data.sellAmount + data.feeAmount
//         );
//         sellToken.transfer(owner, data.feeAmount);
//         GPv2Order.Data memory order = GPv2Order.Data({
//             sellToken: data.sellToken,
//             buyToken: data.buyToken,
//             receiver: data.receiver,
//             sellAmount: data.sellAmount,
//             buyAmount: data.buyAmount,
//             validTo: data.validTo,
//             appData: APP_DATA,
//             feeAmount: 0,
//             kind: GPv2Order.KIND_SELL,
//             partiallyFillable: data.partiallyFillable,
//             sellTokenBalance: GPv2Order.BALANCE_ERC20,
//             buyTokenBalance: GPv2Order.BALANCE_ERC20
//         });

//         bytes32 orderHash = order.hash(domainSeparator);
//         require(unFilledOrderHash[orderHash] == false);
//         unFilledOrderHash[orderHash] = true;
//     }

//     function withdrawAsset(address token, uint256 amount) external {
//         require(depositInfo[msg.sender][token] >= amount);
//         IERC20(token).transfer(msg.sender, amount);
//         //delete unFilledOrderHash[orderHash];
//     }

//     function extractOrderData(
//         Data memory order,
//         bytes memory signature
//     )
//         internal
//         view
//         returns (
//             IERC20 sellToken,
//             IERC20 buyToken,
//             uint256 amountToSell,
//             uint256 amountToBuy,
//             uint256 fee
//         )
//     {   
//         unFilledOrder memory unfilled = unFilledOrderInfo[signature];
//         if(unfilled.amountToBuy==0){
//             sellToken = order.sellToken;
//             buyToken = order.buyToken;
//             amountToSell = order.sellAmount;
//             amountToBuy = order.buyAmount;
//             fee = order.feeAmount;
//         }
//         else{
//             sellToken = unfilled.sellToken;
//             buyToken = unfilled.buyToken;
//             amountToSell = unfilled.amountToSell;
//             amountToBuy = unfilled.amountToBuy;
//         }
//     }

//     function _pay(address _token, uint256 _amount) internal {
//         if (_token == WETH && msg.value > 0) {
//             require(msg.value == _amount);
//             IWETH(_token).deposit{value: _amount}();
//         } else {
//             IERC20(_token).transferFrom(msg.sender, address(this), _amount);
//         }
//     }

//     // Function to hash the struct data
//     function hashData(Data memory data) internal pure returns (bytes32) {
//         return
//             keccak256(
//                 abi.encode(
//                     data.sellToken,
//                     data.buyToken,
//                     data.receiver,
//                     data.sellAmount,
//                     data.buyAmount,
//                     data.validTo,
//                     data.partiallyFillable,
//                     data.feeAmount
//                 )
//             );
//     }

//     // Function to recover the signer from the signature
//     function recoverSignerFromSignature(
//         bytes32 messageHash,
//         bytes memory signature
//     ) internal pure returns (address) {
//         require(signature.length == 65, "Invalid signature length");
//         bytes32 r;
//         bytes32 s;
//         uint8 v;
//         assembly {
//             // First 32 bytes are the signature's r data
//             r := mload(add(signature, 32))
//             // Next 32 bytes are the signature's s data
//             s := mload(add(signature, 64))
//             // Final byte is the signature's v data
//             v := byte(0, mload(add(signature, 96)))
//         }
//         return ecrecover(messageHash, v, r, s);
//     }

//     // Function to verify the signer of the Data struct
//     function verifySigner(
//         Data memory data,
//         bytes memory signature
//     ) public pure returns (address) {
//         bytes32 messageHash = hashData(data);
//         return recoverSignerFromSignature(messageHash, signature);
//     }

//     function isValidSignature(
//         bytes32 hash,
//         bytes calldata signature
//     ) external returns (bytes4 magicValue) {
//         require(unFilledOrderHash[hash], "invalid order");
//         delete unFilledOrderInfo[signature];
//         delete unFilledOrderHash[hash];
//         magicValue = ERC1271_MAGIC_VALUE;
//     }


//     function cancelOrder(bytes calldata signature,Data calldata data) external {
//         require(verifySigner(data, signature) == msg.sender);
//         unFilledOrder memory unfilled  = unFilledOrderInfo[signature];
//         bytes32 orderHash;
//         if(unfilled.amountToSell > 0){
//             GPv2Order.Data memory order = GPv2Order.Data({
//             sellToken: unfilled.sellToken,
//             buyToken: unfilled.buyToken,
//             receiver: data.receiver,
//             sellAmount: unfilled.amountToSell,
//             buyAmount: unfilled.amountToBuy,
//             validTo: data.validTo,
//             appData: APP_DATA,
//             feeAmount: 0,
//             kind: GPv2Order.KIND_SELL,
//             partiallyFillable: data.partiallyFillable,
//             sellTokenBalance: GPv2Order.BALANCE_ERC20,
//             buyTokenBalance: GPv2Order.BALANCE_ERC20
//             });    
//             orderHash = order.hash(domainSeparator);    
//         }

//         else{
//             GPv2Order.Data memory order = GPv2Order.Data({
//             sellToken: unfilled.sellToken,
//             buyToken: unfilled.buyToken,
//             receiver: data.receiver,
//             sellAmount: data.sellAmount,
//             buyAmount: data.buyAmount,
//             validTo: data.validTo,
//             appData: APP_DATA,
//             feeAmount: 0,
//             kind: GPv2Order.KIND_SELL,
//             partiallyFillable: data.partiallyFillable,
//             sellTokenBalance: GPv2Order.BALANCE_ERC20,
//             buyTokenBalance: GPv2Order.BALANCE_ERC20
//         });    
//             orderHash = order.hash(domainSeparator);
//         }
        
//         require(unFilledOrderHash[orderHash]);
//         delete unFilledOrderHash[orderHash];
//         delete unFilledOrderInfo[signature];
//     }

//     function withdraw() external {
        
//     }
// }
