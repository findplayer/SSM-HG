// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/*
 * @title ENS Look Up
 * @author 0xSumo
 */

interface IReverseRegistrar {
    function node(address addr) external view returns (bytes32);
}

interface IReverseResolver {
    function name(bytes32 resolver) external view returns (string memory);
}

contract ENSLookup {

    IReverseRegistrar public ENSReverseRegistrar = IReverseRegistrar(0x084b1c3C81545d370f3634392De611CaaBFf8148);
    IReverseResolver public ENSReverseResolver = IReverseResolver(0xA2C122BE93b0074270ebeE7f6b7292C7deB45047);

    function ensLookup(address[] calldata addresses_) external view returns (string[] memory) {
        uint256 l = addresses_.length;
        string[] memory _batchENS = new string[] (l);
        uint256 i; unchecked { do {
            bytes32 _registrar = ENSReverseRegistrar.node(addresses_[i]);
            string memory _ens = ENSReverseResolver.name(_registrar);
            _batchENS[i] = _ens;
        } while (++i < l); }
        return _batchENS;
    }

    function registrarLookup(address[] calldata addresses_) public view returns (bytes32[] memory) {
        uint256 l = addresses_.length;
        bytes32[] memory _batchRegistrar = new bytes32[] (l);
        uint256 i; unchecked { do {
            bytes32 _registrar = ENSReverseRegistrar.node(addresses_[i]);
            _batchRegistrar[i] = _registrar;
        } while (++i < l); }
        return _batchRegistrar;
    }

    function hasENS(address addr) external view returns (bool) {
        bytes32 _registrar = ENSReverseRegistrar.node(addr);
        if (_registrar == 0x0) { return false; }
        string memory _ens = ENSReverseResolver.name(_registrar);
        if (bytes(_ens).length == 0) { return false; }
        return true;
    }
}