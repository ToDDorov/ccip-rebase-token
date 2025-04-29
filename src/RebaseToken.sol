// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {console} from "forge-std/console.sol";

/**
 * @title RebaseToken
 * @author Todoro Todorov
 * @notice This is a cross-chain rebase token that incentivizes users to deposit into a vault and gain interest in rewards
 * @notice The interest rate in the smart contract can only decrease
 * @notice Each user will have their own interest rate that is the global interest rate at the moment of deposit
 */
contract RebaseToken is ERC20, Ownable(msg.sender), AccessControl {
    error RebaseOtken__InterestRateCanOnlyDecrease(uint256 oldInterestRate, uint256 newInterestRate);

    uint256 private constant PRECISION_FACTOR = 1e18;
    bytes32 private constant MINT_AND_BURN_ROLE = keccak256("MINT_AND_BURN_ROLE");

    uint256 private s_interestRate = (5 * PRECISION_FACTOR) / 1e8; // 10^-8 == 1/ 10^8
    mapping(address => uint256) private s_userInterestRates;
    mapping(address => uint256) private s_userLastUpdatedTimestamp;

    event InterestRateSet(uint256 newInterestRate);

    constructor() ERC20("RebaseToken", "RBT") {}

    function grantMintAndBurnRole(address _account) external onlyOwner {
        _grantRole(MINT_AND_BURN_ROLE, _account);
    }

    /**
     *
     * @param _newInterestRate The new interest rate
     * @notice The interest rate in the smart contract can only decrease
     */
    function setInterestRate(uint256 _newInterestRate) external onlyOwner {
        if (_newInterestRate >= s_interestRate) {
            revert RebaseOtken__InterestRateCanOnlyDecrease(s_interestRate, _newInterestRate);
        }

        s_interestRate = _newInterestRate;
        emit InterestRateSet(s_interestRate);
    }

    /**
     * @notice Returns the principal balance of a user
     * @param _user The user to get the principal balance for
     * @return The principal balance of the user
     */
    function principableBalanceOf(address _user) external view returns (uint256) {
        return super.balanceOf(_user);
    }

    /**
     * @notice Mints tokens for a user
     * @param _to The user to mint tokens for
     * @param _amount The amount of tokens to mint
     */
    function mint(address _to, uint256 _amount, uint256 _userInterestRate) external onlyRole(MINT_AND_BURN_ROLE) {
        _mintAccruedInterest(_to);
        s_userInterestRates[_to] = _userInterestRate;
        _mint(_to, _amount);
    }

    function balanceOf(address _user) public view override returns (uint256) {
        return (super.balanceOf(_user) * _calculateUserAccumulatedInterestSinceLastUpdate(_user)) / PRECISION_FACTOR;
    }

    function transfer(address _recipent, uint256 _amount) public override returns (bool) {
        _mintAccruedInterest(msg.sender);
        _mintAccruedInterest(_recipent);

        if (_amount == type(uint256).max) {
            _amount = balanceOf(msg.sender);
        }

        if (balanceOf(_recipent) == 0) {
            s_userInterestRates[_recipent] = s_userInterestRates[msg.sender];
        }

        return super.transfer(_recipent, _amount);
    }

    function transferFrom(address _sender, address _recipent, uint256 _amount) public override returns (bool) {
        _mintAccruedInterest(_sender);
        _mintAccruedInterest(_recipent);

        if (_amount == type(uint256).max) {
            _amount = balanceOf(_sender);
        }

        if (balanceOf(_recipent) == 0) {
            s_userInterestRates[_recipent] = s_userInterestRates[_sender];
        }

        return super.transferFrom(_sender, _recipent, _amount);
    }

    function _calculateUserAccumulatedInterestSinceLastUpdate(address _user)
        internal
        view
        returns (uint256 linearInterest)
    {
        uint256 timeElapsed = block.timestamp - s_userLastUpdatedTimestamp[_user];
        linearInterest = PRECISION_FACTOR + (s_userInterestRates[_user] * timeElapsed);
    }

    function _mintAccruedInterest(address _to) internal {
        uint256 previousPrincipalBalance = super.balanceOf(_to);
        uint256 currentBalance = balanceOf(_to);
        uint256 balanceIncrease = currentBalance - previousPrincipalBalance;

        s_userLastUpdatedTimestamp[_to] = block.timestamp;
        _mint(_to, balanceIncrease);
    }

    function burn(address _from, uint256 _amount) external onlyRole(MINT_AND_BURN_ROLE) {
        if (_amount == type(uint256).max) {
            _amount = balanceOf(_from);
        }

        _mintAccruedInterest(_from);
        _burn(_from, _amount);
    }

    /**
     * @notice Returns the interest rate for a given user
     * @param _user The user to get the interest rate for
     */
    function getUserInterestRate(address _user) external view returns (uint256) {
        return s_userInterestRates[_user];
    }

    function getInterestRate() external view returns (uint256) {
        return s_interestRate;
    }
}
