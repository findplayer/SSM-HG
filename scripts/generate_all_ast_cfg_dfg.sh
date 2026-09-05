#!/bin/bash
# 自动为每个.sol文件检测pragma版本并切换solc版本，生成AST、CFG、DFG
# 数据源：alldata(readonly)/alldata_sol_source（只读，勿改）
# 输出：raw/AST-raw、raw/CFG-raw、raw/DFG-raw

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# 输出目录（原始产物，供 build_cfg_centered_hetero_graph.py 消费）
AST_DIR="$REPO_ROOT/raw/AST-raw"
CFG_DIR="$REPO_ROOT/raw/CFG-raw"
DFG_DIR="$REPO_ROOT/raw/DFG-raw"

# 源码根目录（只读数据源）
SRC_ROOT="$REPO_ROOT/alldata(readonly)/alldata_sol_source"

# 日志统一放 raw/logs/，不混入产物目录
LOG_DIR="$REPO_ROOT/raw/logs"
mkdir -p "$AST_DIR" "$CFG_DIR" "$DFG_DIR" "$LOG_DIR"

# 日志
AST_ERR="$LOG_DIR/ast_error.log"
CFG_ERR="$LOG_DIR/cfg_error.log"
DFG_ERR="$LOG_DIR/dfg_error.log"

# 清理旧版（把日志写在产物目录里）遗留的日志文件
rm -f "$AST_DIR/ast_error.log" "$CFG_DIR/cfg_error.log" "$DFG_DIR/dfg_error.log"

> "$AST_ERR"
> "$CFG_ERR"
> "$DFG_ERR"

find "$AST_DIR" -maxdepth 1 -type f -name "*.json" -delete
find "$CFG_DIR" -type f -name "*_cfg.txt" -delete
find "$CFG_DIR" -type f -name "*.dot" -delete
find "$CFG_DIR" -maxdepth 1 -type f -name "*.svg" -delete
find "$CFG_DIR" -maxdepth 1 -type f -name "*__cfgdetail.json" -delete
find "$DFG_DIR" -maxdepth 1 -type f -name "*_dfg.txt" -delete

mapfile -t INSTALLED_SOLC_VERSIONS < <(solc-select versions | awk 'match($1, /^[0-9]+\.[0-9]+\.[0-9]+$/) { print $1 }' | sort -V)

version_eq() {
  [[ "$1" == "$2" ]]
}

