// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {ICoWSwapSettlement} from "./interfaces/ICoWSwapSettlement.sol";
import {ERC1271_MAGIC_VALUE, IERC1271} from "./interfaces/IERC1271.sol";
//import {IERC20} from "./interfaces/IERC20.sol";
import {IWETH} from "./interfaces/IWETH.sol";
import {GPv2Order} from "./vendored/GPv2Order.sol";
import {ICoWSwapOnchainOrders} from "./vendored/ICoWSwapOnchainOrders.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import "hardhat/console.sol";

contract Escrow is EIP712, ReentrancyGuard {
    using GPv2Order for *;
    using SafeERC20 for IERC20;
    using SafeMath for uint256;
    bytes32 public constant APP_DATA = keccak256("APEXER");
    IERC20 public WETH = IERC20(0xB4FBF271143F4FBf7B91A5ded31805e42b2208d6);
    ICoWSwapSettlement public immutable settlement =
        ICoWSwapSettlement(0x9008D19f58AAbD9eD0D60971565AA8510560ab41);
    bytes32 public immutable GPV2DomainSeparator;
    
    // bytes32 public immutable DOMAIN_SEPARATOR;
    address public owner;


    bytes32 private constant TYPED_DATA_HASH =
        0xca27b2bd45c1b48e3310724bf5c645b69f94e8b61b032dbe4323c2d0c23e25c7;
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

    // Mapping to store user deposits of tokens
    mapping(address => mapping(IERC20 => uint256)) public deposits;
    // Mapping to store unfilled order information
    mapping(bytes => unfilledOrder) public unfilledOrderInfo;
    // Mapping to track executed orders
    mapping(bytes32 => bool) public unfilledOrderHash;
    // Mapping to track whether an order has been executed
    mapping(bytes => bool) public isExecuted;

    // bytes32 public constant abc = keccak256(
    //      "Order("
    //          "address sellToken," +
    //          "address buyToken," +
    //          "address receiver," +
    //          "uint256 sellAmount," +
    //          "uint256 buyAmount," +
    //          "uint32 validTo," +
    //          "bytes32 appData," +
    //          "uint256 feeAmount," +
    //          "string kind," +
    //          "bool partiallyFillable" +
    //          "string sellTokenBalance" +
    //          "string buyTokenBalance" +
    //      ")"
    //     );
    constructor(
        string memory name,
        string memory version,
        address _owner 
    ) EIP712(name, version) {
        GPV2DomainSeparator = settlement.domainSeparator();
        owner = _owner;
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

    /**
     * @dev Settle a batch of orders by transferring tokens and updating balances.
     * @param data Array of order data.
     * @param signature Array of order signatures.
     */
    function settleOrders(
        Data[] calldata data,
        bytes[] calldata signature 
    ) external nonReentrant {
        uint256 i;
        address signer0;
        address signer1;
        uint256 clearingPrice;
        Data memory order0 = data[0];
        Data memory order1;
        signer0 = getSigner(order0, signature[0]); //not in case of partial
        (
            order0.sellToken,
            order0.buyToken,
            order0.sellAmount,
            order0.buyAmount,
            order0.feeAmount
        ) = extractOrderData(order0, signature[0]);
        require(
            order0.sellAmount >= data[1].buyAmount,
            "ordering not respected"
        );
        for (i = 1; i < data.length; ) {
            order1 = data[i];
            signer1 = getSigner(order1, signature[i]);
            (
                order1.sellToken,
                order1.buyToken,
                order1.sellAmount,
                order1.buyAmount,
                order1.feeAmount
            ) = extractOrderData(data[i], signature[i]);
            clearingPrice = (order0.sellAmount.mul(order1.sellAmount)).div(
                order0.buyAmount
            ); //0.5
            require(clearingPrice >= order1.buyAmount, "limit not respected");
            require(
                order0.sellToken == order1.buyToken &&
                    order0.buyToken == order1.sellToken,
                "mismatch tokens"
            );
            if (clearingPrice > order0.sellAmount) {
                clearingPrice = (order1.sellAmount.mul(order0.sellAmount)).div(
                    order1.buyAmount
                );
                _transferAndUpdateDeposit(
                    signer1,
                    order1.sellToken,
                    clearingPrice,
                    order0.receiver,
                    order1.feeAmount
                );
                _transferAndUpdateDeposit(
                    signer0,
                    order0.sellToken,
                    order0.sellAmount,
                    order1.receiver,
                    order0.feeAmount
                );
                order1.sellAmount -= clearingPrice; //1000-750 250 //last partially filled
                order1.buyAmount -= order0.sellAmount; //0.5-0.375
                order0.sellAmount = 0; //
                order0.buyAmount = 0;
                delete unfilledOrderInfo[signature[0]];
            } else {
                _transferAndUpdateDeposit(
                    signer1,
                    order1.sellToken,
                    order1.sellAmount,
                    order0.receiver,
                    order1.feeAmount
                );
                _transferAndUpdateDeposit(
                    signer0,
                    order0.sellToken,
                    clearingPrice,
                    order1.receiver,
                    order0.feeAmount
                );
                order0.sellAmount -= clearingPrice; //1-0.5 = 0.5, 0.5-0.125 = 0.375
                order0.buyAmount -= order1.sellAmount; //2000-1000, 1000-250 = 750
                order1.sellAmount = 0;
                order1.buyAmount = 0;
                delete unfilledOrderInfo[signature[i]];
            }
            unchecked {
                ++i;
            }
        }
        if (order0.sellAmount > 0) {
            _checkAndUpdatePartialOrder(order0, signature[0], signer0);
        } else if (order1.sellAmount > 0) {
            _checkAndUpdatePartialOrder(order1, signature[i], signer1);
        }
    }

    function getHashGPV2(Data memory data, bytes calldata signature) external {
        require(isExecuted[signature], "Executed Order");
        require(
            deposits[getSigner(data, signature)][data.sellToken] >=
                data.sellAmount + data.feeAmount
        );
        require(data.validTo >= block.timestamp, "order expired");
        deposits[owner][data.sellToken] += data.feeAmount;
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
            partiallyFillable: false,
            sellTokenBalance: GPv2Order.BALANCE_ERC20,
            buyTokenBalance: GPv2Order.BALANCE_ERC20
        });
        //bytes32 orderHash = order.hash(GPV2DomainSeparator);
        unfilledOrderHash[order.hash(GPV2DomainSeparator)] = true;
        isExecuted[signature] = true;
    }

    function withdrawAsset(IERC20 token, uint256 amount) external nonReentrant {
        require(
            deposits[msg.sender][token] >= amount,
            "deposit amount lt withdraw Amount"
        );
        IERC20(token).safeTransfer(msg.sender, amount);
        deposits[msg.sender][token] -= amount;
    }

    function isValidSignature(
        bytes32 hash,
        bytes calldata signature
    ) external returns (bytes4 magicValue) {
        require(msg.sender == address(settlement), "only GPV2");
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
        require(getSigner(data, signature) == msg.sender, "invalid caller");
        bytes32 hash = getUnfilledHashGPV2(
            unfilledOrderInfo[signature],
            data.receiver,
            data.validTo
        );
        delete unfilledOrderHash[hash];
        delete unfilledOrderInfo[signature];
    }

    function withdraw(IERC20 token, uint256 amount) external {
        require(
            deposits[msg.sender][token] >= amount,
            "deposit amount lt asked amount"
        );
        deposits[msg.sender][token] -= amount;
        token.safeTransfer(msg.sender, amount);
    }

    function getSigner(
        Data memory data,
        bytes memory signature
    ) public view returns (address) {
        return _verify(data, signature);
    }

    function _verify(
        Data memory data,
        bytes memory signature
    ) internal view returns (address) {
        bytes32 digest = _hashTypedData(data);
        return ECDSA.recover(digest, signature);
    }

    function _hashTypedData(Data memory data) internal view returns (bytes32) {
        return
            _hashTypedDataV4(
                keccak256(
                    abi.encode(
                        TYPED_DATA_HASH, // keccak hash of typed data
                        data.sellToken,
                        data.buyToken,
                        data.receiver,
                        data.sellAmount,
                        data.buyAmount,
                        data.validTo,
                        data.partiallyFillable,
                        data.feeAmount //uint value
                    )
                )
            );
    }

    function _transferAndUpdateDeposit(
        address signer,
        IERC20 token,
        uint256 amount,
        address receiver,
        uint256 fee
    ) internal {
        token.safeTransfer(receiver, amount);
        if (fee == 0) {
            deposits[signer][token] -= amount;
        } else {
            deposits[signer][token] -= amount + fee;
            deposits[owner][token] += fee;
        }
    }

    function _checkAndUpdatePartialOrder(
        Data memory order,
        bytes memory signature,
        address signer
    ) internal {
        require(order.partiallyFillable, "!partiallyfillable");
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
        orderHash = order.hash(GPV2DomainSeparator);
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
        require(order.receiver != address(this), "invalid receiver");
        require(
            deposits[owner][order.sellToken] >= amountToSell + fee,
            "deposit amount lt sell Amount"
        );
        unfilledOrder memory unfilled = unfilledOrderInfo[signature];
        if (unfilled.sellAmount == 0) {
            require(!isExecuted[signature], "already filled");
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
    }

    function _pay(IERC20 _token, uint256 _amount) internal {
        if (_token == WETH && msg.value > 0) {
            require(msg.value == _amount);
            IWETH(address(_token)).deposit{value: _amount}();
        } else {
            _token.safeTransferFrom(msg.sender, address(this), _amount);
        }
    }
}
