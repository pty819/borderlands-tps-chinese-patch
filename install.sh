#!/usr/bin/env bash
# ============================================================
#  《无主之地：前传》简体中文汉化补丁  v1.0
#  Borderlands: The Pre-Sequel  Simplified Chinese Patch
# ------------------------------------------------------------
#  用法:
#    bash install.sh                 # 安装（自动找游戏目录）
#    bash install.sh --game DIR      # 手动指定游戏目录
#    bash install.sh --verify        # 校验已安装文件
#    bash install.sh --uninstall     # 撤销（恢复安装前状态）
#    bash install.sh --dry-run       # 只打印将要做的事
# ============================================================
set -euo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PAYLOAD="$SELF_DIR/payload"
MANIFEST="$SELF_DIR/manifest.sha256"

MODE="install"
GAME=""
DRY=0

shopt -s nocasematch
CACHE_DIR=""
die() { printf '错误: %s\n' "$*" >&2; exit 1; }
info() { printf '%s\n' "$*"; }

usage() {
  sed -n '3,15p' "$SELF_DIR/install.sh" | sed -n 's/^# \{0,1\}//p; s/^# \{0,1\}$//p'
}

while [ $# -gt 0 ]; do
  case "$1" in
    --game)      [ $# -ge 2 ] || die "--game 需要一个目录参数"; GAME="$2"; shift 2 ;;
    --verify)    MODE="verify"; shift ;;
    --uninstall) MODE="uninstall"; shift ;;
    --dry-run)   DRY=1; shift ;;
    -h|--help)   usage; exit 0 ;;
    *)           die "未知参数: $1（--help 查看用法）" ;;
  esac
done

# ---------- 找游戏目录 ----------
detect_game() {
  local candidates=(
    "${BLTPS_DIR:-}"
    "$HOME/.local/share/Steam/steamapps/common/BorderlandsPreSequel"
    "$HOME/.steam/steam/steamapps/common/BorderlandsPreSequel"
    "$HOME/.steam/root/steamapps/common/BorderlandsPreSequel"
    "$HOME/Steam/steamapps/common/BorderlandsPreSequel"
  )
  local d
  for d in "${candidates[@]}"; do
    [ -n "$d" ] || continue
    if [ -f "$d/WillowGame/CookedPCConsole/Startup.upk" ]; then printf '%s' "$d"; return 0; fi
  done
  # 常见外挂库路径
  for d in /media/*/SteamLibrary/steamapps/common/BorderlandsPreSequel \
           /mnt/*/SteamLibrary/steamapps/common/BorderlandsPreSequel \
           /run/media/*/*/SteamLibrary/steamapps/common/BorderlandsPreSequel; do
    [ -e "$d" ] || continue
    if [ -f "$d/WillowGame/CookedPCConsole/Startup.upk" ]; then printf '%s' "$d"; return 0; fi
  done
  return 1
}

lower() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }

# 逐级大小写不敏感地解析/创建目录: resolve_dir <base> <rel/dir/path>
resolve_dir() {
  local cur="$1" rel="$2" part parts=() found="" bn lc tlc e
  if [ -z "$rel" ] || [ "$rel" = "." ]; then printf '%s' "$cur"; return 0; fi
  IFS='/' read -r -a parts <<< "$rel"
  for part in "${parts[@]}"; do
    [ -n "$part" ] || continue
    found=""
    if [ -d "$cur" ]; then
      if [ -d "$cur/$part" ]; then found="$cur/$part"; fi
    fi
    if [ -z "$found" ] && [ -d "$cur" ]; then
      while IFS= read -r -d '' e; do
        if [ -d "$e" ] && [[ "$(basename "$e")" == "$part" ]]; then found="$e"; break; fi
      done < <(find "$cur" -mindepth 1 -maxdepth 1 -type d -print0 2>/dev/null)
    fi
    if [ -z "$found" ]; then
      found="$cur/$part"
      [ "$DRY" -eq 1 ] || mkdir -p "$found"
    fi
    cur="$found"
  done
  printf '%s' "$cur"
}

# 在目录中按大小写不敏感查找同名文件，输出真实路径
find_ci_file() {
  local dir="$1" name="$2" cache lc hit
  [ -d "$dir" ] || return 1
  if [ -f "$dir/$name" ]; then printf '%s' "$dir/$name"; return 0; fi
  cache="$CACHE_DIR/$(printf '%s' "$dir" | cksum | cut -d' ' -f1)"
  if [ ! -f "$cache" ]; then
    ls -1 "$dir" 2>/dev/null | awk '{print tolower($0)"|"$0}' > "$cache" || true
  fi
  lc="$(printf '%s' "$name" | tr '[:upper:]' '[:lower:]')"
  hit="$(awk -F'|' -v k="$lc" '$1==k {print $2; exit}' "$cache")"
  [ -n "$hit" ] && printf '%s' "$dir/$hit"
  [ -n "$hit" ]
}

