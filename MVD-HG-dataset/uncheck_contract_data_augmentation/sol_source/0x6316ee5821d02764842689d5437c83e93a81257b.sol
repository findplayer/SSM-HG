pragma solidity 0.4.24;




library Address {







    function isContract(address account) internal view returns (bool) {
        uint256 size;
        
        
        
        
        
        
        
        assembly { size := extcodesize(account) }
        return size > 0;
    }
}
















contract Ownable {
    address private _owner;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);





    constructor () internal {
        _owner = msg.sender;
        emit OwnershipTransferred(address(0), _owner);
    }




    function owner() public view returns (address) {
        return _owner;
    }




    modifier onlyOwner() {
        require(isOwner());
        _;
    }




    function isOwner() public view returns (bool) {
        return msg.sender == _owner;
    }







    function renounceOwnership() public onlyOwner {
        emit OwnershipTransferred(_owner, address(0));
        _owner = address(0);
    }





    function transferOwnership(address newOwner) public onlyOwner {
        _transferOwnership(newOwner);
    }





    function _transferOwnership(address newOwner) internal {
        require(newOwner != address(0));
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }
}













contract ContractManager is Ownable {

    event VersionAdded(
        string contractName,
        string versionName,
        address indexed implementation
    );

    event StatusChanged(
        string contractName,
        string versionName,
        Status status
    );

    event BugLevelChanged(
        string contractName,
        string versionName,
        BugLevel bugLevel
    );

    event VersionAudited(string contractName, string versionName);

    event VersionRecommended(string contractName, string versionName);

    event RecommendedVersionRemoved(string contractName);




    enum Status {BETA, RC, PRODUCTION, DEPRECATED}




    enum BugLevel{NONE, LOW, MEDIUM, HIGH, CRITICAL}




    struct Version {
        string versionName; 
        Status status;
        BugLevel bugLevel;
        address implementation;
        bool audited;
        uint256 timeAdded;
    }




    string[] internal _contracts;





    mapping(string => bool) internal _contractExists;




    mapping(string => string[]) internal _contractVsVersionString;




    mapping(string => mapping(string => Version)) internal _contractVsVersions;





    mapping(string => string) internal _contractVsRecommendedVersion;

    modifier nonZeroAddress(address _address){
        require(_address != address(0), "The provided address is a 0 address");
        _;
    }

    modifier contractRegistered(string contractName) {

        require(_contractExists[contractName], "Contract does not exists");
        _;
    }

    modifier versionExists(string contractName, string versionName) {
        require(
            _contractVsVersions[contractName][versionName].implementation != address(0),
            "Version does not exists for contract"
        );
        _;
    }








    function addVersion(
        string contractName,
        string versionName,
        Status status,
        address implementation
    )
        external
        onlyOwner
        nonZeroAddress(implementation)
    {

        
        require(
            bytes(contractName).length > 0,
            "ContractName cannot be empty"
        );

        
        require(
            bytes(versionName).length > 0,
            "VersionName cannot be empty"
        );

        
        require(
            Address.isContract(implementation),
            "Iimplementation cannot be a non-contract address"
        );

        
        require(
            _contractVsVersions[contractName][versionName].implementation == address(0),
            "This Version already exists for this contract"
        );

        
        if (!_contractExists[contractName]) {
            _contracts.push(contractName);
            _contractExists[contractName] = true;
        }

        _contractVsVersionString[contractName].push(versionName);

        _contractVsVersions[contractName][versionName] = Version({
            versionName:versionName,
            status:status,
            bugLevel:BugLevel.NONE,
            implementation:implementation,
            audited:false,
            timeAdded:block.timestamp
        });

        emit VersionAdded(contractName, versionName, implementation);
    }







    function changeStatus(
        string contractName,
        string versionName,
        Status status
    )
        external
        onlyOwner
        contractRegistered(contractName)
        versionExists(contractName, versionName)
    {
        string storage recommendedVersion = _contractVsRecommendedVersion[
            contractName
        ];

        
        
        if (
            keccak256(
                abi.encodePacked(
                    recommendedVersion
                )
            ) == keccak256(
                abi.encodePacked(
                    versionName
                )
            ) && status == Status.DEPRECATED
        )
        {
            removeRecommendedVersion(contractName);
        }

        _contractVsVersions[contractName][versionName].status = status;

        emit StatusChanged(contractName, versionName, status);
    }







    function changeBugLevel(
        string contractName,
        string versionName,
        BugLevel bugLevel
    )
        external
        onlyOwner
        contractRegistered(contractName)
        versionExists(contractName, versionName)
    {
        string storage recommendedVersion = _contractVsRecommendedVersion[
            contractName
        ];

        
        
        
        if (
            keccak256(
                abi.encodePacked(
                    recommendedVersion
                )
            ) == keccak256(
                abi.encodePacked(
                    versionName
                )
            ) && bugLevel == BugLevel.CRITICAL
        )
        {
            removeRecommendedVersion(contractName);
        }

        _contractVsVersions[contractName][versionName].bugLevel = bugLevel;

        emit BugLevelChanged(contractName, versionName, bugLevel);
    }






    function markVersionAudited(
        string contractName,
        string versionName
    )
        external
        contractRegistered(contractName)
        versionExists(contractName, versionName)
        onlyOwner
    {
        
        require(
            !_contractVsVersions[contractName][versionName].audited,
            "Version is already audited"
        );

        _contractVsVersions[contractName][versionName].audited = true;

        emit VersionAudited(contractName, versionName);
    }









    function markRecommendedVersion(
        string contractName,
        string versionName
    )
        external
        onlyOwner
        contractRegistered(contractName)
        versionExists(contractName, versionName)
    {
        
        require(
            _contractVsVersions[contractName][versionName].status == Status.PRODUCTION,
            "Version is not in PRODUCTION state (status level should be 2)"
        );

        
        require(
            _contractVsVersions[contractName][versionName].audited,
            "Version is not audited"
        );

        
        require(
            _contractVsVersions[contractName][versionName].bugLevel < BugLevel.HIGH,
            "Version bug level is HIGH or CRITICAL (bugLevel should be < 3)"
        );

        
        _contractVsRecommendedVersion[contractName] = versionName;

        emit VersionRecommended(contractName, versionName);
    }





    function getRecommendedVersion(
        string contractName
    )
        external
        view
        contractRegistered(contractName)
        returns (
            string versionName,
            Status status,
            BugLevel bugLevel,
            address implementation,
            bool audited,
            uint256 timeAdded
        )
    {
        versionName = _contractVsRecommendedVersion[contractName];

        Version storage recommendedVersion = _contractVsVersions[
            contractName
        ][
            versionName
        ];

        status = recommendedVersion.status;
        bugLevel = recommendedVersion.bugLevel;
        implementation = recommendedVersion.implementation;
        audited = recommendedVersion.audited;
        timeAdded = recommendedVersion.timeAdded;

        return (
            versionName,
            status,
            bugLevel,
            implementation,
            audited,
            timeAdded
        );
    }




    function getTotalContractCount() external view returns (uint256 count) {
        count = _contracts.length;
        return count;
    }





    function getVersionCountForContract(string contractName)
        external
        view
        returns (uint256 count)
    {
        count = _contractVsVersionString[contractName].length;
        return count;
    }





    function getContractAtIndex(uint256 index)
        external
        view
        returns (string contractName)
    {
        contractName = _contracts[index];
        return contractName;
    }






    function getVersionAtIndex(string contractName, uint256 index)
        external
        view
        returns (string versionName)
    {
        versionName = _contractVsVersionString[contractName][index];
        return versionName;
    }






    function getVersionDetails(string contractName, string versionName)
        external
        view
        returns (
            string versionString,
            Status status,
            BugLevel bugLevel,
            address implementation,
            bool audited,
            uint256 timeAdded
        )
    {
        Version storage v = _contractVsVersions[contractName][versionName];

        versionString = v.versionName;
        status = v.status;
        bugLevel = v.bugLevel;
        implementation = v.implementation;
        audited = v.audited;
        timeAdded = v.timeAdded;

        return (
            versionString,
            status,
            bugLevel,
            implementation,
            audited,
            timeAdded
        );
    }






    function removeRecommendedVersion(string contractName)
        public
        onlyOwner
        contractRegistered(contractName)
    {
        
        delete _contractVsRecommendedVersion[contractName];

        emit RecommendedVersionRemoved(contractName);
    }
}