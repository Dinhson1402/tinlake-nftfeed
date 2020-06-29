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
    address mockNFTRegistry;
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

        mockNFTRegistry = address(42);

        feed.init();
    }

    function prepareDefaultNFT(uint tokenId, uint nftValue) public returns(bytes32, uint) {
        uint loan = 1;
        bytes32 nftID = feed.nftID(mockNFTRegistry, tokenId);
        feed.update(nftID, nftValue);
        shelf.setReturn("shelf",mockNFTRegistry, tokenId);
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


    /// setups the following linked list
    /// list : [1 days] -> [2 days] -> [4 days] -> [5 days]
    //         [50 DAI] -> [50 DAI] -> [100 DAI] -> [50 DAI]
    function setupLinkedListBuckets() public {
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
        // list: [2 days]
        assertEq(feed.nav(), 51.960741582371777180 ether);

        // insert next bucket after last bucket
        dueDate = now + 5 days;
        tokenId = 2;
        (nft_, ) = borrow(tokenId, nftValue, amount, dueDate);

        // list : [2 days] -> [5 days]
        //50*1.05^2/(1.03^2) + 50*1.05^5/(1.03^5) ~= 107.00
        assertEq(feed.nav(), 107.007702266903241118 ether);

        // insert between two buckets
        // current list: [2 days] -> [5 days]
        dueDate = now + 4 days;
        tokenId = 3;
        (nft_, ) = borrow(tokenId, nftValue, amount, dueDate);

        // list : [2 days] ->[4 days] -> [5 days]
        //50*1.05^2/(1.03^2) + 50*1.05^4/(1.03^4) + 50*1.05^5/(1.03^5)   ~= 161.00
        assertEq(feed.nav(), 161.006075582703631092 ether);

        // insert at the beginning
        // current list: bucket[now+2days]-> bucket[now+4days] -> bucket[now+5days]
        dueDate = now + 1 days;
        tokenId = 4;
        (nft_, ) = borrow(tokenId, nftValue, amount, dueDate);

        // list : [1 days] -> [2 days] -> [4 days] -> [5 days]
        // (50*1.05^1)/(1.03^1) + 50*1.05^2/(1.03^2) + 50*1.05^4/(1.03^4) + 50*1.05^5/(1.03^5) ~= 211.977
        assertEq(feed.nav(), 211.977019061499360158 ether);

        // add amount to existing bucket
        dueDate = now + 4 days;
        tokenId = 5;
        (nft_, ) = borrow(tokenId, nftValue, amount, dueDate);
        // list : [1 days] -> [2 days] -> [4 days] -> [5 days]
        //(50*1.05^1)/(1.03^1) + 50*1.05^2/(1.03^2) + 100*1.05^4/(1.03^4) + 50*1.05^5/(1.03^5)  ~= 265.97
        assertEq(feed.nav(), 265.975392377299750133 ether);

    }

    function testLinkedListBucket() public {
        setupLinkedListBuckets();

        hevm.warp(now + 1 days);

        // list : [0 days] -> [1 days] -> [3 days] -> [4 days]
        //(50*1.05^1)/(1.03^0) + 50*1.05^2/(1.03^1) + 100*1.05^4/(1.03^3) + 50*1.05^5/(1.03^4)  ~= 273.95
        assertEq(feed.nav(), 273.954279571404002939 ether);

        hevm.warp(now + 1 days);

        // list : [0 days] -> [2 days] -> [3 days]
        // 50*1.05^2/(1.03^0) + 100*1.05^4/(1.03^2) + 50*1.05^5/(1.03^3) ~= 228.09
        assertEq(feed.nav(), 228.097596081095759604 ether);
    }

    function testTimeOverBuckets() public {
        uint nftValue = 100 ether;
        uint tokenId = 1;
        uint dueDate = now + 2 days;
        uint amount = 50 ether;

        // insert first element
        (bytes32 nft_, ) = borrow(tokenId, nftValue, amount, dueDate);

        // 50 * 1.05^2/(1.03^2)
        assertEq(feed.nav(), 51.960741582371777180 ether);

        hevm.warp(now + 3 days);
        assertEq(feed.nav(), 0);
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

    function testRepay() public {
        uint normalizedDay = feed.uniqueDayTimestamp(now);
        uint amount = 50 ether;
        setupLinkedListBuckets();

        uint tokenId = 1;
        uint dueDate = now + 2 days;

        uint loan = 1;

        shelf.setReturn("shelf", mockNFTRegistry, tokenId);
        // loan id doesn't matter because shelf is mocked
        // repay not full amount
        feed.repay(loan, 30 ether);
        listLen();

        // list : [1 days] -> [2 days] -> [4 days] -> [5 days]
        //(50*1.05^1)/(1.03^1) + (50*1.05^2 - 30) /(1.03^2)  + 100*1.05^4/(1.03^4) + 50*1.05^5/(1.03^5)  ~= 237.69
        assertEq(feed.nav(), 237.697437774648442824 ether);

        uint FV = 25.125 ether;  // 50*1.05^2 - 30
        assertEq(feed.dateBucket(normalizedDay + 2 days), FV);

        feed.repay(loan, 25.125 ether);
        assertEq(feed.dateBucket(normalizedDay + 2 days), 0);

        //(50*1.05^1)/(1.03^1) + 100*1.05^4/(1.03^4) + 50*1.05^5/(1.03^5)  ~= 214.014
        assertEq(feed.nav(), 214.014650794927972953 ether);
    }

    function testRemoveBuckets() public {
        // buckets are removed by completely repaying it
        uint[4] memory buckets = [uint(52500000000000000000), uint(55125000000000000000), uint(121550625000000000000), uint(63814078125000000000)];
        uint[4] memory tokenIdForBuckets = [uint(4), uint(1), uint(3), uint(2)];
        // list : [1 days] -> [2 days] -> [4 days] -> [5 days]

        setupLinkedListBuckets();
        assertEq(listLen(), 4);

        // remove bucket in between buckets
        // remove bucket [2 days]
        uint idx = 1;
        shelf.setReturn("shelf", mockNFTRegistry, tokenIdForBuckets[idx]);

        // loan id doesn't matter because shelf is mocked
        feed.repay(1, buckets[idx]);

        assertEq(listLen(), 3);

        // remove first bucket
        // remove [1 days]
        idx = 0;
        shelf.setReturn("shelf", mockNFTRegistry, tokenIdForBuckets[idx]);
        feed.repay(1, buckets[idx]);
        assertEq(listLen(), 2);

        // remove last bucket
        // remove [5 days]
        idx = 3;
        shelf.setReturn("shelf", mockNFTRegistry, tokenIdForBuckets[idx]);
        feed.repay(1, buckets[idx]);
        assertEq(listLen(), 1);
    }

    function listLen() public returns (uint) {
        uint normalizedDay = feed.uniqueDayTimestamp(now);
        uint len = 0;

        uint currDate = normalizedDay;

        if (currDate > feed.lastBucket()) {
            return 0;
        }

        while(feed.nextBucket(currDate) == 0) { currDate = currDate + 1 days; }

        while(currDate != feed.NullDate())
        {
            emit log_named_uint("date_offset", (currDate-normalizedDay)/1 days);
            emit log_named_uint("bucket_value", feed.dateBucket(currDate));
            currDate = feed.nextBucket(currDate);
            len++;

        }
        return len;
    }
}
