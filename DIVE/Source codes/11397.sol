// hevm: flattened sources of src/DssSpell.sol
// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity =0.8.16 >=0.8.16 <0.9.0;

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
    function dai()        public view returns (address) { return getChangelogAddress("MCD_DAI"); }
    function mkr()        public view returns (address) { return getChangelogAddress("MCD_GOV"); }
    function vat()        public view returns (address) { return getChangelogAddress("MCD_VAT"); }
    function dog()        public view returns (address) { return getChangelogAddress("MCD_DOG"); }
    function pot()        public view returns (address) { return getChangelogAddress("MCD_POT"); }
    function vow()        public view returns (address) { return getChangelogAddress("MCD_VOW"); }
    function end()        public view returns (address) { return getChangelogAddress("MCD_END"); }
    function reg()        public view returns (address) { return getChangelogAddress("ILK_REGISTRY"); }
    function spotter()    public view returns (address) { return getChangelogAddress("MCD_SPOT"); }
    function autoLine()   public view returns (address) { return getChangelogAddress("MCD_IAM_AUTO_LINE"); }
    function daiJoin()    public view returns (address) { return getChangelogAddress("MCD_JOIN_DAI"); }
    function lerpFab()    public view returns (address) { return getChangelogAddress("LERP_FAB"); }
    function clip(bytes32 _ilk) public view returns (address _clip) {}
    function flip(bytes32 _ilk) public view returns (address _flip) {}
    function calc(bytes32 _ilk) public view returns (address _calc) {}
    function getChangelogAddress(bytes32 _key) public view returns (address) {}
    function setAuthority(address _base, address _authority) public {}
    function canCast(uint40 _ts, bool _officeHours) public pure returns (bool) {}
    function nextCastTime(uint40 _eta, uint40 _ts, bool _officeHours) public pure returns (uint256 castTime) {}
    function updateCollateralPrice(bytes32 _ilk) public {}
    function setValue(address _base, bytes32 _what, uint256 _amt) public {}
    function setValue(address _base, bytes32 _ilk, bytes32 _what, uint256 _amt) public {}
    function increaseGlobalDebtCeiling(uint256 _amount) public {}
    function increaseIlkDebtCeiling(bytes32 _ilk, uint256 _amount, bool _global) public {}
    function setIlkAutoLineParameters(bytes32 _ilk, uint256 _amount, uint256 _gap, uint256 _ttl) public {}
    function removeIlkFromAutoLine(bytes32 _ilk) public {}
    function setIlkMinVaultAmount(bytes32 _ilk, uint256 _amount) public {}
    function sendPaymentFromSurplusBuffer(address _target, uint256 _amount) public {}
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

interface GemLike {
    function transfer(address, uint256) external returns (bool);
}

interface RwaLiquidationLike_1 {
    function bump(bytes32 ilk, uint256 val) external;
}

