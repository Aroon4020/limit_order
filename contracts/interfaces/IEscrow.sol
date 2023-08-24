// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
interface IEscrow{
    event Deposited(address owner,IERC20 token, uint256 amount);
    event Canceled(address owner, bytes signature);
    event Withdrawn(address owner,IERC20 token, uint256 amount);
    event Settled(bytes signature);
    event Nam();

    
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
        bytes32 orderHash;
    }

    function updateSolverAddress(address _solver) external;

    function depositToken(IERC20 token, uint256 amount) external payable;

    function settleOrders(
        Data[] calldata data,
        bytes[] calldata signature
    ) external;

    function getHashGPV2(Data memory data, bytes calldata signature) external;

    function cancelOrder(
        Data calldata data,
        bytes calldata signature
    ) external;

    function withdraw(IERC20 token, uint256 amount) external;

    function isValidSignature(
        bytes32 hash,
        bytes calldata signature
    ) external returns (bytes4 magicValue);
}