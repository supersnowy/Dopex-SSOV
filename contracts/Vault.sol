//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "hardhat/console.sol";

import {SafeMath} from '@openzeppelin/contracts/math/SafeMath.sol';
import {SafeERC20} from '../libraries/SafeERC20.sol';

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC20PresetMinterPauser} from "@openzeppelin/contracts/token/ERC20/presets/ERC20PresetMinterPauser.sol";

import {BokkyPooBahsDateTimeLibrary} from './libraries/BokkyPooBahsDateTimeLibrary.sol';

import "./IStakingRewards.sol";

contract Vault is Ownable {

  using BokkyPooBahsDateTimeLibrary for uint;

  using SafeMath for uint;
  using SafeERC20 for IERC20;

  IERC20 public dpx;
  IStakingRewards public stakingRewards;

  // Current epoch for vault
  uint public epoch;
  // Initial bootstrap time
  uint public epochInitTime;
  // Mapping of strikes for each epoch
  mapping (uint => uint[]) public epochStrikes;
  // Mapping of (epoch => (strike => tokens))
  mapping (uint => mapping(uint => address)) epochStrikeTokens;

  // Total epoch deposits for strikes
  // mapping (epoch => (strike => deposits))
  mapping (uint => mapping (uint => uint)) public totalEpochDeposits;
  // Epoch deposits by user for each strike
  // mapping (epoch => (abi.encodePacked(user, strike) => user deposits))
  mapping (uint => mapping (bytes32 => uint)) public userEpochDeposits;

  event LogNewStrike(uint epoch, uint strike);
  event LogBootstrap(uint epoch);
  event LogNewDeposit(uint epoch, uint strike, address user);

  constructor(
    address _dpx,
    address _stakingRewards
  ) {
    require(_dpx != address(0), "Invalid dpx address");
    require(_stakingRewards != address(0), "Invalid staking rewards address");
    dpx = IERC20(_dpx);
    _stakingRewards = IStakingRewards(_stakingRewards);
  }

  /**
  * Bootstraps a new epoch and mints option tokens equivalent to user deposits for the epoch
  * @return Whether bootstrap was successful
  */
  function bootstrap() 
  public 
  onlyOwner 
  returns (bool) {
    require(epochStrikes[epoch + 1].length > 0, "Strikes have not been set for next epoch");
    require(getCurrentMonthlyEpoch() == epoch + 1, "Epoch hasn't completed yet");
    if (epoch == 0) {
      epochInitTime = block.timestamp;
    }
    for (uint i = 0; i < epochStrikes[epoch + 1].length; i++) {
      uint strike = epochStrikes[epoch + 1][i];
      string memory name = concatenate("DPX-CALL", strike);
      token = concatenate(token, "-EPOCH-");
      token = concatenate(token, epoch + 1);
      // Create doTokens representing calls for selected strike in epoch
      epochStrikeTokens[epoch + 1][strike] = 
        new ERC20PresetMinterPauser(
          name,
          name
        );
      // Mint tokens equivalent to deposits for strike in epoch
      IERC20(epochStrikeTokens[epoch + 1][strike])
        .mint(
          address(this), 
          totalEpochDeposits[epoch + 1][strike]
        );
    }
    epoch += 1;
    emit LogBootstrap(epoch);
  }

  /**
  * Sets strikes for next epoch
  * @param strikes Strikes to set for next epoch
  * @return Whether strikes were set
  */
  function setStrikes(
    uint[] strikes
  ) 
  public 
  onlyOwner
  returns (bool) {
    epochStrikes[epoch + 1] = strikes;
    for (uint i = 0; i < strikes.length; i++)
      emit LogNewStrike(epoch + 1, strike[i]);
  }

  /**
  * Deposits dpx into vaults to mint options in the next epoch for selected strikes
  * @param strike Strike price
  * @param amount Amout of DPX to deposit
  * @return Whether deposit was successful
  */
  function deposit(
    uint strikeIndex,
    uint amount
  ) 
  public 
  returns (bool) {
    uint strike = epochStrikes[epoch + 1][strikeIndex];
    // Must be a valid strike
    require(strike != 0, "Invalid strike");
    bytes32 userStrike = abi.encodePacked(msg.sender, strike);
    // Add to user epoch deposits
    userEpochDeposits[epoch + 1][userStrike] += amount;
    // Add to total epoch deposits
    totalEpochDeposits[epoch + 1][strike] += amount;
    // Transfer DPX from user to vault
    dpx.transferFrom(msg.sender, address(this), amount);
    // Deposit into staking rewards
    stakingRewards.stake(amount);
    emit LogNewDeposit(epoch + 1, strike, msg.sender);
  }

  /**
  * Deposit DPX multiple times
  * @param strikeIndices Indices of strikes to deposit into
  * @param amounts Amount of DPX to deposit into each strike index
  * @return Whether deposits went through successfully
  */
  function depositMultiple(
    uint[] strikeIndices,
    uint[] amounts
  ) public
  returns (bool) {
    for (uint i = 0; i < strikeIndices.length; i++)
      deposit(strikeIndices[i], amounts[i]);
  }

  function purchase() 
  public {

  }

  function exercise() 
  public {

  }

  function compound() 
  public {

  }

  function withdraw() 
  public {

  }

  /**
   * Returns start and end times for an epoch
   * @param epoch Target epoch
   * @param timePeriod Time period of the epoch (7 days or 28 days)
   */
  function getEpochTimes(
    uint epoch, 
    uint timePeriod
  )
    external
    view
    returns (uint start, uint end)
  {
    if (timePeriod == 7 days) {
      if (epoch == 1) {
        return (epochInitTime, getWeeklyExpiryFromTimestamp(epochInitTime));
      } else {
        uint _start = getWeeklyExpiryFromTimestamp(epochInitTime) + (timePeriod * (epoch - 2));
        return (_start, _start + timePeriod);
      }
    } else if (timePeriod == 28 days) {
      if (epoch == 1) {
        return (epochInitTime, getMonthlyExpiryFromTimestamp(epochInitTime));
      } else {
        uint _start = getMonthlyExpiryFromTimestamp(epochInitTime) + (timePeriod * (epoch - 2));
        return (_start, _start + timePeriod);
      }
    }
  }

  /*=== PURE FUNCTIONS ====*/

  /// @notice Calculates next available Friday expiry from a solidity date
  /// @param timestamp Timestamp from which the friday expiry is to be calculated
  /// @return The friday expiry
  function getWeeklyExpiryFromTimestamp(uint timestamp) public pure returns (uint) {
    // Use friday as 1-index
    uint dayOfWeek = BokkyPooBahsDateTimeLibrary.getDayOfWeek(timestamp, 6);
    uint nextFriday = timestamp + ((7 - dayOfWeek + 1) * 1 days);
    return
      BokkyPooBahsDateTimeLibrary.timestampFromDateTime(
        nextFriday.getYear(),
        nextFriday.getMonth(),
        nextFriday.getDay(),
        12,
        0,
        0
      );
  }

  /// @notice Calculates the monthly expiry from a solidity date
  /// @param timestamp Timestamp from which the monthly expiry is to be calculated
  /// @return The monthly expiry
  function getMonthlyExpiryFromTimestamp(uint timestamp) public pure returns (uint) {
    uint lastDay =
      BokkyPooBahsDateTimeLibrary.timestampFromDate(
        timestamp.getYear(),
        timestamp.getMonth() + 1,
        0
      );
    if (lastDay.getDayOfWeek() < 5) {
      lastDay = BokkyPooBahsDateTimeLibrary.timestampFromDate(
        lastDay.getYear(),
        lastDay.getMonth(),
        lastDay.getDay() - 7
      );
    }
    return
      BokkyPooBahsDateTimeLibrary.timestampFromDateTime(
        lastDay.getYear(),
        lastDay.getMonth(),
        lastDay.getDay() - (lastDay.getDayOfWeek() - 5),
        12,
        0,
        0
      );
  }

  /**
   * @notice Returns the current epoch based on the epoch init time and a 4 week time period
   * @dev Epochs are 1-indexed
   * @return Current monthly epoch number
   */
  function getCurrentMonthlyEpoch() external view returns (uint) {
    if (block.timestamp < epochInitTime) return 0;
    /**
     * Monthly Epoch = ((Current time - Init time) / 28 days) + 1
     * The current time is adjust to account for any 'init time' by adding to it the difference
     * between the init time and the first expiry.
     * Current time = block.timestamp - (28 days - (The first expiry - init time))
     */
    return
      (((block.timestamp +
        (28 days - (getMonthlyExpiryFromTimestamp(epochInitTime) - epochInitTime))) -
        epochInitTime) / (28 days)) + 1;
  }

  /**
   * @notice Returns the current epoch based on the epoch init time and a 1 week time period
   * @dev Epochs are 1-indexed
   * @return Current weekly epoch number
   */
  function getCurrentWeeklyEpoch() external view returns (uint) {
    if (block.timestamp < epochInitTime) return 0;
    /**
     * Weekly Epoch = ((Current time - Init time) / 7 days) + 1
     * The current time is adjust to account for any 'init time' by adding to it the difference
     * between the init time and the first expiry.
     * Current time = block.timestamp - (7 days - (The first expiry - init time))
     */
    return
      (((block.timestamp +
        (7 days - (getWeeklyExpiryFromTimestamp(epochInitTime) - epochInitTime))) - epochInitTime) /
        (7 days)) + 1;
  }

  function concatenate(
    string calldata a,
    string calldata b
  )
  external 
  pure
  returns(string memory) {
    return string(abi.encodePacked(a, b));
  }

}
