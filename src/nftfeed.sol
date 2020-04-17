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

contract ShelfLike {
    function shelf(uint loan) public view returns (address registry, uint tokenId);
    function nftlookup(bytes32 nftID) public returns (uint loan);
}

contract PileLike {
    function setRate(uint loan, uint rate) public;
    function debt(uint loan) public returns (uint);
    function pie(uint loan) public returns (uint);
    function changeRate(uint loan, uint newRate) public;
    function loanRates(uint loan) public returns (uint);
}

contract BaseNFTFeed is DSNote, Auth, Interest {
    // nftID => nftValues
    mapping (bytes32 => uint) public nftValues;

    // nftID => risk
    mapping (bytes32 => uint) public risk;

    // risk => thresholdRatio
    mapping (uint => uint) public thresholdRatio;
    // risk => ceilingRatio
    mapping (uint => uint) public ceilingRatio;
    // risk => rate
    mapping (uint => uint) public rate;

    PileLike pile;
    ShelfLike shelf;

    /// defines default values for risk group 0
    /// all values are denominated in RAY (10^27)
    constructor (uint defaultThresholdRatio, uint defaultCeilingRatio, uint defaultRate) public {
        wards[msg.sender] = 1;
        thresholdRatio[0] = defaultThresholdRatio;
        ceilingRatio[0] = defaultCeilingRatio;
        rate[0] = defaultRate;
    }


    /// sets the dependency to another contract
    function depend(bytes32 contractName, address addr) external auth {
        if (contractName == "pile") {pile = PileLike(addr);}
        else if (contractName == "shelf") { shelf = ShelfLike(addr); }
        else revert();
    }

    function nftID(address registry, uint tokenId) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(registry, tokenId));
    }

    function nftID(uint loan) public view returns (bytes32) {
        (address registry, uint tokenId) = shelf.shelf(loan);
        return nftID(registry, tokenId);
    }

    /// Admin -- Updates
    function setRiskGroup(uint risk_, uint thresholdRatio_, uint ceilingRatio_, uint rate_) public auth {
        thresholdRatio[risk_] = thresholdRatio_;
        ceilingRatio[risk_] = ceilingRatio_;
        rate[risk_]= rate_;
    }

    ///  -- Oracle Updates --

    /// update the nft value
    function update(bytes32 nftID_,  uint value) public auth {
        nftValues[nftID_] = value;
    }

    /// update the nft value and change the risk group
    function update(bytes32 nftID_, uint value, uint risk_) public auth {
        require(thresholdRatio[risk_] != 0, "threshold for risk group not defined");

        // change to new rate in pile if loan is ongoing
        uint loan = shelf.nftlookup(nftID_);
        if (pile.pie(loan) != 0) {
            pile.changeRate(loan, rate[risk_]);
        }

        risk[nftID_] = risk_;
        nftValues[nftID_] = value;

    }

    // LineOf Credit interface
    function borrow(uint loan, uint amount) external auth {
        // ceiling check uses existing loan debt
        require(ceiling(loan) >= safeAdd(pile.debt(loan), amount), "borrow-amount-too-high");

    }

    function repay(uint loan, uint amount) external auth {}

    function borrowEvent(uint loan) public {
        uint rate_ = loanRate(loan);
        // condition is only true if there is no outstanding debt
        // if the rate has been changed with the update method
        // the pile rate is already up to date
        if(pile.loanRates(loan) != rate_) {
            pile.setRate(loan, rate_);
        }
    }

    function unlockEvent(uint loan) public {

    }

    // sets the loan rate in pile
    // not possible for ongoing loans
    function setPileRate(uint loan) public auth {
        pile.setRate(loan, loanRate(loan));
    }

    ///  -- Getter methods --
    function ceiling(uint loan) public view returns (uint) {
        bytes32 nftID_ = nftID(loan);
        return rmul(nftValues[nftID_], ceilingRatio[risk[nftID_]]);
    }

    function threshold(uint loan) public view returns (uint) {
        bytes32 nftID_ = nftID(loan);
        return rmul(nftValues[nftID_], thresholdRatio[risk[nftID_]]);
    }

    function loanRate(uint loan) public view returns (uint) {
        return rate[risk[nftID(loan)]];
    }
}
