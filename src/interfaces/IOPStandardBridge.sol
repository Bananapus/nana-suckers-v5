// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IOPStandardBridge {
    /**
     * @notice Sends ERC20 tokens to a receiver's address on the other chain. Note that if the
     *         ERC20 token on the other chain does not recognize the local token as the correct
     *         pair token, the ERC20 bridge will fail and the tokens will be returned to sender on
     *         this chain.
     *
     * @param localToken  Address of the ERC20 on this chain.
     * @param remoteToken Address of the corresponding token on the remote chain.
     * @param to          Address of the receiver.
     * @param amount      Amount of local tokens to deposit.
     * @param minGasLimit Minimum amount of gas that the bridge can be relayed with.
     * @param extraData   Extra data to be sent with the transaction. Note that the recipient will
     *                     not be triggered with this data, but it will be emitted and can be used
     *                     to identify the transaction.
     */
    function bridgeERC20To(
        address localToken,
        address remoteToken,
        address to,
        uint256 amount,
        uint32 minGasLimit,
        bytes calldata extraData
    ) external;
}
