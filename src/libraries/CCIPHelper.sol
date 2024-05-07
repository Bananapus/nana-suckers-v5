// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

/// @notice Global constants used across Juicebox contracts.
library CCIPHelper {

    /// @notice The respective CCIP router used by the chain
    address public constant ETH_ROUTER = 0x80226fc0Ee2b096224EeAc085Bb9a8cba1146f7D;
    address public constant OP_ROUTER = 0x3206695CaE29952f4b0c22a169725a865bc8Ce0f;
    address public constant ARB_ROUTER = 0x141fa059441E0ca23ce184B6A78bafD2A517DdE8;
    address public constant POLY_ROUTER = 0x849c5ED5a80F5B408Dd4969b78c2C8fdf0565Bfe;
    address public constant AVA_ROUTER = 0xF4c7E640EdA248ef95972845a62bdC74237805dB;
    address public constant BNB_ROUTER = 0x34B03Cb9086d7D758AC55af71584F81A598759FE;
    address public constant BASE_ROUTER = 0x881e3A65B4d4a04dD529061dd0071cf975F58bCD;

    /// @notice The respective chain ids per network
    uint256 public constant ETH_ID = 1;
    uint256 public constant OP_ID = 10;
    uint256 public constant ARB_ID = 42161;
    uint256 public constant POLY_ID = 137;
    uint256 public constant AVA_ID = 43114;
    uint256 public constant BNB_ID = 56;
    uint256 public constant BASE_ID = 8453;

    /// @notice The chain selector per network
    uint64 public constant ETH_SEL = 5009297550715157269;
    uint64 public constant OP_SEL = 3734403246176062136;
    uint64 public constant ARB_SEL = 4949039107694359620;
    uint64 public constant POLY_SEL = 4051577828743386545;
    uint64 public constant AVA_SEL = 6433500567565415381;
    uint64 public constant BNB_SEL = 11344663589394136015;
    uint64 public constant BASE_SEL = 15971525489660198786;
    
    function routerOfChain(uint256 _chainId) public pure returns(address router) {            
        if (_chainId == ETH_ID) {
            return ETH_ROUTER;
        } else if (_chainId == OP_ID) {
            return OP_ROUTER;
        } else if (_chainId == ARB_ID) {
            return ARB_ROUTER;
        } else if (_chainId == POLY_ID) {
            return POLY_ROUTER;
        } else if (_chainId == AVA_ID) {
            return AVA_ROUTER;
        } else if (_chainId == BNB_ID) {
            return BNB_ROUTER;
        } else if (_chainId == BASE_ID) {
            return BASE_ROUTER;
        } else {
            revert("Unsupported chain");
        }
    }

    function selectorOfChain(uint256 _chainId) public pure returns(uint64 selectorId) {            
        if (_chainId == ETH_ID) {
            return ETH_SEL;
        } else if (_chainId == OP_ID) {
            return OP_SEL;
        } else if (_chainId == ARB_ID) {
            return ARB_SEL;
        } else if (_chainId == POLY_ID) {
            return POLY_SEL;
        } else if (_chainId == AVA_ID) {
            return AVA_SEL;
        } else if (_chainId == BNB_ID) {
            return BNB_SEL;
        } else if (_chainId == BASE_ID) {
            return BASE_SEL;
        } else {
            revert("Unsupported chain");
        }
    }

}
