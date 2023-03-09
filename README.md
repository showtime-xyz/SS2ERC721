# SS2ERC721

SS2ERC721 is an experimental ERC721 base contract that aims to provide **hyper-optimized batch mints** to a **large number of distinct recipients** in a single transaction by storing the list of recipient addresses as an SSTORE2 pointer.

| total minted (1 per address) | OZ ERC721 (gas used) | SS2ERC721 (gas used) | diff |
| --- | --- | --- | --- |
| 1 | 73,229 | 84,362 | +15.20% |
| 10 | 732,290 | 142,489 | -80.54% |
| 100 | 7,322,900 | 722,765 | -90.13% |
| 1000 | 73,229,000 | 6,537,658 | -91.07% |

Key points:

- with a typical ERC721 contract, the cost per mint stays constant at 73k gas whereas with our approach the **cost per mint can go down to 6.5k gas**
- we can fit **up to 1228 mints in a single transaction.** The maximum number of mints per transaction is limited by SSTORE2 pointer size, not the block gas limit

Terminology:

- batch minting: mint-1-to-N-addresses (what this contract does)
- bulk minting: mint-M-to-1-address (see [Comparison with ERC721A](#comparison-with-erc721a) section)

We are going to need a new term combining bulk and batch minting (i.e. mint-M-to-N-addresses), which we consider as a potential addition in [Future Work](#future-work).

⚠️ **Caveat**: make sure you read and understand this document fully to know if the SS2ERC721 approach works for you. We make several important and unusual trade-offs that may not be beneficial for your use case. Seriously, it gets weird.

## How it works

Let’s take for example this simple SS2ERC721 implementation:

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {SSTORE2} from "solmate/utils/SSTORE2.sol";
import {SS2ERC721} from "src/SS2ERC721.sol";

contract BasicSS2ERC721 is SS2ERC721 {
    constructor(string memory name_, string memory symbol_)
        SS2ERC721(name_, symbol_) {}

    /// @dev recipients must be a packed encoding of sorted addresses
    /// @dev warning: no auth check on this method
    function mint(bytes calldata recipients) public {
        address ptr = SSTORE2.write(recipients);
        _mint(ptr);
    }

    function tokenURI(uint256)
        public view virtual override returns (string memory)
    {
        return "";
    }
}
```

We start by collecting the addresses of recipients out of band / off-chain.

At the end of the collection phase, we:

- sort the addresses and ensure there are no duplicates
- encode them into a packed bytes array (e.g. using `abi.encodePacked(...)`)
- invoke `BasicSS2ERC721.mint(recipients)` which:
    - writes `recipients` as an SSTORE2 pointer
    - stores `pointer` — this will be used later by SS2ERC721 to determine token ownership and balances
    - iterates over the addresses at `pointer`
    - emits a `Transfer` event for each decoded address

The savings come from:

- being able to mint many NFTs as part of a single transaction (vs spending the intrinsic gas cost of n transactions)
- using a compact encoding of addresses (1000 addresses is stored as a single 20kB buffer)
- using read-only SSTORE2 for storage instead of regular read-write contract storage
- expecting a continuous range of token ids, which allows for an efficient mapping between an address’ index in the byte array and the token id it owns

**✨ Additional goodies**

- because the addresses of primary recipients is immutable and easy to look up, it can be looked up by anyone forever even if they later transfer their NFTs. This could be useful for a reputation system, or as a basis for a non-transferable token
- if 2 collections share the same primary recipients, we don’t actually need to redeploy the SSTORE2 pointer, we can save that cost and actually mint a second collection with the existing pointer. This is about 65% cheaper and brings the cost down to 2.3k/mint.

## Comparison with a regular ERC721

Let’s take a straightforward ERC721 implementation using OpenZeppelin’s ERC721 as a base:

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {ERC721} from "openzeppelin-contracts/contracts/token/ERC721/ERC721.sol";

contract BasicERC721 is ERC721 {
    uint256 nextTokenId = 1;

    constructor() ERC721("basic", unicode"✌️") {}

    function mint() external {
        _mint(msg.sender, nextTokenId);

        unchecked {
            nextTokenId++;
        }
    }
}
```

It uses a `nextTokenId` counter and lets anyone who wants a token mint one (i.e. mint-1-to-1-address).

When we call mint:

- the `_balances` mapping is updated (1 new storage slot if this is a new owner, 20k gas)
- the `_owners` mapping is updated (1 whole new storage slot for the address, 20k gas)
- a `Transfer` event is emitted (about 2k gas)
- `nextTokenId` is updated (1 storage load + 1 storage write to an existing non-0 slot, about 5k gas total)

This whole process needs to be repeated for each `mint` transaction, so after 1000 mints our contract storage has expanded by 2000 storage slots (64kB) and has overwritten the `nextTokenId` slot 1000 times.

The base ERC721 is very general and makes no assumption about token ids being continuous, so we can’t take advantage of the fact that our simple collection uses auto-incrementing token ids.

## Comparison with ERC721A

ERC721A optimizes for **bulk minting**, that is to say it works well when a single minter mints multiple NFTs for a cost comparable to minting a single NFT (mint-M-to-1-address). It accomplishes this by taking advantage of the fact that you can use a compact representation for a range of consecutive token ids.

The use case we are optimizing for (mint-1-to-N-addresses) is actually a worst-case scenario for ERC721A. In that scenario, ERC721A can not take advantage of the range optimization because the range size is always 1.

Note that the current version of SS2ERC721 does not support bulk minting at all, we do not allow duplicates in the bytes array representing recipients, so every recipient gets exactly one token.

## Trade-offs

- the current SS2ERC721 implementation expects a single batch, i.e. a single `mint(address ptr)` transaction with a single SSTORE2 pointer
- as a consequence, the number of tokens supported by this method is limited by the maximum size of an SSTORE2 pointer, which is currently 24576 bytes. This means we can mint up to 1228 token ids in a single transaction.
- we do not support arbitrary token ids, minting to n recipients will result in tokens ids ranging from 1 to n
- because addresses need to be sorted, addresses that are numerically smaller are more likely to get token id 1. This differs from the typical first-come-first-serve or the grab-any-available-token-id models. Collectors can’t know ahead of time exactly what token id they will receive, but they can bias the result by choosing intentionally small or intentionally big addresses.
- SS2ERC721 works well in the context of a free open edition with a limit of 1 per recipient, implementing payments is not straightforward and would need to be done out of band
- to support transfers, we have separate mappings for secondary owners and balances. This means that `balanceOf(address owner)`, `ownerOf(uint256 tokenId)` and the transfer functions are all significantly more expensive than in a typical ERC721 implementation
- we do not explicitly store the balance of primary owners in a mapping to save on storage cost. So instead of the typical O(1) lookup cost, we actually do a binary search and have an O(log n) cost.
- unlike ERC721 and ERC721A, we do no support real-time minting. A centralized entity must collect recipients and then trigger the batch mint for everyone.

| function | BasicERC721 | SS2ERC721 | diff |
| --- | --- | --- | --- |
| balanceOf(address) | 9927 | 16890 | +70.14% |
| ownerOf(uint256) | 7724 | 13868 | +79.54% |
| transferFrom (initial) | 45787 | 90143 | +96.87% |
| transferFrom (subsequent) | 45787 | 45250 | -1.17% |

☝️ make sure you’re ok with these costs before considering adopting SS2ERC721

## How ownerOf works

Since the NFTs are transferrable and the primary owners pointer is immutable, we introduce the following mapping:

```solidity
mapping(uint256 => address) internal _ownerOfSecondary;
```

In `ownerOf(uint256 tokenId)`, we first look up the `_ownerOfSecondary` mapping. If we get `address(0)` back, we know that this tokenId has not been transferred and we need to fall back to the primary owners pointer. For this, we do an O(1) lookup by loading only the necessary slice using SSTORE2 (the owner of tokenId n is the nth 20-byte entry in the buffer):

```solidity
		function _ownerOfPrimary(uint256 id) internal view returns (address owner) {
        require(id > 0, "ZERO_ID");
        require(id <= _ownersPrimaryLength(), "NOT_MINTED");

        unchecked {
            uint256 start = (id - 1) * 20;
            owner = bytesToAddress(SSTORE2.read(_ownersPrimaryPointer, start, start + 20));
        }
    }
```

**Complexity**: O(1)

**Best case**: a single mapping lookup when the tokenId has been transferred

**Worst case**: mapping lookup + 1 SSTORE2 read when the token has not been transferred

Because this is a view function, we are ok with this trade-off. You may want to avoid calling it from another contract to avoid the extra gas cost if possible.

## How balanceOf works

Figuring out the balance of a given address is a little trickier, because:

- we know the balance is either 0 or 1 during the initial mint, by design
- but because of transferrability, the balance can both decrease and increase, so we introduce a signed adjustment mapping

```solidity
mapping(address => int256) internal _balanceOfAdjustment;
```

Unlike for `ownerOf`, given an address and the primary owners pointer, we can’t immediately tell if `_balanceOfPrimary(owner)` should be 0 or 1. But since we require the addresses to be sorted, we can perform a binary search and return 1 if we find a match or 0 if we find no match:

```solidity
function _balanceOfPrimary(address owner) internal view returns (uint256) {
    uint256 low = 1;
    uint256 high = _ownersPrimaryLength();
    uint256 mid = (low + high) / 2;

    while (low <= high) {
        address midOwner = _ownerOfPrimary(mid);
        if (midOwner == owner) {
            return 1;
        } else if (midOwner < owner) {
            low = mid + 1;
        } else {
            high = mid - 1;
        }
        mid = (low + high) / 2;
    }

    return 0;
}
```

Note the usage of `_ownerOfPrimary(mid)`, which we already established is O(1).

After that, we add the signed `_balanceOfAdjustment[owner]`, convert back to a `uint256` and return the result:

```solidity
function balanceOf(address owner)
		public view virtual override returns (uint256)
{
    require(owner != address(0), "ZERO_ADDRESS");

    int256 balance = int256(_balanceOfPrimary(owner)) + _balanceOfAdjustment[owner];
    require(balance >= 0, "OVERFLOW");

    return uint256(balance);
}
```

Examples:

- you were one of the primary recipients, and then sold the NFT so you have `_balanceOfPrimary(owner) = 1` and `_balanceOfAdjustment[owner] = -1` for a resulting balance of 0
- you were not one of the primary recipients, but were gifted an NFT so you have `_balanceOfPrimary(owner) = 0` and `_balanceOfAdjustment[owner] = 1` for a resulting balance of 1
- you were one of the primary recipients, and then acquired 4 more on a secondary market so you have `_balanceOfPrimary(owner) = 1` and `_balanceOfAdjustment[owner] = 4` for a

**Complexity**: O(log n) SSTORE2 reads

**Best case**: a mapping lookup + a quick binary search in the case of a primary owner

**Worst case**: mapping lookup + long binary search in the case of an address that is not a primary owner

Because this is a view function, we are ok with this trade-off. You may want to avoid calling it from another contract to avoid the extra gas cost if possible.

### How transferFrom works

It works just like a regular ERC721 `transferFrom`, except that we operate on the secondary owners and balances mappings:

```solidity
function transferFrom(address from, address to, uint256 id) public virtual override {
		// need to use the ownerOf getter here instead of directly accessing the storage
    require(from == ownerOf(id), "WRONG_FROM");
		...

		unchecked {
		    _balanceOfAdjustment[from]--;
		    _balanceOfAdjustment[to]++;
		}

		_ownerOfSecondary[id] = to;
		delete getApproved[id];
    emit Transfer(from, to, id);
}
```

**Complexity**: O(1) (uses `ownerOf(id)` which is O(1))

**Best case**: transfer from a secondary owner to another secondary owner (so `ownerOf(id)` is cheap, and `_balanceOfAdjustment[from]--` may free a storage slot if it resets to 0)

**Worst case**: transfer from a primary owner to a new secondary owner (so `ownerOf(id)` is expensive, `_balanceOfAdjustment[from]--` stores -1 and `_balanceOfAdjustment[to]++` stores 1)

The cost is initially higher when primary owners transfer their NFTs, but the cost of `transferFrom` after a lot of secondary activity should asymptotically tend toward the cost of regular ERC721 transfers.

## Future work

- combine our batch minting approach (mint-1-to-N-addresses) with ERC721A’s bulk minting (mint-M-to-1-address) to allow many recipients receive one or more tokens (mint-M-to-N-addresses)
- multi-step minting to lift the limit of 1228 recipients in a collection
- prove that there can be no overflows in the binary search and use unchecked maths

## Safety

This is **experimental software** and is provided on an "as is" and "as available" basis.

It has **not been audited** or even **battle tested** yet. Consider it a proof-of-concept.

We **do not give any warranties** and **will not be liable for any loss** incurred through any use of this codebase.

## Installation

To install as a [Foundry](https://github.com/foundry-rs/foundry) dependency:

```bash
forge install showtime-xyz/SS2ERC721
```

To build and run locally:

```python
# clone this repo
git clone git@github.com:showtime-xyz/SS2ERC721.git

# build
forge build

# test
forge test -vvv

# fuzz test harder
FOUNDRY_PROFILE=superheavy_fuzz forge test -vvv
```

## License

This project is dual-licensed as:

- AGPL-3.0 for the parts derived from solmate
- MIT for everything else

See each file header to see what license applies.

## Acknowledgements

We took some inspiration, and sometimes actual code snippets from these projects:

- [ENS](https://github.com/ensdomains/ens-contracts)
- [solmate](https://github.com/transmissions11/solmate/)
- [ERC721A](https://github.com/chiru-labs/ERC721A)
- [OpenZeppelin](https://github.com/OpenZeppelin/openzeppelin-contracts)

Thanks to [horsefacts](https://twitter.com/eth_call), [t11s](https://twitter.com/transmissions11/) and [vectorized.eth](https://twitter.com/optimizoor/) for their feedback
