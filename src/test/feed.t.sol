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
import "./../feed.sol";
import "./mock/shelf.sol";
import "./mock/pile.sol";

contract Hevm {
    function warp(uint256) public;
}

contract NAVTest is DSTest {

    Feed public feed;
    ShelfMock shelf;
    PileMock pile;
    uint defaultRate;
    uint defaultThresholdRatio;
    uint defaultCeilingRatio;
    uint discountRate;
    Hevm hevm;

    function setUp() public {
        hevm = Hevm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);
        hevm.warp(1234567);
        // default values
        defaultThresholdRatio = 8*10**26;                     // 80% threshold
        defaultCeilingRatio = 6*10**26;                       // 60% ceiling
        defaultRate = uint(1000000564701133626865910626);     // 5 % day
        discountRate = uint(1000000342100000000000000000);    // 3 % day
        uint maxDays = 10 days;
        uint defaultRisk = 0;

        feed = new Feed(discountRate, maxDays);
        pile = new PileMock();
        shelf = new ShelfMock();
        feed.depend("shelf", address(shelf));
        feed.depend("pile", address(pile));
        feed.setRiskGroup(defaultRisk, defaultThresholdRatio, defaultCeilingRatio, defaultRate);
    }

    function prepareDefaultNFT(uint nftValue) public returns(bytes32, uint) {
        bytes32 nftID = feed.nftID(address(1), 1);
        feed.update(nftID, nftValue);
        uint loan = 1;
        shelf.setReturn("shelf",address(1), 1);
        pile.setReturn("debt_loan", 0);
        pile.setReturn("rates_ratePerSecond", defaultRate);
        return (nftID, loan);
    }

    function testSimpleBorrow() public {
        uint value = 100 ether;
        (bytes32 nftID, uint loan) = prepareDefaultNFT(value);
        uint dueDate = now + 2 days;
        feed.file("duedate",nftID, dueDate);
        uint amount = 50 ether;
        feed.borrow(loan, amount);

        // check FV
        uint normalizedDueDate = feed.uniqueDayTimestamp(dueDate);

        uint FV = 55.125 ether; // 50 * 1.05 ^ 2 = 55.125
        assertEq(feed.futureValueAtDate(normalizedDueDate), FV);
        // FV/(1.03^2)
        assertEq(feed.nav(), 51.960741582371777180 ether);
        hevm.warp(now + 1 days);
        // FV/(1.03^1)
        assertEq(feed.nav(), 53.519490652735515520 ether);
        hevm.warp(now + 1 days);
        // FV/(1.03^0)
        assertEq(feed.nav(), 55.125 ether);
    }

    function testNormalizeDate() public {
        uint randomUnixTimestamp = 1586977096; // 04/15/2020 @ 6:58pm (UTC)
        uint dayTimestamp = feed.uniqueDayTimestamp(randomUnixTimestamp);

        assertTrue(feed.uniqueDayTimestamp(randomUnixTimestamp) != randomUnixTimestamp);
        uint delta = randomUnixTimestamp - dayTimestamp;

        assertTrue(delta < 24*60*60);
        randomUnixTimestamp += 3 hours;
        assertTrue(feed.uniqueDayTimestamp(randomUnixTimestamp) == dayTimestamp);
    }
}
