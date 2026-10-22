// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title Farming Season (SEASON)
/// @notice Fixed-supply, 18-decimal ERC-20. The deployer receives the entire supply once.
/// @dev No owner, external mint/burn entry points, transfer fees, or upgrade mechanism.
contract FarmingSeason is ERC20 {
    /// @notice One billion SEASON, expressed in the token's smallest units.
    uint256 public constant INITIAL_SUPPLY = 1_000_000_000 * 10 ** 18;

    /// @dev During a factory launch, msg.sender is the factory, which receives all tokens.
    constructor() ERC20("Farming Season", "SEASON") {
        _mint(msg.sender, INITIAL_SUPPLY);
    }
}
