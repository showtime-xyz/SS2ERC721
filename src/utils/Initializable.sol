// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.0;

/// @notice Modern, minimalist, and gas efficient Initializable implementation with no reinitializers
/// @dev warning: this contract is not compatible with OpenZeppelin's Initializable
/// @dev warning: this should be considered very experimental
/// @author karmacoma
abstract contract Initializable {
    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event Initialized();

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    enum InitState {
        NOT_INITIALIZED,
        INITIALIZING,
        INITIALIZED
    }

    InitState private _initState;

    /*//////////////////////////////////////////////////////////////
                          INITIALIZABLE LOGIC
    //////////////////////////////////////////////////////////////*/

    modifier initializer() {
        bool isTopLevelCall = _initState == InitState.NOT_INITIALIZED;

        require(
            (isTopLevelCall) || (_initState == InitState.INITIALIZING),
            "ALREADY_INITIALIZED"
        );
        if (isTopLevelCall) {
            _initState = InitState.INITIALIZING;
        }
        _;
        if (isTopLevelCall) {
            _initState = InitState.INITIALIZED;
            emit Initialized();
        }
    }

    modifier onlyInitializing() {
        require(_initState == InitState.INITIALIZING, "NOT_INITIALIZING");
        _;
    }

    /// locks the contract, preventing any further initialization
    function _lockInitializers() internal virtual {
        require(
            _initState == InitState.NOT_INITIALIZED,
            "MUST_BE_NOT_INITIALIZED"
        );
        _initState = InitState.INITIALIZED;
        emit Initialized();
    }
}
