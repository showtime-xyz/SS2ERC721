// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.0;

import {MultiSS2ERC721} from "./MultiSS2ERC721.sol";
import {Initializable} from "./common/utils/Initializable.sol";

/// @notice Initializable version of MultiSS2ERC721
abstract contract MultiSS2ERC721I is MultiSS2ERC721, Initializable {
    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor() MultiSS2ERC721("", "") {
        _lockInitializers();
    }

    /*//////////////////////////////////////////////////////////////
                              INITIALIZER
    //////////////////////////////////////////////////////////////*/

    function __MultiSS2ERC721_init(string memory _name, string memory _symbol) internal onlyInitializing {
        name = _name;
        symbol = _symbol;
    }
}
