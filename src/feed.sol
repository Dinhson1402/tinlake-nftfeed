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
import "tinlake-math/interest.sol";
import "./nftfeed.sol";

contract Feed is BaseNFTFeed, Interest {

    // gas-optimized implementation instead of a struct each
    // variable has its own mapping

    // linked list of future value buckets
    // normalized timestamp -> value denominated in WAD
    mapping (uint => uint) public dateBucket;
    // normalized timestamp -> normalized timestamp
    mapping (uint => uint) public nextBucket;
    uint public firstBucket;
    uint public lastBucket;

    // nftID => maturityDate
    mapping (bytes32 => uint) public maturityDate;


    uint public discountRate;
    uint public maxDays;

    uint constant public NullDate = 1;

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
        uint maturityDate_ = maturityDate[nftID_];

        if (dateBucket[maturityDate_] == 0) {
            addBucket(maturityDate_);
        }

        // calculate future value of the loan and add it to the bucket
        dateBucket[maturityDate_] = safeAdd(dateBucket[maturityDate_],
            rmul(rpow(pile.loanRates(loan),  safeSub(maturityDate_, normalizedDay), ONE), amount));

    }

    /// adds a new bucket to the linked-list
    function addBucket(uint maturityDate_) internal {
        if (firstBucket == 0) {
            firstBucket = maturityDate_;
            nextBucket[maturityDate_] = NullDate;
            lastBucket = firstBucket;
            return;
        }

        // new bucket before first one
        if (maturityDate_ < firstBucket) {
            nextBucket[maturityDate_] = firstBucket;
            firstBucket = maturityDate_;
            return;
        }

        // find predecessor bucket by going back in one day steps
        // instead of iterating the linked list from the first bucket
        uint prev = maturityDate_;
        while(nextBucket[prev] == 0) {prev = prev - 1 days;}

        if (nextBucket[prev] == NullDate) {
            lastBucket = maturityDate_;
        }
        nextBucket[maturityDate_] = nextBucket[prev];
        nextBucket[prev] = maturityDate_;
    }

    function repay(uint loan, uint amount) external auth {
        uint maturityDate_ = maturityDate[nftID(loan)];

        dateBucket[maturityDate_] = safeSub(dateBucket[maturityDate_], amount);

        if (dateBucket[maturityDate_] == 0) {
            // remove from linked list
            if (maturityDate_ != firstBucket) {
                uint prev = maturityDate_ - 1 days;
                while(nextBucket[prev] == 0) {prev = prev - 1 days;}

                nextBucket[prev] = nextBucket[maturityDate_];
                nextBucket[maturityDate_] = 0;
            }
            else {
                firstBucket = nextBucket[maturityDate_];
                nextBucket[maturityDate_] = 0;
            }
        }

    }

    /// returns the NAV (net asset value) of the pool
    function nav() public view returns(uint) {
        uint normalizedDay = uniqueDayTimestamp(now);
        uint sum = 0;

        uint currDate = normalizedDay;

        if (currDate > lastBucket) {
            return 0;
        }

        while(nextBucket[currDate] == 0) { currDate = currDate + 1 days; }

        while(currDate != NullDate)
        {
            sum = safeAdd(sum, rdiv(dateBucket[currDate], rpow(discountRate,  safeSub(currDate, normalizedDay), ONE)));
            currDate = nextBucket[currDate];
        }
        return sum;
    }
}
