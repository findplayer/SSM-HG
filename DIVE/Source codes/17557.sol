// hevm: flattened sources of src/DssSpell.sol
// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity =0.8.16 >=0.5.12 >=0.8.16 <0.9.0;

////// lib/dss-exec-lib/src/CollateralOpts.sol
//
// CollateralOpts.sol -- Data structure for onboarding collateral
//
// Copyright (C) 2020-2022 Dai Foundation
//
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

/* pragma solidity ^0.8.16; */

struct CollateralOpts {
    bytes32 ilk;
    address gem;
    address join;
    address clip;
    address calc;
    address pip;
    bool    isLiquidatable;
    bool    isOSM;
    bool    whitelistOSM;
    uint256 ilkDebtCeiling;
    uint256 minVaultAmount;
    uint256 maxLiquidationAmount;
    uint256 liquidationPenalty;
    uint256 ilkStabilityFee;
    uint256 startingPriceFactor;
    uint256 breakerTolerance;
    uint256 auctionDuration;
    uint256 permittedDrop;
    uint256 liquidationRatio;
    uint256 kprFlatReward;
    uint256 kprPctReward;
}

////// lib/dss-exec-lib/src/DssExecLib.sol
//
// DssExecLib.sol -- MakerDAO Executive Spellcrafting Library
//
// Copyright (C) 2020-2022 Dai Foundation
//
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

/* pragma solidity ^0.8.16; */

/* import { CollateralOpts } from "./CollateralOpts.sol"; */

interface Initializable {
    function init(bytes32) external;
}

interface Authorizable {
    function rely(address) external;
    function deny(address) external;
    function setAuthority(address) external;
}

interface Fileable {
    function file(bytes32, address) external;
    function file(bytes32, uint256) external;
    function file(bytes32, bytes32, uint256) external;
    function file(bytes32, bytes32, address) external;
}

interface Drippable {
    function drip() external returns (uint256);
    function drip(bytes32) external returns (uint256);
}

interface Pricing {
    function poke(bytes32) external;
}

interface ERC20 {
    function decimals() external returns (uint8);
}

interface DssVat {
    function hope(address) external;
    function nope(address) external;
    function ilks(bytes32) external returns (uint256 Art, uint256 rate, uint256 spot, uint256 line, uint256 dust);
    function Line() external view returns (uint256);
    function suck(address, address, uint256) external;
}

interface ClipLike {
    function vat() external returns (address);
    function dog() external returns (address);
    function spotter() external view returns (address);
    function calc() external view returns (address);
    function ilk() external returns (bytes32);
}

interface DogLike {
    function ilks(bytes32) external returns (address clip, uint256 chop, uint256 hole, uint256 dirt);
}

interface JoinLike {
    function vat() external returns (address);
    function ilk() external returns (bytes32);
    function gem() external returns (address);
    function dec() external returns (uint256);
    function join(address, uint256) external;
    function exit(address, uint256) external;
}

// Includes Median and OSM functions
interface OracleLike_2 {
    function src() external view returns (address);
    function lift(address[] calldata) external;
    function drop(address[] calldata) external;
    function setBar(uint256) external;
    function kiss(address) external;
    function diss(address) external;
    function kiss(address[] calldata) external;
    function diss(address[] calldata) external;
    function orb0() external view returns (address);
    function orb1() external view returns (address);
}

interface MomLike {
    function setOsm(bytes32, address) external;
    function setPriceTolerance(address, uint256) external;
}

interface RegistryLike {
    function add(address) external;
    function xlip(bytes32) external view returns (address);
}

// https://github.com/makerdao/dss-chain-log
interface ChainlogLike {
    function setVersion(string calldata) external;
    function setIPFS(string calldata) external;
    function setSha256sum(string calldata) external;
    function getAddress(bytes32) external view returns (address);
    function setAddress(bytes32, address) external;
    function removeAddress(bytes32) external;
}

