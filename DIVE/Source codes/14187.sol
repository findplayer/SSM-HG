// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

// OpenZeppelin Contracts (last updated v5.0.0) (utils/ReentrancyGuard.sol)
/**
 * @dev Contract module that helps prevent reentrant calls to a function.
 *
 * Inheriting from `ReentrancyGuard` will make the {nonReentrant} modifier
 * available, which can be applied to functions to make sure there are no nested
 * (reentrant) calls to them.
 *
 * Note that because there is a single `nonReentrant` guard, functions marked as
 * `nonReentrant` may not call one another. This can be worked around by making
 * those functions `private`, and then adding `external` `nonReentrant` entry
 * points to them.
 *
 * TIP: If you would like to learn more about reentrancy and alternative ways
 * to protect against it, check out our blog post
 * https://blog.openzeppelin.com/reentrancy-after-istanbul/[Reentrancy After Istanbul].
 */
abstract contract ReentrancyGuard {
    // Booleans are more expensive than uint256 or any type that takes up a full
    // word because each write operation emits an extra SLOAD to first read the
    // slot's contents, replace the bits taken up by the boolean, and then write
    // back. This is the compiler's defense against contract upgrades and
    // pointer aliasing, and it cannot be disabled.

    // The values being non-zero value makes deployment a bit more expensive,
    // but in exchange the refund on every call to nonReentrant will be lower in
    // amount. Since refunds are capped to a percentage of the total
    // transaction's gas, it is best to keep them low in cases like this one, to
    // increase the likelihood of the full refund coming into effect.
    uint256 private constant NOT_ENTERED = 1;
    uint256 private constant ENTERED = 2;

    uint256 private _status;

    /**
     * @dev Unauthorized reentrant call.
     */
    error ReentrancyGuardReentrantCall();

    constructor() {
        _status = NOT_ENTERED;
    }

    /**
     * @dev Prevents a contract from calling itself, directly or indirectly.
     * Calling a `nonReentrant` function from another `nonReentrant`
     * function is not supported. It is possible to prevent this from happening
     * by making the `nonReentrant` function external, and making it call a
     * `private` function that does the actual work.
     */
    modifier nonReentrant() {
        _nonReentrantBefore();
        _;
        _nonReentrantAfter();
    }

    function _nonReentrantBefore() private {
        // On the first call to nonReentrant, _status will be NOT_ENTERED
        if (_status == ENTERED) {
            revert ReentrancyGuardReentrantCall();
        }

        // Any calls to nonReentrant after this point will fail
        _status = ENTERED;
    }

    function _nonReentrantAfter() private {
        // By storing the original value once again, a refund is triggered (see
        // https://eips.ethereum.org/EIPS/eip-2200)
        _status = NOT_ENTERED;
    }

    /**
     * @dev Returns true if the reentrancy guard is currently set to "entered", which indicates there is a
     * `nonReentrant` function in the call stack.
     */
    function _reentrancyGuardEntered() internal view returns (bool) {
        return _status == ENTERED;
    }
}

// OpenZeppelin Contracts (last updated v5.0.0) (utils/Address.sol)
/**
 * @dev Collection of functions related to the address type
 */
