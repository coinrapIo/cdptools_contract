pragma solidity ^0.4.24;

library SetLib
{
    struct Item
    {
        bool flag;
        uint key_idx;
    }

    struct Set 
    { 
        mapping(uint => Item) items;
        uint[] keys;
    }

    function add(Set storage self, uint value) internal returns (bool)
    {
        if (self.items[value].flag)
        {
            return false; // already there
        }
        
        self.items[value].flag = true;
        self.items[value].key_idx = self.keys.push(value)-1;
        return true;
    }

    function remove(Set storage self, uint value) internal returns (bool)
    {
        if (!self.items[value].flag)
        {
            return false; // not there
        }

        uint rm_key_idx = self.items[value].key_idx;
        if (rm_key_idx < self.keys.length - 1)
        {
            uint mv_key = self.keys[self.keys.length-1];
            self.keys[rm_key_idx] = mv_key;
            self.items[mv_key].key_idx = rm_key_idx;
        }
        self.keys.length--;

        delete self.items[value];
        return true;
    }

    function exists(Set storage self, uint value) internal view returns (bool)
    {
        return self.items[value].flag;
    }

    function size(Set storage self) internal view returns (uint)
    {
        return self.keys.length;
    }

    function getKeys(Set storage self) internal view returns (uint[])
    {
        return self.keys;
    }
}