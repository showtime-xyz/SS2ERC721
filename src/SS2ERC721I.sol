// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.0;

import {SS2ERC721} from "./SS2ERC721.sol";
import {Initializable} from "./utils/Initializable.sol";

/// @notice Initializable version of SS2ERC721
abstract contract SS2ERC721I is SS2ERC721, Initializable {
    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor() SS2ERC721("", "") {
        _lockInitializers();
    }

    /*//////////////////////////////////////////////////////////////
                              INITIALIZER
    //////////////////////////////////////////////////////////////*/

    function __SS2ERC721_init(string memory _name, string memory _symbol) internal onlyInitializing {
        name = _name;
        symbol = _symbol;
    }
}
