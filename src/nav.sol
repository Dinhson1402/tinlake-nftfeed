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
import "tinlake-math/math.sol";

import "./nftfeed.sol";

contract NAV is BaseNFTFeed {
    PileLike pile;
    ShelfLike shelf;

    // dueDate => FV
    mapping (uint => uint) public futureValueAtDate;

    // nftID => dueDate
    mapping (bytes32 => uint) public dueDate;
    uint public discountRate;


    /// dueDate is timestamp
    function file(bytes32 what, bytes32 nftID_, uint dueDate_) public {
        if (what == "duedate") {
            dueDate[nftID_] = dueDate_;
        } else { revert("unknown config parameter");}
    }

    constructor (uint defaultThresholdRatio, uint defaultCeilingRatio, uint defaultRate) BaseNFTFeed(defaultThresholdRatio ,defaultCeilingRatio, defaultRate) public {


    }

    // LineOf Credit interface
    function borrow(uint loan, uint amount) external auth {
        // ceiling check uses existing loan debt
        require(ceiling(loan) >= safeAdd(pile.debt(loan), amount), "borrow-amount-too-high");

        bytes32 nftID_ = nftID(loan);
        // calculate future cash flow

        futureValueAtDate[dueDate[nftID_]] = rmul(rpow(rate[risk[nftID(loan)]],  dueDate[nftID_]  - now, ONE), amount);
    }

    function repay(uint loan, uint amount) external auth {}

    // events

    function borrowEvent(uint loan) public {

    }

    function unlockEvent(uint loan) public {

    }

    function currentNAV() public returns(uint) {
        /*

        iterate over mapping FVatDate
        sum = sum +  FV/n



        */


        return 0;
    }

}
