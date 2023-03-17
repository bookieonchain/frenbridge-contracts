// SPDX-License-Identifier: MIT

pragma solidity ^0.8.1;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/Pausable.sol";

import "./interfaces/IAuthority.sol";
import "./interfaces/IBurnable.sol";
import "./interfaces/IBridge.sol";

import "./libraries/TransferHelper.sol";
import "./types/AccessControlled.sol";
import "./BridgeToken.sol";
import "./Signer.sol";

contract Bridge is IBridge, AccessControlled, Signer, Pausable {
    address constant DEAD = 0x000000000000000000000000000000000000dEaD;
    uint8 constant DEFAULT_THRESHOLD = 2;
    uint8 public threshold = DEFAULT_THRESHOLD;
    uint8 public activeRelayerCount = 0;
    uint8 public maxActiveRelayers = 255;
    uint256 public balance;

    address public feeRecipient;
    uint16 public feeAmount = 10; // 1%
    uint16 public constant feeFactor = 1000;

    uint256 public proposalIndex = 0;
    bytes32 immutable chainId;

    mapping(address => bool) public isWhitelistedRelayer;
    mapping(bytes32 => mapping(bytes32 => bool)) tokenWhitelistedForChain;

    mapping(bytes32 => Proposal) public __proposals;
    mapping(bytes32 => Token) public __tokens;
    mapping(bytes32 => Chain) public __chains;

    constructor(
        IAuthority _authority,
        bytes32 chainId_,
        address _feeRecipient,
        // Relayers
        address[] memory _relayers,
        // Chains
        bytes32[] memory _chainNames
    ) AccessControlled(_authority) {
        chainId = chainId_;
        feeRecipient = _feeRecipient;

        for (uint8 i = 0; i < _relayers.length; i++) {
            isWhitelistedRelayer[_relayers[i]] = true;
            activeRelayerCount += 1;
        }
        for (uint8 i = 0; i < _chainNames.length; i++) {
            __chains[_chainNames[i]].isWhitelisted = true;
        }
    }

    /*
     * Controller Methods
     */
    function pause() external onlyController {
        _pause();
    }

    function unpause() external onlyController {
        _unpause();
    }

    function setGasFee(bytes32 token, uint256 amount) external onlyController {
        __tokens[token].gasFee = amount;
    }

    function updateFeeAmount(uint16 _feeAmount) external onlyController {
        feeAmount = _feeAmount;
        emit FeeUpdated(feeAmount);
    }

    function updateFeeRecipient(address _feeRecipient) external onlyController {
        feeRecipient = _feeRecipient;
    }

    function updateRelayer(address _relayer, bool isWhitelisted)
        external
        onlyController
    {
        require(isWhitelistedRelayer[_relayer] != isWhitelisted, "redundant");
        isWhitelistedRelayer[_relayer] = isWhitelisted;
        isWhitelisted ? activeRelayerCount++ : activeRelayerCount--;
        emit WhitelistedRelayer(_relayer);
    }

    function updateMaxTransaction(bytes32 _token, uint256 maxTransaction)
        external
        onlyController
    {
        __tokens[_token].maxTransaction = maxTransaction;
    }

    function updateMinTransaction(bytes32 _token, uint256 minTransaction)
        external
        onlyController
    {
        __tokens[_token].minTransaction = minTransaction;
    }

    function addNativeToken(
        bytes32 _token,
        Token memory tokenData,
        bytes32[] memory chainIds
    ) external onlyController {
        // TODO: would you ever remove a token from the whitelist?
        __tokens[_token] = tokenData;

        // whitelist token for chains
        for (uint256 i = 0; i < chainIds.length; i++) {
            require(__chains[chainIds[i]].isWhitelisted, "unsupported chain");
            tokenWhitelistedForChain[_token][chainIds[i]] = true;
        }
    }

    function addNonNativeToken(
        bytes32 _token,
        uint256 maxTransaction,
        uint256 minTransaction,
        address nativeAddress,
        bytes32 nativeChain,
        bytes32[] memory chainIds,
        string memory name_,
        string memory symbol_,
        uint8 decimals_
    ) external onlyController {
        require(nativeChain != chainId, "native token");

        // TODO: would you ever remove a token from the whitelist?
        __tokens[_token].maxTransaction = maxTransaction;
        __tokens[_token].minTransaction = minTransaction;
        __tokens[_token].nativeAddress = nativeAddress;
        __tokens[_token].nativeChain = nativeChain;

        // whitelist token for chains
        for (uint256 i = 0; i < chainIds.length; i++) {
            require(__chains[chainIds[i]].isWhitelisted, "unsupported chain");
            tokenWhitelistedForChain[_token][chainIds[i]] = true;
        }

        // only create the token contract if there is no native address set
        require(bytes(name_).length != 0);
        require(bytes(symbol_).length != 0);
        require(decimals_ >= 6 && decimals_ <= 18);
        if (__tokens[_token].localAddress == address(0)) {
            BridgeToken _tokenAddress = new BridgeToken(
                authority,
                name_,
                symbol_,
                decimals_
            );
            __tokens[_token].localAddress = address(_tokenAddress);
            emit BridgeTokenCreated(_token, address(_tokenAddress));
        }
    }

    function whitelistChainId(bytes32 _chainId) external onlyController {
        __chains[_chainId] = Chain({isWhitelisted: true});
    }

    function setThreshold(uint8 _threshold) external onlyController {
        threshold = _threshold;
    }

    /*
     * Relayer Methods
     */

    function unwrapMultipleWithSignatures(
        RelayerRequest[] calldata requests,
        bytes[][] memory signatures
    ) external {
        for (uint256 i = 0; i < requests.length; i++) {
            bytes32 hashedProposal = hashProposal(requests[i]);
            for (uint256 j = 0; j < signatures[i].length; j++) {
                address signer = recoverSigner(
                    hashedProposal,
                    signatures[i][j]
                );
                _handleUnwrap(requests[i], hashedProposal, signer);
            }
        }
    }

    function unwrapWithSignatures(
        RelayerRequest calldata request,
        bytes[] memory signatures
    ) external {
        bytes32 hashedProposal = hashProposal(request);
        for (uint256 i = 0; i < signatures.length; i++) {
            address signer = recoverSigner(hashedProposal, signatures[i]);
            _handleUnwrap(request, hashedProposal, signer);
        }
    }

    function unwrapWithSignature(
        RelayerRequest calldata request,
        bytes memory signature
    ) external {
        bytes32 hashedProposal = hashProposal(request);
        address signer = recoverSigner(hashedProposal, signature);
        _handleUnwrap(request, hashedProposal, signer);
    }

    function overrideUnwrap(bytes32 hashedProposal) external onlyController {
        // used to override finalization of transaction
        __proposals[hashedProposal].completed = true;
    }

    function batchUnwrap(RelayerRequest[] calldata requests) external {
        uint256 completed = 0;
        for (uint256 i = 0; i < requests.length; i++) {
            RelayerRequest calldata cur = requests[i];
            bytes32 hashedProposal = hashProposal(cur);
            if (
                __proposals[hashedProposal].completed ||
                __proposals[hashedProposal].voted[msg.sender]
            ) {
                continue;
            }
            unwrap(cur);
            completed++;
        }
        require(completed > 0, "no op"); // this prevents accidently calling this and having no actions take place
    }

    function unwrap(RelayerRequest calldata request) public {
        bytes32 hashedProposal = hashProposal(request);
        _handleUnwrap(request, hashedProposal, msg.sender);
    }

    function _handleUnwrap(
        RelayerRequest calldata request,
        bytes32 hashedProposal,
        address sender
    ) internal whenNotPaused {
        require(isWhitelistedRelayer[sender], "not a valid relayer");
        require(request.targetChainId == chainId, "wrong chain");
        require(!__proposals[hashedProposal].completed, "already unwrapped");
        require(
            !__proposals[hashedProposal].voted[msg.sender],
            "already voted"
        );

        __proposals[hashedProposal].voted[msg.sender] = true;
        __proposals[hashedProposal].voteCount += 1;

        emit ProposalVoted(hashedProposal, msg.sender);

        if (__proposals[hashedProposal].voteCount >= threshold) {
            _unwrap(request.token, request.amount, request.recipient);
            __proposals[hashedProposal].completed = true;
            emit ProposalFinalized(hashedProposal);
        }
    }

    function sync() external {}

    /*
     * Public Method
     */

    function wrap(
        bytes32 token,
        uint256 amount,
        address recipient,
        bytes32 targetChainId
    ) public payable whenNotPaused {
        require(__chains[targetChainId].isWhitelisted, "chain not supported");
        require(
            tokenWhitelistedForChain[token][targetChainId],
            "chain not supported for token"
        );
        require(__tokens[token].isWhitelisted, "token not whitelisted");
        require(
            amount <= __tokens[token].maxTransaction,
            "over max transaction"
        );
        require(
            amount >= __tokens[token].minTransaction,
            "under min transaction"
        );

        uint256 gasFee = __tokens[token].gasFee;
        uint256 fee = (amount * feeAmount) / feeFactor;
        require(gasFee + fee < amount, "Transfer Amount Less Than Fee");
        amount -= fee + gasFee;

        if (__tokens[token].isGasToken) {
            payable(feeRecipient).transfer(fee + gasFee);
        } else {
            TransferHelper.safeTransferFrom(
                __tokens[token].localAddress,
                msg.sender,
                feeRecipient,
                fee + gasFee
            );
        }

        if (__tokens[token].isGasToken) {
            require(amount <= msg.value, "insufficient value provided");
        } else {
            TransferHelper.safeTransferFrom(
                __tokens[token].localAddress,
                msg.sender,
                address(this),
                amount
            );
        }

        if (__tokens[token].nativeChain != chainId) {
            try IBurnable(__tokens[token].localAddress).burn(amount) {} catch {
                IERC20(__tokens[token].localAddress).transfer(DEAD, amount);
            }
        }

        emit LockedToken(
            token,
            amount,
            recipient,
            targetChainId,
            block.number,
            proposalIndex++ // increment index to prevent collisions
        );
    }

    /*
     * Private Functions
     */

    function _unwrap(
        bytes32 token,
        uint256 amount,
        address recipient
    ) private {
        if (__tokens[token].nativeChain == chainId) {
            if (__tokens[token].isGasToken) {
                (bool sent, bytes memory _data) = payable(recipient).call{
                    value: amount
                }("");
                require(sent, "Failed to send Ether");
            } else {
                TransferHelper.safeTransfer(
                    __tokens[token].localAddress,
                    recipient,
                    amount
                );
            }
        } else {
            IBridgeToken(__tokens[token].localAddress).mint(recipient, amount);
        }
    }

    receive() external payable {}

    /*
     * VIEWS
     */

    function hasVoted(bytes32 _hashedProposal, address voter)
        external
        view
        returns (bool)
    {
        return __proposals[_hashedProposal].voted[voter];
    }

    /*
     * Pure Functions
     */

    function hashProposal(RelayerRequest calldata request)
        public
        pure
        returns (bytes32)
    {
        return
            keccak256(
                abi.encodePacked(
                    request.token,
                    request.amount,
                    request.recipient,
                    request.targetChainId,
                    request.transactionBlockNumber,
                    request._proposalIndex
                )
            );
    }
}
