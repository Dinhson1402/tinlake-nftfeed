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
        uint maxDays = 120 days;

        feed = new Feed(discountRate, maxDays);
        pile = new PileMock();
        shelf = new ShelfMock();
        feed.depend("shelf", address(shelf));
        feed.depend("pile", address(pile));

        feed.init();
    }

    function prepareDefaultNFT(uint tokenId, uint nftValue) public returns(bytes32, uint) {
        bytes32 nftID = feed.nftID(address(1), tokenId);
        feed.update(nftID, nftValue);
        uint loan = 1;
        shelf.setReturn("shelf",address(1), tokenId);
        pile.setReturn("debt_loan", 0);
        pile.setReturn("rates_ratePerSecond", defaultRate);
        return (nftID, loan);
    }

    function borrow(uint tokenId, uint nftValue, uint amount, uint maturityDate) internal returns(bytes32, uint) {
        (bytes32 nftID, uint loan) = prepareDefaultNFT(tokenId, nftValue);
        feed.file("maturityDate",nftID, maturityDate);
        uint amount = 50 ether;

        pile.setReturn("loanRates", uint(1000000564701133626865910626));

        feed.borrow(loan, amount);

        return (nftID, loan);
    }

    function testSimpleBorrow() public {
        uint nftValue = 100 ether;
        uint tokenId = 1;
        uint dueDate = now + 2 days;
        uint amount = 50 ether;

        borrow(tokenId, nftValue, amount, dueDate);

        // check FV
        uint normalizedDueDate = feed.uniqueDayTimestamp(dueDate);

        uint FV = 55.125 ether; // 50 * 1.05 ^ 2 = 55.125
        assertEq(feed.dateBucket(normalizedDueDate), FV);
        // FV/(1.03^2)
        assertEq(feed.nav(), 51.960741582371777180 ether);
        hevm.warp(now + 1 days);
        // FV/(1.03^1)
        assertEq(feed.nav(), 53.519490652735515520 ether);
        hevm.warp(now + 1 days);
        // FV/(1.03^0)
        assertEq(feed.nav(), 55.125 ether);
    }

    function testLinkedListBucket() public {
        uint nftValue = 100 ether;
        uint tokenId = 1;
        uint dueDate = now + 2 days;
        uint amount = 50 ether;

        // insert first element
        (bytes32 nft_, ) = borrow(tokenId, nftValue, amount, dueDate);

        uint normalizedDueDate = feed.uniqueDayTimestamp(dueDate);

        uint FV = 55.125 ether; // 50 * 1.05 ^ 2 ~= 55.125
        assertEq(feed.dateBucket(normalizedDueDate), FV);

        // FV/(1.03^2)
        assertEq(feed.nav(), 51.960741582371777180 ether);

        // insert next bucket after last bucket
        dueDate = now + 5 days;
        tokenId = 2;
        (nft_, ) = borrow(tokenId, nftValue, amount, dueDate);

        //50*1.05^2/(1.03^2) + 50*1.05^5/(1.03^5) ~= 107.007702266903241118
        assertEq(feed.nav(), 107.007702266903241118 ether);

        // insert between two buckets
        // current list: bucket[now+3days] -> bucket[now+5days]
        dueDate = now + 4 days;
        tokenId = 3;
        (nft_, ) = borrow(tokenId, nftValue, amount, dueDate);

        //50*1.05^2/(1.03^2) + 50*1.05^5/(1.03^5) + 50*1.05^4/(1.03^4)  ~= 161.006075582703631092
        assertEq(feed.nav(), 161.006075582703631092 ether);

        // insert in the beginning
        // current list: bucket[now+3days] -> bucket[now+4days] -> bucket[now+5days]
        dueDate = now + 2 days;
        tokenId = 4;
        (nft_, ) = borrow(tokenId, nftValue, amount, dueDate);

        //50*1.05^2/(1.03^2) + 50*1.05^5/(1.03^5) + 50*1.05^4/(1.03^4) +
        //50*1.05^2/(1.03^2)  ~= 212.966817165075408273
        assertEq(feed.nav(), 212.966817165075408273 ether);

        // add amount to existing bucket
        dueDate = now + 4 days;
        tokenId = 5;
        (nft_, ) = borrow(tokenId, nftValue, amount, dueDate);
        //50*1.05^2/(1.03^2) + 50*1.05^5/(1.03^5) + 100*1.05^4/(1.03^4) +
        //50*1.05^2/(1.03^2)  ~= 266.965190480875798248
        assertEq(feed.nav(), 266.965190480875798248 ether);

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
