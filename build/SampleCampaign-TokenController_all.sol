
//File: contracts/Controlled.sol
pragma solidity ^0.4.18;

contract Controlled {
    /// @notice The address of the controller is the only address that can call
    ///  a function with this modifier
    modifier onlyController { require(msg.sender == controller); _; }

    address public controller;

    function IControlled() public { controller = msg.sender;}

    /// @notice Changes the controller of the contract
    /// @param _newController The new controller of the contract
    function changeController(address _newController) public onlyController {
        controller = _newController;
    }
}

//File: contracts/EnsPseudoIntrospectionSupport.sol
pragma solidity ^0.4.18;

interface IENS {
    function owner(bytes32 _node) public constant returns(address);
    function resolver(bytes32 _node) public constant returns(address);
    function ttl(bytes32 _node) public constant returns(uint64);
    function setOwner(bytes32 _node, address _owner) public;
    function setSubnodeOwner(bytes32 _node, bytes32 _label, address _owner) public;
    function setResolver(bytes32 _node, address _resolver) public;
    function setTTL(bytes32 _node, uint64 _ttl) public;
}

interface IReverseRegistrar {
    function claimWithResolver(address _owner, address _resolver) public returns (bytes32 node);
}

interface IPublicResolver {
    function addr(bytes32 _node) public constant returns (address ret);
    function setAddr(bytes32 _node, address _addr) public;
}

// [functionSig or interfaceId].[address].addr.reverse

// Base contract for any contract that uses EnsPseudoIntrospection
contract EnsPseudoIntrospectionSupport {
    address constant ENS_MAIN = 0x314159265dD8dbb310642f98f50C066173C1259b;
    address constant ENS_ROPSTEM = 0x112234455C3a32FD11230C42E7Bccd4A84e02010;
    address constant ENS_RINKEBY = 0xe7410170f87102DF0055eB195163A03B7F2Bff4A;
    bytes32 constant public REVERSE_ROOT_NODE = keccak256(keccak256(bytes32(0), keccak256('reverse')), keccak256('addr'));
    bytes32 constant public PUBLICRESOLVE_ROOT_NODE = keccak256(keccak256(bytes32(0), keccak256('eth')), keccak256('resolve'));
    IENS public ens;
    IReverseRegistrar public reverseRegistrar;
    IPublicResolver public publicResolver;

    function BaseContract() public {
      if (isContract(ENS_MAIN)) {
        ens = IENS(ENS_MAIN);
      } else if (isContract(ENS_ROPSTEM)) {
        ens = IENS(ENS_ROPSTEM);
      } else if (isContract(ENS_RINKEBY)) {
        ens = IENS(ENS_RINKEBY);
      } else {
        assert(false);
      }

      IPublicResolver resolver;
      resolver = IPublicResolver(ens.resolver(REVERSE_ROOT_NODE));
      reverseRegistrar = IReverseRegistrar(resolver.addr(REVERSE_ROOT_NODE));

      resolver = IPublicResolver(ens.resolver(PUBLICRESOLVE_ROOT_NODE));
      publicResolver = IPublicResolver(resolver.addr(PUBLICRESOLVE_ROOT_NODE));

      reverseRegistrar.claimWithResolver(
        address(this),
        address(publicResolver));
    }

    function setInterfaceImplementation(string ifaceLabel, address impl) internal {

        bytes32 node = rootNodeForAddress(address(this));
        bytes32 ifaceLabelHash = keccak256(ifaceLabel);
        bytes32 ifaceNode = keccak256(node, ifaceLabelHash);

        ens.setSubnodeOwner(node, ifaceLabelHash, address(this));
        ens.setResolver(ifaceNode, publicResolver);
        publicResolver.setAddr(ifaceNode, impl);
    }

    function interfaceAddr(address addr, string ifaceLabel) internal constant returns(address) {
        bytes32 node = rootNodeForAddress(address(addr));
        bytes32 ifaceNode = keccak256(node, keccak256(ifaceLabel));
        IPublicResolver resolver = IPublicResolver(ens.resolver(ifaceNode));
        return resolver.addr(ifaceNode);
    }

    function rootNodeForAddress(address addr) internal constant returns (bytes32) {
        return keccak256(REVERSE_ROOT_NODE, keccak256HexAddress(addr));
    }

    function keccak256HexAddress(address addr) private constant returns (bytes32 ret) {
        addr; ret; // Stop warning us about unused variables
        assembly {
            let lookup := 0x3031323334353637383961626364656600000000000000000000000000000000
            let i := 40
        loop:
            i := sub(i, 1)
            mstore8(i, byte(and(addr, 0xf), lookup))
            addr := div(addr, 0x10)
            i := sub(i, 1)
            mstore8(i, byte(and(addr, 0xf), lookup))
            addr := div(addr, 0x10)
            jumpi(loop, i)
            ret := keccak256(0, 40)
        }
    }

    /// @dev Internal function to determine if an address is a contract
    /// @param _addr The address being queried
    /// @return True if `_addr` is a contract
    function isContract(address _addr) constant internal returns(bool) {
        uint size;
        if (_addr == 0) return false;
        assembly {
            size := extcodesize(_addr)
        }
        return size>0;
    }
}

