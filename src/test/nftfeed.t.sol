// Copyright (C) 2020 Centrifuge

// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

pragma solidity >=0.5.15;

import "ds-test/test.sol";

import "./../nftfeed.sol";


contract NFTFeedTest is DSTest {

    NFTFeed public nftFeed;

    function setUp() public {
        // default values
        uint thresholdRatio = 8*10**26;                     // 80% threshold
        uint ceilingRatio = 6*10**26;                       // 60% ceiling
        uint rate = uint(1000000564701133626865910626);     // 5 % day

        nftFeed = new NFTFeed(thresholdRatio, ceilingRatio, rate);


    }


    function testNFTFeed() public {
        // todo
    }

}
