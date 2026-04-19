#!/usr/bin/env bash
# Install script for the AIDEX skill.
#
# Usage:
#   ./aidex-install.sh                        Install the AIDEX skill
#   ./aidex-install.sh --uninstall            Uninstall the AIDEX skill
#   ./aidex-install.sh --openclaw-dir <path>  Use a custom OpenClaw directory

set -euo pipefail

# ─── Config ──────────────────────────────────────────────────────────────────
SKILL_NAME="aidex"
TARBALL_URL="https://github.com/AIDEX-DeFi/skills/archive/main.tar.gz"
# Auto-detect OpenClaw directory unless overridden by --openclaw-dir.
find_openclaw_dir() {
  # 1. Standard location: $HOME/.openclaw
  if [[ -f "$HOME/.openclaw/openclaw.json" ]]; then
    echo "$HOME/.openclaw"
    return
  fi
  # 2. WSL: OpenClaw installed on Windows host
  if command -v cmd.exe &>/dev/null; then
    local win_home
    win_home=$(cmd.exe /c 'echo %USERPROFILE%' 2>/dev/null | tr -d '\r')
    if [[ -n "$win_home" ]]; then
      local wsl_path
      wsl_path=$(wslpath "$win_home" 2>/dev/null || true)
      if [[ -n "$wsl_path" && -f "$wsl_path/.openclaw/openclaw.json" ]]; then
        echo "$wsl_path/.openclaw"
        return
      fi
    fi
  fi
  # Not found — return default, pre-flight check will report the error
  echo "$HOME/.openclaw"
}

OPENCLAW_DIR=""

# ─── State ───────────────────────────────────────────────────────────────────
UNINSTALL=false
TMP_DIR=""

# ─── Colors (if terminal supports them) ──────────────────────────────────────
if [[ -t 1 ]]; then
  BOLD='\033[1m'    RESET='\033[0m'
  GREEN='\033[32m'  YELLOW='\033[33m'  RED='\033[31m'
else
  BOLD='' RESET='' GREEN='' YELLOW='' RED=''
fi

info()  { echo -e "  ${GREEN}✓${RESET} $*"; }
warn()  { echo -e "  ${YELLOW}!${RESET} $*"; }
err()   { echo -e "  ${RED}✗${RESET} $*" >&2; }
step()  { echo -e "\n${BOLD}==> $*${RESET}"; }

# Read "version" from a package.json file.
# Fails (non-zero exit) if the file is missing, malformed, or has no version field.
read_version() {
  local pkg_path="$1"
  $NODE_CMD -e '
    const pkg = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
    process.stdout.write(pkg.version);
  ' "$(node_path "$pkg_path")"
}

# Read input with masked echo (prints * for each character, handles backspace).
# Result is stored in MASKED_INPUT global variable.
read_masked() {
  MASKED_INPUT=""
  local char
  while IFS= read -rsn1 char; do
    if [[ -z "$char" ]]; then
      break
    fi
    if [[ "$char" == $'\x7f' || "$char" == $'\b' ]]; then
      if [[ -n "$MASKED_INPUT" ]]; then
        MASKED_INPUT="${MASKED_INPUT%?}"
        printf '\b \b'
      fi
    else
      MASKED_INPUT+="$char"
      printf '*'
    fi
  done
  echo ""
}

# ─── Cleanup ─────────────────────────────────────────────────────────────────
_cleanup() { [[ -n "${TMP_DIR:-}" && -d "${TMP_DIR:-}" ]] && rm -rf "$TMP_DIR" || true; }
trap _cleanup EXIT

# ─── Parse args ──────────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --uninstall)
      UNINSTALL=true
      shift
      ;;
    --openclaw-dir)
      if [[ $# -lt 2 ]]; then
        err "--openclaw-dir requires a path argument"
        exit 1
      fi
      OPENCLAW_DIR="$2"
      shift 2
      ;;
    --help|-h)
      echo "Usage: $0 [OPTIONS]"
      echo ""
      echo "Options:"
      echo "  --uninstall            Uninstall the AIDEX skill."
      echo "  --openclaw-dir <path>  Custom OpenClaw installation directory (default: ~/.openclaw)."
      echo "  -h, --help             Show this help."
      exit 0
      ;;
    *)
      err "Unknown argument: $1 (try --help)"
      exit 1
      ;;
  esac
done

