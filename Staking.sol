// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.7.0 <0.9.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract Staking {
    using SafeERC20 for IERC20;

    IERC20 public nlnt;
    address public admin;

    uint256 public constant cliff = 60 days;
    uint256 public constant totalDuration = 365 days;
    uint256 public constant maxAmount = 10000;
    uint256 public constant minAmount = 100;
    uint256 public constant ReferralPercentage = 5;
    uint8 public constant globalLevel = 3;

    event TokenLocked(address indexed user, uint256 amount);
    event TokensClaimed(address indexed user, uint256 amount);
    event ReferralRewardClaimed(address indexed user, uint256 amount);
    event LevelIncomeClaimed(address indexed user, uint256 amount);
    event EmergencyWithdraw(address indexed admin, uint256 amount);

    struct Lock {
        uint256 nlntAmount;
        uint256 start;
        uint256 claimAmount;
        uint256 levelIncome;
        address referral;
    }

    mapping(address => Lock[]) public allStakeDetails;
    mapping(address => uint256) public referralRewards;

    constructor(address _nlnt) {
        nlnt = IERC20(_nlnt);
        admin = msg.sender;
    }

    modifier onlyAdmin() {
        require(msg.sender == admin, "Only admin can call this function");
        _;
    }

    function emergencyWithdraw(uint256 amount) external onlyAdmin {
        nlnt.safeTransfer(admin, amount);
        emit EmergencyWithdraw(admin, amount);
    }

    function lockToken(address _refAddress, uint256 _nlntAmount) external {
        require(_nlntAmount >= minAmount && _nlntAmount <= maxAmount, "Stake amount out of range");
        require(_refAddress != msg.sender, "Self referral not allowed");

        // Transfer token from user
        nlnt.safeTransferFrom(msg.sender, address(this), _nlntAmount);

        // Handle referral
        if (_refAddress != address(0)) {
            Lock[] storage refLocks = allStakeDetails[_refAddress];
            if (refLocks.length > 0) {
                uint256 referralReward = (_nlntAmount * ReferralPercentage) / 100;
                referralRewards[_refAddress] += referralReward;
            }
        }

        allStakeDetails[msg.sender].push(Lock({
            nlntAmount: _nlntAmount,
            start: block.timestamp,
            claimAmount: 0,
            levelIncome: 0,
            referral: _refAddress
        }));

        emit TokenLocked(msg.sender, _nlntAmount);
    }

    function claimTokens() external {
        Lock[] storage locks = allStakeDetails[msg.sender];
        uint256 totalClaimable;

        for (uint i = 0; i < locks.length; i++) {
            Lock storage l = locks[i];
            if (block.timestamp < l.start + cliff) continue;

            uint256 timePassed = block.timestamp - l.start;
            if (timePassed > totalDuration) timePassed = totalDuration;

            uint256 vestingTime = timePassed - cliff;
            uint256 monthPassed = vestingTime / 30 days;
            uint256 totalVested = (l.nlntAmount * 10 * monthPassed) / 100;

            if (totalVested > l.claimAmount) {
                uint256 claimable = totalVested - l.claimAmount;
                l.claimAmount += claimable;
                totalClaimable += claimable;

                distributeLevel(l.referral, claimable);
            }
        }

        require(totalClaimable > 0, "No tokens available to claim");
        nlnt.safeTransfer(msg.sender, totalClaimable);
        emit TokensClaimed(msg.sender, totalClaimable);
    }

    function claimReferralReward() external {
        uint256 reward = referralRewards[msg.sender];
        require(reward > 0, "No referral reward available");
        referralRewards[msg.sender] = 0;
        nlnt.safeTransfer(msg.sender, reward);
        emit ReferralRewardClaimed(msg.sender, reward);
    }

    function distributeLevel(address _refAddress, uint256 rewardAmount) internal {
        uint8[3] memory levelPercentage = [15, 10, 5];
        address currentRef = _refAddress;

        for (uint i = 0; i < globalLevel; i++) {
            if (currentRef == address(0)) break;

            Lock[] storage refLocks = allStakeDetails[currentRef];
            if (refLocks.length == 0) break;

            uint256 reward = (rewardAmount * levelPercentage[i]) / 100;
            refLocks[0].levelIncome += reward;
            currentRef = refLocks[0].referral;
        }
    }

    function claimLevelIncome() external {
        Lock[] storage locks = allStakeDetails[msg.sender];
        require(locks.length > 0, "No stakes found");

        uint256 income = locks[0].levelIncome;
        require(income > 0, "No level income to claim");

        locks[0].levelIncome = 0;
        nlnt.safeTransfer(msg.sender, income);
        emit LevelIncomeClaimed(msg.sender, income);
    }
}
