// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.10;

import "../interfaces/IAuthority.sol";

abstract contract AccessControlled {
    /* ========== EVENTS ========== */
    event AuthorityUpdated(IAuthority indexed authority);
    string UNAUTHORIZED = "UNAUTHORIZED"; // save gas

    /* ========== STATE VARIABLES ========== */
    IAuthority public authority;

    /* ========== Constructor ========== */

    constructor(IAuthority _authority) {
        authority = _authority;
        emit AuthorityUpdated(_authority);

        if (address(_authority) != address(this)) {
            _ping();
        }
    }

    /* ========== MODIFIERS ========== */

    modifier onlyBridge() {
        require(msg.sender == authority.bridge(), UNAUTHORIZED);
        _;
    }

    modifier onlyController() {
        require(msg.sender == authority.controller(), UNAUTHORIZED);
        _;
    }

    function _ping() internal {
        // used to track contracts using the authority on the authority contract
        // could simplify upgrades
        authority.ping();
    }

    /* ========== GOV ONLY ========== */

    function setAuthority(IAuthority _newAuthority) external onlyController {
        authority = _newAuthority;
        emit AuthorityUpdated(_newAuthority);

        _ping();
    }
}