# ─── Resolve paths ───────────────────────────────────────────────────────────
if [[ -z "$OPENCLAW_DIR" ]]; then
  OPENCLAW_DIR="$(find_openclaw_dir)"
fi
OPENCLAW_DIR="${OPENCLAW_DIR%/}"
CONFIG_PATH="$OPENCLAW_DIR/openclaw.json"
TARGET_DIR="$OPENCLAW_DIR/skills/$SKILL_NAME"

echo ""
echo "  OpenClaw directory: $OPENCLAW_DIR"

# ─── Pre-flight: OpenClaw installation present ───────────────────────────────
if [[ ! -f "$CONFIG_PATH" ]]; then
  err "OpenClaw installation not found at: $OPENCLAW_DIR"
  err ""
  err "If OpenClaw is not installed yet, install it first."
  err ""
  err "If OpenClaw is installed in a non-standard location, re-run with:"
  err "  ./aidex-install.sh --openclaw-dir /path/to/openclaw"
  exit 1
fi

# ─── Pre-flight: Node.js available ───────────────────────────────────────────
# Must run BEFORE the JSON validation below — validation uses node.
# Try `node` first (native), then `node.exe` (WSL interop with Windows host).
# When using node.exe, paths must be converted from Linux to Windows format.
node_path() {
  if [[ "$NODE_CMD" == "node.exe" ]]; then
    wslpath -w "$1"
  else
    echo "$1"
  fi
}

if command -v node &>/dev/null; then
  NODE_CMD="node"
elif command -v node.exe &>/dev/null; then
  NODE_CMD="node.exe"
else
  err "Node.js is required to install the AIDEX skill."
  err ""
  err "Either install Node.js, or run this script from the same environment"
  err "where OpenClaw runs and Node.js is already available."
  exit 1
fi

# ─── Pre-flight: validate OpenClaw config ────────────────────────────────────
if ! $NODE_CMD -e '
  const fs = require("fs");
  const configPath = process.argv[1];
  let config;
  try {
    config = JSON.parse(fs.readFileSync(configPath, "utf8"));
  } catch (err) {
    console.error("✗ Failed to parse OpenClaw config: " + configPath);
    console.error("  " + err.message);
    console.error("  Please fix the file manually before running this script again.");
    process.exit(1);
  }
  if (typeof config !== "object" || config === null || Array.isArray(config)) {
    console.error("✗ OpenClaw config is not a JSON object: " + configPath);
    process.exit(1);
  }
' "$(node_path "$CONFIG_PATH")"; then
  exit 1
fi

# ─── Uninstall branch ────────────────────────────────────────────────────────
if [[ "$UNINSTALL" == true ]]; then
  step "Uninstalling AIDEX skill"

  if [[ ! -d "$TARGET_DIR" ]]; then
    info "AIDEX skill was not installed, or has already been uninstalled."
    exit 0
  fi

  UNINSTALLED_VERSION="$(read_version "$TARGET_DIR/package.json" 2>/dev/null || true)"
  rm -rf "$TARGET_DIR"
  info "Removed $TARGET_DIR"

  $NODE_CMD -e '
    const fs = require("fs");
    const configPath = process.argv[1];
    const skillName = process.argv[2];
    const config = JSON.parse(fs.readFileSync(configPath, "utf8"));
    if (config.skills && config.skills.entries && config.skills.entries[skillName]) {
      delete config.skills.entries[skillName];
      fs.writeFileSync(configPath, JSON.stringify(config, null, 2));
    }
  ' "$(node_path "$CONFIG_PATH")" "$SKILL_NAME"
  info "Cleaned up OpenClaw config"

  echo ""
  echo -e "  ${GREEN}✓${RESET} AIDEX skill ${UNINSTALLED_VERSION:+v${UNINSTALLED_VERSION} }uninstalled from $TARGET_DIR"
  echo ""
  echo "  To apply the changes:"
  echo "    1. Run: openclaw gateway restart"
  echo -e "    ${BOLD}2. In the OpenClaw chat, type: /new${RESET}"
  echo ""
  exit 0
fi

# ─── Banner ──────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}  AIDEX Skill Installer${RESET}"
echo ""

# ─── Ensure skills directory exists ──────────────────────────────────────────
if [[ ! -d "$OPENCLAW_DIR/skills" ]]; then
  mkdir -p "$OPENCLAW_DIR/skills"
  info "Created skills directory: $OPENCLAW_DIR/skills"