# ---------- 安装清单 ----------
# 只处理 payload/ 下的 WillowGame/** 与 DLC/**
list_payload() {
  local f rel
  while IFS= read -r -d '' f; do
    rel="${f#"$PAYLOAD"/}"
    case "$rel" in
      WillowGame/*|DLC/*) printf '%s\0' "$rel" ;;
    esac
  done < <(find "$PAYLOAD" -type f -print0)
}

latest_backup() {
  local d="$GAME/bltps-cn-backup"
  [ -d "$d" ] && printf '%s' "$d"
}

sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | awk '{print $1}'
  else shasum -a 256 "$1" | awk '{print $1}'; fi
}

# ---------- 主流程 ----------
if [ -z "$GAME" ]; then
  if ! GAME="$(detect_game)"; then
    die "没找到游戏目录。请用 --game 指定，例如:
  bash install.sh --game \"$HOME/.local/share/Steam/steamapps/common/BorderlandsPreSequel\""
  fi
fi
[ -d "$GAME" ] || die "游戏目录不存在: $GAME"
[ -f "$GAME/WillowGame/CookedPCConsole/Startup.upk" ] || die "这个目录不像 BLTPS 安装目录（缺 WillowGame/CookedPCConsole/Startup.upk）: $GAME"
GAME="$(cd "$GAME" && pwd)"
CACHE_DIR="$(mktemp -d)"
trap 'rm -rf "$CACHE_DIR"' EXIT
info "游戏目录: $GAME"

case "$MODE" in

install)
  BK="$GAME/bltps-cn-backup"
  if [ "$DRY" -eq 1 ]; then
    info "[dry-run] 将备份到: $BK"
  else
    mkdir -p "$BK/files"
    touch "$BK/added.txt"
  fi

  copied=0; added=0; backed=0
  while IFS= read -r -d '' rel; do
    dir_rel="$(dirname "$rel")"
    name="$(basename "$rel")"
    tdir="$(resolve_dir "$GAME" "$dir_rel")"
    existing="$(find_ci_file "$tdir" "$name" || true)"
    target="$tdir/$name"

    if [ "$DRY" -eq 1 ]; then
      info "  + $rel -> ${target#"$GAME"/}"
      copied=$((copied+1)); continue
    fi

    if [ -n "$existing" ]; then
      if grep -qxF "$rel" "$BK/added.txt" 2>/dev/null; then
        : # 上次安装新增的文件，不算原版，不做备份
      elif [ ! -f "$BK/files/$rel" ]; then
        mkdir -p "$BK/files/$(dirname "$rel")"
        cp -p "$existing" "$BK/files/$rel"
        backed=$((backed+1))
      fi
      [ "$existing" = "$target" ] || rm -f "$existing"
    else
      if ! grep -qxF "$rel" "$BK/added.txt" 2>/dev/null; then
        printf '%s\n' "$rel" >> "$BK/added.txt"
        added=$((added+1))
      fi
    fi
    cp "$PAYLOAD/$rel" "$target"
    copied=$((copied+1))
  done < <(list_payload)

  info ""
  info "完成: 写入 ${copied} 个文件（覆盖 ${backed} 个，新增 ${added} 个）"
  if [ "$DRY" -eq 0 ]; then
    info "安装前备份: $BK"
    info "校验: bash install.sh --verify"
    info "撤销: bash install.sh --uninstall"
  fi
  ;;

verify)
  [ -f "$MANIFEST" ] || die "缺少校验清单 manifest.sha256"
  total=0; ok=0; bad=0; missing=0
  while IFS=' ' read -r h rel; do
    [ -n "$rel" ] || continue
    total=$((total+1))
    dir_rel="$(dirname "$rel")"; name="$(basename "$rel")"
    tdir="$(resolve_dir "$GAME" "$dir_rel")"
    f="$(find_ci_file "$tdir" "$name" || true)"
    if [ -z "$f" ]; then missing=$((missing+1)); printf '缺少: %s\n' "$rel"; continue; fi
    ah="$(sha256_of "$f")"
    if [ "$ah" = "$h" ]; then ok=$((ok+1)); else bad=$((bad+1)); printf '不一致: %s\n' "$rel"; fi
  done < "$MANIFEST"

  info ""
  info "校验结果: 共 ${total} 项，正常 ${ok}，不一致 ${bad}，缺失 ${missing}"
  if [ "$bad" -eq 0 ] && [ "$missing" -eq 0 ]; then
    info "PASS - 汉化文件完整"
  else
    info "FAIL - 建议重新运行: bash install.sh"
    exit 1
  fi
  ;;

uninstall)
  BK="$(latest_backup || true)"
  [ -n "$BK" ] || die "没有找到备份目录（bltps-cn-backup），无法自动撤销。"
  info "使用备份: $BK"
  restored=0; removed=0
  if [ -d "$BK/files" ]; then
    while IFS= read -r -d '' f; do
      rel="${f#"$BK/files"/}"
      dir_rel="$(dirname "$rel")"; name="$(basename "$rel")"
      tdir="$(resolve_dir "$GAME" "$dir_rel")"
      exist="$(find_ci_file "$tdir" "$name" || true)"
      [ -n "$exist" ] && [ "$exist" != "$tdir/$name" ] && rm -f "$exist"
      cp -p "$f" "$tdir/$name"
      restored=$((restored+1))
    done < <(find "$BK/files" -type f -print0)
  fi
  if [ -f "$BK/added.txt" ]; then
    while IFS= read -r rel; do
      [ -n "$rel" ] || continue
      dir_rel="$(dirname "$rel")"; name="$(basename "$rel")"
      tdir="$(resolve_dir "$GAME" "$dir_rel")"
      exist="$(find_ci_file "$tdir" "$name" || true)"
      [ -n "$exist" ] && rm -f "$exist" && removed=$((removed+1))
    done < "$BK/added.txt"
  fi
  info "撤销完成: 恢复 ${restored} 个文件，删除 ${removed} 个新增文件"
  ;;

esac