version_lt() {
  [[ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | head -n1)" == "$1" && "$1" != "$2" ]]
}

version_le() {
  version_lt "$1" "$2" || version_eq "$1" "$2"
}

version_gt() {
  version_lt "$2" "$1"
}

version_ge() {
  version_le "$2" "$1"
}

extract_pragma_expr() {
  # 2026-09-04：先过滤注释行（避免命中注释里的 pragma），再 -o 提取匹配段
  # （-o 同时规避 CRLF 行尾的 \r 破坏末尾 ; 剥离）。
  grep -vE '^[[:space:]]*(//|/\*|\*)' "$1" | grep -Eo 'pragma solidity [^;]*;' | head -n1 | sed -E 's/^pragma solidity[[:space:]]+//; s/[[:space:]]*;$//; s/[[:space:]]+/ /g'
}

extract_ast_json() {
  python3 -c 'import json, sys
data = sys.stdin.read()
start = data.find("{")
if start == -1:
    sys.exit(1)
try:
  obj, end = json.JSONDecoder().raw_decode(data[start:])
except json.JSONDecodeError:
    sys.exit(1)
sys.stdout.write(json.dumps(obj, indent=2) + "\n")'
}

probe_solc_version() {
  local source_file="$1"
  local candidate_version="$2"
  local source_dir
  local source_base
  local probe_log

  source_dir=$(dirname "$source_file")
  source_base=$(basename "$source_file")
  probe_log=$(mktemp)

  if solc-select use "$candidate_version" >/dev/null 2>"$probe_log" && (cd "$source_dir" && solc --combined-json ast "$source_base" >/dev/null 2>>"$probe_log"); then
    rm -f "$probe_log"
    return 0
  fi

  rm -f "$probe_log"
  return 1
}

next_caret_upper_bound() {
  local major minor patch
  IFS=. read -r major minor patch <<< "$1"
  if [ "$major" -gt 0 ]; then
    echo "$((major + 1)).0.0"
  elif [ "$minor" -gt 0 ]; then
    echo "0.$((minor + 1)).0"
  else
    echo "0.0.$((patch + 1))"
  fi
}

pragma_matches_version() {
  local version="$1"
  local expr="$2"
  local token target

  for token in $expr; do
    case "$token" in
      ">="*)
        target="${token#>=}"
        version_ge "$version" "$target" || return 1
        ;;
      ">"*)
        target="${token#>}"
        version_gt "$version" "$target" || return 1
        ;;
      "<="*)
        target="${token#<=}"
        version_le "$version" "$target" || return 1
        ;;
      "<"*)
        target="${token#<}"
        version_lt "$version" "$target" || return 1
        ;;
      "="*)
        target="${token#=}"
        version_eq "$version" "$target" || return 1
        ;;
      "~"*)
        # ~x.y.z 语义:>=x.y.z 且 <x.(y+1).0(允许指定次版本内补丁更新);
        # major=0 时与 caret 相同:>=0.y.z 且 <0.(y+1).0。
        # (2026-09-05 新增,原实现把 ~ 归入 * 直接拒绝,导致 ~0.4.x 类合约全部失败)
        target="${token#~}"
        IFS=. read -r t_major t_minor t_patch <<< "$target"
        version_ge "$version" "$target" || return 1
        if [ "$t_major" -gt 0 ]; then
          version_lt "$version" "$t_major.$((t_minor + 1)).0" || return 1
        else
          version_lt "$version" "0.$((t_minor + 1)).0" || return 1
        fi
        ;;
      [0-9]*.[0-9]*.[0-9]*)
        version_eq "$version" "$token" || return 1
        ;;
      *)
        return 1
        ;;
    esac
  done
}

