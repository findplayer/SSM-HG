#!/usr/bin/env bash
# 5.3 六个传统工具的**可复现安装脚本**（Ubuntu 24.04 / WSL2）。
#
# 为什么要有这个脚本：这六个工具的装法**全部踩过坑**，且坑位不在明面上。
# 每一条 `PIN` 注释都是一次实测失败换来的，删掉就会重蹈覆辙。
#
# 🔴 三条硬环境事实（2026-09-23 实测）：
#   1. **PyPI 直连被墙** —— 所有 pip 必须加 `-i https://pypi.tuna.tsinghua.edu.cn/simple`。
#   2. **绝不装进 conda base** —— base 里的 torch 2.0.1+cu118 是本仓全部实验的地基。
#      五个工具各开独立 env，base 只保留既有的 Slither 0.11.5。
#   3. **本机无 docker** —— 全部走 conda env + 官方预编译包。
#
# 用法：bash scripts/install_traditional_tools.sh [slither|mythril|manticore|smartcheck|securify|oyente|all]

set -u

MIRROR="https://pypi.tuna.tsinghua.edu.cn/simple"
BASE=/home/saumarez/anaconda3
TOOLS="${HOME}/tools"

pipin() { "$1/bin/pip" install --no-input -i "$MIRROR" "${@:2}"; }

# --------------------------------------------------------------------------- Slither
# 已在 base（crytic/slither 0.11.5）。本脚本不重装，只自检。
install_slither() {
    echo "== Slither：base 既有，自检 =="
    "${BASE}/bin/slither" --version
}

# --------------------------------------------------------------------------- Mythril
install_mythril() {
    echo "== Mythril =="
    conda create -y -n mythril python=3.11
    pipin "${BASE}/envs/mythril" mythril==0.24.8
    # PIN: conda 新建的 py3.11 不带 setuptools，而 `eth` 包顶层 `import pkg_resources`。
    #      且 setuptools>=81 **已删除 pkg_resources**，必须钉 <81，否则 `myth version` 报
    #      ModuleNotFoundError（实测：84.0.0 失败，80.10.2 通过）。
    pipin "${BASE}/envs/mythril" "setuptools<81"
    # solc 由 py-solc-x 自己下（binaries.soliditylang.org 实测可达），无需 solc-select。
    "${BASE}/envs/mythril/bin/myth" version
}

# --------------------------------------------------------------------------- Manticore
install_manticore() {
    echo "== Manticore =="
    conda create -y -n manticore python=3.9
    pipin "${BASE}/envs/manticore" manticore==0.3.8.dev240227
    # PIN 🔴 本脚本最关键的一条：manticore 声明 `crytic-compile>=0.2.2`，pip 会装最新的
    #      0.3.11，而 0.3.11 把 `CompilationUnit` 拆分重命名了 ——
    #      `bytecode_init` / `contracts_names_without_libraries` 搬到了 `SourceUnit` 上。
    #      后果**不是报错而是静默**：编译拿不到字节码，"创建合约"产出 0 笔交易，
    #      日志只留一句 `Manticore failed to run`，看起来像合约太难。
    #      钉 0.2.4 后实测：25+ 测试用例、覆盖率 86%、正确报出 reentrancy。
    pipin "${BASE}/envs/manticore" "crytic-compile==0.2.4"
    # 🔴 两条调用口径（不是安装项，但写在这里免得忘）：
    #   (a) 必须把 env 的 bin 加进 PATH —— manticore 调的是**外部 z3 可执行文件**
    #       （`consts.z3_bin`），不是 z3 的 python 模块；漏了会报
    #       `SolverException: No Solver not found`。
    #   (b) 必须加 `--thorough-mode` —— manticore 的 CLI 在**非** thorough 模式下强制
    #       `exclude_all=True`，**一个检测器都不跑**；且该模式还会撞上 finalize() 里
    #       `last_tx.result` 的判空缺失 bug（上游 1758 行，紧邻的 1761 行才做 None 兜底）。
    #       thorough-mode 既开全部 12 个检测器、又天然绕开那个 bug，故**不需要打补丁**。
    PATH="${BASE}/envs/manticore/bin:${PATH}" "${BASE}/envs/manticore/bin/manticore" --version
}

