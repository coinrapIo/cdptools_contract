pragma solidity ^0.4.24;

import "ds-math/math.sol";
import "./SetLib.sol";

interface IERC20 {
    function allowance(address, address) external view returns (uint);
    function balanceOf(address who) external view returns (uint256);
    function transfer(address to, uint256 value) external returns (bool);
    function approve(address spender, uint256 value) external returns (bool);
    function transferFrom(address from, address to, uint256 value) external returns (bool);
}

interface MakerCDP {
    function open() external returns (bytes32 cup);
    function join(uint wad) external; // Join PETH
    function exit(uint wad) external; // Exit PETH
    function give(bytes32 cup, address guy) external;
    function lock(bytes32 cup, uint wad) external;
    function free(bytes32 cup, uint wad) external;
    function draw(bytes32 cup, uint wad) external;
    function wipe(bytes32 cup, uint wad) external;
    function shut(bytes32 cup) external;
    function per() external view returns (uint ray);
    function lad(bytes32 cup) external view returns (address);
    function pep() external view returns(PepInterface);
    function sai() external view returns (IERC20);
    function gov() external view returns (IERC20);
    function gem() external view returns (IERC20);
    function skr() external view returns (IERC20);
    function tab(bytes32 cup) external returns (uint);
    function ink(bytes32 cup) external returns (uint);
    function bid(uint wad) external returns (uint);

}

interface WETHFace {
    function balanceOf(address who) external view returns (uint256);
    function deposit() external payable;
    function withdraw(uint wad) external;
}

interface OtcInterface {
    function getPayAmount(address, address, uint) external view returns (uint);
    function buyAllAmount(address, uint, address pay_gem, uint) external returns (uint);
}

interface PepInterface {
    function peek() external returns (bytes32, bool);
}