interface IAMLike {
    function ilks(bytes32) external view returns (uint256,uint256,uint48,uint48,uint48);
    function setIlk(bytes32,uint256,uint256,uint256) external;
    function remIlk(bytes32) external;
    function exec(bytes32) external returns (uint256);
}

interface LerpFactoryLike {
    function newLerp(bytes32 name_, address target_, bytes32 what_, uint256 startTime_, uint256 start_, uint256 end_, uint256 duration_) external returns (address);
    function newIlkLerp(bytes32 name_, address target_, bytes32 ilk_, bytes32 what_, uint256 startTime_, uint256 start_, uint256 end_, uint256 duration_) external returns (address);
}

interface LerpLike {
    function tick() external returns (uint256);
}

interface RwaOracleLike {
    function bump(bytes32 ilk, uint256 val) external;
}


library DssExecLib {

    /* WARNING

The following library code acts as an interface to the actual DssExecLib
library, which can be found in its own deployed contract. Only trust the actual
library's implementation.

    */

    address constant public LOG = 0xdA0Ab1e0017DEbCd72Be8599041a2aa3bA7e740F;
    uint256 constant internal WAD      = 10 ** 18;
    uint256 constant internal RAY      = 10 ** 27;
    uint256 constant internal RAD      = 10 ** 45;
    uint256 constant internal THOUSAND = 10 ** 3;
    uint256 constant internal MILLION  = 10 ** 6;
    uint256 constant internal BPS_ONE_PCT             = 100;
    uint256 constant internal BPS_ONE_HUNDRED_PCT     = 100 * BPS_ONE_PCT;
    uint256 constant internal RATES_ONE_HUNDRED_PCT   = 1000000021979553151239153027;
    function vat()        public view returns (address) { return getChangelogAddress("MCD_VAT"); }
    function jug()        public view returns (address) { return getChangelogAddress("MCD_JUG"); }
    function end()        public view returns (address) { return getChangelogAddress("MCD_END"); }
    function reg()        public view returns (address) { return getChangelogAddress("ILK_REGISTRY"); }
    function autoLine()   public view returns (address) { return getChangelogAddress("MCD_IAM_AUTO_LINE"); }
    function lerpFab()    public view returns (address) { return getChangelogAddress("LERP_FAB"); }
    function clip(bytes32 _ilk) public view returns (address _clip) {}
    function flip(bytes32 _ilk) public view returns (address _flip) {}
    function calc(bytes32 _ilk) public view returns (address _calc) {}
    function getChangelogAddress(bytes32 _key) public view returns (address) {}
    function setAuthority(address _base, address _authority) public {}
    function canCast(uint40 _ts, bool _officeHours) public pure returns (bool) {}
    function nextCastTime(uint40 _eta, uint40 _ts, bool _officeHours) public pure returns (uint256 castTime) {}
    function setValue(address _base, bytes32 _what, uint256 _amt) public {}
    function setValue(address _base, bytes32 _ilk, bytes32 _what, uint256 _amt) public {}
    function setIlkDebtCeiling(bytes32 _ilk, uint256 _amount) public {}
    function setIlkAutoLineParameters(bytes32 _ilk, uint256 _amount, uint256 _gap, uint256 _ttl) public {}
    function setIlkStabilityFee(bytes32 _ilk, uint256 _rate, bool _doDrip) public {}
    function linearInterpolation(bytes32 _name, address _target, bytes32 _ilk, bytes32 _what, uint256 _startTime, uint256 _start, uint256 _end, uint256 _duration) public returns (address) {}
}

////// lib/dss-exec-lib/src/DssAction.sol
//
// DssAction.sol -- DSS Executive Spell Actions
//
// Copyright (C) 2020-2022 Dai Foundation
//
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

/* pragma solidity ^0.8.16; */

/* import { DssExecLib } from "./DssExecLib.sol"; */
/* import { CollateralOpts } from "./CollateralOpts.sol"; */