# --------------------------------------------------------------------------- SmartCheck
install_smartcheck() {
    echo "== SmartCheck =="
    # 用 SmartDec 官方 npm 包（**不是** npm 上那个同名 0.0.x 占位包）。
    # PIN: npm 全局前缀是 /usr/local，必须 sudo；jdeploy 包内自带 jar，只需系统有 java。
    # PIN: README 说"仅支持较老的 java8"，实测 openjdk-8u504 可用。
    sudo apt-get install -y openjdk-8-jdk
    sudo npm install -g @smartdec/smartcheck
    java -version
    command -v smartcheck
    echo "   用法：cd <合约目录> && smartcheck -p .   # --help 不是合法参数，会抛 IllegalArgumentException"
}

# --------------------------------------------------------------------------- Securify2
install_securify() {
    echo "== Securify2 =="
    conda create -y -n securify python=3.7
    pipin "${BASE}/envs/securify" --upgrade pip setuptools wheel
    # PIN: py-etherscan-api **不能省** —— `securify/__main__.py` 无条件 import 它，
    #      少了连本地 .sol 都跑不起来。
    pipin "${BASE}/envs/securify" py-solc semantic_version graphviz py-etherscan-api requests

    mkdir -p "${TOOLS}"
    [ -d "${TOOLS}/securify2" ] || git clone --depth 1 https://github.com/eth-sri/securify2.git "${TOOLS}/securify2"
    pipin "${BASE}/envs/securify" -e "${TOOLS}/securify2"
    # functor 共享库（纯 extern "C"，与 souffle 版本解耦）
    ( cd "${TOOLS}/securify2/securify/staticanalysis/libfunctors" && ./compile_functors.sh )

    install_souffle_162
    echo "   用法见脚本末尾 usage 段"
}