contract CdpBank is DSMath{
    using SetLib for SetLib.Set;
    address public owner;
    
    address cdpAddr; // SaiTub
    mapping(uint => address) cdps; // CDP Number >>> Borrower
    mapping(address => SetLib.Set) guys; // Borrower >>> CDP IDS
    uint16 fee = 0; // fee / 10000
    
    bool public freezed;

    event SetOwner(address from, address to);
    event SetFee(uint16 from, uint16 to);
    event NewCup(uint cdpId, address borrower);
    event LockedETH(uint cdpId, address borrower, uint lockETH, uint lockPETH);
    event LoanedDAI(uint cdpId, address borrower, uint loanDAI, address payTo);
    event WipeDAI(uint cdpId, address borrower, uint wipeDAI, uint chargedMKR);
    event FreeETH(uint cdpId, address borrower, uint freeETH);
    event ShutCDP(uint cdpId, address borrower, uint wipeDAI, uint freeETH);
    event TransferInternal(uint cdpId, address owner, address nextOwner);
    event TransferExternal(uint cdpId, address owner, address nextOwner);
    event MKRCollected(uint amount);

    constructor(address tubAddr) public{
        owner = msg.sender;
        cdpAddr = tubAddr;
        approveERC20();
    }
    
    modifier isFreezed() {
        require(!freezed, "Operation Denied");
        _;
    }

    modifier onlyAdmin() {
        require(msg.sender == owner, "Permission Denied");
        _;
    }

    modifier isCupOwner(uint cdpId) {
        require(cdps[cdpId] == msg.sender || cdps[cdpId] == address(0x0) || cdpId == 0, "Permission Denied");
        _;
    }

    function setOwner(address guy) public onlyAdmin {
        require(guy != 0x0,  'Owner can not be null!');
        emit SetOwner(owner, guy);
        owner = guy;
    }

    function setFee(uint16 newFee) public onlyAdmin {
        emit SetFee(fee, newFee);
        fee = newFee;
    }

    function pethPEReth(uint ethNum) public view returns (uint rpeth) {
        MakerCDP loanMaster = MakerCDP(cdpAddr);
        rpeth = rdiv(ethNum, loanMaster.per());
    }
    
    function borrow(uint cdpId, uint daiDraw, address beneficiary) public payable isFreezed isCupOwner(cdpId) {
        MakerCDP loanMaster = MakerCDP(cdpAddr);
        bytes32 cup = bytes32(cdpId);

        // create new CDP
        if(cdpId == 0){
            cup = loanMaster.open();
            cdps[uint(cup)] = msg.sender;
            guys[msg.sender].add(uint(cup));
            emit NewCup(uint(cup), msg.sender);
        }

        // locking ETH
        if(msg.value > 0){
            WETHFace wethTkn = WETHFace(loanMaster.gem());
            wethTkn.deposit.value(msg.value)(); // ETH to WETH
            uint pethToLock = pethPEReth(msg.value);
            loanMaster.join(pethToLock); // WETH to PETH
            loanMaster.lock(cup, pethToLock); // PETH to CDP
            emit LockedETH(uint(cup), msg.sender, msg.value, pethToLock);
        }

        // minting DAI
        if (daiDraw > 0) {
            loanMaster.draw(cup, daiDraw);
            IERC20 daiTkn = IERC20(loanMaster.sai());
            address payTo = beneficiary;
            if(beneficiary == address(0x0)){
                payTo = msg.sender;
            }
            daiTkn.transfer(payTo, daiDraw);
            emit LoanedDAI(uint(cup), msg.sender, daiDraw, payTo);
        }

    }

    function wipeDAI(address otc, uint cdpId, uint daiWipe) public payable {
        MakerCDP loanMaster = MakerCDP(cdpAddr);
        IERC20 daiTkn = IERC20(loanMaster.sai());
        IERC20 mkrTkn = IERC20(loanMaster.gov());
        bytes32 cup = bytes32(cdpId);

        uint mkrBalance = mkrTkn.balanceOf(address(this)); // contract MKR balance before wiping
        daiTkn.transferFrom(msg.sender, address(this), daiWipe); // get DAI to pay the debt
        loanMaster.wipe(cup, daiWipe); // wipe DAI

        if(fee > 0){
            uint fees = (daiWipe * fee / 10000);
            daiTkn.transferFrom(msg.sender, address(this), fees);
        }

        uint mkrCharged = mkrBalance - mkrTkn.balanceOf(address(this)); // MKR fee = before wiping bal - after wiping bal

        uint mkrSenderBalance = mkrTkn.balanceOf(msg.sender);
        uint mkrSenderAllowance = mkrTkn.allowance(msg.sender, address(this));

        if(mkrSenderBalance > mkrCharged && mkrSenderAllowance > mkrCharged){
            mkrTkn.transferFrom(msg.sender, address(this), mkrCharged); // user paying MKR fees
        }else{
            handleGovFee(loanMaster, mkrCharged, otc); // get MKR from DAI (from user)
        }

        emit WipeDAI(cdpId, msg.sender, daiWipe, mkrCharged);    
    }

    function unlockETH(uint cdpId, uint ethFree) public isFreezed isCupOwner(cdpId){
        bytes32 cup = bytes32(cdpId);
        uint pethToUnlock = pethPEReth(ethFree);
        MakerCDP tub = MakerCDP(cdpAddr);
        tub.free(cup, pethToUnlock); // CDP to PETH
        tub.exit(pethToUnlock); // PETH to WETH
        WETHFace wethTkn = WETHFace(tub.gem());
        wethTkn.withdraw(ethFree); // WETH to ETH
        msg.sender.transfer(ethFree);
        emit FreeETH(cdpId, msg.sender, ethFree);
    }

    function safeShut(address otc, uint cdpId, uint daiDebt) public payable isFreezed isCupOwner(cdpId) {
        if(daiDebt > 0){
            wipeDAI(otc, cdpId, daiDebt);
        }

        MakerCDP tub = MakerCDP(cdpAddr);
        bytes32 cup = bytes32(cdpId);
        uint tab = tub.tab(cup);
        uint ink = tub.ink(cup);
        require(tab == 0, "Must wipe DAI before shut.");
        uint wethBal = tub.bid(ink);

        tub.shut(cup);
        tub.exit(ink); // PETH to WETH

        WETHFace wethTkn = WETHFace(tub.gem());
        wethTkn.withdraw(wethBal);
        msg.sender.transfer(wethBal);

        cdps[cdpId] = address(0x0);
        require(guys[msg.sender].remove(cdpId), "");
        if(guys[msg.sender].size() == 0){
            delete guys[msg.sender];
        }

        emit ShutCDP(cdpId, msg.sender, daiDebt, wethBal);
    }

    function shut(address otc, uint cdpId, uint daiDebt) public payable isFreezed isCupOwner(cdpId) {
        if(daiDebt > 0){
            wipeDAI(otc, cdpId, daiDebt);
        }
        MakerCDP tub = MakerCDP(cdpAddr);
        tub.shut(bytes32(cdpId));

        IERC20 pethTkn = IERC20(tub.skr());
        uint pethBal = pethTkn.balanceOf(address(this));
        tub.exit(pethBal); // PETH to WETH

        WETHFace wethTkn = WETHFace(tub.gem());
        uint wethBal = wethTkn.balanceOf(address(this));
        wethTkn.withdraw(wethBal); // WETH to ETH
        msg.sender.transfer(wethBal);  // ETH to borrower

        cdps[cdpId] = address(0x0);
        require(guys[msg.sender].remove(cdpId), "");
        if(guys[msg.sender].size() == 0){
            delete guys[msg.sender];
        }

        emit ShutCDP(cdpId, msg.sender, daiDebt, wethBal);
    }

    function transferInternal(uint cdpId, address nextOwner) public isCupOwner(cdpId) {
        require(nextOwner != address(0x0), "Invalid Address.");
        cdps[cdpId] = nextOwner;
        require(guys[nextOwner].add(cdpId), "");
        require(guys[msg.sender].remove(cdpId), "");
        if(guys[msg.sender].size() ==0){
            delete guys[msg.sender];
        }
        emit TransferInternal(cdpId, msg.sender, nextOwner);
    }

    function transferExternal(uint cdpId, address nextOwner) public isFreezed isCupOwner(cdpId) {
        require(nextOwner != address(0x0), "Invalid Address.");
        MakerCDP tub = MakerCDP(cdpAddr);
        tub.give(bytes32(cdpId), nextOwner);
        cdps[cdpId] = address(0x0);
        require(guys[msg.sender].remove(cdpId), "");
        if(guys[msg.sender].size() == 0){
            delete guys[msg.sender];
        }
        emit TransferExternal(cdpId, msg.sender, nextOwner);
    }

    function getCDP(uint cdpId) public view returns(address, bytes32) { 
        return (cdps[cdpId], bytes32(cdpId));
    }

    function approveERC20() internal {
        MakerCDP tub = MakerCDP(cdpAddr);
        IERC20 wethTkn = IERC20(tub.gem());
        wethTkn.approve(cdpAddr, 2 ** 256 - 1);
        IERC20 pethTkn = IERC20(tub.skr());
        pethTkn.approve(cdpAddr, 2 ** 256 - 1);
        IERC20 mkrTkn = IERC20(tub.gov());
        mkrTkn.approve(cdpAddr, 2 ** 256 - 1);
        IERC20 daiTkn = IERC20(tub.sai());
        daiTkn.approve(cdpAddr, 2 ** 256 - 1);
    }
    
    function freeze(bool stop) public onlyAdmin {
        freezed = stop;
    }

    function collectMKR(uint amount) public onlyAdmin {
        MakerCDP tub = MakerCDP(cdpAddr);
        IERC20 mkrTkn = IERC20(tub.gov());
        mkrTkn.transfer(msg.sender, amount);
        emit MKRCollected(amount);
    }

    function getCdps(address guy) public returns(uint[]){
        return guys[guy].getKeys();
    }

    function handleGovFee(MakerCDP tub, uint saiDebtFee, address otc_) internal {
        bytes32 val;
        bool ok;
        (val, ok) = tub.pep().peek();
        if (ok && val != 0) {
            uint govAmt = wdiv(saiDebtFee, uint(val));
            if (otc_ != address(0)) {
                uint saiGovAmt = OtcInterface(otc_).getPayAmount(tub.sai(), tub.gov(), govAmt);
                if (tub.sai().allowance(this, otc_) != uint(-1)) {
                    tub.sai().approve(otc_, uint(-1));
                }
                tub.sai().transferFrom(msg.sender, this, saiGovAmt);
                OtcInterface(otc_).buyAllAmount(tub.gov(), govAmt, tub.sai(), saiGovAmt);
            } else {
                tub.gov().transferFrom(msg.sender, this, govAmt);
            }
        }
    }

    function() external payable {}
}