interface OracleLike_1 {
    function src() external view returns (address);
}

abstract contract DssAction {

    using DssExecLib for *;

    // Modifier used to limit execution time when office hours is enabled
    modifier limited {
        require(DssExecLib.canCast(uint40(block.timestamp), officeHours()), "Outside office hours");
        _;
    }

    // Office Hours defaults to true by default.
    //   To disable office hours, override this function and
    //    return false in the inherited action.
    function officeHours() public view virtual returns (bool) {
        return true;
    }

    // DssExec calls execute. We limit this function subject to officeHours modifier.
    function execute() external limited {
        actions();
    }

    // DssAction developer must override `actions()` and place all actions to be called inside.
    //   The DssExec function will call this subject to the officeHours limiter
    //   By keeping this function public we allow simulations of `execute()` on the actions outside of the cast time.
    function actions() public virtual;

    // Provides a descriptive tag for bot consumption
    // This should be modified weekly to provide a summary of the actions
    // Hash: seth keccak -- "$(wget https://<executive-vote-canonical-post> -q -O - 2>/dev/null)"
    function description() external view virtual returns (string memory);

    // Returns the next available cast time
    function nextCastTime(uint256 eta) external view returns (uint256 castTime) {
        require(eta <= type(uint40).max);
        castTime = DssExecLib.nextCastTime(uint40(eta), uint40(block.timestamp), officeHours());
    }
}

////// lib/dss-exec-lib/src/DssExec.sol
//
// DssExec.sol -- MakerDAO Executive Spell Template
//
// Copyright (C) 2020-2022 Dai Foundation
//
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

/* pragma solidity ^0.8.16; */

interface PauseAbstract {
    function delay() external view returns (uint256);
    function plot(address, bytes32, bytes calldata, uint256) external;
    function exec(address, bytes32, bytes calldata, uint256) external returns (bytes memory);
}

interface Changelog {
    function getAddress(bytes32) external view returns (address);
}

interface SpellAction {
    function officeHours() external view returns (bool);
    function description() external view returns (string memory);
    function nextCastTime(uint256) external view returns (uint256);
}

contract DssExec {

    Changelog      constant public log   = Changelog(0xdA0Ab1e0017DEbCd72Be8599041a2aa3bA7e740F);
    uint256                 public eta;
    bytes                   public sig;
    bool                    public done;
    bytes32       immutable public tag;
    address       immutable public action;
    uint256       immutable public expiration;
    PauseAbstract immutable public pause;

    // Provides a descriptive tag for bot consumption
    // This should be modified weekly to provide a summary of the actions
    // Hash: seth keccak -- "$(wget https://<executive-vote-canonical-post> -q -O - 2>/dev/null)"
    function description() external view returns (string memory) {
        return SpellAction(action).description();
    }

    function officeHours() external view returns (bool) {
        return SpellAction(action).officeHours();
    }

    function nextCastTime() external view returns (uint256 castTime) {
        return SpellAction(action).nextCastTime(eta);
    }

    // @param _description  A string description of the spell
    // @param _expiration   The timestamp this spell will expire. (Ex. block.timestamp + 30 days)
    // @param _spellAction  The address of the spell action
    constructor(uint256 _expiration, address _spellAction) {
        pause       = PauseAbstract(log.getAddress("MCD_PAUSE"));
        expiration  = _expiration;
        action      = _spellAction;

        sig = abi.encodeWithSignature("execute()");
        bytes32 _tag;                    // Required for assembly access
        address _action = _spellAction;  // Required for assembly access
        assembly { _tag := extcodehash(_action) }
        tag = _tag;
    }

    function schedule() public {
        require(block.timestamp <= expiration, "This contract has expired");
        require(eta == 0, "This spell has already been scheduled");
        eta = block.timestamp + PauseAbstract(pause).delay();
        pause.plot(action, tag, sig, eta);
    }

    function cast() public {
        require(!done, "spell-already-cast");
        done = true;
        pause.exec(action, tag, sig, eta);
    }
}

