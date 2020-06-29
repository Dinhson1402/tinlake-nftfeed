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


contract Buckets {
    // linked list of future value buckets
    // the linked list on top of a mapping is more gas efficient instead of an array
    // the key in the map is a timestamp and acts as pointer for the linked list
    // two mappings with two uints are more gas efficient than one mapping with one struct
    // normalized timestamp -> value denominated in WAD
    mapping (uint => uint) public dateBucket;
    // normalized timestamp -> normalized timestamp
    // pointer to the next bucket
    mapping (uint => uint) public nextBucket;
    
    // pointer to the first bucket and last bucket
    uint public firstBucket;
    uint public lastBucket;

    uint constant public NullDate = 1;

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

    function removeBucket(uint maturityDate_) internal {
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
