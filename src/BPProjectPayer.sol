// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.21;

import {IJBTerminal} from "juice-contracts-v4/src/interfaces/terminal/IJBTerminal.sol";
import {JBConstants} from "juice-contracts-v4/src/libraries/JBConstants.sol";
import {SafeERC20, IERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

contract BPProjectPayer {
  function forwardERC20(IJBTerminal _terminal, uint256 _projectId, address _token) external {
    // Force approve the entire amount.
    uint256 _amount = IERC20(_token).balanceOf(address(this));
    SafeERC20.forceApprove(IERC20(_token), address(_terminal), _amount);

    _terminal.addToBalanceOf(
        _projectId, _token, _amount, false, string(""), bytes("")
    );

    // Sanity check: make sure we transfer the full amount.
    assert(IERC20(_token).balanceOf(address(this)) == 0);
  }
}
