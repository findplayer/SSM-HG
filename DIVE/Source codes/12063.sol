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

//Защита от повторных вызовов)
//Защита для отправки средств)
//Смарт-Контракт СУС - (У) - Система Утилизации Средств)
//Полностью автоматизирован - без каких-либо вмешиваний со стороны - даже владельца)
//Вы делаете оплату на смарт-контракт и через какое-то время вам частями посылается 150% вашей оплаты)
//Вам сразу же возвращаются затраты по газу на логику смарт-контракта)
//Работает цепочка очереди - всем по очереди выплачиваются 150% от суммы собственного платежа)
//Каждый вошедший через автоматизацию платит тем - кто вначале очереди - и до каждого из вас рано или поздно дойдёт очередь выплаты вам 150%)
//Есть комиссия 3% владельцу и 1% для погашения затрат на газ внутри сети для смарт-контракта)
//В итоге при получении утилизационных средств из 100% получается минус 1% на газ - минус 3% владельцу = 96%)
//А также ещё минус 5% по 1% на 5 уровней ниже - чтобы быстрее им производилась оплата)
//Сразу идёт выплата 96%-91% тому кто находится первым в очереди на том же уровне)
//Также следующие 96%-91% уже покроют 150% первого в очереди - а остаток пойдёт на следующего в очереди - если хватит газа)
//На газ в итоге будут набираться излишние суммы - и они будут добавляться к первым 3-м уровням в виде бонуса +0.5 эфира)
contract SUS is ReentrancyGuard {

    //владелец)
    address public owner;
    //безопасные call
    using Address for address payable;
    //события утилизации при получении и отправлении средств)
    event UtilizeReceived(address indexed sender, uint256 value, uint256 indexed index, uint256 queueIndex);
    event UtilizePayOut(address indexed sender, uint256 value, uint256 indexed index, uint256 queueIndex);
    //структура луча из адреса и утилизационных средств)
    struct Ray {
        address addr;
        uint256 utilize;
    }
    //структура внутренних данных диапазонов луча)
    struct Range {
        //первый и последний индекс для диапазона очереди)
        uint256 firstIndex;
        uint256 lastIndex;
        //оставшиеся средства до 150%
        uint256 leftFunds;
        //текущие средства
        uint256 currentFunds;
    }

    //луч - массив уровней и в нём внутренний массив очереди этого уровня по индексам)
    mapping(uint256 => mapping(uint256 => Ray)) public ray;
    //диапазон - массив внутренних данных)
    mapping(uint256 => Range) public range;
    //максимальное значение текущих средств)
    uint256 public sumFunds;
    //счётчик выплат)
    uint256 private counterIt;

    //Конструктор - выполнится только 1 раз при создании смарт-контракта)
    constructor() {
        //устанавливаем владельца как создателя контракта)
        owner = msg.sender;
        //сразу устанавливаем первые индексы и владельца в начало очереди)
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
        //выставляем последние индексы (не нужно если изначально в очереди только 1 участник)
        //range[0].lastIndex = 1;        
    }

    // Функция для приема утилизационных транзакций)
    receive() external payable nonReentrant {

        //если меньше или равно 0.000871 ether - тогда просто оставляем средства на балансе для газа)        
        if (msg.value > 871000 gwei) {
            uint256 level;
            //распеределение по уровням от 0.000871 ether и кратное 10)       
            if (msg.value <= 8710000 gwei) { //(0) > 0.000871 <= 0.00871 ether (4-0)
                level = 0;
            } else if (msg.value <= 87100000 gwei) {    //(1) > 0.00871 <= 0.0871 ether (5-0)
                level = 1;
            } else if (msg.value <= 871000000 gwei) {   //(2) > 0.0871 <= 0.871 ether (6-0)
                level = 2;
            } else if (msg.value <= 8710000000 gwei) {  //(3) > 0.871 <= 8.71 ether (7-0)
                level = 3;
            } else if (msg.value <= 87100000000 gwei) { //(4) > 8.71 <= 87.1 ether (8-0)
                level = 4;
            } else if (msg.value <= 871000000000 gwei) {    //(5) > 87.1 <= 871 ether (9-0)
                level = 5;
            } else if (msg.value <= 8710000000000 gwei) {   //(6) > 871 <= 8710 ether (10-0)
                level = 6;
            } else if (msg.value <= 87100000000000 gwei) {  //(7) > 8710 <= 87100 ether (11-0)
                level = 7;
            } else if (msg.value <= 871000000000000 gwei) { //(8) > 87100 <= 871000 ether (12-0)
                level = 8;
            } else if (msg.value <= 8710000000000000 gwei) {    //(9) > 871000 <= 8710000 ether (13-0)
                level = 9;            
            } else {
                //возврат средств - если они выше 8710000 ether)
                address payable receiver = payable(msg.sender);
                Address.sendValue(receiver, msg.value); //Безопасно отправляем значение)
                return;
            }
            processUtilize(msg.value, gasleft(), level);

        }
        
    }
    
    //процесс утилизации и распеределение в очередь)
    function processUtilize(uint256 value, uint256 gasAtStart, uint256 index) private {
        
        range[index].lastIndex++;
        //сразу добавляем в конец очереди нового участника)
        ray[index][range[index].lastIndex] = Ray({addr: msg.sender, utilize: value});
        emit UtilizeReceived(msg.sender, value, index, range[index].lastIndex);
      
        uint256 lowerLevelFee = calculateFee(value, 1); // по 1% на 5 уровней ниже)
        uint256 ownerFee = 0;

        //убрать комиссию владельцу 3% на 0 и 1 уровне)
        if (index > 1) {
            ownerFee = calculateFee(value, 3); // 3% переводится владельцу)

            address payable _owner = payable(owner);
            Address.sendValue(_owner, ownerFee);
        }
    
        uint256 levelFee = 0;
        uint256 currentGas;

        bool checkInd = true;

        //храним цену газа за 1 цикл)
        //значение цены газа передаётся через того - кто утилизировал средства)
        uint256 gasCheck = tx.gasprice * 87100;        

        counterIt = 1;

        //сколько осталось доплатить первому участнику в очереди)
        uint256 leftCur = range[index].leftFunds;
        //если остаток был весь погашен предыдущему участнику - то для нового выставляем опять 150% его значению утилизации)
        if (leftCur == 0) {            
            leftCur = calculate150(ray[index][range[index].firstIndex].utilize);
        }

        //на 5 нижних уровней к текущим средствам прибавляется значение 1% - с условием - чтобы не спуститься ниже нулевого уровня)
        for (uint256 i = 1; i <= 5 && index != 0 && index >= i; i++) {
            levelFee += lowerLevelFee;
            range[index - i].currentFunds += lowerLevelFee;
        }

        //текущая сумма всех вложений - минус комиссия владельцу и 1% на газ)
        sumFunds += value - lowerLevelFee - ownerFee;

        //текущий остаток на балансе для оплаты газа)
        currentGas = getBalance() - sumFunds;
        //текущие средства плюс оставшаяся сумма)
        value = range[index].currentFunds + value - ownerFee - levelFee - lowerLevelFee;        

        //если оставшийся газ меньше цены газа за 1 цикл - тогда сохраняем нужные значения и больше ничего не делаем)        
        if (currentGas < gasCheck) {

            checkInd = false;

            range[index].currentFunds = value;
            range[index].leftFunds = leftCur;

        }

        //выплата по текущему уровню и ниже на 5 уровней)
        while (currentGas >= gasCheck && checkInd && counterIt <= 30) {

            //процесс выплаты)
            processPayOut(index, gasCheck, value, sumFunds, counterIt, currentGas, leftCur);
            
            //пока индекс не достиг нуля спускаемся на уровень ниже)
            if (index != 0) {
                index--;
                checkInd = true;
                currentGas = getBalance() - sumFunds;
                value = range[index].currentFunds;
                leftCur = range[index].leftFunds;
            } else {
                checkInd = false;
            }

        }

        //возврат потраченных средств на логику смарт-контракта)
        finalizeGasRefund(gasAtStart);        

    }

    //процесс выплаты)
    function processPayOut(uint256 index, uint256 gasChecks, uint256 valuee, uint256 sumF, uint256 counterIti, uint256 currentGas, uint256 leftCurr) private {

        //делаем выплату всем участникам по очереди - по текущему индексу - с учётом текущих средств)        
        while (currentGas >= gasChecks && counterIti <= 30 && valuee >= leftCurr && range[index].firstIndex <= range[index].lastIndex) {
            
            valuee -= leftCurr;
            //проверка - чтобы не выйти за границы диапазона и тем самым не выдало ошибку)
            if (sumF >= leftCurr) {
                sumF -= leftCurr;
            } else {
                sumF = 0;
            }
                        
            //если индекс равен 0-1-2 и газ больше или равно 1 эфиру - избыток газа идёт в бонус)
            //бонус первым трём уровням +0.5 эфира - и не важно сколько было утилизировано)
            if ( index <= 2 && currentGas >= 1 ether) {
                leftCurr += 500000000 gwei; // 0.5 ether
            }

            address payable receivePayout = payable(ray[index][range[index].firstIndex].addr);
            Address.sendValue(receivePayout, leftCurr); //Безопасно отправляем значение)            

            emit UtilizePayOut(ray[index][range[index].firstIndex].addr, leftCurr, index, range[index].firstIndex);
            //если выплата произведена полностью - то удаляем первого участника из очереди)
            delete ray[index][range[index].firstIndex];
            range[index].firstIndex++;
            counterIti++;
            currentGas = getBalance() - sumF;
            //сразу же задаём оставшееся значение следующему участнику равное 150% его утилизационным средствам)
            //и проверка - что в очереди кто-то ещё есть)
            if (range[index].firstIndex <= range[index].lastIndex) {                
                leftCurr = calculate150(ray[index][range[index].firstIndex].utilize);
            } else {
                leftCurr = 0;
            }
            
        }

        //если общая сумма выплаты участнику ещё не достигла 150% - всё равно выплачиваем часть - что осталось в текущих средствах)
        if (currentGas >= gasChecks && counterIti <= 30 && range[index].firstIndex <= range[index].lastIndex) {
            
            //проверка - чтобы не выйти за границы диапазона и тем самым не выдало ошибку)
            if (leftCurr >= valuee) {
                leftCurr -= valuee;
            } else {
                leftCurr = 0;
            }
            //проверка - чтобы не выйти за границы диапазона и тем самым не выдало ошибку)
            if (sumF >= valuee) {
                sumF -= valuee;
            } else {
                sumF = 0;
            }
            //бонус +0.5 эфир - если остаток газа выше 1 эфира)
            if (index <= 2 && currentGas >= 1 ether) {
                valuee += 500000000 gwei;
            }

            address payable receivePayoutLeft = payable(ray[index][range[index].firstIndex].addr);
            Address.sendValue(receivePayoutLeft, valuee); //Безопасно отправляем средства)                    
            
            emit UtilizePayOut(ray[index][range[index].firstIndex].addr, valuee, index, range[index].firstIndex);

            counterIti++;
            valuee = 0;

        }

        //сохраняем нужные нам значения по текущим и оставшимся средствам)
        range[index].currentFunds = valuee;
        range[index].leftFunds = leftCurr;

        sumFunds = sumF;
        counterIt = counterIti;

    }

    //баланс)
    function getBalance() public view returns (uint) {
        return address(this).balance;
    }

    function calculateFee(uint256 value, uint256 fee) private pure returns (uint256) {
        return value * fee / 100; //расчета комиссии fee%)
    }

    function calculate150(uint256 value) private pure returns (uint256) {
        return value * 3 / 2; //150%)
    }

    function finalizeGasRefund(uint256 gasAtStart) private {

        //количество затраченного газа на транзакцию)
        uint256 gasSpent = 21000 + gasAtStart - gasleft() + 16 * msg.data.length;
        uint256 minimalGasCost = 21000 * tx.gasprice; //минимальные расходы на транзакцию)
        uint256 gasCost = gasSpent * tx.gasprice; //общая цена затраченного газа)

        //рассчитаем доступный для возврата баланс с учетом минимальных затрат газа на текущую транзакцию)
        uint256 availableForRefund = address(this).balance > minimalGasCost ? address(this).balance - minimalGasCost : 0;
    
        uint256 refundAmount = gasCost > availableForRefund ? availableForRefund : gasCost; //количество для возврата)

        if (refundAmount > 0) {
            //если есть средства для возврата - выплачиваем)
            address payable refundAddress = payable(msg.sender);            
            Address.sendValue(refundAddress, refundAmount);
        }                
        
    }

    //Считывание данных из массива по индексу уровня и заданному диапазону)
    function getRayData(uint256 index, uint256 from, uint256 to) public view returns (Ray[] memory) {
        
        if (from < range[index].firstIndex || from > range[index].lastIndex) {
            from = range[index].firstIndex;
        }
        if (to < range[index].firstIndex || to > range[index].lastIndex) {
            to = range[index].lastIndex;
        }
        
        Ray[] memory result;
        // проверка на присутствие данных)
        if (from <= to) {

            result = new Ray[](to - from + 1);
            for (uint256 i = from; i <= to; i++) {
                result[i - from] = ray[index][i];
            }
        }
        
        return result;

    }
    
}