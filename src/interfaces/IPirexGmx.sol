// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface IPirexGmx {
    function depositFsGlp(uint256 amount, address receiver)
        external
        returns (
            uint256,
            uint256,
            uint256
        );
}
