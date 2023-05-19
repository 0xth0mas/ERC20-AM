// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;


import {ILiquidityPoolCodeHashRegistry} from './ILiquidityPoolCodeHashRegistry.sol';

/// @notice Modern and gas efficient ERC20 + EIP-2612 implementation with anti-MEV protection
/// @author 0xth0mas 
/// @author Modified from Solmate (https://github.com/transmissions11/solmate/blob/main/src/tokens/ERC20.sol)
/// @author Modified from Uniswap (https://github.com/Uniswap/uniswap-v2-core/blob/master/contracts/UniswapV2ERC20.sol)
/// @dev Do not manually set balances without updating totalSupply, as the sum of all user balances must not exceed it.
abstract contract ERC20 {


    /*//////////////////////////////////////////////////////////////
                                 STRUCTS
    //////////////////////////////////////////////////////////////*/

    struct PackedBalance {
        uint64 lastBlock;
        bool balanceIncreased;
        uint184 balance;
    }

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event Transfer(address indexed from, address indexed to, uint256 amount);

    event Approval(address indexed owner, address indexed spender, uint256 amount);

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error CannotIncreaseAndDecreaseInSameBlock();

    /*//////////////////////////////////////////////////////////////
                            METADATA STORAGE
    //////////////////////////////////////////////////////////////*/

    string public name;

    string public symbol;

    uint8 public immutable decimals;

    /*//////////////////////////////////////////////////////////////
                              ERC20 STORAGE
    //////////////////////////////////////////////////////////////*/

    uint256 public totalSupply;

    mapping(address => PackedBalance) private _balances;

    mapping(address => mapping(address => uint256)) public allowance;

    /*//////////////////////////////////////////////////////////////
                            ANTI-MEV STORAGE
    //////////////////////////////////////////////////////////////*/

    mapping(bytes32 => bool) private _allowedCodeHash;

    ILiquidityPoolCodeHashRegistry liquidityPoolRegistry = ILiquidityPoolCodeHashRegistry(0x9876543210987654321098765432109876543210);

    /*//////////////////////////////////////////////////////////////
                            EIP-2612 STORAGE
    //////////////////////////////////////////////////////////////*/

    uint256 internal immutable INITIAL_CHAIN_ID;

    bytes32 internal immutable INITIAL_DOMAIN_SEPARATOR;

    mapping(address => uint256) public nonces;

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(
        string memory _name,
        string memory _symbol,
        uint8 _decimals
    ) {
        name = _name;
        symbol = _symbol;
        decimals = _decimals;

        INITIAL_CHAIN_ID = block.chainid;
        INITIAL_DOMAIN_SEPARATOR = computeDomainSeparator();
    }

    /*//////////////////////////////////////////////////////////////
                               ERC20 LOGIC
    //////////////////////////////////////////////////////////////*/

    function balanceOf(address owner) public view returns(uint256 _balance) {
        _balance = uint256(_balances[owner].balance);
    }

    function approve(address spender, uint256 amount) public virtual returns (bool) {
        allowance[msg.sender][spender] = amount;

        emit Approval(msg.sender, spender, amount);

        return true;
    }

    function transfer(address to, uint256 amount) public virtual returns (bool) {
        _transfer(msg.sender, to, amount);

        return true;
    }

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) public virtual returns (bool) {
        uint256 allowed = allowance[from][msg.sender]; // Saves gas for limited approvals.

        if (allowed != type(uint256).max) allowance[from][msg.sender] = allowed - amount;

        _transfer(from, to, amount);

        return true;
    }

    function _transfer(address from, address to, uint256 amount) internal {
        PackedBalance storage fromPackedBalance = _balances[from];
        PackedBalance storage toPackedBalance = _balances[to];

        fromPackedBalance.balance -= uint184(amount);
        toPackedBalance.balance += uint184(amount);

        if(fromPackedBalance.lastBlock == block.number && fromPackedBalance.balanceIncreased) {
            if(!isValidPool(from)) {
                revert CannotIncreaseAndDecreaseInSameBlock();
            }
        }

        if(toPackedBalance.lastBlock == block.number && !toPackedBalance.balanceIncreased) {
            if(!isValidPool(to)) {
                revert CannotIncreaseAndDecreaseInSameBlock();
            }
        }

        fromPackedBalance.lastBlock = uint64(block.number);
        fromPackedBalance.balanceIncreased = false;
        toPackedBalance.lastBlock = uint64(block.number);
        toPackedBalance.balanceIncreased = true;

        emit Transfer(from, to, amount);
    }

    /*//////////////////////////////////////////////////////////////
                               ANTI-MEV LOGIC
    //////////////////////////////////////////////////////////////*/
    

    function isValidPool(address _address) internal returns(bool) {
        if(_address.code.length == 0) {
            return false;
        } else {
            bytes32 codeHash;    
            assembly { codeHash := extcodehash(_address) }
            if(!_allowedCodeHash[codeHash]) {
                if(liquidityPoolRegistry.isValidCodeHash(codeHash)) {
                    _allowedCodeHash[codeHash] = true;
                } else {
                    return false;
                }
            } 
        }
        return true;
    }
    

    function updateCodeHashCache(address[] calldata _addresses) public {
        for(uint256 i = 0;i < _addresses.length;) {
            address _address = _addresses[i];
            bytes32 codeHash;
            assembly { codeHash := extcodehash(_address) }
            _allowedCodeHash[codeHash] = liquidityPoolRegistry.isValidCodeHash(codeHash);

            unchecked { ++i; }
        }
    }

    /*//////////////////////////////////////////////////////////////
                             EIP-2612 LOGIC
    //////////////////////////////////////////////////////////////*/

    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public virtual {
        require(deadline >= block.timestamp, "PERMIT_DEADLINE_EXPIRED");

        // Unchecked because the only math done is incrementing
        // the owner's nonce which cannot realistically overflow.
        unchecked {
            address recoveredAddress = ecrecover(
                keccak256(
                    abi.encodePacked(
                        "\x19\x01",
                        DOMAIN_SEPARATOR(),
                        keccak256(
                            abi.encode(
                                keccak256(
                                    "Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"
                                ),
                                owner,
                                spender,
                                value,
                                nonces[owner]++,
                                deadline
                            )
                        )
                    )
                ),
                v,
                r,
                s
            );

            require(recoveredAddress != address(0) && recoveredAddress == owner, "INVALID_SIGNER");

            allowance[recoveredAddress][spender] = value;
        }

        emit Approval(owner, spender, value);
    }

    function DOMAIN_SEPARATOR() public view virtual returns (bytes32) {
        return block.chainid == INITIAL_CHAIN_ID ? INITIAL_DOMAIN_SEPARATOR : computeDomainSeparator();
    }

    function computeDomainSeparator() internal view virtual returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                    keccak256(bytes(name)),
                    keccak256("1"),
                    block.chainid,
                    address(this)
                )
            );
    }

    /*//////////////////////////////////////////////////////////////
                        INTERNAL MINT/BURN LOGIC
    //////////////////////////////////////////////////////////////*/

    function _mint(address to, uint256 amount) internal virtual {
        totalSupply += amount;

        PackedBalance storage toPackedBalance = _balances[to];
        toPackedBalance.balance += uint184(amount);
        toPackedBalance.lastBlock = uint64(block.number);
        toPackedBalance.balanceIncreased = true;

        emit Transfer(address(0), to, amount);
    }

    function _burn(address from, uint256 amount) internal virtual {
        PackedBalance storage fromPackedBalance = _balances[from];
        fromPackedBalance.balance -= uint184(amount);
        fromPackedBalance.lastBlock = uint64(block.number);
        fromPackedBalance.balanceIncreased = false;
        
        // Cannot underflow because a user's balance
        // will never be larger than the total supply.
        unchecked {
            totalSupply -= amount;
        }

        emit Transfer(from, address(0), amount);
    }
}