// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

//Смарт-Контракт СУС - (У) - Система Утилизации Средств)
//Полностью автоматизирован - без каких-либо вмешиваний со стороны - даже владельца)
//Только транзакция с кошельков на адрес смарт-контракта приводит его в движение)
//Вы делаете оплату на смарт-контракт и через какое-то время вам частями посылается 150% вашей оплаты)
//Работает цепочка очереди - всем по очереди выплачиваются 150% от суммы собственного платежа)
//Каждый вошедший через автоматизацию платит тем - кто вначале очереди - и до каждого из вас рано или поздно дойдёт очередь выплаты вам 150%)
//Есть комиссия 3% владельцу и 1% для погашения затрат на газ внутри сети для смарт-контракта)
//Вы производите оплату 100% - дополнительно за газ этой транзакции вы платите сами - и ровно 150% возвращается вам)
//В итоге при получении утилизационных средств из 100% получается минус 1% на газ - минус 3% владельцу = 96%)
//А также ещё минус 5% по 1% на 5 уровней ниже - чтобы быстрее им производилась оплата)
//Сразу идёт выплата 96%-91% тому кто находится первым в очереди на том же уровне)
//Также следующие 96%-91% уже покроют 150% первого в очереди - а остаток пойдёт на следующего в очереди - если хватит газа)
//На газ в итоге будут набираться неплохие суммы - поэтому излишки будут добавляться к первым 3-м уровням в виде бонуса)
//Бонусом будет +1 эфир - кому повезёт - тот и счастливчик)
//Так как все опреации требуют газа - поэтому будет стоять ограничение на минимальную утилизацию - будет зависеть от цены газа)

