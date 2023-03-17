// SPDX-License-Identifier: MIT

pragma solidity ^0.8.1;

import "./interfaces/IAuthority.sol";
import "./types/AccessControlled.sol";

contract Authority is IAuthority, AccessControlled {
    /* ========== EVENTS ========== */
    event BridgePushed(address indexed from, address indexed to);
    event ControllerPushed(
        address indexed from,
        address indexed to,
        bool _effectiveImmediately
    );
    event ControllerPulled(address indexed from, address indexed to);
    event Ping(address indexed from);

    /* ========== STATE VARIABLES ========== */
    address public override bridge;
    address public override controller;
    address public newBridge;
    address public newController;

    /* ========== Constructor ========== */

    constructor(address _controller)
        AccessControlled(IAuthority(address(this)))
    {
        controller = _controller;
    }

    /* ========== CONTROLLER ONLY ========== */

    function setBridge(address _newBridge) external onlyController {
        bridge = _newBridge;
        emit BridgePushed(bridge, newBridge);
    }

    function pushController(address _newController, bool _effectiveImmediately)
        external
        onlyController
    {
        if (_effectiveImmediately) controller = _newController;
        newController = _newController;
        emit ControllerPushed(controller, newController, _effectiveImmediately);
    }

    /* ========== PENDING ROLE ONLY ========== */

    function pullController() external {
        require(msg.sender == newController, "!newController");
        emit ControllerPulled(controller, newController);
        controller = newController;
    }

    function ping() external {
        // This can be used to track addresses using the contract
        emit Ping(msg.sender);
    }
}
