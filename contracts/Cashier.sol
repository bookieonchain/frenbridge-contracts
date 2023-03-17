// SPDX-License-Identifier: MIT

pragma solidity ^0.8.1;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract Cashier {
    address owner;

    constructor() {
        owner = msg.sender;
    }

    receive() external payable {}

    fallback() external payable {}

    function withdraw(IERC20 token, uint256 amount) external {
        require(msg.sender == owner, "only owner");
        token.transfer(msg.sender, amount);
    }

    function withdrawETH(uint256 amount) external {
        // (bool sent, bytes memory data) = payable(owner).call{
        //     value: address(this).balance
        // }("");
        payable(owner).transfer(amount);
        // require(sent, "Failed to send Ether");
    }
}
