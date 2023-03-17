// SPDX-License-Identifier: MIT

pragma solidity ^0.8.10;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import "./interfaces/IBridgeToken.sol";

import "./types/AccessControlled.sol";
import "./interfaces/IAuthority.sol";

contract BridgeToken is IBridgeToken, ERC20, AccessControlled {
    uint8 immutable _decimals;

    constructor(
        IAuthority _authority,
        string memory name_,
        string memory symbol_,
        uint8 decimals_
    ) ERC20(name_, symbol_) AccessControlled(_authority) {
        _decimals = decimals_;
    }

    function mint(address account, uint256 amount) external onlyBridge {
        _mint(account, amount);
    }

    function decimals() public view virtual override returns (uint8) {
        return _decimals;
    }
}
