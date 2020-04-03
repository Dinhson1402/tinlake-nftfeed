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
import "./mock/shelf.sol";
import "./mock/pile.sol";



contract NFTFeedTest is DSTest {

    NFTFeed public nftFeed;
    ShelfMock shelf;
    PileMock pile;

    uint defaultRate;
    uint defaultThresholdRatio;
    uint defaultCeilingRatio;


    function setUp() public {
        // default values
        defaultThresholdRatio = 8*10**26;                     // 80% threshold
        defaultCeilingRatio = 6*10**26;                       // 60% ceiling
        defaultRate = uint(1000000564701133626865910626);     // 5 % day

        nftFeed = new NFTFeed(defaultThresholdRatio, defaultCeilingRatio, defaultRate);
        pile = new PileMock();
        shelf = new ShelfMock();

        nftFeed.depend("shelf", address(shelf));
        nftFeed.depend("pile", address(pile));

    }

    function testBasisNFT() public {
        bytes32 nftID = nftFeed.nftID(address(1), 1);
        uint value = 100 ether;
        nftFeed.update(nftID, value);

        uint loan = 1;
        shelf.setReturn("shelf",address(1), 1);

        assertEq(nftFeed.nftValues(nftID), 100 ether);
        assertEq(nftFeed.threshold(loan), 80 ether);
        assertEq(nftFeed.ceiling(loan), 60 ether);
        assertEq(nftFeed.loanRate(loan), defaultRate);
    }

    function testRiskGroup() public {
        // risk group
        uint risk = 1;
        uint thresholdRatio = 7*10**26;                     // 70% threshold
        uint ceilingRatio = 5*10**26;                       // 50% ceiling
        uint rate = uint(1000001311675458706187136988);     // 12 % day

        nftFeed.setRiskGroup(1, thresholdRatio, ceilingRatio, rate);

        // nft
        bytes32 nftID = nftFeed.nftID(address(1), 1);
        uint loan = 1;
        uint value = 100 ether;
        shelf.setReturn("shelf",address(1), 1);

        nftFeed.update(nftID, value, risk);

        assertEq(nftFeed.nftValues(nftID), 100 ether);
        assertEq(nftFeed.threshold(loan), 70 ether);
        assertEq(nftFeed.ceiling(loan), 50 ether);
        assertEq(nftFeed.loanRate(loan), rate);
    }


}
