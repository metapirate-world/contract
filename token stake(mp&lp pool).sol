// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.7.0;
pragma experimental ABIEncoderV2;
import "../Manager/Member.sol";
import "../Utils/IERC20.sol";
import "../Utils/SafeMath.sol";
contract TokenStake is Member {
    
    using SafeMath for uint256;
    uint256 public totalDepositedAmount;
    uint256 public round;
    uint256 public totalRewards;
    uint256 public totalStakers;

    uint256 public timeLock = 15 minutes;
    
    IERC20 mp;
    IERC20 stakeToken;

    struct DaliyInfo {
        uint256 daliyDividends;
        uint256 rewardedAmount;
        uint256 totalDeposited;
    }

    struct UserInfo {
        uint256 depositedToken;
        uint256 lastRewardRound;
        uint256 pendingReward;
        uint256 receivedReward;
        uint256 pendingWithdraw;
    }
    
    mapping(uint256 => DaliyInfo) public daliyInfo;
    mapping(address => UserInfo) public userInfo;
    mapping(uint256 => uint256) public roundTime;
    mapping(address => uint256) public lockRequest;

    event NewRound(uint256 _round);
    event WithdrawRequest(address _user);
    event Withdraw(address _user, uint256 _amount);
    event GetReward(address _user, uint256 _amount);
    event Deposit(address _user, uint256 _amount);
    
    modifier validSender{
        require(msg.sender == manager.members("mpToken") || msg.sender == address(manager.members("nftMasterChef")) || msg.sender == manager.members("nft") || msg.sender == manager.members("updatecard") || msg.sender == manager.members("owner"));
        _;
    }
    
    constructor(IERC20 _mp, IERC20 _stakeToken) {
        mp = _mp;
        stakeToken = _stakeToken;
        // init();
    }
    
    function init() internal {
    }

    function getDaliyTotalDeposited(uint256 _round) public view returns(uint256) {
        return daliyInfo[_round].totalDeposited;
    }

    function claimReward(address _user) internal {
        uint256 reward = settleRewards(_user);
        userInfo[_user].pendingReward = userInfo[_user].pendingReward.add(reward);
        userInfo[_user].lastRewardRound = round;
    }
    
    function update(uint256 amount) external validSender {
        if(block.timestamp >= roundTime[round] + 24 minutes) {
            round++;
            roundTime[round] = block.timestamp;
            daliyInfo[round].daliyDividends = 0;
            daliyInfo[round].rewardedAmount = 0;
            daliyInfo[round].totalDeposited = daliyInfo[round-1].totalDeposited;

            if(round > 16) {
                IERC20(mp).transfer(address(manager.members("funder")), daliyInfo[round - 16].daliyDividends.sub(daliyInfo[round - 16].rewardedAmount));
            }
            emit NewRound(round);
        }
        daliyInfo[round].daliyDividends = daliyInfo[round].daliyDividends.add(amount);
        totalRewards = totalRewards.add(amount);
    }
    
    function deposit(uint256 amount) public {
        require(lockRequest[msg.sender] == 0, "is in pending");
        require(amount > 0);
        IERC20(stakeToken).transferFrom(msg.sender, address(this), amount);
        claimReward(msg.sender);
        if(userInfo[msg.sender].depositedToken == 0) {
            totalStakers++;
        }
        userInfo[msg.sender].depositedToken = userInfo[msg.sender].depositedToken.add(amount);
        totalDepositedAmount = totalDepositedAmount.add(amount);
        daliyInfo[round].totalDeposited = daliyInfo[round].totalDeposited.add(amount);
        emit Deposit(msg.sender, amount);
    }

    function getReward() public {
        uint256 reward = settleRewards(msg.sender);
        uint256 payReward = reward.add(userInfo[msg.sender].pendingReward);
        IERC20(mp).transfer(msg.sender, payReward);
        userInfo[msg.sender].receivedReward = userInfo[msg.sender].receivedReward.add(payReward);
        userInfo[msg.sender].pendingReward = 0;
        userInfo[msg.sender].lastRewardRound = round;
        emit GetReward(msg.sender, reward);
    }

    function timeLockChange(uint256 _period) public {
        require(msg.sender == manager.members("owner"), "onlyOwner");
        timeLock = _period;
    }
    
    function withdraw() public {
        require(lockRequest[msg.sender] !=0 && block.timestamp >= lockRequest[msg.sender].add(timeLock), "locked");
        uint256 pendingWithdraw = userInfo[msg.sender].pendingWithdraw;
        uint256 fee = pendingWithdraw.mul(2).div(100);
        IERC20(stakeToken).transfer(msg.sender, pendingWithdraw.sub(fee));
        IERC20(stakeToken).transfer(address(manager.members("OfficalAddress")), fee);
        
        lockRequest[msg.sender] = 0;
        totalDepositedAmount = totalDepositedAmount.sub(pendingWithdraw);
        userInfo[msg.sender].pendingWithdraw = 0;
        emit Withdraw(msg.sender, pendingWithdraw);
    }

    function withdrawRequest() public {
        require(lockRequest[msg.sender] == 0, "is in pending");
        getReward();

        uint256 userDeposited = userInfo[msg.sender].depositedToken;
        daliyInfo[round].totalDeposited = daliyInfo[round].totalDeposited.sub(userDeposited);
        userInfo[msg.sender].depositedToken = 0;
        userInfo[msg.sender].pendingWithdraw = userDeposited;
        totalStakers--;
        lockRequest[msg.sender] = block.timestamp;
        emit WithdrawRequest(msg.sender);
    }
    
    function pendingRewards(address _user) public view returns (uint256 reward){
        if(userInfo[_user].depositedToken == 0){
            return 0;
        }
        uint8 i = round.sub(userInfo[_user].lastRewardRound) >= 15 ? 15: uint8(round.sub(userInfo[_user].lastRewardRound));
        for(i; i >0; i--) {
            if(daliyInfo[round-i].daliyDividends == 0 || daliyInfo[round-i].totalDeposited == 0){
                continue;
            }
            reward = reward.add(daliyInfo[round-i].daliyDividends.mul(userInfo[_user].depositedToken).div(daliyInfo[round-i].totalDeposited));
        }
        reward = reward.add(userInfo[_user].pendingReward);
    }

    function settleRewards(address _user) internal returns (uint256 reward){
        if(userInfo[_user].depositedToken == 0){
            return 0;
        }
        uint8 i = round.sub(userInfo[_user].lastRewardRound) >= 15 ? 15: uint8(round.sub(userInfo[_user].lastRewardRound));
        uint256 roundReward;

        for(i; i >0; i--) {
            if(daliyInfo[round-i].daliyDividends == 0 || daliyInfo[round-i].totalDeposited == 0){
                continue;
            }
            // (daliyDividends * 用戶質押數 / 當時全網總質押)
            roundReward = daliyInfo[round-i].daliyDividends.mul(userInfo[_user].depositedToken).div(daliyInfo[round-i].totalDeposited);
            reward = reward.add(roundReward);
            daliyInfo[round-i].rewardedAmount+=roundReward;
        }
    }
    
}