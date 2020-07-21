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
import "./buckets.sol";

contract NAVFeed is BaseNFTFeed, Interest, Buckets  {
    // nftID => maturityDate
    mapping (bytes32 => uint) public maturityDate;

    // risk => recoveryRatePD
    mapping (uint => uint) public recoveryRatePD;

    // loan => futureValue
    mapping (uint => uint) public futureValue;

    WriteOff [2] public writeOffs;

    struct WriteOff {
        uint rateGroup;
        // denominated in RAY (10^27)
        uint percentage;
    }

    uint public discountRate;
    uint public maxDays;

    constructor (uint discountRate_, uint maxDays_) public {
        discountRate = discountRate_;
        maxDays = maxDays_;
    }

    function init() public {
        super.init();
        // gas optimized initialization of writeOffs
        // write off are hardcoded in the contract instead of init function params

        // risk group recoveryRatePD
        recoveryRatePD[0] = ONE;
        recoveryRatePD[1] = 90 * 10**25;

        // 60% -> 40% write off
        // 91 is a random sample for a rateGroup in pile for overdue loans
        writeOffs[0] = WriteOff(91, 6 * 10**26);
        // 80% -> 20% write off
        // 90 is a random sample for a rateGroup in pile for overdue loans
        writeOffs[1] = WriteOff(90, 8 * 10**26);
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

        // ceiling check uses existing loan debt
        require(ceiling(loan) >= safeAdd(pile.debt(loan), amount), "borrow-amount-too-high");

        bytes32 nftID_ = nftID(loan);
        uint maturityDate_ = maturityDate[nftID_];

        // calculate future value FV
        uint fv = calcFutureValue(loan, amount, maturityDate_, recoveryRatePD[risk[nftID_]]);
        futureValue[loan] = safeAdd(futureValue[loan], fv);

        if (buckets[maturityDate_].value == 0) {
            addBucket(maturityDate_, fv);
            return;
        }

        buckets[maturityDate_].value = safeAdd(buckets[maturityDate_].value, fv);
    }

    function calcFutureValue(uint loan, uint amount, uint maturityDate_, uint recoveryRatePD_) public returns(uint) {
        return rmul(rmul(rpow(pile.loanRates(loan),  safeSub(maturityDate_, uniqueDayTimestamp(now)), ONE), amount), recoveryRatePD_);

    }

    /// update the nft value and change the risk group
    function update(bytes32 nftID_, uint value, uint risk_) public auth {
        require(thresholdRatio[risk_] != 0, "threshold for risk group not defined");

        risk[nftID_] = risk_;
        nftValues[nftID_] = value;

        uint loan = shelf.nftlookup(nftID_);

        // no loan borrowed yet
        // first loan id starts with one
        if (futureValue[loan] == 0) {
            return;
        }

        uint maturityDate_ = maturityDate[nftID_];

        // calculate future value FV
        buckets[maturityDate_].value = safeSub(buckets[maturityDate_].value, futureValue[loan]);

        futureValue[loan] = calcFutureValue(loan, pile.debt(loan), maturityDate[nftID_], recoveryRatePD[risk[nftID_]]);
        buckets[maturityDate_].value = safeAdd(buckets[maturityDate_].value, futureValue[loan]);
    }

    function repay(uint loan, uint amount) external auth {
        bytes32 nftID_ = nftID(loan);
        uint maturityDate_ = maturityDate[nftID_];

        // remove future value for loan from bucket
        buckets[maturityDate_].value = safeSub(buckets[maturityDate_].value, futureValue[loan]);

        uint debt = pile.debt(loan);

        debt = safeSub(debt, amount);

        if (debt != 0) {
            // calculate new future value for loan if debt is still existing
            uint fv = calcFutureValue(loan, debt, maturityDate_, recoveryRatePD[risk[nftID_]]);
            buckets[maturityDate_].value = safeAdd(buckets[maturityDate_].value, fv);
            futureValue[loan] = fv;
        }

        if (buckets[maturityDate_].value == 0) {
            removeBucket(maturityDate_);
        }
    }

    function calcDiscount() public view returns(uint) {
        uint normalizedDay = uniqueDayTimestamp(now);
        uint sum = 0;

        uint currDate = normalizedDay;

        if (currDate > lastBucket) {
            return 0;
        }

        while(buckets[currDate].next == 0) { currDate = currDate + 1 days; }

        while(currDate != NullDate)
        {
            sum = safeAdd(sum, rdiv(buckets[currDate].value, rpow(discountRate, safeSub(currDate, normalizedDay), ONE)));
            currDate = buckets[currDate].next;
        }
        return sum;
    }

    /// returns the NAV (net asset value) of the pool
    function currentNAV() view public returns(uint) {
        uint nav_ = calcDiscount();

        // add write offs to NAV
        for (uint i = 0; i < writeOffs.length; i++) {
            (uint pie, uint chi, ,) = pile.rates(writeOffs[i].rateGroup);
            nav_ = safeAdd(nav_, rmul(rmul(pie, chi), writeOffs[i].percentage));
        }
        return nav_;
    }

    function dateBucket(uint timestamp) public view returns (uint) {
        return buckets[timestamp].value;
    }
}