//File: contracts/IERC223bTokenFallback.sol
pragma solidity ^0.4.18;

interface IERC223bTokenFallback {
    function tokenFallback(address _from, address _to, uint _value, bytes _data) public;
}

//File: contracts/IERC223bMiniMeTokenController.sol
pragma solidity ^0.4.18;

/// @dev The token controller contract must implement these functions
interface IERC223bMiniMeTokenController {
    /// @notice Called when `_owner` sends ether to the MiniMe Token contract
    /// @param _owner The address that sent the ether to create tokens
    /// @return True if the ether is accepted, false if it throws
    function proxyPayment(address _owner) public payable returns(bool);

    /// @notice Notifies the controller about a token transfer allowing the
    ///  controller to react if desired
    /// @param _from The origin of the transfer
    /// @param _to The destination of the transfer
    /// @param _amount The amount of the transfer
    /// @return False if the controller does not authorize the transfer
    function onTransfer(address _from, address _to, uint _amount, bytes data) public returns(bool);
}

//File: contracts/ERC223bMiniMeToken.sol
pragma solidity ^0.4.18;

/*
    Copyright 2016, Jordi Baylina

    This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

/// @title MiniMeToken Contract
/// @author Jordi Baylina
/// @dev This token contract's goal is to make it easy for anyone to clone this
///  token using the token distribution at a given block, this will allow DAO's
///  and DApps to upgrade their features in a decentralized manner without
///  affecting the original token
/// @dev It is ERC20 compliant, but still needs to under go further testing.






contract ApproveAndCallFallBack {
    function receiveApproval(address from, uint256 _amount, address _token, bytes _data) public;
}

/// @dev The actual token contract, the default controller is the msg.sender
///  that deploys the contract, so usually this token will be deployed by a
///  token controller contract, which Giveth will call a "Campaign"
contract ERC223bMiniMeToken is Controlled, EnsPseudoIntrospectionSupport {

    string public name;                //The Token's name: e.g. DigixDAO Tokens
    uint8 public decimals;             //Number of decimals of the smallest unit
    string public symbol;              //An identifier: e.g. REP
    string public version = 'ERC223bMiniMeToken_1.0'; //An arbitrary versioning scheme


    /// @dev `Checkpoint` is the structure that attaches a block number to a
    ///  given value, the block number attached is the one that last changed the
    ///  value
    struct  Checkpoint {

        // `fromBlock` is the block number that the value was generated from
        uint128 fromBlock;

        // `value` is the amount of tokens at a specific block number
        uint128 value;
    }

    // `parentToken` is the Token address that was cloned to produce this token;
    //  it will be 0x0 for a token that was not cloned
    ERC223bMiniMeToken public parentToken;

    // `parentSnapShotBlock` is the block number from the Parent Token that was
    //  used to determine the initial distribution of the Clone Token
    uint public parentSnapShotBlock;

    // `creationBlock` is the block number that the Clone Token was created
    uint public creationBlock;

    // `balances` is the map that tracks the balance of each address, in this
    //  contract when the balance changes the block number that the change
    //  occurred is also included in the map
    mapping (address => Checkpoint[]) balances;

    // Tracks the history of the `totalSupply` of the token
    Checkpoint[] totalSupplyHistory;

    // Flag that determines if the token is transferable or not.
    bool public transfersEnabled;

    // The factory used to create new clone tokens
    MiniMeTokenFactory public tokenFactory;

////////////////
// Constructor
////////////////

    /// @notice Constructor to create a MiniMeToken
    /// @param _tokenFactory The address of the MiniMeTokenFactory contract that
    ///  will create the Clone token contracts, the token factory needs to be
    ///  deployed first
    /// @param _parentToken Address of the parent token, set to 0x0 if it is a
    ///  new token
    /// @param _parentSnapShotBlock Block of the parent token that will
    ///  determine the initial distribution of the clone token, set to 0 if it
    ///  is a new token
    /// @param _tokenName Name of the new token
    /// @param _decimalUnits Number of decimals of the new token
    /// @param _tokenSymbol Token Symbol for the new token
    /// @param _transfersEnabled If true, tokens will be able to be transferred
    function ERC223bMiniMeToken(
        address _tokenFactory,
        address _parentToken,
        uint _parentSnapShotBlock,
        string _tokenName,
        uint8 _decimalUnits,
        string _tokenSymbol,
        bool _transfersEnabled
    ) public {
        tokenFactory = MiniMeTokenFactory(_tokenFactory);
        name = _tokenName;                                 // Set the name
        decimals = _decimalUnits;                          // Set the decimals
        symbol = _tokenSymbol;                             // Set the symbol
        parentToken = ERC223bMiniMeToken(_parentToken);
        parentSnapShotBlock = _parentSnapShotBlock;
        transfersEnabled = _transfersEnabled;
        creationBlock = block.number;
        setInterfaceImplementation("IERC223b", address(this));
    }


///////////////////
// ERC20 Methods
///////////////////

    /// @notice Send `_amount` tokens to `_to` from `msg.sender`
    /// @param _to The address of the recipient
    /// @param _amount The amount of tokens to be transferred
    /// @return Whether the transfer was successful or not
    function transfer(address _to, uint256 _amount) public returns (bool success) {
        if (!transfersEnabled) return false;
        return doTransfer(msg.sender, _to, _amount, "");
    }

    /// @notice Send `_amount` tokens to `_to` from `msg.sender`
    /// @param _to The address of the recipient
    /// @param _amount The amount of tokens to be transferred
    /// @param _data Date to be transfered to the receipt interface
    /// @return Whether the transfer was successful or not
    function transfer(address _to, uint256 _amount, bytes _data) public returns (bool success) {
        if (!transfersEnabled) return false;
        return doTransfer(msg.sender, _to, _amount, _data);
    }

    /// @dev This is the actual transfer function in the token contract, it can
    ///  only be called by other functions in this contract.
    /// @param _from The address holding the tokens being transferred
    /// @param _to The address of the recipient
    /// @param _amount The amount of tokens to be transferred
    /// @return True if the transfer was successful
    function doTransfer(address _from, address _to, uint _amount, bytes _data
    ) internal returns(bool) {

            if (_amount == 0) {
               return true;
            }

            require(parentSnapShotBlock < block.number);

            // Do not allow transfer to 0x0 or the token contract itself
            require((_to != 0) && (_to != address(this)));

            // If the amount being transfered is more than the balance of the
            //  account the transfer returns false
            var previousBalanceFrom = balanceOfAt(_from, block.number);
            if (previousBalanceFrom < _amount) {
               return false;
            }

            address controllerImpl = interfaceAddr(controller, "IERC223bMiniMeTokenController");
            if (controllerImpl != 0) {
                if (!IERC223bMiniMeTokenController(controllerImpl).onTransfer(_from, _to, _amount, _data)) return false;
            }

            address fallbackImpl = interfaceAddr(_to, "IERC223bTokenFallback");

            // If IERC223bTokenFallback is not implemented for _to only allow
            // transfers to normal address and not to contracts.
            if (fallbackImpl == 0 && isContract(_to)) return false;

            // First update the balance array with the new value for the address
            //  sending the tokens
            updateValueAtNow(balances[_from], previousBalanceFrom - _amount);

            // Then update the balance array with the new value for the address
            //  receiving the tokens
            var previousBalanceTo = balanceOfAt(_to, block.number);
            require(previousBalanceTo + _amount >= previousBalanceTo); // Check for overflow
            updateValueAtNow(balances[_to], previousBalanceTo + _amount);

            // An event to make the transfer easy to find on the blockchain
            Transfer(_from, _to, _amount, _data);

            if (fallbackImpl != 0) {
                IERC223bTokenFallback(fallbackImpl).tokenFallback(_from, _to, _amount, _data);
            }

            return true;
    }

    /// @param _owner The address that's balance is being requested
    /// @return The balance of `_owner` at the current block
    function balanceOf(address _owner) public constant returns (uint256 balance) {
        return balanceOfAt(_owner, block.number);
    }

    /// @dev This function makes it easy to get the total number of tokens
    /// @return The total number of tokens
    function totalSupply() public constant returns (uint) {
        return totalSupplyAt(block.number);
    }


////////////////
// Query balance and totalSupply in History
////////////////

    /// @dev Queries the balance of `_owner` at a specific `_blockNumber`
    /// @param _owner The address from which the balance will be retrieved
    /// @param _blockNumber The block number when the balance is queried
    /// @return The balance at `_blockNumber`
    function balanceOfAt(address _owner, uint _blockNumber) public constant
        returns (uint) {

        // These next few lines are used when the balance of the token is
        //  requested before a check point was ever created for this token, it
        //  requires that the `parentToken.balanceOfAt` be queried at the
        //  genesis block for that token as this contains initial balance of
        //  this token
        if ((balances[_owner].length == 0)
            || (balances[_owner][0].fromBlock > _blockNumber)) {
            if (address(parentToken) != 0) {
                return parentToken.balanceOfAt(_owner, min(_blockNumber, parentSnapShotBlock));
            } else {
                // Has no parent
                return 0;
            }

        // This will return the expected balance during normal situations
        } else {
            return getValueAt(balances[_owner], _blockNumber);
        }
    }

    /// @notice Total amount of tokens at a specific `_blockNumber`.
    /// @param _blockNumber The block number when the totalSupply is queried
    /// @return The total amount of tokens at `_blockNumber`
    function totalSupplyAt(uint _blockNumber) public constant returns(uint) {

        // These next few lines are used when the totalSupply of the token is
        //  requested before a check point was ever created for this token, it
        //  requires that the `parentToken.totalSupplyAt` be queried at the
        //  genesis block for this token as that contains totalSupply of this
        //  token at this block number.
        if ((totalSupplyHistory.length == 0)
            || (totalSupplyHistory[0].fromBlock > _blockNumber)) {
            if (address(parentToken) != 0) {
                return parentToken.totalSupplyAt(min(_blockNumber, parentSnapShotBlock));
            } else {
                return 0;
            }

        // This will return the expected totalSupply during normal situations
        } else {
            return getValueAt(totalSupplyHistory, _blockNumber);
        }
    }

////////////////
// Clone Token Method
////////////////

    /// @notice Creates a new clone token with the initial distribution being
    ///  this token at `_snapshotBlock`
    /// @param _cloneTokenName Name of the clone token
    /// @param _cloneDecimalUnits Number of decimals of the smallest unit
    /// @param _cloneTokenSymbol Symbol of the clone token
    /// @param _snapshotBlock Block when the distribution of the parent token is
    ///  copied to set the initial distribution of the new clone token;
    ///  if the block is zero than the actual block, the current block is used
    /// @param _transfersEnabled True if transfers are allowed in the clone
    /// @return The address of the new MiniMeToken Contract
    function createCloneToken(
        string _cloneTokenName,
        uint8 _cloneDecimalUnits,
        string _cloneTokenSymbol,
        uint _snapshotBlock,
        bool _transfersEnabled
        ) public returns(address) {
        if (_snapshotBlock == 0) _snapshotBlock = block.number;
        ERC223bMiniMeToken cloneToken = tokenFactory.createCloneToken(
            this,
            _snapshotBlock,
            _cloneTokenName,
            _cloneDecimalUnits,
            _cloneTokenSymbol,
            _transfersEnabled
            );

        cloneToken.changeController(msg.sender);

        // An event to make the token easy to find on the blockchain
        NewCloneToken(address(cloneToken), _snapshotBlock);
        return address(cloneToken);
    }

////////////////
// Generate and destroy tokens
////////////////

    /// @notice Generates `_amount` tokens that are assigned to `_owner`
    /// @param _owner The address that will be assigned the new tokens
    /// @param _amount The quantity of tokens generated
    /// @return True if the tokens are generated correctly
    function generateTokens(address _owner, uint _amount, bytes _data
    ) public onlyController returns (bool) {

        address fallbackImpl = interfaceAddr(_owner, "IERC223bTokenFallback");

        // If IERC223bTokenFallback is not implemented for _to only allow
        // transfers to normal address and not to contracts.
        if (fallbackImpl == 0 && isContract(_owner)) return false;

        uint curTotalSupply = totalSupply();
        require(curTotalSupply + _amount >= curTotalSupply); // Check for overflow
        uint previousBalanceTo = balanceOf(_owner);
        require(previousBalanceTo + _amount >= previousBalanceTo); // Check for overflow
        updateValueAtNow(totalSupplyHistory, curTotalSupply + _amount);
        updateValueAtNow(balances[_owner], previousBalanceTo + _amount);
        Transfer(0, _owner, _amount, _data);

        if (fallbackImpl != 0) {
            IERC223bTokenFallback(fallbackImpl).tokenFallback(0, _owner, _amount, _data);
        }

        return true;
    }


    /// @notice Burns `_amount` tokens from `_owner`
    /// @param _owner The address that will lose the tokens
    /// @param _amount The quantity of tokens to burn
    /// @return True if the tokens are burned correctly
    function destroyTokens(address _owner, uint _amount
    ) onlyController public returns (bool) {
        uint curTotalSupply = totalSupply();
        require(curTotalSupply >= _amount);
        uint previousBalanceFrom = balanceOf(_owner);
        require(previousBalanceFrom >= _amount);
        updateValueAtNow(totalSupplyHistory, curTotalSupply - _amount);
        updateValueAtNow(balances[_owner], previousBalanceFrom - _amount);
        Transfer(_owner, 0, _amount, "");
        return true;
    }

////////////////
// Enable tokens transfers
////////////////


    /// @notice Enables token holders to transfer their tokens freely if true
    /// @param _transfersEnabled True if transfers are allowed in the clone
    function enableTransfers(bool _transfersEnabled) public onlyController {
        transfersEnabled = _transfersEnabled;
    }

////////////////
// Internal helper functions to query and set a value in a snapshot array
////////////////

    /// @dev `getValueAt` retrieves the number of tokens at a given block number
    /// @param checkpoints The history of values being queried
    /// @param _block The block number to retrieve the value at
    /// @return The number of tokens being queried
    function getValueAt(Checkpoint[] storage checkpoints, uint _block
    ) constant internal returns (uint) {
        if (checkpoints.length == 0) return 0;

        // Shortcut for the actual value
        if (_block >= checkpoints[checkpoints.length-1].fromBlock)
            return checkpoints[checkpoints.length-1].value;
        if (_block < checkpoints[0].fromBlock) return 0;

        // Binary search of the value in the array
        uint min = 0;
        uint max = checkpoints.length-1;
        while (max > min) {
            uint mid = (max + min + 1)/ 2;
            if (checkpoints[mid].fromBlock<=_block) {
                min = mid;
            } else {
                max = mid-1;
            }
        }
        return checkpoints[min].value;
    }

    /// @dev `updateValueAtNow` used to update the `balances` map and the
    ///  `totalSupplyHistory`
    /// @param checkpoints The history of data being updated
    /// @param _value The new number of tokens
    function updateValueAtNow(Checkpoint[] storage checkpoints, uint _value
    ) internal  {
        if ((checkpoints.length == 0)
        || (checkpoints[checkpoints.length -1].fromBlock < block.number)) {
               Checkpoint storage newCheckPoint = checkpoints[ checkpoints.length++ ];
               newCheckPoint.fromBlock =  uint128(block.number);
               newCheckPoint.value = uint128(_value);
           } else {
               Checkpoint storage oldCheckPoint = checkpoints[checkpoints.length-1];
               oldCheckPoint.value = uint128(_value);
           }
    }

    /// @dev Helper function to return a min betwen the two uints
    function min(uint a, uint b) pure internal returns (uint) {
        return a < b ? a : b;
    }

    /// @notice The fallback function: If the contract's controller has not been
    ///  set to 0, then the `proxyPayment` method is called which relays the
    ///  ether and creates tokens as described in the token controller contract
    function () public payable {
        address controllerImpl = interfaceAddr(controller, "IERC223bMiniMeTokenController");
        require(controllerImpl != 0);
        require(IERC223bMiniMeTokenController(controllerImpl).proxyPayment.value(msg.value)(msg.sender));
    }

//////////
// Safety Methods
//////////

    /// @notice This method can be used by the controller to extract mistakenly
    ///  sent tokens to this contract.
    /// @param _token The address of the token contract that you want to recover
    ///  set to 0 in case you want to extract ether.
    function claimTokens(address _token) public onlyController {
        if (_token == 0x0) {
            controller.transfer(this.balance);
            return;
        }

        ERC223bMiniMeToken token = ERC223bMiniMeToken(_token);
        uint balance = token.balanceOf(this);
        token.transfer(controller, balance);
        ClaimedTokens(_token, controller, balance);
    }

////////////////
// Events
////////////////
    event ClaimedTokens(address indexed token, address indexed controller, uint amount);
    event Transfer(address indexed from, address indexed to, uint256 amount, bytes data);
    event NewCloneToken(address indexed cloneToken, uint snapshotBlock);

}


////////////////
// MiniMeTokenFactory
////////////////

/// @dev This contract is used to generate clone contracts from a contract.
///  In solidity this is the way to create a contract from a contract of the
///  same class
contract MiniMeTokenFactory {

    /// @notice Update the DApp by creating a new token with new functionalities
    ///  the msg.sender becomes the controller of this clone token
    /// @param _parentToken Address of the token being cloned
    /// @param _snapshotBlock Block of the parent token that will
    ///  determine the initial distribution of the clone token
    /// @param _tokenName Name of the new token
    /// @param _decimalUnits Number of decimals of the new token
    /// @param _tokenSymbol Token Symbol for the new token
    /// @param _transfersEnabled If true, tokens will be able to be transferred
    /// @return The address of the new token contract
    function createCloneToken(
        address _parentToken,
        uint _snapshotBlock,
        string _tokenName,
        uint8 _decimalUnits,
        string _tokenSymbol,
        bool _transfersEnabled
    ) public returns (ERC223bMiniMeToken) {
        ERC223bMiniMeToken newToken = new ERC223bMiniMeToken(
            this,
            _parentToken,
            _snapshotBlock,
            _tokenName,
            _decimalUnits,
            _tokenSymbol,
            _transfersEnabled
            );

        newToken.changeController(msg.sender);
        return newToken;
    }
}

//File: ./contracts/SampleCampaign-TokenController.sol
pragma solidity ^0.4.18;

/*
    Copyright 2017, Jordi Baylina

    This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

/// @title MilestoneTracker Contract
/// @author Jordi Baylina
/// @dev This contract controls the issuance of tokens for the MiniMe Token
///  Contract. This version specifically acts as a Campaign manager for raising
///  funds for non-profit causes, but it can be customized for any variety of
///  purposes.




/// @dev `Owned` is a base level contract that assigns an `owner` that can be
///  later changed
contract Owned {
    /// @dev `owner` is the only address that can call a function with this
    /// modifier
    modifier onlyOwner { require (msg.sender == owner); _; }

    address public owner;

    /// @notice The Constructor assigns the message sender to be `owner`
    function Owned() public { owner = msg.sender;}

    /// @notice `owner` can step down and assign some other address to this role
    /// @param _newOwner The address of the new owner. 0x0 can be used to create
    ///  an unowned neutral vault, however that cannot be undone
    function changeOwner(address _newOwner) public onlyOwner {
        owner = _newOwner;
    }
}


/// @dev This is designed to control the issuance of a MiniMe Token for a
///  non-profit Campaign. This contract effectively dictates the terms of the
///  funding round.

contract Campaign is IERC223bMiniMeTokenController, Owned, EnsPseudoIntrospectionSupport {

    uint public startFundingTime;       // In UNIX Time Format
    uint public endFundingTime;         // In UNIX Time Format
    uint public maximumFunding;         // In wei
    uint public totalCollected;         // In wei
    ERC223bMiniMeToken public tokenContract;   // The new token for this Campaign
    address public vaultAddress;        // The address to hold the funds donated

/// @notice 'Campaign()' initiates the Campaign by setting its funding
/// parameters
/// @dev There are several checks to make sure the parameters are acceptable
/// @param _startFundingTime The UNIX time that the Campaign will be able to
/// start receiving funds
/// @param _endFundingTime The UNIX time that the Campaign will stop being able
/// to receive funds
/// @param _maximumFunding In wei, the Maximum amount that the Campaign can
/// receive (currently the max is set at 10,000 ETH for the beta)
/// @param _vaultAddress The address that will store the donated funds
/// @param _tokenAddress Address of the token contract this contract controls

    function Campaign(
        uint _startFundingTime,
        uint _endFundingTime,
        uint _maximumFunding,
        address _vaultAddress,
        address _tokenAddress

    ) public {
        require ((_endFundingTime >= now) &&           // Cannot end in the past
            (_endFundingTime > _startFundingTime) &&
            (_maximumFunding <= 10000 ether) &&        // The Beta is limited
            (_vaultAddress != 0));                    // To prevent burning ETH
        startFundingTime = _startFundingTime;
        endFundingTime = _endFundingTime;
        maximumFunding = _maximumFunding;
        tokenContract = ERC223bMiniMeToken(_tokenAddress);// The Deployed Token Contract
        vaultAddress = _vaultAddress;
        setInterfaceImplementation("IERC223bMiniMeTokenController", address(this));

    }

/// @dev The fallback function is called when ether is sent to the contract, it
/// simply calls `doPayment()` with the address that sent the ether as the
/// `_owner`. Payable is a required solidity modifier for functions to receive
/// ether, without this modifier functions will throw if ether is sent to them

    function ()  public payable {
        doPayment(msg.sender);
    }

/////////////////
// TokenController interface
/////////////////

/// @notice `proxyPayment()` allows the caller to send ether to the Campaign and
/// have the tokens created in an address of their choosing
/// @param _owner The address that will hold the newly created tokens

    function proxyPayment(address _owner) public payable returns(bool) {
        doPayment(_owner);
        return true;
    }

/// @notice Notifies the controller about a transfer, for this Campaign all
///  transfers are allowed by default and no extra notifications are needed
/// @param _from The origin of the transfer
/// @param _to The destination of the transfer
/// @param _amount The amount of the transfer
/// @return False if the controller does not authorize the transfer
    function onTransfer(address _from, address _to, uint _amount, bytes _data) public returns(bool) {
        return true;
    }



/// @dev `doPayment()` is an internal function that sends the ether that this
///  contract receives to the `vault` and creates tokens in the address of the
///  `_owner` assuming the Campaign is still accepting funds
/// @param _owner The address that will hold the newly created tokens

    function doPayment(address _owner) internal {

// First check that the Campaign is allowed to receive this donation
        require ((now >= startFundingTime) &&
            (now <= endFundingTime) &&
            (tokenContract.controller() != 0) &&           // Extra check
            (msg.value != 0) &&
            (totalCollected + msg.value <= maximumFunding));

//Track how much the Campaign has collected
        totalCollected += msg.value;

//Send the ether to the vault
        vaultAddress.transfer(msg.value);

// Creates an equal amount of tokens as ether sent. The new tokens are created
//  in the `_owner` address
        require (tokenContract.generateTokens(_owner, msg.value, ""));

        return;
    }

/// @notice `finalizeFunding()` ends the Campaign by calling setting the
///  controller to 0, thereby ending the issuance of new tokens and stopping the
///  Campaign from receiving more ether
/// @dev `finalizeFunding()` can only be called after the end of the funding period.

    function finalizeFunding() public {
        require(now >= endFundingTime);
        tokenContract.changeController(0);
    }


/// @notice `onlyOwner` changes the location that ether is sent
/// @param _newVaultAddress The address that will receive the ether sent to this
///  Campaign
    function setVault(address _newVaultAddress) public onlyOwner {
        vaultAddress = _newVaultAddress;
    }

}