select_solc_version() {
  local pragma_expr="$1"
  local source_file="$2"
  local normalized_expr="$1"
  local selected_version=""
  local version

  normalized_expr=$(printf '%s' "$normalized_expr" | sed -E 's/([<>=^~])[[:space:]]+/\1/g; s/[[:space:]]+/ /g')

  if [[ "$normalized_expr" =~ ^\^([0-9]+\.[0-9]+\.[0-9]+)$ ]]; then
    normalized_expr=">=${BASH_REMATCH[1]} <$(next_caret_upper_bound "${BASH_REMATCH[1]}")"
  elif [[ "$normalized_expr" =~ ^([0-9]+\.[0-9]+\.[0-9]+)$ ]]; then
    normalized_expr="=${normalized_expr}"
  fi

  # 2026-09-04 修正：从最高满足版本往下试（而不是最低）。
  # 原因：极老 solc（<=0.4.10）的 --combined-json 不输出完整 srcmap，
  # Slither 的 source_mapping.lines 为空，导致 cfgdetail 节点行号全部丢失。
  for ((i = ${#INSTALLED_SOLC_VERSIONS[@]} - 1; i >= 0; i--)); do
    version="${INSTALLED_SOLC_VERSIONS[$i]}"
    if pragma_matches_version "$version" "$normalized_expr"; then
      if probe_solc_version "$source_file" "$version"; then
        selected_version="$version"
        break
      fi
    fi
  done

  printf '%s' "$selected_version"
}

select_no_pragma_version() {
  local source_file="$1"
  local version
  local selected_version=""

  # 大纲 4.1.1：pragma 缺失时优先回退 solc 0.8.x（同样取最高 0.8.x）
  for ((i = ${#INSTALLED_SOLC_VERSIONS[@]} - 1; i >= 0; i--)); do
    version="${INSTALLED_SOLC_VERSIONS[$i]}"
    if [[ "$version" == 0.8.* ]]; then
      if probe_solc_version "$source_file" "$version"; then
        selected_version="$version"
        break
      fi
    fi
  done

  if [ -n "$selected_version" ]; then
    printf '%s' "$selected_version"
    return
  fi

  # 无 0.8.x 可用时，从最新安装版本往回试
  for ((i = ${#INSTALLED_SOLC_VERSIONS[@]} - 1; i >= 0; i--)); do
    version="${INSTALLED_SOLC_VERSIONS[$i]}"
    if probe_solc_version "$source_file" "$version"; then
      printf '%s' "$version"
      return
    fi
  done
}

prepare_slither_workdir() {
  local source_file="$1"
  local selected_version="$2"
  local workdir
  local source_basename
  local target_file

  workdir=$(mktemp -d)
  source_basename=$(basename "$source_file")
  target_file="$workdir/$source_basename"

  cp "$source_file" "$target_file"
  if version_lt "$selected_version" "0.5.0"; then
    python3 - "$target_file" <<'PY'
from pathlib import Path
import re
import sys

path = Path(sys.argv[1])
text = path.read_text()
text = re.sub(r'\(\s*bool success\s*,\s*\)\s*=\s*(.*?);', r'bool success = \1;', text, flags=re.S)
path.write_text(text)
PY
  fi

  printf '%s\n%s\n' "$workdir" "$source_basename"
}

# 过滤统计（写入 raw/filter_report.txt，大纲 4.1.1 透明性声明）
total_files=0
ast_fail_count=0
cfg_fail_count=0
dfg_fail_count=0
cfgdetail_fail_count=0
cfg_retry_count=0
slither_error_count=0
assembly_gt50_count=0
delegatecall_dyn_count=0
# 无 pragma 文件数 / 无满足版本(且无回退)文件数(2026-09-05 新增,写入 filter_report)
pragma_missing_count=0
no_version_count=0

while IFS= read -r -d '' solfile; do
  total_files=$((total_files + 1))
  rel_path="${solfile#${SRC_ROOT}/}"
  safe_name="${rel_path//\//__}"
  safe_name="${safe_name%.sol}"
  ast_out="$AST_DIR/${safe_name}.json"
  dfg_out="$DFG_DIR/${safe_name}_dfg.txt"

  # assembly 块超过 50 行统计（2026-09-04：花括号深度计数，修复原 awk 嵌套括号提前闭合）
  if python3 - "$solfile" <<'PY'
import re, sys

text = open(sys.argv[1], encoding="utf-8", errors="ignore").read()
start = None
depth = 0
big = False
for i, line in enumerate(text.splitlines(), 1):
    if start is None and re.search(r"\bassembly\s*\{", line):
        start = i
        depth = 0
    if start is not None:
        depth += line.count("{") - line.count("}")
        if depth <= 0:
            if i - start + 1 > 50:
                big = True
            start = None
sys.exit(0 if big else 1)
PY
then
    assembly_gt50_count=$((assembly_gt50_count + 1))
    echo "$solfile: filtered (>50 lines inline assembly)" >> "$AST_ERR"
    continue
  fi

  # delegatecall 动态绑定统计（调用目标不是 0x 字面量地址）
  if grep -E 'delegatecall' "$solfile" | grep -qvE '0x[0-9a-fA-F]{40}'; then
    delegatecall_dyn_count=$((delegatecall_dyn_count + 1))
    echo "$solfile: filtered (dynamic delegatecall binding)" >> "$AST_ERR"
    continue
  fi

  # 检测pragma solidity版本
  pragma=$(extract_pragma_expr "$solfile")
  if [ -z "$pragma" ]; then
    pragma_missing_count=$((pragma_missing_count + 1))
    selected_version=$(select_no_pragma_version "$solfile")
    if [ -z "$selected_version" ]; then
      echo "$solfile: No pragma found and no fallback solc version available" >> "$AST_ERR"
      no_version_count=$((no_version_count + 1))
      continue
    fi
  else
    selected_version=$(select_solc_version "$pragma" "$solfile")
    if [ -z "$selected_version" ]; then
      echo "$solfile: No installed solc version satisfies pragma '$pragma'" >> "$AST_ERR"
      no_version_count=$((no_version_count + 1))
      continue
    fi
  fi

  # 尝试切换solc版本
  if ! solc-select use "$selected_version" 2>> "$AST_ERR"; then
    echo "$solfile: solc-select use $selected_version failed for pragma '$pragma'" >> "$AST_ERR"
    continue
  fi

  sol_dir=$(dirname "$solfile")
  sol_base=$(basename "$solfile")

  # 生成AST（警告只作临时保存，成功后丢弃，避免污染 error 日志）
  ast_err_tmp=$(mktemp)
  if ! (set -o pipefail; cd "$sol_dir" && solc --combined-json ast "$sol_base" | extract_ast_json) > "$ast_out" 2>"$ast_err_tmp"; then
    echo "$solfile: AST generation failed" >> "$AST_ERR"
    cat "$ast_err_tmp" >> "$AST_ERR"
    ast_fail_count=$((ast_fail_count + 1))
    rm -f "$ast_out"
    rm -f "$ast_err_tmp"
    continue
  fi
  rm -f "$ast_err_tmp"

  slither_workdir=""
  slither_source_name=""

  # 生成CFG (slither 会在临时目录生成 .dot 文件)
  mapfile -t slither_workdir_info < <(prepare_slither_workdir "$solfile" "$selected_version")
  slither_workdir="${slither_workdir_info[0]}"
  slither_source_name="${slither_workdir_info[1]}"
  cfg_ts=$(mktemp)
  touch "$cfg_ts"
  cfg_err_tmp=$(mktemp)
  if ! (cd "$slither_workdir" && slither "$slither_source_name" --print cfg) > /dev/null 2>"$cfg_err_tmp"; then
    # 2026-09-04：Slither 0.11.5 对部分 0.4.12+ AST 常量折叠崩溃（NotConstant），
    # 依次回退到较低版本重试；AST 一并按回退版本重生成，保持工具链版本一致。
    retry_ok=0
    for ((i = ${#INSTALLED_SOLC_VERSIONS[@]} - 1; i >= 0; i--)); do
      fb="${INSTALLED_SOLC_VERSIONS[$i]}"
      [ "$fb" = "$selected_version" ] && continue
      if probe_solc_version "$solfile" "$fb" \
         && (set -o pipefail; cd "$sol_dir" && solc --combined-json ast "$sol_base" | extract_ast_json) > "$ast_out" 2>/dev/null \
         && (cd "$slither_workdir" && slither "$slither_source_name" --print cfg) > /dev/null 2>"$cfg_err_tmp"; then
        selected_version="$fb"
        cfg_retry_count=$((cfg_retry_count + 1))
        retry_ok=1
        break
      fi
    done
    if [ "$retry_ok" -ne 1 ]; then
      echo "$solfile: CFG generation failed (all versions)" >> "$CFG_ERR"
      cfg_fail_count=$((cfg_fail_count + 1))
      cat "$cfg_err_tmp" >> "$CFG_ERR"
      rm -f "$cfg_err_tmp" "$ast_out"
      rm -rf "$slither_workdir"
      continue
    fi
  fi
  rm -f "$cfg_err_tmp"
  find "$slither_workdir" -maxdepth 1 -type f -name "${slither_source_name}-*.dot" -newer "$cfg_ts" -print0 | while IFS= read -r -d '' dot_file; do
    dot_base=$(basename "$dot_file")
    # 2026-09-04：函数签名过长导致文件名超 255 字节时用哈希名（dot 仅为回退输入）
    if [ "${#dot_base}" -gt 200 ]; then
      dot_base="$(printf '%s' "$dot_base" | sha1sum | cut -c1-16).dot"
    fi
    cp "$dot_file" "$CFG_DIR/${safe_name}__${dot_base}"
  done
  rm -f "$cfg_ts"

  # 生成DFG (使用 data-dependency printer)
  # Slither's data-dependency printer writes its content to stderr.
  if ! (cd "$slither_workdir" && slither "$slither_source_name" --print data-dependency) > /dev/null 2> "$dfg_out"; then
    echo "$solfile: DFG generation failed" >> "$DFG_ERR"
    dfg_fail_count=$((dfg_fail_count + 1))
    if grep -qiE 'error' "$dfg_out"; then
      slither_error_count=$((slither_error_count + 1))
    fi
    rm -f "$dfg_out"
    rm -f "$ast_out" "$CFG_DIR/${safe_name}__"*
    rm -rf "$slither_workdir"
    continue
  fi

  # 生成带分支类型（seq/true/false）的 CFG 明细（dump_cfg.py，见手册 7.4）
  cfgdetail_out="$CFG_DIR/${safe_name}__cfgdetail.json"
  solc-select use "$selected_version" >/dev/null 2>&1
  if ! (cd "$slither_workdir" && python3 "$REPO_ROOT/scripts/dump_cfg.py" "$slither_source_name" "$cfgdetail_out" 2>> "$CFG_ERR"); then
    echo "$solfile: cfgdetail failed" >> "$CFG_ERR"
    cfgdetail_fail_count=$((cfgdetail_fail_count + 1))
    rm -f "$cfgdetail_out"
  fi
  rm -rf "$slither_workdir"
done < <(find "$SRC_ROOT" -name "*.sol" -print0)

# 过滤统计报告（大纲 4.1.1 透明性声明，占比必须进论文）
{
  echo "Filter report (generate_all_ast_cfg_dfg.sh)"
  echo "==========================================="
  echo "total_source_files=$total_files"
  echo "ast_failed=$ast_fail_count"
  echo "cfg_failed=$cfg_fail_count"
  echo "dfg_failed=$dfg_fail_count"
  echo "cfgdetail_failed=$cfgdetail_fail_count"
  echo "cfg_retried_lower_version=$cfg_retry_count"
  echo "slither_error_contracts=$slither_error_count"
  echo "assembly_gt50_lines=$assembly_gt50_count"
  echo "delegatecall_dynamic_binding=$delegatecall_dyn_count"
  echo "pragma_missing=$pragma_missing_count"
  echo "no_satisfying_or_fallback_version=$no_version_count"
  if [ "$total_files" -gt 0 ]; then
    awk -v t="$total_files" -v a="$ast_fail_count" -v c="$cfg_fail_count" -v d="$dfg_fail_count" \
        -v s="$slither_error_count" -v asm="$assembly_gt50_count" -v dl="$delegatecall_dyn_count" \
        -v pm="$pragma_missing_count" -v nv="$no_version_count" \
      'BEGIN{
        printf "ast_failed_ratio=%.4f\n", a/t;
        printf "cfg_failed_ratio=%.4f\n", c/t;
        printf "dfg_failed_ratio=%.4f\n", d/t;
        printf "slither_error_ratio=%.4f\n", s/t;
        printf "assembly_gt50_ratio=%.4f\n", asm/t;
        printf "delegatecall_dyn_ratio=%.4f\n", dl/t;
        printf "pragma_missing_ratio=%.4f\n", pm/t;
        printf "no_satisfying_or_fallback_ratio=%.4f\n", nv/t;
      }'
  fi
} > "$REPO_ROOT/raw/filter_report.txt"
