// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {ICoWSwapSettlement} from "./interfaces/ICoWSwapSettlement.sol";
import {ERC1271_MAGIC_VALUE, IERC1271} from "./interfaces/IERC1271.sol";
import {IERC20} from "./interfaces/IERC20.sol";
import {IWETH} from "./interfaces/IWETH.sol";
import {GPv2Order} from "./vendored/GPv2Order.sol";
import {ICoWSwapOnchainOrders} from "./vendored/ICoWSwapOnchainOrders.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "hardhat/console.sol";

contract Escrow {
    using GPv2Order for *;
    bytes32 public constant APP_DATA = keccak256("ABC");
    address WETH;
    struct Data {
        IERC20 sellToken;
        IERC20 buyToken;
        address receiver;
        uint256 sellAmount;
        uint256 buyAmount;
        uint32 validTo;
        bool partiallyFillable;
        uint256 feeAmount;
    }

    struct unFilledOrder {
        uint256 remainingAmountToSell;
        uint256 remainingAmountToBuy;
    }

    mapping(address => mapping(address => uint256)) public depositInfo;
    mapping(address => unFilledOrder) public unFilledOrderInfo; //should not be against msg.sender!
    mapping(bytes32 => bool) public unFilledOrderHash;

    ICoWSwapSettlement public immutable settlement;
    bytes32 public immutable domainSeparator;

    constructor(ICoWSwapSettlement settlement_) {
        settlement = settlement_;
        domainSeparator = settlement_.domainSeparator();
    }

    receive() external payable {}

    function depositToken(address token, uint256 amount) external payable {
        _pay(token, amount);
        depositInfo[msg.sender][token] =
            depositInfo[msg.sender][token] +
            amount;
    }

    // function settle(Data[] calldata data, bytes [] calldata signature) external {
    //     uint256 totalAmountBought0;
    //     uint256 totalAmountSold0;
    //     uint256 totalAmountBought1;
    //     uint256 totalAmountSold1;
    //     address signer0 =  verifySigner(data[0],signature[0]);
    //     (IERC20 sellToken0,IERC20 buyToken0,uint256 amountToSell0,uint256 amountToBuy0,uint256 feeAmount0) = extractOrderData(data[0]);
    //     totalAmountSold0 = amountToSell0;
    //     //uint256 singleUnitPrice0 = amountToBuy0/amountToSell0;
    //     // require(
    //     //     order.sellAmount.mul(sellPrice) >= order.buyAmount.mul(buyPrice),
    //     //
    //     // );
    //     // uint256 totAmountReq0 = amountToSell0+feeAmount0;
    //     // uint256 totalBal0 = depositInfo[signer0][address(sellToken0)];
    //     // require(totAmountReq0<=totalBal0);
    //     for(uint256 i = 1;i<data.length;){
    //         Data memory order1 = data[i];
    //         address signer1 =  verifySigner(order1,signature[i]);
    //         (IERC20 sellToken1,IERC20 buyToken1,uint256 amountToSell1,uint256 amountToBuy1,uint256 feeAmount1) = extractOrderData(data[i]);

    //         //uint256 singleUnitPrice1 = amountToBuy1/amountToSell1;
    //         //require(sellToken0==buyToken1);
    //         //require(buyToken0 == sellToken1);
    //        // uint256 totAmountReq1 = amountToSell1+feeAmount1;
    //         //uint256 totalBal1 = depositInfo[signer1][address(sellToken1)];
    //         //require(totAmountReq1<=totalBal1);
    //         //1eth 2000
    //         //0.45 1000
    //         //serve both order ordering and amount satisfied

    //         require(amountToSell0*amountToSell1 >= amountToBuy0*amountToBuy1);
    //         //Tricky Tricky
    //         uint256 amountreq0 = amountToBuy0-totalAmountBought0;
    //         uint256 amountToGive0 = amountToSell0 - totalAmountSold0;

    //         //check all when covering last order
    //         /*
    //         if first and last orders are not partials

    //         sellToken1.transfer(signer0,amountToSell1);
    //         buyToken1.transfer(signer1,amountToBuy1);
    //         amounttotalAmountBought0>=amountToBuy0
    //         amounttotalAmountBought1>=amountToBuy1
    //         */

    //        /*
    //        if first is full and last is partial
    //         sellToken1.transfer(signer0,amountreq0);
    //         buyToken1.transfer(signer1,amountToGive0);
    //         amounttotalAmountBought0>=amountToBuy0
    //         generate hash for unsettled order for cowswap
    //         */

    //        /*
    //         if first is partial and last is full
    //         sellToken1.transfer(signer0,amountToSell1);
    //         buyToken1.transfer(signer1,amountToBuy1);
    //         generate hash for unsettled order
    //         */

    //        /*
    //        if first is partial and last is partial

    //         */
    //         if(amountreq0>0){

    //             //still amount remain to filled
    //         }
    //         if(i==data.length-1){
    //             if(!data[0].partiallyFillable){
    //                 //verify singer1 details(amountToSell, amountToBuy)
    //                 //send signer0 remainig amount to buy0
    //                 //send signer1 remainig amount to sell0
    //             }
    //             else{

    //             }

    //         }
    //         else{
    //             sellToken1.transfer(signer0,amountToSell1);
    //             buyToken1.transfer(signer1,amountToBuy1);
    //             depositInfo[signer0][address(buyToken1)] = depositInfo[signer0][address(buyToken1)]-amountToBuy1;
    //             depositInfo[signer1][address(sellToken1)] = depositInfo[signer1][address(sellToken1)]-amountToSell1;
    //             totalAmountBought0 = totalAmountBought0 +  amountToSell1;
    //             totalAmountSold0 = totalAmountSold0 - amountToBuy1;
    //         }

    //         unchecked{
    //             ++i;
    //         }
    //         if(i==data.length){
    //             if(!data[0].partiallyFillable)
    //             require(totalAmountBought0>=amountToBuy0);
    //             // if(!order1.partiallyFillable)
    //             // require("");
    //             //check fisrt and last orders are partials
    //             // if yes
    //         }
    //     }

    // }

    function executeOrder(
        Data[] calldata data,
        bytes[] calldata signature
    ) external {
        Data memory order0 = data[0];
        address signer0 = verifySigner(order0, signature[0]);
        (
            IERC20 sellToken0,
            IERC20 buyToken0,
            uint256 amountToSell0,
            uint256 amountToBuy0,
            uint256 feeAmount0
        ) = extractOrderData(order0);
        uint256 clearingPrice;
        uint256 remAmountToSell = amountToSell0;
        uint256 remAmountToBuy = amountToBuy0;
        require(depositInfo[signer0][address(sellToken0)]>=amountToSell0+feeAmount0);
        //We can deduct fees here for order0
        for (uint256 i = 1; i < data.length; ) {
            Data memory order1 = data[i];
            address signer1 = verifySigner(order1, signature[i]);
            (
                IERC20 sellToken1,
                IERC20 buyToken1,
                uint256 amountToSell1,
                uint256 amountToBuy1,
                uint256 feeAmount1
            ) = extractOrderData(data[i]);
            //1 eth 2000
            //1200 0.625
            //1000 0.5
            require(buyToken0==sellToken1);
            require(sellToken1==buyToken1);
            require(depositInfo[signer1][address(sellToken1)]>=amountToSell1+feeAmount1);
            clearingPrice = (amountToSell0 * amountToSell1) / amountToBuy0;
            require(clearingPrice <= amountToBuy1);
            //deduct fees for remaning orders
            if (clearingPrice > remAmountToSell) {
                sellToken1.transfer(signer0, remAmountToBuy);
                buyToken1.transfer(signer1, remAmountToSell);
            } else {
                sellToken1.transfer(signer0, amountToSell1);
                buyToken1.transfer(signer1, clearingPrice);
            }
            //0.5
            //1 
            remAmountToSell = remAmountToSell - clearingPrice;
            remAmountToBuy = remAmountToBuy - amountToSell1;
            if (i == data.length - 1) {
                if (clearingPrice > remAmountToSell) {
                    uint256 sellAmount = amountToSell1 - remAmountToSell;
                    uint256 buyAmount = amountToBuy1 - remAmountToSell;
                    Data memory unFilled;
                    unFilled.sellToken = order1.sellToken;
                    unFilled.buyToken = order1.buyToken;
                    unFilled.receiver = order1.receiver;
                    unFilled.validTo = order1.validTo;
                    unFilled.sellAmount = sellAmount;
                    unFilled.buyAmount = buyAmount;
                    unFilled.partiallyFillable = order1.partiallyFillable;
                    getUnfilledHashGPV2(unFilled);
                    //last partillyFilled
                } else if (remAmountToSell > 0 && remAmountToBuy > 0) {
                    Data memory unFilled;
                    unFilled.sellToken = order0.sellToken;
                    unFilled.buyToken = order0.buyToken;
                    unFilled.receiver = order0.receiver;
                    unFilled.validTo = order0.validTo;
                    unFilled.sellAmount = remAmountToSell;
                    unFilled.buyAmount = remAmountToBuy;
                    unFilled.partiallyFillable = order0.partiallyFillable;
                    getUnfilledHashGPV2(unFilled);
                    //first is partially or fully filled
                }
            }

            unchecked {
                ++i;
            }
        }
    }

    function getUnfilledHashGPV2(Data memory data) internal {
        GPv2Order.Data memory order = GPv2Order.Data({
            sellToken: data.sellToken,
            buyToken: data.buyToken,
            receiver: data.receiver,
            sellAmount: data.sellAmount,
            buyAmount: data.buyAmount,
            validTo: data.validTo,
            appData: APP_DATA,
            feeAmount: 0,
            kind: GPv2Order.KIND_SELL,
            partiallyFillable: data.partiallyFillable,
            sellTokenBalance: GPv2Order.BALANCE_ERC20,
            buyTokenBalance: GPv2Order.BALANCE_ERC20
        });

        bytes32 orderHash = order.hash(domainSeparator);
        require(unFilledOrderHash[orderHash] == false);
        unFilledOrderHash[orderHash] = true;
    }

    function getHashGPV2(Data memory data, bytes calldata signature) public {
        //deduct Fees here? if order completly filled by cowswap
        address signer = verifySigner(data, signature);
        IERC20 sellToken = data.sellToken;
        uint256 amountToSell = data.sellAmount + data.feeAmount;
        uint256 total = depositInfo[signer][address(sellToken)];
        require(amountToSell <= total);
        GPv2Order.Data memory order = GPv2Order.Data({
            sellToken: data.sellToken,
            buyToken: data.buyToken,
            receiver: data.receiver,
            sellAmount: data.sellAmount,
            buyAmount: data.buyAmount,
            validTo: data.validTo,
            appData: APP_DATA,
            feeAmount: 0,
            kind: GPv2Order.KIND_SELL,
            partiallyFillable: data.partiallyFillable,
            sellTokenBalance: GPv2Order.BALANCE_ERC20,
            buyTokenBalance: GPv2Order.BALANCE_ERC20
        });

        bytes32 orderHash = order.hash(domainSeparator);
        require(unFilledOrderHash[orderHash] == false);
        unFilledOrderHash[orderHash] = true;
    }

    function extractOrderData(
        Data memory order
    )
        internal
        pure
        returns (
            IERC20 sellToken,
            IERC20 buyToken,
            uint256 amountToSell,
            uint256 amountToBuy,
            uint256 fee
        )
    {
        sellToken = order.sellToken;
        buyToken = order.buyToken;
        amountToSell = order.sellAmount;
        amountToBuy = order.buyAmount;
        fee = order.feeAmount;
    }

    function _pay(address _token, uint256 _amount) internal {
        if (_token == WETH && msg.value > 0) {
            require(msg.value == _amount);
            IWETH(_token).deposit{value: _amount}();
        } else {
            IERC20(_token).transferFrom(msg.sender, address(this), _amount);
        }
    }

    // Function to hash the struct data
    function hashData(Data memory data) internal pure returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    data.sellToken,
                    data.buyToken,
                    data.receiver,
                    data.sellAmount,
                    data.buyAmount,
                    data.validTo,
                    data.partiallyFillable,
                    data.feeAmount
                )
            );
    }

    // Function to recover the signer from the signature
    function recoverSignerFromSignature(
        bytes32 messageHash,
        bytes memory signature
    ) internal pure returns (address) {
        require(signature.length == 65, "Invalid signature length");
        bytes32 r;
        bytes32 s;
        uint8 v;
        assembly {
            // First 32 bytes are the signature's r data
            r := mload(add(signature, 32))
            // Next 32 bytes are the signature's s data
            s := mload(add(signature, 64))
            // Final byte is the signature's v data
            v := byte(0, mload(add(signature, 96)))
        }
        return ecrecover(messageHash, v, r, s);
    }

    // Function to verify the signer of the Data struct
    function verifySigner(
        Data memory data,
        bytes calldata signature
    ) public pure returns (address) {
        bytes32 messageHash = hashData(data);
        return recoverSignerFromSignature(messageHash, signature);
    }

    function isValidSignature(
        bytes32 hash,
        bytes calldata
    ) external view returns (bytes4 magicValue) {
        require(unFilledOrderHash[hash], "invalid order");
        magicValue = ERC1271_MAGIC_VALUE;
    }
}
