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
    function file(bytes32, uint, uint) public;
    function rates(uint rate) public view returns(uint, uint, uint ,uint48);
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

    PileLike pile;
    ShelfLike shelf;

    constructor () public {
        wards[msg.sender] = 1;
    }

    /// sets the dependency to another contract
    function depend(bytes32 contractName, address addr) external auth {
        if (contractName == "pile") {pile = PileLike(addr);}
        else if (contractName == "shelf") { shelf = ShelfLike(addr); }
        else revert();
    }

    /// returns a unique id based on registry and tokenId
    /// the nftID allows to define a risk group and an nft value
    /// before a loan is issued
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
        // the risk group is used as a rate id in the pile
        pile.file("rate", risk_, rate_);
    }

    ///  -- Oracle Updates --

    /// update the nft value
    function update(bytes32 nftID_,  uint value) public auth {
        nftValues[nftID_] = value;
    }

    /// update the nft value and change the risk group
    function update(bytes32 nftID_, uint value, uint risk_) public auth {
        require(thresholdRatio[risk_] != 0, "threshold for risk group not defined");

        // change to new rate immediately in pile if a loan debt exists
        uint loan = shelf.nftlookup(nftID_);
        if (pile.pie(loan) != 0) {
            pile.changeRate(loan, risk_);
        }

        risk[nftID_] = risk_;
        nftValues[nftID_] = value;
    }

    // method is called by the pile to check the ceiling
    function borrow(uint loan, uint amount) external auth {
        // ceiling check uses existing loan debt
        require(ceiling(loan) >= safeAdd(pile.debt(loan), amount), "borrow-amount-too-high");
    }

    // method is called by the pile to check the ceiling
    function repay(uint loan, uint amount) external auth {}

    // borrowEvent is called by the shelf in the borrow method
    function borrowEvent(uint loan) public auth {
        uint risk_ = risk[nftID(loan)];

        // condition is only true if there is no outstanding debt
        // if the rate has been changed with the update method
        // the pile rate is already up to date
        if(pile.loanRates(loan) != risk_) {
            pile.setRate(loan, risk_);
        }
    }

    // unlockEvent is called by the shelf.unlock method
    function unlockEvent(uint loan) public auth {}

    ///  -- Getter methods --
    /// returns the ceiling of a loan
    /// the ceiling defines the maximum amount which can be borrowed
    function ceiling(uint loan) public view returns (uint) {
        bytes32 nftID_ = nftID(loan);
        return rmul(nftValues[nftID_], ceilingRatio[risk[nftID_]]);
    }

    /// returns the threshold of a loan
    /// if the loan debt is above the loan threshold the NFT can be seized
    function threshold(uint loan) public view returns (uint) {
        bytes32 nftID_ = nftID(loan);
        return rmul(nftValues[nftID_], thresholdRatio[risk[nftID_]]);
    }

    /// returns the rate per second of a loan
    function loanRatePerSecond(uint loan) public view returns (uint) {
        bytes32 nftID_ = nftID(loan);
        // the risk group is used as a rateId in pile
        (,,uint rate ,) = pile.rates(risk[nftID_]);
        return rate;
    }
}