////// lib/dss-test/lib/dss-interfaces/src/dss/VestAbstract.sol
/* pragma solidity >=0.5.12; */

// https://github.com/makerdao/dss-vest/blob/master/src/DssVest.sol
interface VestAbstract {
    function TWENTY_YEARS() external view returns (uint256);
    function wards(address) external view returns (uint256);
    function rely(address) external;
    function deny(address) external;
    function awards(uint256) external view returns (address, uint48, uint48, uint48, address, uint8, uint128, uint128);
    function ids() external view returns (uint256);
    function cap() external view returns (uint256);
    function usr(uint256) external view returns (address);
    function bgn(uint256) external view returns (uint256);
    function clf(uint256) external view returns (uint256);
    function fin(uint256) external view returns (uint256);
    function mgr(uint256) external view returns (address);
    function res(uint256) external view returns (uint256);
    function tot(uint256) external view returns (uint256);
    function rxd(uint256) external view returns (uint256);
    function file(bytes32, uint256) external;
    function create(address, uint256, uint256, uint256, uint256, address) external returns (uint256);
    function vest(uint256) external;
    function vest(uint256, uint256) external;
    function accrued(uint256) external view returns (uint256);
    function unpaid(uint256) external view returns (uint256);
    function restrict(uint256) external;
    function unrestrict(uint256) external;
    function yank(uint256) external;
    function yank(uint256, uint256) external;
    function move(uint256, address) external;
    function valid(uint256) external view returns (bool);
}

////// src/DssSpell.sol
// SPDX-FileCopyrightText: © 2020 Dai Foundation <www.daifoundation.org>
//
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

/* pragma solidity 0.8.16; */

/* import "dss-exec-lib/DssExec.sol"; */
/* import "dss-exec-lib/DssAction.sol"; */
/* import { VestAbstract } from "dss-interfaces/dss/VestAbstract.sol"; */

interface InputConduitJarLike {
    function push(uint256) external;
}

interface JarLike {
    function void() external;
}

interface ProxyLike_1 {
    function exec(address target, bytes calldata args) external payable returns (bytes memory out);
}

