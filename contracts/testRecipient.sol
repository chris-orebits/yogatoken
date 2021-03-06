pragma solidity ^0.4.18;

import "../node_modules/eip672/contracts/EIP672.sol";

contract ERC20 {
    function transferFrom(address from, address to, uint amount) public returns(bool);
}

contract RecipientERC20 {

    function collect(address token, uint amount) public {
        require(ERC20(token).transferFrom(msg.sender, address(this), amount));
    }

}

contract RecipientERC223 is EIP672 {

    uint public dataLen;

    function RecipientERC223() public {
        setInterfaceImplementation("ITokenFallback", address(this));
    }

    function tokenFallback(address from, address to, uint amount, bytes data, bytes32 ref) public {
        require(data.length == 1 && data[0] == 0x01);
    }
}

contract ExternalContract {
    function ExternalContract() public {

    }
}

contract ProxyAccept {
    function tokenFallback(address from, address to, uint amount, bytes data, bytes32 ref) public {}
}

contract ProxyReject {
    function tokenFallback(address from, address to, uint amount, bytes data, bytes32 ref) public {
        require(false);
    }
}

contract Erc20Operator {
    address public owner;

    function Erc20Operator() public {
        owner = msg.sender;
    }

    function transferFrom(address token, address from, address to, uint amount) public {
        require(msg.sender == owner);
        require(ERC20(token).transferFrom(from, to, amount));
    }
}
