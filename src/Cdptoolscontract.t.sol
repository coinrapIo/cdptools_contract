pragma solidity ^0.4.24;

import "ds-test/test.sol";

import "./Cdptoolscontract.sol";

contract CdptoolscontractTest is DSTest {
    Cdptoolscontract contract;

    function setUp() public {
        contract = new Cdptoolscontract();
    }

    function testFail_basic_sanity() public {
        assertTrue(false);
    }

    function test_basic_sanity() public {
        assertTrue(true);
    }
}
