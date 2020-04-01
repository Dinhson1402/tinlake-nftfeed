pragma solidity ^0.5.17;

import "ds-test/test.sol";

import "./TinlakeNftfeed.sol";

contract TinlakeNftfeedTest is DSTest {
    TinlakeNftfeed nftfeed;

    function setUp() public {
        nftfeed = new TinlakeNftfeed();
    }

    function testFail_basic_sanity() public {
        assertTrue(false);
    }

    function test_basic_sanity() public {
        assertTrue(true);
    }
}
