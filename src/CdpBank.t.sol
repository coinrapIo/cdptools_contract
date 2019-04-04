pragma solidity ^0.4.24;

import "ds-test/test.sol";
// import "ds-token/token.sol";
import "ds-math/math.sol";
// import "ds-value/value.sol";
import "./SetLib.sol";
import "./CdpBank.sol";

contract CdpBankTest is DSTest, DSMath {
    

    function setUp() public {
    }

    function test() public{
        address guy = address(0xa71937147b55Deb8a530C7229C442Fd3F31b7db2);
        uint cdpId = 1000000;
        uint cdpIdTwo = 2000000;
        
        
        // emit log_named_uint('###1', bk.getIds(guy).length);
        // bk.open(cdpId, guy);
        // emit log_named_uint('###2', bk.getIds(guy).length);
        // bk.open(cdpIdTwo, guy);
        // emit log_named_uint('###3', bk.getIds(guy).length);
        // bk.shut(cdpIdTwo, guy);
        // emit log_named_uint('###4', bk.getIds(guy).length);
        // // emit log_named_uint('ids.length', addrs[adr].ids.length);
        // assertTrue(false);
    }
}