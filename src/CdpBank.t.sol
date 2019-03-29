pragma solidity ^0.4.24;

import "ds-test/test.sol";
import "ds-token/token.sol";
import "ds-math/math.sol";
import "ds-value/value.sol";


contract CdpBankTest is DSTest, DSMath {
    function setUp() public {

    }

    function test() public{
        uint p = 123180000000000000000;
        uint a = 1;
        uint v = wmul(a, p);
        emit log_named_uint("#test", v);
        assertTrue(false);
    }
}