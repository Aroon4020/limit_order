// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {ICoWSwapSettlement} from "./interfaces/ICoWSwapSettlement.sol";
import {ERC1271_MAGIC_VALUE, IERC1271} from "./interfaces/IERC1271.sol";
//import {IERC20} from "./interfaces/IERC20.sol";
import {IWETH} from "./interfaces/IWETH.sol";
import {GPv2Order} from "./vendored/GPv2Order.sol";
import {ICoWSwapOnchainOrders} from "./vendored/ICoWSwapOnchainOrders.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "hardhat/console.sol";

contract Escrow {
    using GPv2Order for *;
    using SafeERC20 for IERC20;
    bytes32 public constant APP_DATA = keccak256("ABC");
    IERC20 WETH;

    // Struct to represent order data
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

    // Struct to represent unfilled order data
    struct unfilledOrder {
        address owner;
        IERC20 sellToken;
        uint256 sellAmount;
        IERC20 buyToken;
        uint256 buyAmount;
    }

    address owner;

    // Mapping to store user deposits of tokens
    mapping(address => mapping(IERC20 => uint256)) public deposits;
    // Mapping to store unfilled order information
    mapping(bytes => unfilledOrder) public unfilledOrderInfo;
    // Mapping to track executed orders
    mapping(bytes32 => bool) public unfilledOrderHash;
    // Mapping to track whether an order has been executed
    mapping(bytes => bool) public isExecuted;

    ICoWSwapSettlement public immutable settlement;
    bytes32 public immutable domainSeparator;

    /**
     * @dev Constructor to initialize the Escrow contract
     * @param settlement_ The address of the CoWSwapSettlement contract
     */
    constructor(ICoWSwapSettlement settlement_) {
        settlement = settlement_;
        domainSeparator = settlement_.domainSeparator();
    }

    receive() external payable {}

    /**
     * @dev Deposit ERC20 tokens into the escrow contract.
     * @param token The ERC20 token to deposit.
     * @param amount The amount of tokens to deposit.
     */
    function depositToken(IERC20 token, uint256 amount) external payable {
        _pay(token, amount);
        deposits[msg.sender][token] += amount;
        if (token.allowance(address(this), settlement.vaultRelayer()) == 0) {
            token.safeApprove(settlement.vaultRelayer(), type(uint256).max);
        }
    }

    //The 'taker' is someone who decides to place an order that is instantly matched with an existing order on the order book. Maker.
    //You become a “maker” when you place an order and it does not trade immediately, so your order stays

    //1 ETH - 2000 USDT
    //1000 USDT - 1 ETH
    //500 USDT - 0.25

    /**
     * @dev Settle a batch of orders by transferring tokens and updating balances.
     * @param data Array of order data.
     * @param signature Array of order signatures.
     */
    function settleOrders(
        Data[] calldata data,
        bytes[] calldata signature
    ) external {
        uint256 i;
        address signer0;
        address signer1;
        uint256 clearingPrice;
        Data memory order0 = data[0];
        Data memory order1;
        uint256 totalFee;
        signer0 = verifySigner(order0, signature[0]); //not in case of partial
        (
            order0.sellToken,
            order0.buyToken,
            order0.sellAmount,
            order0.buyAmount,
            order0.feeAmount
        ) = extractOrderData(order0, signature[0]);
        require(order0.sellAmount>=data[1].buyAmount,"ordering not respected");
        if (order0.feeAmount > 0) {
            totalFee += order0.feeAmount;
        }

        //deduct % of amount of trade filled

        for (i = 1; i < data.length; ) {
            order1 = data[i];
            signer1 = verifySigner(order1, signature[i]);
            (
                order1.sellToken,
                order1.buyToken,
                order1.sellAmount,
                order1.buyAmount,
                order1.feeAmount
            ) = extractOrderData(data[i], signature[i]);
            if (order1.feeAmount > 0) {
                totalFee += order1.feeAmount;
            }
            clearingPrice =
                (order0.sellAmount * order1.sellAmount) /
                order0.buyAmount; //0.5
            require(clearingPrice >= order1.buyAmount, "limit not respected");
            //require(clearingPrice <= order0.sellAmount, "limit not respected");
            require(order0.sellToken==order1.buyToken && order0.buyToken==order1.sellToken,"mismatch tokens");
            order1.sellToken.safeTransfer(order0.receiver, order1.sellAmount); //750
            order1.buyToken.safeTransfer(order1.receiver, clearingPrice);

            if (clearingPrice > order0.sellAmount) {
                clearingPrice =
                (order1.sellAmount * order0.sellAmount) /
                order1.buyAmount; //0.5
                
                order0.feeAmount > 0
                    ? deposits[signer0][order0.sellToken] -=
                        order0.sellAmount +
                        order0.feeAmount
                    : deposits[signer0][order0.sellToken] -= order0.sellAmount;
                order1.feeAmount > 0
                    ? deposits[signer1][order1.sellToken] -=
                        order0.buyAmount +
                        order1.feeAmount
                    : deposits[signer1][order1.sellToken] -= order0.buyAmount;
                deposits[signer0][order0.sellToken] -= order0.sellAmount;
                order1.sellAmount -= order0.buyAmount; //1000-750 250 //last partially filled
                order1.buyAmount -= order0.sellAmount; //0.5-0.375
                // order0.sellAmount = 0; //
                // order0.buyAmount = 0;
                delete unfilledOrderInfo[signature[0]];
            } else {

                // order1.feeAmount > 0
                //     ? deposits[signer1][order0.sellToken] -=
                //         order1.sellAmount +
                //         order1.feeAmount
                //     : deposits[signer1][order0.sellToken] -= order1.sellAmount;
                // order0.feeAmount > 0
                //     ? deposits[signer0][order0.sellToken] -=
                //         clearingPrice +
                //         order0.feeAmount
                //     : deposits[signer0][order0.sellToken] -= clearingPrice;
                order0.sellAmount -= clearingPrice; //1-0.5 = 0.5, 0.5-0.125 = 0.375
                order0.buyAmount -= order1.sellAmount; //2000-1000, 1000-250 = 750
                // order1.sellAmount = 0;
                // order1.buyAmount = 0;
                delete unfilledOrderInfo[signature[i]];
            }
            unchecked {
                ++i;
            }
        }
        if (order0.sellAmount > 0) {
            checkAndUpdatePartialOrder(order0, signature[0], signer0);
        } else if (order1.sellAmount > 0) {
            checkAndUpdatePartialOrder(order1, signature[i], signer1);
        }
    }

    function checkAndUpdatePartialOrder(
        Data memory order,
        bytes memory signature,
        address signer
    ) internal {
        require(order.partiallyFillable);
        unfilledOrder memory unfilled;
        unfilled.owner = signer;
        unfilled.sellToken = order.sellToken;
        unfilled.buyToken = order.buyToken;
        unfilled.sellAmount = order.sellAmount;
        unfilled.buyAmount = order.buyAmount;
        bytes32 hash = getUnfilledHashGPV2(
            unfilled,
            order.receiver,
            order.validTo
        );
        unfilledOrderHash[hash] = true;
        unfilledOrderInfo[signature] = unfilled;
    }

    function getUnfilledHashGPV2(
        unfilledOrder memory data,
        address receiver,
        uint32 validTo
    ) internal view returns (bytes32 orderHash) {
        GPv2Order.Data memory order = GPv2Order.Data({
            sellToken: (data.sellToken),
            buyToken: data.buyToken,
            receiver: receiver,
            sellAmount: data.sellAmount,
            buyAmount: data.buyAmount,
            validTo: validTo,
            appData: APP_DATA,
            feeAmount: 0,
            kind: GPv2Order.KIND_SELL,
            partiallyFillable: false,
            sellTokenBalance: GPv2Order.BALANCE_ERC20,
            buyTokenBalance: GPv2Order.BALANCE_ERC20
        });
        orderHash = order.hash(domainSeparator);
    }

    function getHashGPV2(Data memory data, bytes calldata signature) public {
        require(isExecuted[signature], "Executed Order");
        address signer = verifySigner(data, signature);
        IERC20 sellToken = data.sellToken;
        uint256 amountToSell = data.sellAmount + data.feeAmount;
        uint256 total = deposits[signer][sellToken];
        require(amountToSell <= total);
        require(
            deposits[signer][data.sellToken] >= data.sellAmount + data.feeAmount
        );
        sellToken.safeTransfer(owner, data.feeAmount);
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
        unfilledOrderHash[orderHash] = true;
    }

    function withdrawAsset(IERC20 token, uint256 amount) external {
        require(deposits[msg.sender][token] >= amount);
        IERC20(token).safeTransfer(msg.sender, amount);
        deposits[msg.sender][token] -= amount;
    }

    function extractOrderData(
        Data memory order,
        bytes memory signature
    )
        internal
        returns (
            IERC20 sellToken,
            IERC20 buyToken,
            uint256 amountToSell,
            uint256 amountToBuy,
            uint256 fee
        )
    {
        require(order.validTo >= block.timestamp, "order expired");
        require(order.receiver != address(this));
        unfilledOrder memory unfilled = unfilledOrderInfo[signature];
        if (unfilled.sellAmount == 0) {
            require(!isExecuted[signature], "order already executed");
            sellToken = order.sellToken;
            buyToken = order.buyToken;
            amountToSell = order.sellAmount;
            amountToBuy = order.buyAmount;
            fee = order.feeAmount;
            isExecuted[signature] = true;
        } else {
            sellToken = unfilled.sellToken;
            buyToken = unfilled.buyToken;
            amountToSell = unfilled.sellAmount;
            amountToBuy = unfilled.buyAmount;
        }
        require(deposits[owner][order.sellToken] >= amountToSell + fee);
    }

    function _pay(IERC20 _token, uint256 _amount) internal {
        if (_token == WETH && msg.value > 0) {
            require(msg.value == _amount);
            IWETH(address(_token)).deposit{value: _amount}();
        } else {
            _token.safeTransferFrom(msg.sender, address(this), _amount);
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
        bytes memory signature
    ) public pure returns (address) {
        bytes32 messageHash = hashData(data);
        return recoverSignerFromSignature(messageHash, signature);
    }

    function isValidSignature(
        bytes32 hash,
        bytes calldata signature
    ) external returns (bytes4 magicValue) {
        require(msg.sender == address(settlement),"only GPV2");
        require(unfilledOrderHash[hash], "invalid order");
        unfilledOrder memory order = unfilledOrderInfo[signature];
        deposits[order.owner][order.sellToken] -= order.sellAmount;
        delete unfilledOrderInfo[signature];
        delete unfilledOrderHash[hash];
        magicValue = ERC1271_MAGIC_VALUE;
    }

    function cancelOrder(
        bytes calldata signature,
        Data calldata data
    ) external {
        require(verifySigner(data, signature) == msg.sender);
        bytes32 hash = getUnfilledHashGPV2(
            unfilledOrderInfo[signature],
            data.receiver,
            data.validTo
        );
        require(unfilledOrderHash[hash]);
        delete unfilledOrderHash[hash];
        delete unfilledOrderInfo[signature];
    }

    function withdraw(IERC20 token, uint256 amount) external {
        require(deposits[msg.sender][token] >= amount);
        deposits[msg.sender][token] -= amount;
        token.safeTransfer(msg.sender, amount);
        
    }
}
