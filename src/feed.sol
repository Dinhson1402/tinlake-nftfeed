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
    // dueDate => FV
    mapping (uint => uint) public futureValueAtDate;
    // nftID => dueDate
    mapping (bytes32 => uint) public dueDate;


    uint public discountRate;
    uint public maxDays;

    constructor (uint discountRate_, uint maxDays_) public {
        discountRate = discountRate_;
        maxDays = maxDays_;
    }

    function uniqueDayTimestamp(uint timestamp) public pure returns (uint) {
        return (1 days) * (timestamp/(1 days));
    }

    /// dueDate is a unix timestamp
    function file(bytes32 what, bytes32 nftID_, uint dueDate_) public {
        if (what == "duedate") {
            dueDate[nftID_] = uniqueDayTimestamp(dueDate_);
        } else { revert("unknown config parameter");}
    }

    /// Ceiling Implementation
    function borrow(uint loan, uint amount) external auth {
        uint normalizedDay = uniqueDayTimestamp(now);

        // ceiling check uses existing loan debt
        require(ceiling(loan) >= safeAdd(pile.debt(loan), amount), "borrow-amount-too-high");

        bytes32 nftID_ = nftID(loan);
        // calculate future cash flow
        futureValueAtDate[dueDate[nftID_]] = rmul(rpow(pile.loanRates(loan),  dueDate[nftID_]  - normalizedDay, ONE), amount);
    }

    function repay(uint loan, uint amount) external auth {}

    /// returns the NAV (net asset value) of the pool
    function nav() public view returns(uint) {
        uint normalizedDay = uniqueDayTimestamp(now);
        uint sum = 0;

        // current implementation ignores overdue nfts
        for (uint i = 0;i <= maxDays; i=i + 1 days) {
            sum += rdiv(futureValueAtDate[normalizedDay + i], rpow(discountRate,  i, ONE));
        }
        return sum;
    }
}