contract DssSpellAction is DssAction {
    // Provides a descriptive tag for bot consumption
    // This should be modified weekly to provide a summary of the actions
    // Hash: cast keccak -- "$(wget https://raw.githubusercontent.com/makerdao/community/7d2ba4cf5c3d47e321bdc0d9dc521a0663bf046a/governance/votes/Executive%20vote%20-%20March%2029%2C%202023.md -q -O - 2>/dev/null)"
    string public constant override description =
        "2023-03-29 MakerDAO Executive Spell | Hash: 0xcab66000cc34553a71300a97f7809bde72c2fbf964fc6a071e4d67058a8e1a3f";

    // Turn office hours on
    function officeHours() public pure override returns (bool) {
        return true;
    }

    // Many of the settings that change weekly rely on the rate accumulator
    // described at https://docs.makerdao.com/smart-contract-modules/rates-module
    // To check this yourself, use the following rate calculation (example 8%):
    //
    // $ bc -l <<< 'scale=27; e( l(1.08)/(60 * 60 * 24 * 365) )'
    //
    // A table of rates can be found at
    //    https://ipfs.io/ipfs/QmVp4mhhbwWGTfbh2BzwQB9eiBrQBKiqcPRZCaAxNUaar6
    //
    // uint256 internal constant X_PCT_RATE      = ;

    uint256 internal constant MILLION = 10 ** 6;
    uint256 internal constant BILLION = 10 ** 9;
    
    uint256 internal constant WAD     = 10 ** 18;

    uint256 internal constant ZERO_BASIS_POINTS = 0;
    uint256 internal constant ONE_BASIS_POINT   = 1 * WAD / 10000;

    address internal immutable MIP21_LIQUIDATION_ORACLE = DssExecLib.getChangelogAddress("MIP21_LIQUIDATION_ORACLE");
    address internal immutable MCD_PSM_USDC_A           = DssExecLib.getChangelogAddress("MCD_PSM_USDC_A");
    address internal immutable MCD_PSM_GUSD_A           = DssExecLib.getChangelogAddress("MCD_PSM_GUSD_A");
    address internal immutable MCD_PSM_PAX_A            = DssExecLib.getChangelogAddress("MCD_PSM_PAX_A");

    GemLike  internal immutable MKR                     = GemLike(DssExecLib.mkr());

    address constant internal LBSBLOCKCHAIN_WALLET      = 0xB83b3e9C8E3393889Afb272D354A7a3Bd1Fbcf5C;
    address constant internal CONSENSYS_WALLET          = 0xE78658A8acfE982Fde841abb008e57e6545e38b3;
    address constant internal SES_WALLET                = 0x87AcDD9208f73bFc9207e1f6F0fDE906bcA95cc6;
    address constant internal CES_WALLET                = 0x25307aB59Cd5d8b4E2C01218262Ddf6a89Ff86da;
    address constant internal PHOENIX_LABS_WALLET       = 0xD9847E6b1314f0327F320E43B51ca0AaAD6FF509;
    
    // Monetalis Update - Excess Funds Declaration
    // Poll:  https://vote.makerdao.com/polling/QmfZ2nxw#poll-details
    // Forum: https://forum.makerdao.com/t/request-to-poll-return-excess-mip65-funds-to-surplus-buffer/20115
    string constant public MIP65 = "Qmf7oGxgVoGKMGkzPi2T6nBSTLgrU5C7jmNqaefjJ52Zup";

    function actions() public override {

        // Uncleared Delegate Compensation
        // Poll:  https://vote.makerdao.com/polling/Qmd2W3Q4#poll-details
        // Forum: https://forum.makerdao.com/t/mip4c2-sp29-amend-mip61-to-tighten-up-recognized-delegate-participation-metrics/18696

        // London Business School Blockchain - 3126 DAI - 0xB83b3e9C8E3393889Afb272D354A7a3Bd1Fbcf5C
        DssExecLib.sendPaymentFromSurplusBuffer(LBSBLOCKCHAIN_WALLET,   3_126);
        // ConsenSys                         -  181 DAI - 0xE78658A8acfE982Fde841abb008e57e6545e38b3
        DssExecLib.sendPaymentFromSurplusBuffer(CONSENSYS_WALLET,         181);


        // SES-001 MKR Transfer
        // Poll:  https://vote.makerdao.com/polling/QmSmhV7z#poll-details
        // Forum: https://forum.makerdao.com/t/mip40c3-sp17-sustainable-ecosystem-scaling-core-unit-mkr-budget-ses-001/8043
        
        MKR.transfer(SES_WALLET, 229.78 ether);  // NOTE: 'ether' is a keyword helper, only MKR is transferred here

        // CES-001 MKR Transfer
        // Poll:  https://vote.makerdao.com/polling/QmbNVQ1E#poll-details
        // Forum: https://forum.makerdao.com/t/request-to-poll-one-time-mkr-distribution-to-correct-ces-001-incentive-program-shortfall/19326

        MKR.transfer(CES_WALLET, 77.34 ether);  // NOTE: 'ether' is a keyword helper, only MKR is transferred here


        // Phoenix Labs SPF DAI Funding
        // Poll:  https://vote.makerdao.com/polling/QmYBegVf#poll-details
        // Forum: https://forum.makerdao.com/t/mip55c3-sp15-phoenix-labs-initial-funding-spf/19733

        DssExecLib.sendPaymentFromSurplusBuffer(PHOENIX_LABS_WALLET, 50_000);


        // RETH-A Dust Adjustment from 15,000 DAI to 7,500 DAI
        // Poll:  https://vote.makerdao.com/polling/QmcLGa49#poll-details
        // Forum: https://forum.makerdao.com/t/adjusting-reth-a-dust-parameter-march-2023/20021

        DssExecLib.setIlkMinVaultAmount("RETH-A", 7_500);


        // Monetalis Update - Remove DC-IAM from RWA-007
        // Poll:  https://vote.makerdao.com/polling/QmRJSSGW#poll-details
        // Forum: https://forum.makerdao.com/t/request-to-poll-increase-debt-ceiling-for-mip65-by-750m-to-1-250m/20119
        
        DssExecLib.removeIlkFromAutoLine("RWA007-A");

        // Monetalis Update - Increase the MIP65 (RWA007-A) Debt Ceiling by 750M DAI from 500M DAI to 1,250M DAI
        // Poll:  https://vote.makerdao.com/polling/QmNTSr9j#poll-details
        // Forum: https://forum.makerdao.com/t/request-to-poll-increase-debt-ceiling-for-mip65-by-750m-to-1-250m/20119

        // Increase RWA007-A line by 750M DAI from 500M DAI to 1,250M DAI
        DssExecLib.increaseIlkDebtCeiling(
            "RWA007-A", 
            750 * MILLION,  // DC to 1,250M less existing 500M
            true            // Increase global Line
        );

        // Bump MIP21 Oracle's `val` to 1,250M as WAD (No need to calculate anything since the rate is 0%)
        RwaLiquidationLike_1(MIP21_LIQUIDATION_ORACLE).bump(
            "RWA007-A",
             1_250 * MILLION * WAD
        );

        // Update the RWA007-A `spot` value in Vat
        DssExecLib.updateCollateralPrice("RWA007-A");

        // PSM Parameter Normalization
        // Poll:  https://vote.makerdao.com/polling/QmQ1fYm3#poll-detail
        // Forum: https://forum.makerdao.com/t/signal-request-set-psm-fees-to-0/10894

        //PSM-USDC-A
        //Reduce the Fee In (tin) by 1% from 1% to 0%.
        DssExecLib.setValue(MCD_PSM_USDC_A, "tin", ZERO_BASIS_POINTS);
        //Increase the Target Available Debt (gap) by 150 million DAI from 250 million DAI to 400 million DAI.
        DssExecLib.setIlkAutoLineParameters("PSM-USDC-A", 10 * BILLION, 400 * MILLION, 24 hours);

        // PSM-GUSD-A
        // Reduce the Fee In (tin) by 0.1% from 0.1% to 0%.
        DssExecLib.setValue(MCD_PSM_GUSD_A, "tin", ZERO_BASIS_POINTS);
        // Increase the Fee Out (tout) by 0.01% from 0% to 0.01%.
        DssExecLib.setValue(MCD_PSM_GUSD_A, "tout", ONE_BASIS_POINT);
        // Increase the Target Available Debt (gap) by 40 million DAI from 10 million DAI to 50 million DAI.
        DssExecLib.setIlkAutoLineParameters("PSM-GUSD-A", 500 * MILLION, 50 * MILLION, 24 hours);

        // PSM-PAX-A
        // Reduce the Fee Out (tout) by 1% from 1% to 0%.
        DssExecLib.setValue(MCD_PSM_PAX_A, "tout", ZERO_BASIS_POINTS);
        // Reduce the Target Available Debt (gap) by 200 million DAI from 250 million DAI to 50 million DAI.
        // Reduce the Maximum Debt Ceiling (line) by 500 million DAI from 1 billion DAI to 500 million DAI.
        DssExecLib.setIlkAutoLineParameters("PSM-PAX-A", 500 * MILLION, 50 * MILLION, 24 hours);

    }
}

contract DssSpell is DssExec {
    constructor() DssExec(block.timestamp + 30 days, address(new DssSpellAction())) {}
}

