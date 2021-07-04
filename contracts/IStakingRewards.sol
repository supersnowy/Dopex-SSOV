//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

interface IStakingRewards {

  function stake(uint256 amount) external payable;
  function withdraw(uint256 amount) public;
  function compound() public;
  function rewardsDPX(address user) public returns (uint256);
  function balanceOf(address user) public returns (uint256);
  function getReward(uint256 id) public;

}
