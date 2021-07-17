// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

contract Vesting is Ownable {
  using SafeMath for uint256;
  using SafeERC20 for IERC20;

  IERC20 public token;
  uint256 public startBlock;
  uint256 public vestPerBlock;
  uint256 public withdrawn;

  constructor(IERC20 _token, uint256 _startBlock, uint256 _vestPerBlock) public {
    token = _token;
    startBlock = _startBlock;
    vestPerBlock = _vestPerBlock;
    withdrawn = 0;
  }

  function withdrawVested(address to) public onlyOwner {
    require(block.number >= startBlock, "withdrawVested: not vested");

    uint256 withdrawAmount = block.number.sub(startBlock).mul(vestPerBlock).sub(withdrawn);
    uint256 balance = token.balanceOf(address(this));
    if (balance < withdrawAmount) {
      withdrawAmount = balance;
    }
    if (withdrawAmount > 0) {
      withdrawn = withdrawn.add(withdrawAmount);
      token.safeTransfer(to, withdrawAmount);
    }
  }
}
