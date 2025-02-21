//SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

// import {BaseHook} from "../lib/v4-periphery/src/utils/BaseHook.sol";
// import {ERC20} from "../lib/solmate/src/tokens/ERC20.sol";
// import {Currency} from "../lib/v4-core/src/types/Currency.sol";
// import {PoolKey} from "../lib/v4-core/src/types/PoolKey.sol";
// import {BalanceDelta} from "../lib/v4-core/src/types/BalanceDelta.sol";
// import {IPoolManager} from "../lib/v4-core/src/interfaces/IPoolManager.sol";
// import {Hooks} from "../lib/v4-core/src/libraries/Hooks.sol";

import {BaseHook} from "@uniswap/v4-periphery/src/utils/BaseHook.sol";
import {ERC20} from "@solmate/src/tokens/ERC20.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";

contract PointHooks is BaseHook, ERC20 {
    constructor(
        IPoolManager _poolManager,
        string memory _name,
        string memory _symbol
    ) BaseHook(_poolManager) ERC20(_name, _symbol, 18) {}

     mapping(address => uint256) public liquidityAddedTimestamp;
     uint256 public constant MINIMUM_LOCKUP_TIME = 7 days; 

    function getHookPermissions()
        public
        pure
        override
        returns (Hooks.Permissions memory) 
    {
        return
            Hooks.Permissions({
                beforeInitialize: false,
                afterInitialize: false,
                beforeAddLiquidity: false,
                afterAddLiquidity: true,
                beforeRemoveLiquidity: false,
                afterRemoveLiquidity: true,
                beforeSwap: false,
                afterSwap: true,
                beforeDonate: false,
                afterDonate: false,
                beforeSwapReturnDelta: false,
                afterSwapReturnDelta: false,
                afterAddLiquidityReturnDelta: false,
                afterRemoveLiquidityReturnDelta: false
            });
    }  

    // the afterSwap function takes in the following paramaters
    // address sender: the address of the sender 
    // PoolKey key: pool information (currencies, fees, etc.)
    // swap details (zeroForOne, amount)
    // actual amounts swapped
    // additional data passed to the hook

    function _afterSwap(
        address,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata swapParams,
        BalanceDelta delta,
        bytes calldata hookData
    ) internal override virtual onlyPoolManager returns (bytes4, int128) {

// check if the token0 current is ETH. if it is not, return 0
        if (!key.currency0.isAddressZero()) 
            return (this.afterSwap.selector, 0);

// check if the swap is from ETH. zeroForOne is true if the swap is from ETH to the token
// if the swap is not from ETH return zero

        if (!swapParams.zeroForOne) 
            return (this.afterSwap.selector, 0);

// calculate the amount of points for the swap.
// delta.amount0 is how much eth was spent (negative is spend)

        uint256 ethSpendAmount = uint256(int256(-delta.amount0()));
        uint256 pointsForSwap = ethSpendAmount / 5;

        // Mint the points  
        _assignPoints(hookData, pointsForSwap);

        return (this.afterSwap.selector, 0);
    }
    
function _assignPoints(bytes calldata hookdata, uint points) internal {
    if (hookdata.length == 0) return;

    address user = abi.decode(hookdata, (address));

    // if there is no address, no points rewarded

    if (user == address(0)) return;

    _mint(user, points);
}

function _afterAddLiquidity(
        address sender,
        PoolKey calldata key,
        IPoolManager.ModifyLiquidityParams calldata,
        BalanceDelta delta,
        BalanceDelta fees,
        bytes calldata hookData
    ) internal override returns (bytes4, BalanceDelta) {

        // If this is not an ETH-TOKEN pool with this hook attached, ignore
        if (!key.currency0.isAddressZero()) return (this.afterSwap.selector, delta);

        // Mint points equivalent to how much ETH they're adding in liquidity
        uint256 pointsForAddingLiquidity = uint256(int256(-delta.amount0()));

        // Store the timestamp when liquidity is added
        liquidityAddedTimestamp[msg.sender] = block.timestamp;

        // Mint the points including any referral points
        _assignPoints(hookData, pointsForAddingLiquidity);

        return (this.afterAddLiquidity.selector, delta);
    }

     function _beforeRemoveLiquidity(
        address sender,
        PoolKey calldata,
        IPoolManager.ModifyLiquidityParams calldata,
        bytes calldata
    ) internal view override returns (bytes4) {
        // Check if the lock-up period has elapsed
        require(
            block.timestamp >= liquidityAddedTimestamp[sender] + MINIMUM_LOCKUP_TIME,
            "Liquidity is still locked"
        );
        return this.beforeRemoveLiquidity.selector;
    }


}