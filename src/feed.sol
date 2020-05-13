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

import "ds-note/note.sol";
import "tinlake-auth/auth.sol";
import "tinlake-math/Interest.sol";
import "ds-test/test.sol";
import "./nftfeed.sol";

contract Feed is BaseNFTFeed, Interest, DSTest {

    // gas-optimized implementation instead of a struct each
    // variable has its own mapping

    // linked list of future value buckets
    // normalized timestamp -> value denominated in WAD
    mapping (uint => uint) public dateBucket;
    // normalized timestamp -> normalized timestamp
    mapping (uint => uint) public nextBucket;
    uint firstBucket;

    // nftID => maturityDate
    mapping (bytes32 => uint) public maturityDate;


    uint public discountRate;
    uint public maxDays;

    uint constant EmptyBucket = 1;

    constructor (uint discountRate_, uint maxDays_) public {
        discountRate = discountRate_;
        maxDays = maxDays_;
    }

    function uniqueDayTimestamp(uint timestamp) public pure returns (uint) {
        return (1 days) * (timestamp/(1 days));
    }

    /// maturityDate is a unix timestamp
    function file(bytes32 what, bytes32 nftID_, uint maturityDate_) public {
        if (what == "maturityDate") {
            maturityDate[nftID_] = uniqueDayTimestamp(maturityDate_);
        } else { revert("unknown config parameter");}
    }

    /// Ceiling Implementation
    function borrow(uint loan, uint amount) external auth {
        uint normalizedDay = uniqueDayTimestamp(now);

        // ceiling check uses existing loan debt
        require(ceiling(loan) >= safeAdd(pile.debt(loan), amount), "borrow-amount-too-high");

        bytes32 nftID_ = nftID(loan);
        // calculate future cash flow
        uint maturityDate_ = maturityDate[nftID_];
        dateBucket[maturityDate_] = rmul(rpow(pile.loanRates(loan),  safeSub(maturityDate_, normalizedDay), ONE), amount);

        if (dateBucket[maturityDate_] == 0) {

        }
    }

    function addToLinkedList(uint maturityDate_) internal {
        if (firstBucket == 0) {
            firstBucket = maturityDate_;
            nextBucket[maturityDate_] = EmptyBucket;
            return;
        }

        // find previous bucket
        uint prev = maturityDate_;
        while(nextBucket[prev] != 0) {prev = prev - 1 days;}

        // maturityDate is the new last bucket
        if(nextBucket[prev] == EmptyBucket) {
            nextBucket[prev] = maturityDate_;
            nextBucket[maturityDate_] = EmptyBucket;
            return;

        }

        nextBucket[maturityDate_] = nextBucket[prev];
        nextBucket[prev] = maturityDate_;
    }

    function repay(uint loan, uint amount) external auth {
        // remove from FV
        // remove from linked list

    }

    /// returns the NAV (net asset value) of the pool
    function nav() public view returns(uint) {
        uint normalizedDay = uniqueDayTimestamp(now);
        uint sum = 0;

        // current implementation ignores overdue nfts
        for (uint i = 0;i <= maxDays; i=i + 1 days) {
            sum += rdiv(dateBucket[normalizedDay + i], rpow(discountRate,  i, ONE));
        }
        return sum;
    }
}
