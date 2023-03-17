// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.10;

import "./IBridgeToken.sol";

interface IBridge {
    struct Proposal {
        mapping(address => bool) voted;
        uint8 voteCount;
        bool completed;
    }

    struct RelayerRequest {
        bytes32 token;
        uint256 amount;
        address recipient;
        bytes32 targetChainId;
        uint256 transactionBlockNumber;
        uint256 _proposalIndex;
    }

    struct Token {
        bool isWhitelisted;
        address localAddress;
        // track the native token address for simplicity, even if redundant
        address nativeAddress;
        bytes32 nativeChain;
        // max amount in a single transaction
        uint256 maxTransaction;
        // min amount in a single transaction
        uint256 minTransaction;
        bool isGasToken;
        uint256 gasFee;
    }

    struct Chain {
        bool isWhitelisted;
    }

    event FeeUpdated(uint16);
    event ProposalFinalized(bytes32);
    event ProposalVoted(bytes32, address);
    event LockedToken(
        bytes32 token,
        uint256 amount,
        address recipient,
        bytes32 targetChainId,
        uint256 blockNumber,
        uint256 proposalIndex
    );
    event WhitelistedRelayer(address);
    event BridgeTokenCreated(bytes32, address);
}