# --------------------------------------------------------------------------- souffle for securify
# 🔴 实测结论（与本轮之前调研的推测相反）：**souffle 2.5 不行，必须 1.6.2**。
#    2.5 的类型检查比 1.6 严，securify2 那套 2019 年的 .dl 直接被拒：
#      Error: Atom's argument type is not a subtype of its declared type  (locked-ether.dl / timestamp.dl / tx-origin.dl)
#      Error: Ambiguous record in trusted-variable.dl
#      → 5 errors generated, evaluation aborted
#    另外 souffle **不在 Ubuntu 24.04 的 apt 源**、也**不在 conda-forge**（均已实测），
#    但官方 release 有 1.6.2 的 deb。
#
#    ⚠ 1.6.2 链接的是三个 24.04 已彻底移除的旧 soname：
#        libffi.so.6 / libncurses.so.5 / libtinfo.so.5
#      修法 = 连同三个旧库一起 `dpkg-deb -x` 解包到 /opt/souffle162（**不装系统包**），
#      再用 wrapper 把 LD_LIBRARY_PATH 限定在 /opt 内 —— 不污染系统库。
install_souffle_162() {
    echo "== souffle 1.6.2（securify2 用）=="
    local D=/tmp/souf162
    mkdir -p "$D" && cd "$D"
    local URLS=(
        "https://github.com/souffle-lang/souffle/releases/download/1.6.2/souffle_1.6.2-1_amd64.deb"
        "http://archive.ubuntu.com/ubuntu/pool/main/libf/libffi/libffi6_3.2.1-8_amd64.deb"
        "http://archive.ubuntu.com/ubuntu/pool/universe/n/ncurses/libncurses5_6.3-2_amd64.deb"
        "http://archive.ubuntu.com/ubuntu/pool/universe/n/ncurses/libtinfo5_6.3-2_amd64.deb"
    )
    for u in "${URLS[@]}"; do [ -f "$(basename "$u")" ] || curl -sSLO "$u"; done

    sudo mkdir -p /opt/souffle162
    for d in souffle_1.6.2-1_amd64.deb libffi6_3.2.1-8_amd64.deb \
             libncurses5_6.3-2_amd64.deb libtinfo5_6.3-2_amd64.deb; do
        sudo dpkg-deb -x "$D/$d" /opt/souffle162
    done
    # PIN ⚠ 两个目录**都要**给：libffi 在 usr/lib 下，ncurses/tinfo 在 lib 下
    #      （dpkg-deb -x 保留 deb 原始布局）。只给一个会报
    #      `libncurses.so.5: cannot open shared object file`。
    # PIN ⚠ 不要写成 `echo 1 | sudo -S tee f <<EOF` —— heredoc 与管道**争抢 stdin**，
    #      sudo 会把 heredoc 当密码读掉，tee 收不到内容（本轮实际踩到，wrapper 静默没更新）。
    #      改成先落盘再 `sudo cp`。
    cat > /tmp/souffle162_wrapper.sh <<'EOF'
#!/bin/bash
export LD_LIBRARY_PATH=/opt/souffle162/lib/x86_64-linux-gnu:/opt/souffle162/usr/lib/x86_64-linux-gnu:$LD_LIBRARY_PATH
exec /opt/souffle162/usr/bin/souffle "$@"
EOF
    sudo cp /tmp/souffle162_wrapper.sh /usr/local/bin/souffle162
    sudo chmod +x /usr/local/bin/souffle162
    sudo apt-get install -y mcpp          # souffle 预处理需要
    souffle162 --version | head -1
}

# --------------------------------------------------------------------------- Oyente
install_oyente() {
    echo "== Oyente =="
    # 🔴 不要装 PyPI 的 oyente==0.2.7 —— 那是 py2 专属，且它依赖的 web3<=4.x
    #    **在 PyPI 上没有任何 py2 wheel**，是泥潭。**git master 已经是 py3**，走 master。
    conda create -y -n oyente python=3.8
    pipin "${BASE}/envs/oyente" --upgrade pip setuptools wheel
    # PIN: z3 钉 4.8.17（有 manylinux wheel 且 `z3.z3util` 尚在 —— oyente 启动时硬检查它）。
    pipin "${BASE}/envs/oyente" "z3-solver==4.8.17" requests six tqdm
    # PIN 🔴 第二条关键修正：**必须 crytic-compile==0.1.2**（不是调研建议的 0.3.5）。
    #      oyente 的 `input_helper._extract_bin_obj()` 用的是**扁平 API**：
    #          com.contracts_names / com.contracts_names_without_libraries /
    #          com.contracts_filenames[name].absolute / com.bytecode_runtime(name)
    #      这套 API 只存在于 0.1.2；0.1.4 起就已移除（逐 tag 实测：0.1.4/0.1.10/0.1.12 均为 0 个定义），
    #      0.2.x 起改为 `compilation_units`，0.3.x 又拆成 `SourceUnit`。
    #      装 0.3.5 的后果：编译成功后才崩 `AttributeError: 'CryticCompile' object has no attribute 'contracts_names'`。
    pipin "${BASE}/envs/oyente" "crytic-compile==0.1.2"

    mkdir -p "${TOOLS}" && cd "${TOOLS}"
    [ -d "${TOOLS}/oyente" ] || git clone https://github.com/enzymefinance/oyente.git "${TOOLS}/oyente"
    # PIN: oyente 启动时硬检查 `evm` 二进制（go-ethereum），apt 里没有；
    #      官方 alltools 1.7.3 正是代码里 tested 的版本。
    if [ ! -d "${TOOLS}/geth-alltools-linux-amd64-1.7.3-4bb3c89d" ]; then
        curl -sSLO https://gethstore.blob.core.windows.net/builds/geth-alltools-linux-amd64-1.7.3-4bb3c89d.tar.gz
        tar xzf geth-alltools-linux-amd64-1.7.3-4bb3c89d.tar.gz
    fi
    # PIN: oyente 经 crytic-compile 编译，找的是 **PATH 上的 `solc`**（不认 SOLC_BINARY），
    #      而全局 solc 是 0.5.17 → 必须钉 0.4.19。做法 = 在 **env 的 bin 内**放 shim
    #      （激活该 env 才生效），**不要动 `solc-select use` 的全局 symlink**（会漏到别的工具下）。
    ln -sf "${HOME}/.solc-select/artifacts/solc-0.4.19/solc-0.4.19" "${BASE}/envs/oyente/bin/solc"
    PATH="${BASE}/envs/oyente/bin:${PATH}" solc --version | tail -1
}

