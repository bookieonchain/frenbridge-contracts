// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.10;

interface IAuthority {
    function bridge() external view returns (address);

    function controller() external view returns (address);

    function ping() external;
}