library Address {
    /**
     * @dev The ETH balance of the account is not enough to perform the operation.
     */
    error AddressInsufficientBalance(address account);

    /**
     * @dev There's no code at `target` (it is not a contract).
     */
    error AddressEmptyCode(address target);

    /**
     * @dev A call to an address target failed. The target may have reverted.
     */
    error FailedInnerCall();

    /**
     * @dev Replacement for Solidity's `transfer`: sends `amount` wei to
     * `recipient`, forwarding all available gas and reverting on errors.
     *
     * https://eips.ethereum.org/EIPS/eip-1884[EIP1884] increases the gas cost
     * of certain opcodes, possibly making contracts go over the 2300 gas limit
     * imposed by `transfer`, making them unable to receive funds via
     * `transfer`. {sendValue} removes this limitation.
     *
     * https://consensys.net/diligence/blog/2019/09/stop-using-soliditys-transfer-now/[Learn more].
     *
     * IMPORTANT: because control is transferred to `recipient`, care must be
     * taken to not create reentrancy vulnerabilities. Consider using
     * {ReentrancyGuard} or the
     * https://solidity.readthedocs.io/en/v0.8.20/security-considerations.html#use-the-checks-effects-interactions-pattern[checks-effects-interactions pattern].
     */
    function sendValue(address payable recipient, uint256 amount) internal {
        if (address(this).balance < amount) {
            revert AddressInsufficientBalance(address(this));
        }

        (bool success, ) = recipient.call{value: amount}("");
        if (!success) {
            revert FailedInnerCall();
        }
    }

    /**
     * @dev Performs a Solidity function call using a low level `call`. A
     * plain `call` is an unsafe replacement for a function call: use this
     * function instead.
     *
     * If `target` reverts with a revert reason or custom error, it is bubbled
     * up by this function (like regular Solidity function calls). However, if
     * the call reverted with no returned reason, this function reverts with a
     * {FailedInnerCall} error.
     *
     * Returns the raw returned data. To convert to the expected return value,
     * use https://solidity.readthedocs.io/en/latest/units-and-global-variables.html?highlight=abi.decode#abi-encoding-and-decoding-functions[`abi.decode`].
     *
     * Requirements:
     *
     * - `target` must be a contract.
     * - calling `target` with `data` must not revert.
     */
    function functionCall(address target, bytes memory data) internal returns (bytes memory) {
        return functionCallWithValue(target, data, 0);
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`],
     * but also transferring `value` wei to `target`.
     *
     * Requirements:
     *
     * - the calling contract must have an ETH balance of at least `value`.
     * - the called Solidity function must be `payable`.
     */
    function functionCallWithValue(address target, bytes memory data, uint256 value) internal returns (bytes memory) {
        if (address(this).balance < value) {
            revert AddressInsufficientBalance(address(this));
        }
        (bool success, bytes memory returndata) = target.call{value: value}(data);
        return verifyCallResultFromTarget(target, success, returndata);
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`],
     * but performing a static call.
     */
    function functionStaticCall(address target, bytes memory data) internal view returns (bytes memory) {
        (bool success, bytes memory returndata) = target.staticcall(data);
        return verifyCallResultFromTarget(target, success, returndata);
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`],
     * but performing a delegate call.
     */
    function functionDelegateCall(address target, bytes memory data) internal returns (bytes memory) {
        (bool success, bytes memory returndata) = target.delegatecall(data);
        return verifyCallResultFromTarget(target, success, returndata);
    }

    /**
     * @dev Tool to verify that a low level call to smart-contract was successful, and reverts if the target
     * was not a contract or bubbling up the revert reason (falling back to {FailedInnerCall}) in case of an
     * unsuccessful call.
     */
    function verifyCallResultFromTarget(
        address target,
        bool success,
        bytes memory returndata
    ) internal view returns (bytes memory) {
        if (!success) {
            _revert(returndata);
        } else {
            // only check if target is a contract if the call was successful and the return data is empty
            // otherwise we already know that it was a contract
            if (returndata.length == 0 && target.code.length == 0) {
                revert AddressEmptyCode(target);
            }
            return returndata;
        }
    }

    /**
     * @dev Tool to verify that a low level call was successful, and reverts if it wasn't, either by bubbling the
     * revert reason or with a default {FailedInnerCall} error.
     */
    function verifyCallResult(bool success, bytes memory returndata) internal pure returns (bytes memory) {
        if (!success) {
            _revert(returndata);
        } else {
            return returndata;
        }
    }

    /**
     * @dev Reverts with returndata if present. Otherwise reverts with {FailedInnerCall}.
     */
    function _revert(bytes memory returndata) private pure {
        // Look for revert reason and bubble it up if present
        if (returndata.length > 0) {
            // The easiest way to bubble the revert reason is using memory via assembly
            /// @solidity memory-safe-assembly
            assembly {
                let returndata_size := mload(returndata)
                revert(add(32, returndata), returndata_size)
            }
        } else {
            revert FailedInnerCall();
        }
    }
}

// Защита от повторных вызовов)
// Защита для отправки средств)
// Смарт-Контракт СУС - (У) - Система Утилизации Средств)
// Полностью автоматизирован - без каких-либо вмешиваний со стороны - даже владельца)
// Вы делаете оплату на смарт-контракт и через какое-то время вам частями посылается 150% вашей оплаты вместе с комиссией)
// Работает цепочка очереди - всем по очереди выплачиваются 150% от суммы собственного платежа)
// Каждый вошедший через автоматизацию платит тем - кто вначале очереди - и до каждого из вас рано или поздно дойдёт очередь выплаты вам 150%)
// Есть комиссия - 3% владельцу - 1% на баланс смарт-контракта для бонусов - 5% по 1% на 5 уровней ниже)
// Со временеи на балансе в итоге будут набираться излишние суммы - и они будут добавляться к первым 2-м уровням в виде бонуса +0.5 эфира)
contract SUS is ReentrancyGuard {

    address public owner;   //владелец)
    using Address for address payable;  // безопасные выплаты)
    // события утилизации при получении и отправлении средств)
    event UtilizeReceived(address indexed sender, uint256 value, uint256 indexed level, uint256 queueIndex);
    event UtilizePayOut(address indexed sender, uint256 value, uint256 indexed level, uint256 queueIndex);
    // структура луча из адреса и утилизационных средств)
    struct Ray {
        address addr;
        uint256 utilize;
    }
    // структура внутренних данных диапазонов луча)
    struct Range {
        // первый и последний индекс для диапазона очереди)
        uint256 firstIndex;
        uint256 lastIndex;        
        uint256 leftFunds;  // оставшиеся средства до 150%        
        uint256 currentFunds;   // текущие средства
    }

    mapping(uint256 => Range) public range; // диапазон - массив внутренних данных)
    // луч - массив уровней и в нём внутренний массив очереди этого уровня по индексам)
    mapping(uint256 => mapping(uint256 => Ray)) public ray;
    
    uint256 public sumFunds; // максимальное значение текущих средств)

    // Константы)
    uint256 private constant MAX_ITERATIONS = 24;    
    uint256 private constant GAS_PER_ITERATION = 178000;
    uint256 private constant GAS_MIN_UTILIZE = 387100;
    uint256 private constant GAS_POSSIBLE_FEE = 141780;
    uint256 private constant BONUS = 500000000 gwei;

    // конструктор - выполнится только 1 раз при создании смарт-контракта)
    constructor() {
        // устанавливаем владельца как создателя контракта)
        owner = msg.sender;
        // сразу устанавливаем первые индексы и владельца в начало очереди)
        ray[0][0] = Ray(msg.sender, 8710000 gwei);
        ray[1][0] = Ray(msg.sender, 18781000 gwei);
        ray[2][0] = Ray(msg.sender, 87178000 gwei);
        ray[3][0] = Ray(msg.sender, 871780000 gwei);
        ray[4][0] = Ray(msg.sender, 8717800000 gwei);
        ray[5][0] = Ray(msg.sender, 87178000000 gwei);
        ray[6][0] = Ray(msg.sender, 871780000000 gwei);
        ray[7][0] = Ray(msg.sender, 8717800000000 gwei);
        ray[8][0] = Ray(msg.sender, 87178000000000 gwei);
        ray[9][0] = Ray(msg.sender, 871780000000000 gwei);        
        // выставляем последние индексы (не нужно если изначально в очереди только 1 участник)
        // range[0].lastIndex = 1;        
    }

    // функция для приема утилизационных транзакций)
    receive() external payable nonReentrant {

        // если меньше или равно 0.000871 ether - тогда просто оставляем средства на балансе)
        if (msg.value > 871000 gwei) {

            uint256 level;  // уровни)
            uint256 gasPrice = tx.gasprice;     // цена газа)
            // сразу же к утилизированным средствам добавляем примерную комиссию по газу)
            // это делается для того - чтобы сразу сменить уровень на +1 - если утилизация + комиссия выходит за рамки диапазона уровня)
            uint256 value = msg.value + GAS_PER_ITERATION * gasPrice;   // значение утилизированных средств плюс комиссия)

            // распеределение по уровням от 0.000871 ether и кратное 10)
            if (value <= 8710000 gwei) { // (0) > 0.000871 <= 0.00871 ether (4-0)
                level = 0;
            } else if (value <= 87100000 gwei) {    // (1) > 0.00871 <= 0.0871 ether (5-0)
                level = 1;
            } else if (value <= 871000000 gwei) {   // (2) > 0.0871 <= 0.871 ether (6-0)
                level = 2;
            } else if (value <= 8710000000 gwei) {  // (3) > 0.871 <= 8.71 ether (7-0)
                level = 3;
            } else if (value <= 87100000000 gwei) { // (4) > 8.71 <= 87.1 ether (8-0)
                level = 4;
            } else if (value <= 871000000000 gwei) {    // (5) > 87.1 <= 871 ether (9-0)
                level = 5;
            } else if (value <= 8710000000000 gwei) {   // (6) > 871 <= 8710 ether (10-0)
                level = 6;
            } else if (value <= 87100000000000 gwei) {  // (7) > 8710 <= 87100 ether (11-0)
                level = 7;
            } else if (value <= 871000000000000 gwei) { // (8) > 87100 <= 871000 ether (12-0)
                level = 8;
            } else if (value <= 8710000000000000 gwei) {    // (9) > 871000 <= 8710000 ether (13-0)
                level = 9;
            } else {
                // возврат средств - если они выше 8710000 ether)
                address payable receiver = payable(msg.sender);
                Address.sendValue(receiver, msg.value); // безопасно отправляем значение)
                return;
            }

            // если утилизация слишком мала с учётом возможной комиссии - тогда просто добавляем в очередь и завершаем)
            if (msg.value < GAS_MIN_UTILIZE * gasPrice) { // 387100)
                
                // возможная комиссия - на добавление в очередь)
                uint256 gasCost = GAS_POSSIBLE_FEE * gasPrice;  // 141780)
                
                range[level].lastIndex++;
                // утилизационные средства плюс возможная комиссия)
                value = msg.value + gasCost;
                // в текущие средства данного уровня добавляем только утилизационные средства)
                range[level].currentFunds += msg.value;
                // в общую сумму добавляем только утилизационные средства)
                sumFunds += msg.value;

                // в конец очереди текущего уровня добавляем этого участника)
                ray[level][range[level].lastIndex] = Ray({addr: msg.sender, utilize: value});
                emit UtilizeReceived(msg.sender, value, level, range[level].lastIndex);

            } else {    //в остальных случаях выполняем логику)
                processUtilize(msg.value, gasPrice, level);
            }

        }

    }
    
    // процесс утилизации и распределения в очередь)
    function processUtilize(uint256 value, uint256 gasPrice, uint256 level) private {

        uint256 maxCounter;
        uint256 counterIt = 1;        
        uint256 gasCost;
        uint256 levelFee;
        uint256 lowerLevelFee = value / 100; // комиссия 1%)
        uint256 ownerFee = 0;
        uint256 leftCur = range[level].leftFunds; // сколько осталось доплатить первому участнику в очереди)
        uint256 valueMsg;

        // убираем комиссию владельцу 3% на 0 и 1 уровне)
        if (level > 1) {
            ownerFee = calculateFee(value, 3); // 3% переводится владельцу)
            address payable _owner = payable(owner);
            Address.sendValue(_owner, ownerFee);
        }        

        // на 5 нижних уровней к текущим средствам прибавляется значение 1% - с условием - чтобы не спуститься ниже нулевого уровня)
        for (uint256 i = 1; i <= 5 && level > 1 && level >= i; i++) {
            levelFee += lowerLevelFee;
            range[level - i].currentFunds += lowerLevelFee;
        }

        // текущая сумма всех вложений - минус комиссия владельцу и 1% на баланс)
        sumFunds += value - lowerLevelFee - ownerFee;

        // текущие средства плюс оставшаяся сумма)        
        value = value - ownerFee - levelFee - lowerLevelFee;       

        // вычисляем максимальное количество итераций)
        maxCounter = calculateMaxIterations(msg.value, gasPrice);
        range[level].lastIndex++;   // инкремент крайнего индекса)

        // добавляем текущие средства)
        value += range[level].currentFunds;
        // вычисляем примерную комиссию - точную вычислить не получится - из-за ранего добавления в очередь)
        gasCost = maxCounter * GAS_PER_ITERATION * gasPrice;

        // комиссия по газу плюс утилизационные средства)
        valueMsg = msg.value + gasCost;

        // добавляем в конец очереди текущего участника)
        ray[level][range[level].lastIndex] = Ray({addr: msg.sender, utilize: valueMsg});
        // записываем в событие UtilizeReceived)
        emit UtilizeReceived(msg.sender, valueMsg, level, range[level].lastIndex);

        // если остаток был весь погашен предыдущему участнику - то для нового выставляем опять 150% его значению утилизации)
        if (leftCur == 0) {
            leftCur = calculate150(ray[level][range[level].firstIndex].utilize);
        }

        // выплата по текущему уровню и ниже по уровням - пока хватает итераций)
        for (uint256 i = 0; level >= i && counterIt < maxCounter; i++) {
            
            // процесс выплаты)
            counterIt = processPayOut(value, sumFunds, leftCur, level - i, counterIt, maxCounter);

            if (counterIt < maxCounter && level - i > 0) {
                uint256 levelDown = level - i - 1;
                value = range[levelDown].currentFunds;
                leftCur = range[levelDown].leftFunds;
            }

        }

    }

    // процесс выплаты)
    function processPayOut(uint256 value, uint256 sumF, uint256 leftCur, uint256 level, uint256 counterIt, uint256 maxCounter) private returns (uint256) {

        // делаем выплату всем участникам по очереди - по текущему индексу - с учётом текущих средств)
        while (counterIt < maxCounter && value >= leftCur && range[level].firstIndex <= range[level].lastIndex) {

            value -= leftCur;
            // проверка - чтобы не выйти за границы диапазона и тем самым не выдало ошибку)
            sumF = sumF > leftCur ? sumF - leftCur : 0;

            // если индекс равен 0 или 1 и газ больше или равно 1 эфиру - избыток газа идёт в бонус)
            // бонус первым двум уровням +0.5 эфира - и не важно сколько было утилизировано)
            if ( level < 2 && address(this).balance > sumF  && address(this).balance - sumF >= 1 ether) {
                leftCur += BONUS; // 0.5 ether
            }

            address payable receivePayout = payable(ray[level][range[level].firstIndex].addr);
            Address.sendValue(receivePayout, leftCur); // безопасно отправляем значение)
            // записываем в событие UtilizePayOut)
            emit UtilizePayOut(ray[level][range[level].firstIndex].addr, leftCur, level, range[level].firstIndex);
            // если выплата произведена полностью - то удаляем первого участника из очереди)
            delete ray[level][range[level].firstIndex];
            range[level].firstIndex++;
            counterIt++;

            // сразу же задаём оставшееся значение следующему участнику равное 150% его утилизационным средствам)
            // и проверка - что в очереди кто-то есть ещё)
            if (range[level].firstIndex <= range[level].lastIndex) {
                leftCur = calculate150(ray[level][range[level].firstIndex].utilize);
            } else {
                leftCur = 0;
            }

        }

        // если общая сумма выплаты участнику ещё не достигла 150% - всё равно выплачиваем часть - что осталось в текущих средствах)
        if (counterIt < maxCounter && range[level].firstIndex <= range[level].lastIndex) {

            // проверка - чтобы не выйти за границы диапазона и тем самым не выдало ошибку)
            leftCur = leftCur > value ? leftCur - value : 0;

            // проверка - чтобы не выйти за границы диапазона и тем самым не выдало ошибку)
            sumF = sumF > value ? sumF - value : 0;

            // первым двум уровням бонус +0.5 эфир - если на балансе выше 1 эфира)
            if (level < 2 && address(this).balance > sumF && address(this).balance - sumF >= 1 ether) {
                value += BONUS;
            }

            address payable receivePayoutLeft = payable(ray[level][range[level].firstIndex].addr);
            Address.sendValue(receivePayoutLeft, value); // безопасно отправляем средства)                    
            // записываем в событие UtilizePayOut)
            emit UtilizePayOut(ray[level][range[level].firstIndex].addr, value, level, range[level].firstIndex);

            // если первому в очереди произведена вся оплата и оставшихся средств не осталось - тогда удаляем его из очереди)
            if (leftCur == 0) {
                delete ray[level][range[level].firstIndex];
                range[level].firstIndex++;
            }

            counterIt++;
            value = 0;  // так как мы выплатили остаток - который был в текущих средствах - поэтому значение делаем в ноль)

        }

        // сохраняем нужные нам значения по текущим и оставшимся средствам)
        range[level].currentFunds = value;        
        range[level].leftFunds = leftCur;

        sumFunds = sumF;    // Общая сумма текущих средств по всем уровням)
        return counterIt;   // возвращаем текущее количество пройденных итераций)

    }

    // баланс)
    function getBalance() public view returns (uint256) {
        return address(this).balance;
    }

    function calculateFee(uint256 value, uint256 fee) private pure returns (uint256) {
        return value * fee / 100; // расчёт комиссии fee%)
    }
    // вычисление 150%)
    function calculate150(uint256 value) private pure returns (uint256) {
        return value * 3 / 2; // 150%)
    }
    // вычисление количества итераций)
    function calculateMaxIterations(uint256 value, uint256 gasPrice) private pure returns (uint256) {

        // проверка - чтобы не было деления на ноль)
        if (gasPrice == 0) {
            gasPrice = 1 gwei;
        }
        
        uint256 gasAmount = value / gasPrice;
        uint256 possibleIterations = gasAmount / GAS_PER_ITERATION;
        
        if (possibleIterations > MAX_ITERATIONS) {
            return MAX_ITERATIONS;  // возвращаем максимум)
        } else {
            return possibleIterations;  // возвращаем сколько получилось)
        }

    }

    // считывание данных из массива по индексу уровня и заданному диапазону)
    function getRayData(uint8 level, uint256 from, uint256 to) public view returns (Ray[] memory) {
        
        if (from < range[level].firstIndex || from > range[level].lastIndex) {
            from = range[level].firstIndex;
        }
        if (to < range[level].firstIndex || to > range[level].lastIndex) {
            to = range[level].lastIndex;
        }
        
        Ray[] memory result;
        // проверка на присутствие данных)
        if (from <= to) {

            result = new Ray[](to - from + 1);
            for (uint256 i = from; i <= to; i++) {
                result[i - from] = ray[level][i];
            }
        }
        
        return result;

    }
    
}