case "${1:-all}" in
    slither)    install_slither ;;
    mythril)    install_mythril ;;
    manticore)  install_manticore ;;
    smartcheck) install_smartcheck ;;
    securify)   install_securify ;;
    oyente)     install_oyente ;;
    all)
        install_slither; install_mythril; install_manticore
        install_smartcheck; install_securify; install_oyente
        ;;
    *) echo "用法: $0 [slither|mythril|manticore|smartcheck|securify|oyente|all]"; exit 2 ;;
esac

cat <<'USAGE'

-------------------------------------------------------------------------- 调用口径备忘
六个工具（Slither 除外）**都要先激活各自的 env**，否则会出各种"找不到依赖"：

  # Slither（base；沿用既有 baseline_static_tools.py）
  python scripts/baseline_static_tools.py --limit 5

  # Mythril（solc 自己下；~3-10 min/合约）
  conda activate mythril
  cd <合约目录> && myth analyze <file>.sol --execution-timeout 90 -o json

  # Manticore（必须 --thorough-mode，见上）
  conda activate manticore
  manticore <file>.sol --thorough-mode --workspace /tmp/mcore_x

  # SmartCheck（--help 非法；-p 必给）
  cd <合约目录> && smartcheck -p .

  # Securify2（SOUFFLE_BINARY 必须指 souffle162）
  conda activate securify
  export SOLC_BINARY=$HOME/.solc-select/artifacts/solc-0.5.12/solc-0.5.12
  export SOUFFLE_BINARY=souffle162
  export LD_LIBRARY_PATH=$HOME/tools/securify2/securify/staticanalysis/libfunctors:$LD_LIBRARY_PATH
  cd $HOME/tools/securify2 && securify <file>.sol

  # Oyente（须在 oyente/ 子目录内跑，源码用顶层 import；solc 0.4.19 已由 env 内 shim 保证）
  conda activate oyente
  export PATH=$HOME/tools/geth-alltools-linux-amd64-1.7.3-4bb3c89d:$PATH
  cd $HOME/tools/oyente/oyente && python oyente.py -s <file>.sol

⚠ 两个 solc 需求互相冲突（securify=0.5.12 / oyente=0.4.19）：
  一律按 env 隔离（securify 用 SOLC_BINARY，oyente 用 env 内 shim），
  **不要动 `solc-select use` 的全局 symlink** —— 会漏到别的工具下面去。

⚠ 三处「工具能力边界」（不是安装问题，是 5.3 表格必须披露的口径）：
  · securify2 只吃 **Solidity >= 0.5.8** 且 **扁平（无 import）** 的合约；
  · oyente 按 **solc 0.4.19** 测试，编译期就按 0.4.19 处理；
  · manticore 只跑 `--thorough-mode` 下的 12 个检测器（无 `front_running` 对应项）。
  跑前应先统计各工具的「可分析合约数」，写进对比表行注。
USAGE
