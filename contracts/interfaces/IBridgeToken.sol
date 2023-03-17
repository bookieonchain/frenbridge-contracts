// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.10;

interface IBridgeToken {
    function mint(address account, uint256 amount) external;
}