fi

# ─── Check that the skill is not already installed ───────────────────────────
if [[ -d "$TARGET_DIR" ]]; then
  err "Skill \"$SKILL_NAME\" is already installed at: $TARGET_DIR"
  err ""
  err "  To reinstall, first remove it with:"
  err "    ./aidex-install.sh --uninstall"
  exit 1
fi

# ─── Check required tools ────────────────────────────────────────────────────
for cmd in curl tar; do
  if ! command -v "$cmd" &>/dev/null; then
    err "$cmd is required but not found"
    exit 1
  fi
done

# ─── Download, install, enable ───────────────────────────────────────────────
TMP_DIR="$(mktemp -d)"
tarball_file="$TMP_DIR/aidex.tar.gz"
mkdir -p "$TMP_DIR/extracted"
info "Downloading..."
if ! curl -fsSL "$TARBALL_URL" -o "$tarball_file"; then
  err "Failed to download from $TARBALL_URL"
  exit 1
fi
info "Installing..."
# --strip-components=1 drops GitHub's <repo>-<ref>/ wrapper directory.
if ! tar -xzf "$tarball_file" -C "$TMP_DIR/extracted" --strip-components=1; then
  err "Failed to extract the downloaded archive"
  exit 1
fi

SOURCE_PATH="$TMP_DIR/extracted/skills/aidex"
if [[ ! -f "$SOURCE_PATH/SKILL.md" ]]; then
  err "Downloaded archive does not contain skills/aidex/SKILL.md"
  exit 1
fi

INSTALLED_VERSION="$(read_version "$SOURCE_PATH/package.json")"

mkdir -p "$TARGET_DIR"
cp -r "$SOURCE_PATH/." "$TARGET_DIR/"

info "Enabling..."
$NODE_CMD -e '
  const fs = require("fs");
  const configPath = process.argv[1];
  const skillName = process.argv[2];
  const config = JSON.parse(fs.readFileSync(configPath, "utf8"));
  if (!config.skills) config.skills = {};
  if (!config.skills.entries) config.skills.entries = {};
  if (!config.skills.entries[skillName]) config.skills.entries[skillName] = {};
  config.skills.entries[skillName].enabled = true;
  fs.writeFileSync(configPath, JSON.stringify(config, null, 2));
' "$(node_path "$CONFIG_PATH")" "$SKILL_NAME"

# ─── Optional: configure private key (interactive only) ─────────────────────
if [[ -t 0 ]]; then
  echo ""
  echo "  Would you like to configure your private key now?"
  echo "  This is optional — press Enter to skip."
  echo ""
  while true; do
    printf "  Private key: "
    read_masked
    private_key="$MASKED_INPUT"

    if [[ -z "$private_key" ]]; then
      info "Skipped."
      break
    fi

    if [[ "$private_key" =~ ^(0x)?[0-9a-fA-F]{64}$ ]]; then
      export AIDEX_KEY="$private_key"
      export WSLENV="${WSLENV:-}:AIDEX_KEY"
      $NODE_CMD -e '
        const fs = require("fs");
        const configPath = process.argv[1];
        const skillName = process.argv[2];
        const key = process.env.AIDEX_KEY;
        const config = JSON.parse(fs.readFileSync(configPath, "utf8"));
        if (!config.skills.entries[skillName].env) config.skills.entries[skillName].env = {};
        config.skills.entries[skillName].env.AIDEX_PRIVATE_KEY = key;
        fs.writeFileSync(configPath, JSON.stringify(config, null, 2));
      ' "$(node_path "$CONFIG_PATH")" "$SKILL_NAME"
      unset AIDEX_KEY
      info "Private key configured."
      break
    fi

    err "Invalid key format. Expected 64 hex characters, optionally prefixed with 0x."
    echo "  Please try again, or press Enter to skip."
    echo ""
  done
fi

# ─── Done ────────────────────────────────────────────────────────────────────
echo ""
echo -e "  ${GREEN}✓${RESET} AIDEX skill v${INSTALLED_VERSION} installed at $TARGET_DIR"
echo ""
echo "  To activate the skill:"
echo "    1. Run: openclaw gateway restart"
echo -e "    ${BOLD}2. In the OpenClaw chat, type: /new${RESET}"
echo ""
echo "  Note: The first request may take up to a minute while"
echo "  the skill installs its dependencies."
echo ""
