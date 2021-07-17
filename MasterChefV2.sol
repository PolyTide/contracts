// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./IRewardToken.sol";

// MasterChef is the master of OYSTER. He can make OYSTER and he is a fair guy.
//
// Note that it's ownable and the owner wields tremendous power. The ownership
// will be transferred to a governance smart contract once OYSTER is sufficiently
// distributed and the community can show to govern itself.
//
// Have fun reading it. Hopefully it's bug-free. God bless.
contract MasterChefV2 is Ownable, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    // Info of each user.
    struct UserInfo {
        uint256 amount;         // How many LP tokens the user has provided.
        uint256 rewardDebt;     // Reward debt. See explanation below.
        //
        // We do some fancy math here. Basically, any point in time, the amount of OYSTERs
        // entitled to a user but is pending to be distributed is:
        //
        //   pending reward = (user.amount * pool.accOysterPerShare) - user.rewardDebt
        //
        // Whenever a user deposits or withdraws LP tokens to a pool. Here's what happens:
        //   1. The pool's `accOysterPerShare` (and `lastRewardBlock`) gets updated.
        //   2. User receives the pending reward sent to his/her address.
        //   3. User's `amount` gets updated.
        //   4. User's `rewardDebt` gets updated.
    }

    // Info of each pool.
    struct PoolInfo {
        IERC20 lpToken;           // Address of LP token contract.
        uint256 allocPoint;       // How many allocation points assigned to this pool. OYSTERs to distribute per block.
        uint256 lastRewardBlock;  // Last block number that OYSTERs distribution occurs.
        uint256 accOysterPerShare;   // Accumulated OYSTERs per share, times 1e12. See below.
        uint16 depositFeeBP;      // Deposit fee in basis points
        uint256 totalDepositAmount;
    }

    // The OYSTER TOKEN!
    IRewardToken public oyster;
    // Dev address.
    address public devaddr;
    // OYSTER tokens created per block.
    uint256 public oysterPerBlock;
    // Bonus muliplier for early OYSTER makers.
    uint256 public constant BONUS_MULTIPLIER = 1;
    // Deposit Fee address
    address public feeAddress;

    // Info of each pool.
    PoolInfo[] public poolInfo;
    // Info of each user that stakes LP tokens.
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;
    // Total allocation points. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint = 0;
    // The block number when OYSTER mining starts.
    uint256 public startBlock;

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event SetFeeAddress(address indexed user, address indexed newAddress);
    event SetDevAddress(address indexed user, address indexed newAddress);
    event UpdateEmissionRate(address indexed user, uint256 oysterPerBlock);

    constructor(
        IRewardToken _oyster,
        address _devaddr,
        address _feeAddress,
        uint256 _oysterPerBlock,
        uint256 _startBlock
    ) public {
        oyster = _oyster;
        devaddr = _devaddr;
        feeAddress = _feeAddress;
        oysterPerBlock = _oysterPerBlock;
        startBlock = _startBlock;
    }

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    // Add a new lp to the pool. Can only be called by the owner.
    function add(uint256 _allocPoint, IERC20 _lpToken, uint16 _depositFeeBP, bool _withUpdate) public onlyOwner {
        require(_depositFeeBP <= 10000, "add: invalid deposit fee basis points");
        if (_withUpdate) {
            massUpdatePools();
        }
        uint256 lastRewardBlock = block.number > startBlock ? block.number : startBlock;
        totalAllocPoint = totalAllocPoint.add(_allocPoint);
        poolInfo.push(PoolInfo({
        lpToken : _lpToken,
        allocPoint : _allocPoint,
        lastRewardBlock : lastRewardBlock,
        accOysterPerShare : 0,
        depositFeeBP : _depositFeeBP,
        totalDepositAmount: 0
        }));
    }

    // Update the given pool's OYSTER allocation point and deposit fee. Can only be called by the owner.
    function set(uint256 _pid, uint256 _allocPoint, uint16 _depositFeeBP, bool _withUpdate) public onlyOwner {
        require(_depositFeeBP <= 10000, "set: invalid deposit fee basis points");
        if (_withUpdate) {
            massUpdatePools();
        }
        totalAllocPoint = totalAllocPoint.sub(poolInfo[_pid].allocPoint).add(_allocPoint);
        poolInfo[_pid].allocPoint = _allocPoint;
        poolInfo[_pid].depositFeeBP = _depositFeeBP;
    }

    // Return reward multiplier over the given _from to _to block.
    function getMultiplier(uint256 _from, uint256 _to) public pure returns (uint256) {
        return _to.sub(_from).mul(BONUS_MULTIPLIER);
    }

    // View function to see pending OYSTERs on frontend.
    function pendingOyster(uint256 _pid, address _user) external view returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accOysterPerShare = pool.accOysterPerShare;
        uint256 lpSupply = pool.totalDepositAmount;
        if (block.number > pool.lastRewardBlock && lpSupply != 0) {
            uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
            uint256 oysterReward = multiplier.mul(oysterPerBlock).mul(pool.allocPoint).div(totalAllocPoint);
            accOysterPerShare = accOysterPerShare.add(oysterReward.mul(1e12).div(lpSupply));
        }
        return user.amount.mul(accOysterPerShare).div(1e12).sub(user.rewardDebt);
    }

    // Update reward variables for all pools. Be careful of gas spending!
    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    // Update reward variables of the given pool to be up-to-date.
    function updatePool(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        if (block.number <= pool.lastRewardBlock) {
            return;
        }
        uint256 lpSupply = pool.totalDepositAmount;
        if (lpSupply == 0 || pool.allocPoint == 0) {
            pool.lastRewardBlock = block.number;
            return;
        }
        uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
        uint256 oysterReward = multiplier.mul(oysterPerBlock).mul(pool.allocPoint).div(totalAllocPoint);
        oyster.mint(devaddr, oysterReward.div(10));
        oyster.mint(address(this), oysterReward);
        pool.accOysterPerShare = pool.accOysterPerShare.add(oysterReward.mul(1e12).div(lpSupply));
        pool.lastRewardBlock = block.number;
    }

    // Deposit LP tokens to MasterChef for OYSTER allocation.
    function deposit(uint256 _pid, uint256 _amount) public nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        updatePool(_pid);
        if (user.amount > 0) {
            uint256 pending = user.amount.mul(pool.accOysterPerShare).div(1e12).sub(user.rewardDebt);
            if (pending > 0) {
                safeOysterTransfer(msg.sender, pending);
            }
        }
        if (_amount > 0) {
            pool.lpToken.safeTransferFrom(address(msg.sender), address(this), _amount);
            if (pool.depositFeeBP > 0) {
                uint256 depositFee = _amount.mul(pool.depositFeeBP).div(10000);
                pool.lpToken.safeTransfer(feeAddress, depositFee);
                user.amount = user.amount.add(_amount).sub(depositFee);
                pool.totalDepositAmount = pool.totalDepositAmount.add(_amount).sub(depositFee);
            } else {
                user.amount = user.amount.add(_amount);
                pool.totalDepositAmount = pool.totalDepositAmount.add(_amount);
            }
        }
        user.rewardDebt = user.amount.mul(pool.accOysterPerShare).div(1e12);
        emit Deposit(msg.sender, _pid, _amount);
    }

    // Withdraw LP tokens from MasterChef.
    function withdraw(uint256 _pid, uint256 _amount) public nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(user.amount >= _amount, "withdraw: not good");
        updatePool(_pid);
        uint256 pending = user.amount.mul(pool.accOysterPerShare).div(1e12).sub(user.rewardDebt);
        if (pending > 0) {
            safeOysterTransfer(msg.sender, pending);
        }
        if (_amount > 0) {
            user.amount = user.amount.sub(_amount);
            pool.totalDepositAmount = pool.totalDepositAmount.sub(_amount);
            pool.lpToken.safeTransfer(address(msg.sender), _amount);
        }
        user.rewardDebt = user.amount.mul(pool.accOysterPerShare).div(1e12);
        emit Withdraw(msg.sender, _pid, _amount);
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(uint256 _pid) public nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        uint256 amount = user.amount;
        user.amount = 0;
        user.rewardDebt = 0;
        pool.totalDepositAmount = pool.totalDepositAmount.sub(amount);
        pool.lpToken.safeTransfer(address(msg.sender), amount);
        emit EmergencyWithdraw(msg.sender, _pid, amount);
    }

    // Safe OYSTER transfer function, just in case if rounding error causes pool to not have enough OYSTERs.
    function safeOysterTransfer(address _to, uint256 _amount) internal {
        uint256 oysterBal = oyster.balanceOf(address(this));
        bool transferSuccess = false;
        if (_amount > oysterBal) {
            transferSuccess = oyster.transfer(_to, oysterBal);
        } else {
            transferSuccess = oyster.transfer(_to, _amount);
        }
        require(transferSuccess, "safeOysterTransfer: transfer failed");
    }

    // Update dev address by the previous dev.
    function dev(address _devaddr) public {
        require(msg.sender == devaddr, "dev: wut?");
        devaddr = _devaddr;
        emit SetDevAddress(msg.sender, _devaddr);
    }

    function setFeeAddress(address _feeAddress) public {
        require(msg.sender == feeAddress, "setFeeAddress: FORBIDDEN");
        feeAddress = _feeAddress;
        emit SetFeeAddress(msg.sender, _feeAddress);
    }

    function updateEmissionRate(uint256 _oysterPerBlock) external onlyOwner {
        massUpdatePools();
        oysterPerBlock = _oysterPerBlock;
        emit UpdateEmissionRate(msg.sender, _oysterPerBlock);
    }

    function updateTides(uint256[] memory allocPoints) external onlyOwner {
        uint256 length = poolInfo.length;
        require(length == allocPoints.length, "updateTides: wrong length");

        massUpdatePools();
        totalAllocPoint = 0;
        for (uint256 pid = 0; pid < length; ++pid) {
            uint256 allocPoint = allocPoints[pid];
            poolInfo[pid].allocPoint = allocPoint;
            totalAllocPoint = totalAllocPoint.add(allocPoint);
        }
    }
}