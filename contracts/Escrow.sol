// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;
import {IWETH} from "./interfaces/IWETH.sol";
import {IEscrow} from "./interfaces/IEscrow.sol";
import {GPv2Order} from "./vendored/GPv2Order.sol";
import {ICoWSwapOnchainOrders} from "./vendored/ICoWSwapOnchainOrders.sol";
import {ICoWSwapSettlement} from "./interfaces/ICoWSwapSettlement.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import "hardhat/console.sol";

contract Escrow is IEscrow, EIP712, ReentrancyGuard, Ownable {
    using GPv2Order for *;
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    bytes4 constant ERC1271_MAGIC_VALUE = 0x1626ba7e;
    bytes32 public constant APP_DATA = keccak256("APEXER");
    IERC20 public WETH = IERC20(0xB4FBF271143F4FBf7B91A5ded31805e42b2208d6);
    ICoWSwapSettlement public immutable settlement =
        ICoWSwapSettlement(0x9008D19f58AAbD9eD0D60971565AA8510560ab41);
    bytes32 public immutable GPV2DomainSeparator;
    bytes32 private constant TYPED_DATA_HASH =
        0xca27b2bd45c1b48e3310724bf5c645b69f94e8b61b032dbe4323c2d0c23e25c7;

    mapping(address => mapping(IERC20 => uint256)) public deposits;

    mapping(bytes => unfilledOrder) public unfilledOrderInfo;

    mapping(bytes => bool) public isExecuted;

    mapping(address => bool) public isSolver;

    modifier onlySolver() {
        require(isSolver[msg.sender], "!solver");
        _;
    }

    modifier onlySettlement() {
        require(msg.sender == address(settlement), "!settlement");
        _;
    }

    constructor() EIP712("Dafi-Protocol", "V1") {
        GPV2DomainSeparator = settlement.domainSeparator();
    }

    receive() external payable {}

    function updateSolverAddress(address _solver) external override onlyOwner {
        isSolver[_solver]
            ? isSolver[_solver] = true
            : isSolver[_solver] = false;
    }

    /**
     * @dev Deposit ERC20 tokens into the escrow contract.
     * @param token The ERC20 token to deposit.
     * @param amount The amount of tokens to deposit.
     */
    function depositToken(
        IERC20 token,
        uint256 amount
    ) external payable override {
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
    ) external override nonReentrant onlySolver {
        address signer0;
        address signer1;
        uint256 clearingPrice;
        Data memory order0 = data[0];
        Data memory order1;
        (
            signer0,
            order0.sellToken,
            order0.buyToken,
            order0.sellAmount,
            order0.buyAmount,
            order0.feeAmount
        ) = extractOrderData(order0, signature[0]);
        for (uint256 i = 1; i < data.length; ) {
            order1 = data[i];
            (
                signer1,
                order1.sellToken,
                order1.buyToken,
                order1.sellAmount,
                order1.buyAmount,
                order1.feeAmount
            ) = extractOrderData(data[i], signature[i]);
            clearingPrice = (order0.sellAmount.mul(order1.sellAmount)).div(
                order0.buyAmount
            );
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
                order1.sellAmount -= clearingPrice;
                order1.buyAmount -= order0.sellAmount;
                order0.sellAmount = 0; //
                order0.buyAmount = 0;
                if (unfilledOrderInfo[signature[0]].buyAmount > 0)
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
                order0.sellAmount -= clearingPrice;
                order0.buyAmount -= order1.sellAmount;
                order1.sellAmount = 0;
                order1.buyAmount = 0;
                if (unfilledOrderInfo[signature[i]].buyAmount > 0)
                    delete unfilledOrderInfo[signature[i]];
            }
            unchecked {
                ++i;
            }
        }

        if (order0.sellAmount > 0) {
            _checkAndUpdatePartialOrder(order0, signature[0], signer0);
        } else if (order1.sellAmount > 0) {
            _checkAndUpdatePartialOrder(
                order1,
                signature[signature.length - 1],
                signer1
            );
        }
    }

    function getHashGPV2(
        Data memory data,
        bytes calldata signature
    ) external override onlySolver {
        require(!isExecuted[signature], "Executed Order");
        require(
            deposits[getSigner(data, signature)][data.sellToken] >=
                data.sellAmount + data.feeAmount,
            "not enough deposit"
        );
        require(data.validTo >= block.timestamp, "order expired");
        require(
            data.receiver != address(this) || data.receiver != address(0),
            "Invalid recevier"
        );
        deposits[owner()][data.sellToken] += data.feeAmount;
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
        unfilledOrder memory unfilled;
        unfilled.owner = getSigner(data, signature);
        unfilled.sellToken = order.sellToken;
        unfilled.buyToken = order.buyToken;
        unfilled.sellAmount = order.sellAmount;
        unfilled.buyAmount = order.buyAmount;
        unfilled.orderHash = order.hash(GPV2DomainSeparator);
        unfilledOrderInfo[signature] = unfilled;
        isExecuted[signature] = true;
    }

    function cancelOrder(
        Data calldata data,
        bytes calldata signature
    ) external override {
        require(unfilledOrderInfo[signature].buyAmount > 0, "order filled");
        require(getSigner(data, signature) == msg.sender, "invalid caller");
        delete unfilledOrderInfo[signature];
    }

    function withdraw(IERC20 token, uint256 amount) external override {
        require(deposits[msg.sender][token] >= amount, "not enough deposit");
        deposits[msg.sender][token] -= amount;
        token.safeTransfer(msg.sender, amount);
    }

    function isValidSignature(
        bytes32 hash,
        bytes calldata signature
    ) external override onlySettlement returns (bytes4 magicValue) {
        unfilledOrder memory order = unfilledOrderInfo[signature];
        require(order.orderHash == hash, "invalid hash");
        deposits[order.owner][order.sellToken] -= order.sellAmount;
        delete unfilledOrderInfo[signature];
        magicValue = ERC1271_MAGIC_VALUE;
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
            deposits[owner()][token] += fee;
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
        bytes32 hash = _getUnfilledHashGPV2(
            unfilled,
            order.receiver,
            order.validTo
        );
        unfilled.orderHash = hash;
        unfilledOrderInfo[signature] = unfilled;
    }

    function _getUnfilledHashGPV2(
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
            address signer,
            IERC20 sellToken,
            IERC20 buyToken,
            uint256 amountToSell,
            uint256 amountToBuy,
            uint256 fee
        )
    {
        require(order.validTo >= block.timestamp, "order expired");
        unfilledOrder memory unfilled = unfilledOrderInfo[signature];
        if (unfilled.sellAmount == 0) {
            require(
                order.receiver != address(this) || order.receiver != address(0),
                "invalid receiver"
            );
            require(!isExecuted[signature], "already filled");
            sellToken = order.sellToken;
            buyToken = order.buyToken;
            amountToSell = order.sellAmount;
            amountToBuy = order.buyAmount;
            fee = order.feeAmount;
            signer = getSigner(order, signature);
            isExecuted[signature] = true;
            require(
                deposits[signer][order.sellToken] >= amountToSell + fee,
                "not enough deposit"
            );
        } else {
            sellToken = unfilled.sellToken;
            buyToken = unfilled.buyToken;
            amountToSell = unfilled.sellAmount;
            amountToBuy = unfilled.buyAmount;
            signer = unfilled.owner;
            require(
                deposits[signer][order.sellToken] >= amountToSell,
                "not enough deposit"
            );
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