contract SUS {

    //владелец)
    address public owner;
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
    uint256 counterIt;

    //переменная для блокировки)
    bool private reentrancyLock = false;
    //блокирует повторное рекурсивное использование функции)
    //этот модификатор здесь особо не нужен - но на всякий случай будет использоваться)    
    modifier nonReentrant() {
        require(!reentrancyLock, "Reentrancy Guard - Function is locked)");
        reentrancyLock = true;
        _;
        reentrancyLock = false;
    }

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
        ray[10][0] = Ray(msg.sender, 8717800000000000 gwei);
        //выставляем последние индексы (не нужно если изначально в очереди только 1 участник)
        //for (uint i = 0; i < 11; i++) {
        //    range[i].lastIndex = 0;
        //}
    }

    // Функция для приема утилизационных транзакций)
    receive() external payable {

        //транзакции с других смарт-контрактов не допускаются - только с кошельков)
        require(tx.origin == msg.sender, "Only external accounts are allowed to send funds)");        

        //если меньше 0.000871 ether - тогда просто оставляем средства на балансе для газа)        
        if (msg.value <= 871000 gwei) {
        //распеределение по уровням от 0.000871 ether и кратное 10)
        } else {

            //защита на минимальную утилизацию - связанную с текущей ценой газа)
            require(msg.value >= tx.gasprice * 178000 + 1, "Insufficient minimum utilize)");

            if (msg.value <= 8710000 gwei) { //(0) > 0.000871 <= 0.00871 ether (4-0)
                processUtilize(msg.value, 0);
            } else if (msg.value <= 87100000 gwei) {    //(1) > 0.00871 <= 0.0871 ether (5-0)
                processUtilize(msg.value, 1);
            } else if (msg.value <= 871000000 gwei) {   //(2) > 0.0871 <= 0.871 ether (6-0)
                processUtilize(msg.value, 2);
            } else if (msg.value <= 8710000000 gwei) {  //(3) > 0.871 <= 8.71 ether (7-0)
                processUtilize(msg.value, 3);
            } else if (msg.value <= 87100000000 gwei) { //(4) > 8.71 <= 87.1 ether (8-0)
                processUtilize(msg.value, 4);
            } else if (msg.value <= 871000000000 gwei) {    //(5) > 87.1 <= 871 ether (9-0)
                processUtilize(msg.value, 5);
            } else if (msg.value <= 8710000000000 gwei) {   //(6) > 871 <= 8710 ether (10-0)
                processUtilize(msg.value, 6);
            } else if (msg.value <= 87100000000000 gwei) {  //(7) > 8710 <= 87100 ether (11-0)
                processUtilize(msg.value, 7);
            } else if (msg.value <= 871000000000000 gwei) { //(8) > 87100 <= 871000 ether (12-0)
                processUtilize(msg.value, 8);
            } else if (msg.value <= 8710000000000000 gwei) {    //(9) > 871000 <= 8710000 ether (13-0)
                processUtilize(msg.value, 9);
            } else if (msg.value <= 87100000000000000 gwei) {   //(10) > 8710000 <= 87100000 ether (14-0)
                processUtilize(msg.value, 10);
            } else {
            //откат - если выше всех уровней луча > 87100000 ether)
            require(msg.value <= 87100000000000000 wei);
            }
        }
        
    }
    
    //процесс утилизации и распеределение в очередь)
    function processUtilize(uint256 value, uint256 index) private nonReentrant {
        
        range[index].lastIndex++;
        //сразу добавляем в конец очереди нового участника)
        ray[index][range[index].lastIndex] = Ray({addr: msg.sender, utilize: value});
        emit UtilizeReceived(msg.sender, value, index, range[index].lastIndex);
      
        uint256 lowerLevelFee = value / 100; // по 1% на 5 уровней ниже)
        uint256 ownerFee = lowerLevelFee * 3; // 3% переводится владельцу)
        (bool ownerSuccess, ) = payable(owner).call{value: ownerFee}("");
        require(ownerSuccess, "Transfer failed (owner)");
    
        uint256 levelFee = 0;
        uint256 currentGas;

        bool checkInd = true;

        //храним цену газа за 1 цикл)
        //значение цены газа передаётся через того - кто утилизировал средства)
        uint256 gasCheck = tx.gasprice * 178000;

        counterIt = 1;

        //сколько осталось доплатить первому участнику в очереди)
        uint256 leftCur = range[index].leftFunds;
        //если остаток был весь погашен предыдущему участнику - то для нового выставляем опять 150% его значению утилизации)
        if (leftCur == 0) {
            leftCur = ray[index][range[index].firstIndex].utilize * 3 / 2;
        }

        //на 5 нижних уровней к текущим средствам прибавляется значение 1% - с условием - чтобы не спуститься ниже нулевого уровня)
        for (uint256 i = 1; i <= 5 && index != 0 && index >= i; i++) {
            levelFee += lowerLevelFee;
            range[index - i].currentFunds += lowerLevelFee;
        }

        //текущая сумма всех вложений - минус 3% комиссия владельцу и 1% на газ)
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

    }

    //процесс выплаты)
    function processPayOut(uint256 index, uint256 gasChecks, uint256 valuee, uint256 sumF, uint256 counterIti, uint256 currentGas, uint256 leftCurr) private {

        //делаем выплату всем участникам по очереди - по текущему индексу - с учётом текущих средств)
        //двойная проверка по газу - чтобы газа хватило и на последние действия после цикла)
        while (currentGas >= gasChecks && currentGas >= gasChecks * 2 && counterIti <= 30 && valuee >= leftCurr && range[index].firstIndex <= range[index].lastIndex) {
            
            valuee -= leftCurr;
            //проверка - чтобы не выйти за границы диапазона и тем самым не выдало ошибку)
            if (sumF >= leftCurr) {
                sumF -= leftCurr;
            } else {
                sumF = 0;
            }
                        
            //если индекс равен 0-1-2 и газ больше или равно 2 эфира - избыток газа идёт в бонус)
            //большой бонус первым трём уровням +1 эфир - и не важно сколько было утилизировано)
            if ( index <= 2 && currentGas >= 2 ether) {
                leftCurr += 1 ether;
            }

            (bool payoutSuccess, ) = payable(ray[index][range[index].firstIndex].addr).call{value: leftCurr}("");
            require(payoutSuccess, "Transfer failed (payout)");

            emit UtilizePayOut(ray[index][range[index].firstIndex].addr, leftCurr, index, range[index].firstIndex);
            //если выплата произведена полностью - то удаляем первого участника из очереди)
            delete ray[index][range[index].firstIndex];
            range[index].firstIndex++;
            counterIti++;
            currentGas = getBalance() - sumF;
            //сразу же задаём оставшееся значение следующему участнику равное 150% его утилизационным средствам)
            //и проверка - что в очереди кто-то ещё есть)
            if (range[index].firstIndex <= range[index].lastIndex) {
                leftCurr = ray[index][range[index].firstIndex].utilize * 3 / 2;
            } else {
                leftCurr = 0;
            }
            
        }

        //если общая сумма выплаты участнику ещё не достигла 150% - всё равно выплачиваем часть - что осталось в текущих средствах)
        if (currentGas >= gasChecks && currentGas >= gasChecks * 2 && counterIti <= 30 && range[index].firstIndex <= range[index].lastIndex) {
            
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
            //бонус +1 эфир - если остаток газа выше 2 эфиров)
            if (index <= 2 && currentGas >= 2 ether) {
                valuee += 1 ether;
            }

            (bool leftPayoutSuccess, ) = payable(ray[index][range[index].firstIndex].addr).call{value: valuee}("");
            require(leftPayoutSuccess, "Transfer failed (left payout)");
            
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