// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.0;

import {ERC721} from "solmate/tokens/ERC721.sol";

import {ERC721TokenReceiver} from "./ERC721TokenReceiver.sol";
import {Initializable} from "./utils/Initializable.sol";

/// @notice Initializable version of Solmate's ERC721
abstract contract ERC721I is ERC721, Initializable {
    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor() ERC721("", "") {
        _lockInitializers();
    }

    /*//////////////////////////////////////////////////////////////
                              INITIALIZER
    //////////////////////////////////////////////////////////////*/

    function __ERC721_init(string memory _name, string memory _symbol) internal onlyInitializing {
        name = _name;
        symbol = _symbol;
    }
}