contract DssSpellAction is DssAction {
    // Provides a descriptive tag for bot consumption
    // This should be modified weekly to provide a summary of the actions
    // Hash: cast keccak -- "$(wget 'https://raw.githubusercontent.com/makerdao/community/ab5af3e3179d17d7a91a97ac0fec234bec0e26bb/governance/votes/Executive%20vote%20-%20February%2022%2C%202024.md' -q -O - 2>/dev/null)"
    string public constant override description =
        "2024-02-22 MakerDAO Executive Spell | Hash: 0xfbaf5ce577a6f054a014681eacff991c409f625b8146e8f8bdcd4f8f58ab386d";

    // Set office hours according to the summary
    function officeHours() public pure override returns (bool) {
        return false;
    }

    // ---------- Rates ----------
    // Many of the settings that change weekly rely on the rate accumulator
    // described at https://docs.makerdao.com/smart-contract-modules/rates-module
    // To check this yourself, use the following rate calculation (example 8%):
    //
    // $ bc -l <<< 'scale=27; e( l(1.08)/(60 * 60 * 24 * 365) )'
    //
    // A table of rates can be found at
    //    https://ipfs.io/ipfs/QmVp4mhhbwWGTfbh2BzwQB9eiBrQBKiqcPRZCaAxNUaar6
    //
    // uint256 internal constant X_PCT_RATE = ;
    uint256 internal constant SIX_PT_ONE_SIX_PCT_RATE     = 1000000001895522707144698926;
    uint256 internal constant SIX_PT_FOUR_PCT_RATE        = 1000000001967129343622160710;
    uint256 internal constant SIX_PT_FOUR_ONE_PCT_RATE    = 1000000001970109447195256751;
    uint256 internal constant SIX_PT_FOUR_THREE_PCT_RATE  = 1000000001976068814257775407;
    uint256 internal constant SIX_PT_SIX_FIVE_PCT_RATE    = 1000000002041548040175924154;
    uint256 internal constant SIX_PT_SIX_EIGHT_PCT_RATE   = 1000000002050466558600245373;
    uint256 internal constant SIX_PT_NINE_ONE_PCT_RATE    = 1000000002118758660201099744;
    uint256 internal constant SEVEN_PT_ONE_EIGHT_PCT_RATE = 1000000002198740428552847104;

    //  ---------- Math ----------
    uint256 internal constant WAD      = 10 ** 18;
    uint256 internal constant MILLION  = 10 ** 6;

    // ---------- Contract addresses ----------
    address internal immutable DIRECT_SPARK_DAI_PLAN                       = DssExecLib.getChangelogAddress("DIRECT_SPARK_DAI_PLAN");
    address internal immutable MCD_VEST_DAI                                = DssExecLib.getChangelogAddress("MCD_VEST_DAI");
    address internal immutable MCD_VEST_MKR_TREASURY                       = DssExecLib.getChangelogAddress("MCD_VEST_MKR_TREASURY");
    InputConduitJarLike internal immutable MCD_PSM_PAX_A_INPUT_CONDUIT_JAR = InputConduitJarLike(DssExecLib.getChangelogAddress("MCD_PSM_PAX_A_INPUT_CONDUIT_JAR"));
    JarLike internal immutable MCD_PSM_PAX_A_JAR                           = JarLike(DssExecLib.getChangelogAddress("MCD_PSM_PAX_A_JAR"));

    // ---------- Trigger Spark Proxy Spell ----------
    // Spark Proxy: https://github.com/marsfoundation/sparklend/blob/d42587ba36523dcff24a4c827dc29ab71cd0808b/script/output/1/primary-sce-latest.json#L2
    address internal constant SPARK_PROXY = 0x3300f198988e4C9C63F75dF86De36421f06af8c4;
    address internal constant SPARK_SPELL = 0x5D9406F377e6aFebAE18552806EA327eC7B10000;

    function actions() public override {
        // ---------- Stability Fee Changes ----------
        // Forum: https://forum.makerdao.com/t/stability-scope-parameter-changes-9/23688

        // Decrease the ETH-A Stability Fee (SF) by 0.33 percentage points, from 6.74% to 6.41%.
        DssExecLib.setIlkStabilityFee("ETH-A", SIX_PT_FOUR_ONE_PCT_RATE, true);

        // Decrease the ETH-B Stability Fee (SF) by 0.33 percentage points, from 7.24% to 6.91%.
        DssExecLib.setIlkStabilityFee("ETH-B", SIX_PT_NINE_ONE_PCT_RATE, true);

        // Decrease the ETH-C Stability Fee (SF) by 0.33 percentage points, from 6.49% to 6.16%.
        DssExecLib.setIlkStabilityFee("ETH-C", SIX_PT_ONE_SIX_PCT_RATE, true);

        // Decrease the WSTETH-A Stability Fee (SF) by 0.51 percentage points, from 7.16% to 6.65%.
        DssExecLib.setIlkStabilityFee("WSTETH-A", SIX_PT_SIX_FIVE_PCT_RATE, true);

        // Decrease the WSTETH-B Stability Fee (SF) by 0.51 percentage points, from 6.91% to 6.40%.
        DssExecLib.setIlkStabilityFee("WSTETH-B", SIX_PT_FOUR_PCT_RATE, true);

        // Decrease the WBTC-A Stability Fee (SF) by 0.02 percentage points, from 6.70% to 6.68%.
        DssExecLib.setIlkStabilityFee("WBTC-A", SIX_PT_SIX_EIGHT_PCT_RATE, true);

        // Decrease the WBTC-B Stability Fee (SF) by 0.02 percentage points, from 7.20% to 7.18%.
        DssExecLib.setIlkStabilityFee("WBTC-B", SEVEN_PT_ONE_EIGHT_PCT_RATE, true);

        // Decrease the WBTC-C Stability Fee (SF) by 0.02 percentage points, from 6.45% to 6.43%.
        DssExecLib.setIlkStabilityFee("WBTC-C", SIX_PT_FOUR_THREE_PCT_RATE, true);

        // ---------- Spark Protocol DC-IAM Parameter Changes (main spell) ----------
        // Forum: https://forum.makerdao.com/t/feb-9-2024-proposed-changes-to-sparklend-for-upcoming-spell/23656
        // Poll: https://vote.makerdao.com/polling/QmS8ch8r

        // Increase the DIRECT-SPARK-DAI Maximum Debt Ceiling (line) by 300 million DAI from 1.2 billion DAI to 1.5 billion DAI.
        // Increase the DIRECT-SPARK-DAI Target Available Debt (gap) by 20 million DAI from 20 million DAI to 40 million DAI.
        // Increase the DIRECT-SPARK-DAI Ceiling Increase Cooldown (ttl) by 12 hours from 12 hours to 24 hours.
        DssExecLib.setIlkAutoLineParameters("DIRECT-SPARK-DAI", /* line = */ 1500 * MILLION, /* gap = */ 40 * MILLION, /* ttl = */ 24 hours);

        // Increase the DIRECT-SPARK-DAI buffer by 20 million DAI from 30 million DAI to 50 million DAI.
        DssExecLib.setValue(DIRECT_SPARK_DAI_PLAN, "buffer", 50 * MILLION * WAD); // NOTE: adjusting DIRECT_SPARK_DAI_PLAN.buffer value to WAD

        // ---------- Push USDP out of input conduit ----------
        // Forum: https://forum.makerdao.com/t/proposed-housekeeping-items-upcoming-executive-spell-2024-02-22/23697

        // Raise PSM-PAX-A DC to 1,000,000 DAI
        DssExecLib.setIlkDebtCeiling("PSM-PAX-A", MILLION);

        // Call push() on MCD_PSM_PAX_A_INPUT_CONDUIT_JAR (use push(uint256 amt)) to push 754,598.72 USDP
        MCD_PSM_PAX_A_INPUT_CONDUIT_JAR.push(754_598.72 ether); // Note: `ether` is only a keyword helper

        // Call void() on MCD_PSM_PAX_A_JAR
        MCD_PSM_PAX_A_JAR.void();

        // Set PSM-PAX-A DC to 0 DAI
        DssExecLib.setIlkDebtCeiling("PSM-PAX-A", 0);

        // ---------- yank vest streams ----------
        // Forum: https://forum.makerdao.com/t/proposed-housekeeping-items-upcoming-executive-spell-2024-02-22/23697

        // yank BA Labs DAI stream 20
        VestAbstract(MCD_VEST_DAI).yank(20);

        // yank BA Labs DAI stream 21
        VestAbstract(MCD_VEST_DAI).yank(21);

        // yank BA Labs MKR stream 35
        VestAbstract(MCD_VEST_MKR_TREASURY).yank(35);

        // ---------- Trigger Spark Proxy Spell ----------
        // Forum: https://forum.makerdao.com/t/feb-14-2024-proposed-changes-to-sparklend-for-upcoming-spell/23684
        // Forum: https://forum.makerdao.com/t/stability-scope-parameter-changes-9/23688#stability-fee-changes-8
        // Poll: https://vote.makerdao.com/polling/QmQC1UXZ

        // Activate Spark Proxy Spell - 0x5D9406F377e6aFebAE18552806EA327eC7B10000
        ProxyLike_1(SPARK_PROXY).exec(SPARK_SPELL, abi.encodeWithSignature("execute()"));
    }
}

contract DssSpell is DssExec {
    constructor() DssExec(block.timestamp + 30 days, address(new DssSpellAction())) {}
}

