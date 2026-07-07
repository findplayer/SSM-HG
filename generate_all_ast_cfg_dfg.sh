#!/bin/bash
# 自动为每个.sol文件检测pragma版本并切换solc版本，生成AST、CFG、DFG

# 输出目录
AST_DIR="/home/saumarez/projects/deep-learning/SSM-HG/dataset/2026test/test_ast_generate/AST"
CFG_DIR="/home/saumarez/projects/deep-learning/SSM-HG/dataset/2026test/test_ast_generate/CFG"
DFG_DIR="/home/saumarez/projects/deep-learning/SSM-HG/dataset/2026test/test_ast_generate/DFG"

# 源码根目录
SRC_ROOT="/home/saumarez/projects/deep-learning/SSM-HG/dataset/reentrancy_contract/sol_source"

mkdir -p "$AST_DIR" "$CFG_DIR" "$DFG_DIR"

# 日志
AST_ERR="$AST_DIR/ast_error.log"
CFG_ERR="$CFG_DIR/cfg_error.log"
DFG_ERR="$DFG_DIR/dfg_error.log"

> "$AST_ERR"
> "$CFG_ERR"
> "$DFG_ERR"

find "$AST_DIR" -maxdepth 1 -type f -name "*.json" -delete
find "$CFG_DIR" -type f -name "*_cfg.txt" -delete
find "$CFG_DIR" -type f -name "*.dot" -delete
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
  grep -Eo 'pragma solidity [^;]*;' "$1" | head -n1 | sed -E 's/^pragma solidity[[:space:]]+//; s/[[:space:]]*;$//; s/[[:space:]]+/ /g'
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

  for version in "${INSTALLED_SOLC_VERSIONS[@]}"; do
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

  for version in "${INSTALLED_SOLC_VERSIONS[@]}"; do
    if [[ "$version" == 0.4.* ]]; then
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

  if [ "${#INSTALLED_SOLC_VERSIONS[@]}" -gt 0 ]; then
    printf '%s' "${INSTALLED_SOLC_VERSIONS[$((${#INSTALLED_SOLC_VERSIONS[@]} - 1))]}"
  fi
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

while IFS= read -r -d '' solfile; do
  rel_path="${solfile#${SRC_ROOT}/}"
  safe_name="${rel_path//\//__}"
  safe_name="${safe_name%.sol}"
  ast_out="$AST_DIR/${safe_name}.json"
  dfg_out="$DFG_DIR/${safe_name}_dfg.txt"

  # 检测pragma solidity版本
  pragma=$(extract_pragma_expr "$solfile")
  if [ -z "$pragma" ]; then
    selected_version=$(select_no_pragma_version "$solfile")
    if [ -z "$selected_version" ]; then
      echo "$solfile: No pragma found and no fallback solc version available" >> "$AST_ERR"
      continue
    fi
  else
    selected_version=$(select_solc_version "$pragma" "$solfile")
    if [ -z "$selected_version" ]; then
      echo "$solfile: No installed solc version satisfies pragma '$pragma'" >> "$AST_ERR"
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

  # 生成AST
  if ! (set -o pipefail; cd "$sol_dir" && solc --combined-json ast "$sol_base" | extract_ast_json) > "$ast_out" 2>> "$AST_ERR"; then
    echo "$solfile: AST generation failed" >> "$AST_ERR"
    rm -f "$ast_out"
    continue
  fi

  slither_workdir=""
  slither_source_name=""

  # 生成CFG (slither 会在临时目录生成 .dot 文件)
  mapfile -t slither_workdir_info < <(prepare_slither_workdir "$solfile" "$selected_version")
  slither_workdir="${slither_workdir_info[0]}"
  slither_source_name="${slither_workdir_info[1]}"
  cfg_ts=$(mktemp)
  touch "$cfg_ts"
  if ! (cd "$slither_workdir" && slither "$slither_source_name" --print cfg) > /dev/null 2>> "$CFG_ERR"; then
    echo "$solfile: CFG generation failed" >> "$CFG_ERR"
  fi
  find "$slither_workdir" -maxdepth 1 -type f -name "${slither_source_name}-*.dot" -newer "$cfg_ts" -print0 | while IFS= read -r -d '' dot_file; do
    dot_base=$(basename "$dot_file")
    cp "$dot_file" "$CFG_DIR/${safe_name}__${dot_base}"
    svg_base="${dot_base%.dot}.svg"
    if ! dot -Tsvg "$dot_file" -o "$CFG_DIR/${safe_name}__${svg_base}"; then
      echo "$dot_file: CFG svg rendering failed" >> "$CFG_ERR"
    fi
  done
  rm -f "$cfg_ts"

  # 生成DFG (使用 data-dependency printer)
  # Slither's data-dependency printer writes its content to stderr.
  if ! (cd "$slither_workdir" && slither "$slither_source_name" --print data-dependency) > /dev/null 2> "$dfg_out"; then
    echo "$solfile: DFG generation failed" >> "$DFG_ERR"
    rm -f "$dfg_out"
  fi
  rm -rf "$slither_workdir"
done < <(find "$SRC_ROOT" -name "*.sol" -print0)
