#!/usr/bin/env bash
set -Eeuo pipefail

###############################################################################
# Learning Platform Setup Wizard
# Supports:
# - macOS Terminal
# - Ubuntu on WSL
# - Linux
#
###############################################################################

#######################################
# Globals
#######################################
DOCTOR_ONLY="false"
AUTO_YES="false"

if [[ "${1:-}" == "--doctor" ]]; then
  DOCTOR_ONLY="true"
fi

if [[ "${1:-}" == "--yes" ]] || [[ "${2:-}" == "--yes" ]]; then
  AUTO_YES="true"
fi

#######################################
# Colors / formatting
#######################################
if [[ -t 1 ]]; then
  BOLD="\033[1m"
  DIM="\033[2m"
  RED="\033[31m"
  GREEN="\033[32m"
  YELLOW="\033[33m"
  BLUE="\033[34m"
  MAGENTA="\033[35m"
  CYAN="\033[36m"
  RESET="\033[0m"
else
  BOLD=""
  DIM=""
  RED=""
  GREEN=""
  YELLOW=""
  BLUE=""
  MAGENTA=""
  CYAN=""
  RESET=""
fi

#######################################
# Paths
#######################################
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CURRENT_INFRA_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
ROOT_DIR="${HOME}/workspace/lms"
TARGET_INFRA_DIR="${ROOT_DIR}/learn-ops-infrastructure"
API_DIR="${ROOT_DIR}/learn-ops-api"
CLIENT_DIR="${ROOT_DIR}/learn-ops-client"
MONARCH_DIR="${ROOT_DIR}/service-monarch"

#######################################
# Repo URLs
# Adjust these if needed.
#######################################
API_REPO_URL="git@github.com:System-Explorer-Cohorts/learn-ops-api.git"
CLIENT_REPO_URL="git@github.com:System-Explorer-Cohorts/learn-ops-client.git"
INFRA_REPO_URL_DEFAULT="git@github.com:System-Explorer-Cohorts/learn-ops-infrastructure.git"
MONARCH_REPO_URL="git@github.com:System-Explorer-Cohorts/service-monarch.git"
NSS_ORG="System-Explorer-Cohorts"
GITHUB_API="https://api.github.com"

#######################################
# State
#######################################
OS_FAMILY=""
MAC_ARCH=""
WSL_ARCH=""
RUNNING_IN_WSL="false"

#######################################
# Utilities
#######################################
have_cmd() {
  command -v "$1" >/dev/null 2>&1
}

port_in_use() {
  local port="$1"
  if command -v lsof >/dev/null 2>&1; then
    lsof -i :"${port}" -sTCP:LISTEN -t >/dev/null 2>&1
  else
    (echo >/dev/tcp/localhost/"${port}") 2>/dev/null
  fi
}

hr() {
  printf "%b\n" "${CYAN}================================================================${RESET}"
}

header() {
  echo
  hr
  printf "%b\n" "${BOLD}${CYAN}Learning Platform Setup Wizard${RESET}"
  printf "%b\n" "${DIM}Preparing a complete LMS workspace in ${ROOT_DIR}${RESET}"
  hr
  echo
}

step() {
  echo
  printf "%b\n" "${BOLD}${BLUE}▶ $1${RESET}"
}

substep() {
  printf "   %b\n" "${DIM}$1${RESET}"
}

ok() {
  printf "%b\n" "${GREEN}   ✔ $1${RESET}"
}

warn() {
  printf "%b\n" "${YELLOW}   ⚠ $1${RESET}"
}

err() {
  printf "%b\n" "${RED}   ✖ $1${RESET}"
}

die() {
  err "$1"
  exit 1
}

on_error() {
  local exit_code=$?
  echo
  err "Setup stopped because a command failed."
  warn "Exit code: ${exit_code}"
  warn "If you rerun setup, it will reuse anything already completed."
  exit "${exit_code}"
}
trap on_error ERR

section_done() {
  printf "%b\n" "${GREEN}${BOLD}✓ $1 complete${RESET}"
}

# Returns 0 (true) if version $1 >= $2 (semver-aware)
version_ge() {
  [ "$(printf '%s\n' "$1" "$2" | sort -V | head -n1)" = "$2" ]
}

#######################################
# Prompt helpers
#######################################
prompt_text() {
  local message="$1"
  printf "%b" "${BOLD}${message}${RESET} "
}

# Stores the result of masked_read — avoids bash local-variable shadowing.
_MASKED_INPUT=""

# Read a secret value, printing • for each character so users can confirm
# their paste landed and has the right length. Handles backspace and Enter.
# Result is stored in the global _MASKED_INPUT.
masked_read() {
  _MASKED_INPUT=""
  local char=""

  while IFS= read -r -s -n1 char; do
    if [[ -z "$char" ]]; then                                      # Enter
      break
    elif [[ "$char" == $'\x7f' || "$char" == $'\b' ]]; then       # Backspace
      if [[ -n "$_MASKED_INPUT" ]]; then
        _MASKED_INPUT="${_MASKED_INPUT%?}"
        printf "\b \b"
      fi
    elif [[ "$char" == $'\x1b' ]]; then                            # ESC sequence — skip rest of sequence
      local seq=""
      IFS= read -r -s -n1 -t 0.05 seq || true
      if [[ "$seq" == "[" ]]; then
        IFS= read -r -s -n1 -t 0.05 || true   # consume final byte
      fi
    else
      _MASKED_INPUT+="$char"
      printf "•"
    fi
  done
  printf "\n"
}

prompt_required() {
  local var_name="$1"
  local title="$2"
  local helper="$3"
  local secret="${4:-false}"
  local value=""

  echo
  printf "%b\n" "${BOLD}${MAGENTA}${title}${RESET}"
  printf "%b\n" "${DIM}${helper}${RESET}"

  while [[ -z "${value}" ]]; do
    if [[ "${secret}" == "true" ]]; then
      printf "%b" "$(prompt_text "→ Enter value:")"
      masked_read
      value="$_MASKED_INPUT"
    else
      read -r -p "$(prompt_text "→ Enter value:")" value
    fi

    if [[ -z "${value}" ]]; then
      warn "This value is required."
    fi
  done

  printf -v "${var_name}" '%s' "${value}"
}

prompt_with_default() {
  local var_name="$1"
  local title="$2"
  local helper="$3"
  local default_value="$4"
  local value=""

  echo
  printf "%b\n" "${BOLD}${MAGENTA}${title}${RESET}"
  printf "%b\n" "${DIM}${helper}${RESET}"

  read -r -p "$(prompt_text "→ Press Enter to use '${default_value}', or type a new value:")" value

  value="${value:-$default_value}"
  printf -v "${var_name}" '%s' "${value}"
}

prompt_reuse_secret() {
  local var_name="$1"
  local title="$2"
  local helper="$3"
  local cached_value="$4"

  if [[ -z "${cached_value}" ]]; then
    prompt_required "${var_name}" "${title}" "${helper}" true
    return
  fi

  echo
  printf "%b\n" "${BOLD}${MAGENTA}${title}${RESET}"
  local preview="${cached_value:0:6}••••"
  printf "%b\n" "${DIM}Saved value found: ${preview}${RESET}"

  if confirm_yes_no "Reuse this saved value?"; then
    printf -v "${var_name}" '%s' "${cached_value}"
    ok "Reusing saved ${title}"
  else
    prompt_required "${var_name}" "${title}" "${helper}" true
  fi
}

confirm_yes_no() {
  local prompt="$1"

  if [[ "${AUTO_YES}" == "true" ]]; then
    return 0
  fi

  local answer=""
  read -r -p "$(prompt_text "${prompt} [Y/n]")" answer
  answer="${answer:-Y}"
  [[ "${answer}" =~ ^[Yy]$ ]]
}

#######################################
# Detection
#######################################
detect_platform() {
  step "Detecting your environment"

  local uname_s
  uname_s="$(uname -s)"

  case "${uname_s}" in
    Darwin)
      OS_FAMILY="macOS"
      local uname_m
      uname_m="$(uname -m)"
      if [[ "${uname_m}" == "arm64" ]]; then
        MAC_ARCH="arm64"
      else
        MAC_ARCH="amd64"
      fi
      ;;
    Linux)
      OS_FAMILY="Linux"
      if grep -qi microsoft /proc/version 2>/dev/null || [[ -n "${WSL_DISTRO_NAME:-}" ]]; then
        RUNNING_IN_WSL="true"
        OS_FAMILY="WSL"
        local uname_m
        uname_m="$(uname -m)"
        if [[ "${uname_m}" == "aarch64" ]]; then
          WSL_ARCH="arm64"
        else
          WSL_ARCH="amd64"
        fi
      fi
      ;;
    *)
      die "Unsupported platform: ${uname_s}. Use macOS Terminal or Ubuntu in WSL."
      ;;
  esac

  ok "Detected platform: ${OS_FAMILY}"

  if [[ "${OS_FAMILY}" == "WSL" ]]; then
    ok "Running inside WSL (${WSL_ARCH})"
  fi

  if [[ "${OS_FAMILY}" == "Linux" ]]; then
    warn "Regular Linux detected. This script is optimized for macOS and Ubuntu on WSL, but Linux should work."
  fi

  section_done "Environment detection"
}

#######################################
# Command checks
#######################################
need_cmd() {
  local cmd="$1"
  local help_text="$2"

  if have_cmd "${cmd}"; then
    ok "Found ${cmd}"
  else
    die "'${cmd}' is not installed. ${help_text}"
  fi
}

check_make_usage_note() {
  if [[ "${OS_FAMILY}" == "WSL" ]]; then
    ok "Windows users should run this inside Ubuntu WSL, not PowerShell"
  fi
}

print_docker_install_instructions() {
  case "${OS_FAMILY}" in
    macOS)
      local docker_url
      if [[ "${MAC_ARCH}" == "arm64" ]]; then
        docker_url="https://desktop.docker.com/mac/main/arm64/Docker.dmg"
        printf "   %b\n" "${BOLD}Apple Silicon Mac detected — Install Docker Desktop:${RESET}"
      else
        docker_url="https://desktop.docker.com/mac/main/amd64/Docker.dmg"
        printf "   %b\n" "${BOLD}Intel Mac detected — Install Docker Desktop:${RESET}"
      fi
      printf "     %s\n" "1. Download: ${docker_url}"
      printf "     %s\n" "2. Open the .dmg and drag Docker to Applications"
      printf "     %s\n" "3. Launch Docker from Applications"
      printf "     %s\n" "4. Accept the Docker terms of service when prompted"
      printf "     %s\n" "5. Wait for the whale icon to appear in the menu bar"
      printf "\n"
      printf "   %b\n" "${BOLD}Heads up — you may see these popups during setup:${RESET}"
      printf "     %s\n" "* macOS asks: \"Terminal would like to access data from other apps\" → click Allow"
      printf "     %s\n" "* Docker asks you to sign in or create an account → click Skip (not required)"
      ;;
    WSL)
      local docker_win_url
      if [[ "${WSL_ARCH}" == "arm64" ]]; then
        docker_win_url="https://desktop.docker.com/win/main/arm64/Docker%20Desktop%20Installer.exe"
        printf "   %b\n" "${BOLD}ARM64 Windows detected — Install Docker Desktop:${RESET}"
      else
        docker_win_url="https://desktop.docker.com/win/main/amd64/Docker%20Desktop%20Installer.exe"
        printf "   %b\n" "${BOLD}AMD64 Windows detected — Install Docker Desktop:${RESET}"
      fi
      printf "     %s\n" "1. Download (run this in Windows, not WSL): ${docker_win_url}"
      printf "     %s\n" "2. Run the installer"
      printf "     %s\n" "3. Launch Docker Desktop from the Start Menu"
      printf "     %s\n" "4. Accept the Docker terms of service when prompted"
      printf "     %s\n" "5. Wait for the whale icon to appear in the system tray (bottom-right of taskbar)"
      printf "     %s\n" "6. Settings → Resources → WSL Integration → enable Ubuntu"
      printf "     %s\n" "7. Restart Docker Desktop"
      printf "\n"
      printf "   %b\n" "${BOLD}Heads up — you may see this popup during setup:${RESET}"
      printf "     %s\n" "* Docker asks you to sign in or create an account → click Skip (not required)"
      ;;
    *)
      printf "   %b\n" "${BOLD}Install Docker Engine:${RESET}"
      printf "     %s\n" "1. curl -fsSL https://get.docker.com | sh"
      printf "     %s\n" "   (or follow https://docs.docker.com/engine/install/)"
      printf "     %s\n" "2. sudo usermod -aG docker \$USER"
      printf "     %s\n" "3. newgrp docker          (or log out and back in)"
      printf "     %s\n" "4. sudo systemctl enable --now docker"
      ;;
  esac
}

check_docker_installed() {
  until have_cmd docker; do
    err "Docker is not installed."
    print_docker_install_instructions
    printf "   Press Enter once Docker is installed, or Ctrl+C to cancel...\n"
    read -r
    hash -r 2>/dev/null || true
  done
  ok "Found docker"
}

print_compose_install_instructions() {
  case "${OS_FAMILY}" in
    macOS|WSL)
      printf "   %b\n" "${BOLD}Docker Desktop includes Compose v2 — ensure it is up to date:${RESET}"
      printf "     %s\n" "1. Click the Docker icon → Check for Updates"
      printf "     %s\n" "2. Or download the latest from https://www.docker.com/products/docker-desktop/"
      printf "     %s\n" "3. Restart Docker Desktop after updating"
      ;;
    *)
      printf "   %b\n" "${BOLD}Install the Docker Compose plugin:${RESET}"
      printf "     %s\n" "Debian/Ubuntu:  sudo apt-get update && sudo apt-get install docker-compose-plugin"
      printf "     %s\n" "Other distros:  https://docs.docker.com/compose/install/linux/"
      ;;
  esac
}

check_compose_available() {
  until docker compose version >/dev/null 2>&1; do
    err "docker compose is unavailable."
    print_compose_install_instructions
    printf "   Press Enter once Compose is available, or Ctrl+C to cancel...\n"
    read -r
  done
  ok "Found docker compose"
}

check_prereqs() {
  step "Checking required tools"

  need_cmd git "Install Git, then rerun setup."
  check_docker_installed
  need_cmd python3 "Install Python 3, then rerun setup."
  need_cmd make "Install make, then rerun setup."

  check_compose_available

  check_make_usage_note
  section_done "Prerequisite checks"
}

#######################################
# Docker checks
#######################################
check_docker_running() {
  step "Checking Docker status"
  substep "Making sure the Docker daemon is reachable"

  until docker info >/dev/null 2>&1; do
    warn "Docker is not running. Please start Docker Desktop (or Docker Engine)."
    printf "   Press Enter once Docker is running, or Ctrl+C to cancel...\n"
    read -r
  done
  ok "Docker daemon is running"

  if [[ "${OS_FAMILY}" == "WSL" ]]; then
    warn "Make sure Docker Desktop has WSL integration enabled for your Ubuntu distro."
  fi

  check_docker_versions

  section_done "Docker status"
}

check_docker_versions() {
  local required_cli="28.1.1"
  local required_desktop="4.69.0"

  # --- Docker CLI version ---
  local cli_version
  cli_version=$(docker version --format '{{.Client.Version}}' 2>/dev/null || true)

  if [[ -z "${cli_version}" ]]; then
    die "Could not determine Docker CLI version. Please ensure Docker is running and up to date (requires ${required_cli})."
  fi

  while ! version_ge "${cli_version}" "${required_cli}"; do
    err "Docker CLI version ${cli_version} is too old. Requires ${required_cli} or newer."
    if [[ "${OS_FAMILY}" == "WSL" ]]; then
      printf "   To update on WSL:\n"
      printf "     1. Open Docker Desktop on Windows.\n"
      printf "     2. Click the Docker tray icon → Settings → Software Updates → Check for updates.\n"
      printf "     3. Or download the latest version from https://www.docker.com/products/docker-desktop/\n"
      printf "     4. After updating, restart Docker Desktop.\n"
    elif [[ "${OS_FAMILY}" == "macOS" ]]; then
      printf "   To update on macOS:\n"
      printf "     1. Click the Docker icon in the menu bar → Check for Updates.\n"
      printf "     2. Or download the latest version from https://www.docker.com/products/docker-desktop/\n"
      printf "     3. After updating, restart Docker Desktop.\n"
    else
      printf "   Please update Docker Engine to ${required_cli} or newer.\n"
    fi
    printf "   Press Enter once Docker has been updated and restarted, or Ctrl+C to cancel...\n"
    read -r
    cli_version=$(docker version --format '{{.Client.Version}}' 2>/dev/null || true)
  done
  ok "Docker CLI version ${cli_version} meets requirement (>= ${required_cli})"

  # --- Docker Desktop version (macOS only) ---
  if [[ "${OS_FAMILY}" == "macOS" ]]; then
    local desktop_version
    desktop_version=$(defaults read /Applications/Docker.app/Contents/Info CFBundleShortVersionString 2>/dev/null || true)

    while [[ -n "${desktop_version}" ]] && ! version_ge "${desktop_version}" "${required_desktop}"; do
      err "Docker Desktop version ${desktop_version} is too old. Requires ${required_desktop} or newer."
      printf "   To update on macOS:\n"
      printf "     1. Click the Docker icon in the menu bar → Check for Updates.\n"
      printf "     2. Or download the latest version from https://www.docker.com/products/docker-desktop/\n"
      printf "     3. After updating, restart Docker Desktop.\n"
      printf "   Press Enter once Docker Desktop has been updated and restarted, or Ctrl+C to cancel...\n"
      read -r
      desktop_version=$(defaults read /Applications/Docker.app/Contents/Info CFBundleShortVersionString 2>/dev/null || true)
    done

    if [[ -z "${desktop_version}" ]]; then
      warn "Could not read Docker Desktop version (is Docker Desktop installed at /Applications/Docker.app?)."
    else
      ok "Docker Desktop version ${desktop_version} meets requirement (>= ${required_desktop})"
    fi
  fi
}

show_port_blocker() {
  local port="$1"
  if command -v lsof >/dev/null 2>&1; then
    local pids
    pids="$(lsof -i :"${port}" -sTCP:LISTEN -t 2>/dev/null || true)"
    if [[ -n "${pids}" ]]; then
      printf "     %s\n" "What's using port ${port}:"
      lsof -i :"${port}" -sTCP:LISTEN -P -n 2>/dev/null | tail -n +2 | while IFS= read -r line; do
        printf "       %s\n" "${line}"
      done
      printf "     %s\n" "To stop it, run:"
      for pid in ${pids}; do
        printf "       %s\n" "kill ${pid}"
      done
    fi
  else
    printf "     %s\n" "Run this to find what's using port ${port}:"
    printf "       %s\n" "sudo ss -tlnp | grep :${port}"
  fi
}

port_name() {
  case "$1" in
    5432) printf "PostgreSQL" ;;
    8000) printf "Django API" ;;
    3000) printf "React Client" ;;
    9090) printf "Prometheus" ;;
    3001) printf "Grafana" ;;
    9187) printf "PostgreSQL Exporter" ;;
    5678) printf "Python Debugger" ;;
    6379) printf "Valkey Cache" ;;
    *)    printf "Unknown" ;;
  esac
}

check_port_conflicts() {
  step "Checking for port conflicts"

  local -a required_ports=(5432 8000 3000)
  local -a optional_ports=(9090 3001 9187 5678 6379)

  for port in "${optional_ports[@]}"; do
    if port_in_use "${port}"; then
      warn "Port ${port} ($(port_name "${port}")) is already in use — monitoring/debug may be affected"
    else
      ok "Port ${port} ($(port_name "${port}")) is free"
    fi
  done

  for port in "${required_ports[@]}"; do
    while port_in_use "${port}"; do
      err "Port ${port} ($(port_name "${port}")) is already in use — must be free before setup can continue"
      show_port_blocker "${port}"
      printf "   Press Enter once port %s is free, or Ctrl+C to cancel...\n" "${port}"
      read -r
      hash -r 2>/dev/null || true
    done
    ok "Port ${port} ($(port_name "${port}")) is free"
  done

  section_done "Port conflict check"
}

#######################################
# Infra repo normalization
#######################################
get_current_infra_remote() {
  local remote=""
  if git -C "${CURRENT_INFRA_DIR}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    remote="$(git -C "${CURRENT_INFRA_DIR}" remote get-url origin 2>/dev/null || true)"
  fi
  echo "${remote:-${INFRA_REPO_URL_DEFAULT}}"
}

ensure_workspace_root() {
  step "Preparing workspace root"

  mkdir -p "${ROOT_DIR}"
  ok "Workspace directory ready: ${ROOT_DIR}"

  section_done "Workspace root"
}

normalize_infra_location_if_needed() {
  step "Ensuring the infrastructure repo is in the expected location"

  if [[ "${CURRENT_INFRA_DIR}" == "${TARGET_INFRA_DIR}" ]]; then
    ok "Infrastructure repo is already at ${TARGET_INFRA_DIR}"
    section_done "Infrastructure repo location"
    return
  fi

  echo
  hr
  err "Setup must be run from the expected workspace location."
  echo
  warn "You ran setup from:  ${CURRENT_INFRA_DIR}"
  warn "Expected location:   ${TARGET_INFRA_DIR}"
  echo
  substep "Please move the repo to the correct location and re-run setup:"
  echo
  printf "   %b\n" "${BOLD}mv ${CURRENT_INFRA_DIR} ${TARGET_INFRA_DIR}${RESET}"
  printf "   %b\n" "${BOLD}cd ${TARGET_INFRA_DIR}${RESET}"
  printf "   %b\n" "${BOLD}make setup${RESET}"
  echo
  hr
  echo
  exit 1
}

#######################################
# SSH setup
#######################################
ensure_github_ssh() {
  step "Setting up SSH access to GitHub"

  # Fast path: SSH to GitHub already works — nothing to do.
  local test_out
  test_out="$(ssh -o BatchMode=yes -o ConnectTimeout=5 -T git@github.com 2>&1)" || true
  if echo "${test_out}" | grep -q "successfully authenticated"; then
    ok "GitHub SSH already configured and working"
    section_done "GitHub SSH access"
    return 0
  fi

  # Find an existing private key or generate a new one.
  local ssh_key=""
  for candidate in "${HOME}/.ssh/id_ed25519" "${HOME}/.ssh/id_ecdsa" "${HOME}/.ssh/id_rsa"; do
    if [[ -f "${candidate}" ]]; then
      ssh_key="${candidate}"
      break
    fi
  done

  if [[ -z "${ssh_key}" ]]; then
    substep "No SSH key found — generating a new ed25519 key..."
    ssh-keygen -t ed25519 -C "${USER_EMAIL}" -f "${HOME}/.ssh/id_ed25519" -N ""
    ssh_key="${HOME}/.ssh/id_ed25519"
    ok "SSH key generated: ${ssh_key}"
  else
    ok "Found existing SSH key: ${ssh_key}"
  fi

  # Ensure ssh-agent is running and the key is loaded.
  if ! ssh-add -l >/dev/null 2>&1; then
    eval "$(ssh-agent -s)" >/dev/null
  fi
  if [[ "${OS_FAMILY}" == "macOS" ]]; then
    # Prefer the modern --apple-use-keychain flag (macOS Ventura+);
    # fall back to legacy -K (older macOS), then plain add.
    ssh-add --apple-use-keychain "${ssh_key}" 2>/dev/null \
      || ssh-add -K "${ssh_key}" 2>/dev/null \
      || ssh-add "${ssh_key}"
  else
    ssh-add "${ssh_key}"
  fi

  # Display public key and guide the student to add it to GitHub.
  echo
  printf "%b\n" "${BOLD}Your SSH public key — copy everything on the line below:${RESET}"
  echo
  cat "${ssh_key}.pub"
  echo
  printf "%b\n" "${BOLD}Add this key to GitHub now:${RESET}"
  printf "   %s\n" "1. Open: https://github.com/settings/ssh/new"
  printf "   %s\n" "2. Title: Learning Platform"
  printf "   %s\n" "3. Paste the key above into the 'Key' field"
  printf "   %s\n" "4. Click 'Add SSH key'"
  echo

  # Verify the connection — loop until it succeeds.
  local verified=false
  while [[ "${verified}" == "false" ]]; do
    confirm_yes_no "Press Y once you have added the SSH key to GitHub"
    substep "Verifying SSH connection to GitHub..."
    local verify_out
    verify_out="$(ssh -o ConnectTimeout=10 -T git@github.com 2>&1)" || true
    if echo "${verify_out}" | grep -q "successfully authenticated"; then
      ok "SSH connection to GitHub verified"
      verified=true
    else
      err "Could not verify connection. GitHub responded: ${verify_out}"
      warn "Double-check that the key was saved correctly, then try again."
    fi
  done

  section_done "GitHub SSH access"
}

#######################################
# Clone helpers
#######################################
clone_if_missing() {
  local label="$1"
  local repo_url="$2"
  local target_dir="$3"

  if [[ -d "${target_dir}/.git" ]]; then
    ok "${label} already present"
  else
    substep "Cloning ${label} into ${target_dir}"
    git clone "${repo_url}" "${target_dir}"
    ok "Cloned ${label}"
  fi
}

verify_repo_dir() {
  local label="$1"
  local target_dir="$2"

  if [[ -d "${target_dir}/.git" ]]; then
    ok "${label} verified"
  else
    die "${label} was expected at ${target_dir}, but was not found."
  fi
}

clone_workspace_repos() {
  step "Cloning required repositories"

  substep "Your final workspace will look like:"
  printf "   %s\n" "${ROOT_DIR}"
  printf "   %s\n" "├── learn-ops-api"
  printf "   %s\n" "├── learn-ops-client"
  printf "   %s\n" "├── learn-ops-infrastructure"
  printf "   %s\n" "└── service-monarch"

  clone_if_missing "learn-ops-client" "${CLIENT_REPO_URL}" "${CLIENT_DIR}"
  clone_if_missing "learn-ops-api" "${API_REPO_URL}" "${API_DIR}"
  clone_if_missing "service-monarch" "${MONARCH_REPO_URL}" "${MONARCH_DIR}"

  verify_repo_dir "learn-ops-client" "${CLIENT_DIR}"
  verify_repo_dir "learn-ops-api" "${API_DIR}"
  verify_repo_dir "service-monarch" "${MONARCH_DIR}"
  verify_repo_dir "learn-ops-infrastructure" "${TARGET_INFRA_DIR}"

  section_done "Repository cloning"
}

#######################################
# Student fork helpers
#######################################

# Fork one NSS-Workshops repo to the student's account and echo the fork URL.
# Idempotent: GitHub returns the existing fork if it already exists.
ensure_fork_exists() {
  local repo_name="$1"

  # NOTE: This function is called via $() substitution so its stdout is captured
  # as the return value (the SSH URL). All display output MUST go to stderr (&2)
  # or it will be embedded in the URL that gets set as the git remote.
  substep "Forking ${NSS_ORG}/${repo_name} to ${GH_USERNAME}..." >&2

  local http_code
  http_code="$(curl -s -o /dev/null -w "%{http_code}" \
    -X POST \
    -H "Authorization: Bearer ${GITHUB_TOKEN}" \
    -H "Accept: application/vnd.github+json" \
    "${GITHUB_API}/repos/${NSS_ORG}/${repo_name}/forks")"

  case "${http_code}" in
    200|202)
      : # success or async — will poll below
      ;;
    401)
      die "GitHub rejected your token (HTTP 401) when forking ${repo_name}. The token is expired, revoked, or invalid. Re-run setup and paste a new PAT." >&2
      ;;
    403)
      die "GitHub denied the fork request for ${repo_name}. Ensure your PAT has 'repo' scope." >&2
      ;;
    *)
      die "Unexpected response (HTTP ${http_code}) when forking ${repo_name}." >&2
      ;;
  esac

  # Poll until the fork is visible (handles GitHub's async 202 case)
  local attempts=0
  local max_attempts=6
  while [[ "${attempts}" -lt "${max_attempts}" ]]; do
    local check_code
    check_code="$(curl -s -o /dev/null -w "%{http_code}" \
      -H "Authorization: Bearer ${GITHUB_TOKEN}" \
      -H "Accept: application/vnd.github+json" \
      "${GITHUB_API}/repos/${GH_USERNAME}/${repo_name}")"

    if [[ "${check_code}" == "200" ]]; then
      ok "Fork ready: github.com/${GH_USERNAME}/${repo_name}" >&2
      echo "git@github.com:${GH_USERNAME}/${repo_name}.git"   # ← stdout: the captured URL
      return 0
    fi

    attempts=$(( attempts + 1 ))
    substep "Waiting for fork to become available... (${attempts}/${max_attempts})" >&2
    sleep 5
  done

  die "Fork of ${repo_name} did not become available after ${max_attempts} attempts." >&2
}

# Update git remotes so origin → student fork, upstream → NSS-Workshops.
# Idempotent: exits early if origin already points to the fork.
fixup_remotes() {
  local label="$1"
  local repo_dir="$2"
  local upstream_url="$3"
  local fork_url="$4"

  substep "Configuring remotes for ${label}"

  local current_origin
  current_origin="$(git -C "${repo_dir}" remote get-url origin 2>/dev/null || true)"

  if [[ "${current_origin}" == "${fork_url}" ]]; then
    ok "${label}: remotes already configured"
    # Ensure upstream exists even on re-run
    if ! git -C "${repo_dir}" remote get-url upstream >/dev/null 2>&1; then
      git -C "${repo_dir}" remote add upstream "${upstream_url}"
    fi
    return 0
  fi

  # Wire up upstream (rename existing origin, or set-url if upstream already present)
  if git -C "${repo_dir}" remote get-url upstream >/dev/null 2>&1; then
    git -C "${repo_dir}" remote set-url upstream "${upstream_url}"
  else
    git -C "${repo_dir}" remote rename origin upstream
  fi

  # Wire up origin → student fork
  if git -C "${repo_dir}" remote get-url origin >/dev/null 2>&1; then
    git -C "${repo_dir}" remote set-url origin "${fork_url}"
  else
    git -C "${repo_dir}" remote add origin "${fork_url}"
  fi

  ok "${label}: origin  → ${fork_url}"
  ok "${label}: upstream → ${upstream_url}"
}

setup_student_forks() {
  step "Setting up your personal forks"

  substep "Each course repo will be forked to your GitHub account."
  substep "You can push your work to 'origin' (your fork) and pull instructor"
  substep "updates from 'upstream' (the course repo) at any time."

  local -a repos=(
    "learn-ops-api|${API_REPO_URL}|${API_DIR}"
    "learn-ops-client|${CLIENT_REPO_URL}|${CLIENT_DIR}"
    "service-monarch|${MONARCH_REPO_URL}|${MONARCH_DIR}"
    "learn-ops-infrastructure|${INFRA_REPO_URL_DEFAULT}|${TARGET_INFRA_DIR}"
  )

  for entry in "${repos[@]}"; do
    local repo_name upstream_url repo_dir fork_url
    IFS='|' read -r repo_name upstream_url repo_dir <<< "${entry}"

    fork_url="$(ensure_fork_exists "${repo_name}")"
    fixup_remotes "${repo_name}" "${repo_dir}" "${upstream_url}" "${fork_url}"
  done

  section_done "Student forks"
}

#######################################
# Secret generation
#######################################
random_alnum() {
  python3 - <<'PY'
import secrets
import string
alphabet = string.ascii_letters + string.digits
print(''.join(secrets.choice(alphabet) for _ in range(30)))
PY
}

#######################################
# Credential cache (read from .env files)
#######################################
parse_env_value() {
  local file="$1" key="$2"
  grep -E "^${key}=" "${file}" 2>/dev/null | head -1 | cut -d= -f2- || true
}

load_cached_credentials() {
  local api_env="${API_DIR}/.env"
  local monarch_env="${MONARCH_DIR}/.env"

  CACHED_LEARN_OPS_CLIENT_ID=""
  CACHED_LEARN_OPS_SECRET_KEY=""
  CACHED_GITHUB_TOKEN=""
  CACHED_SLACK_TOKEN=""
  CACHED_SLACK_WEBHOOK_URL=""
  CACHED_GH_USERNAME=""
  CACHED_SUPERUSER_NAME=""
  CACHED_SUPERUSER_PASSWORD=""

  if [[ -f "${api_env}" ]]; then
    CACHED_LEARN_OPS_CLIENT_ID="$(parse_env_value "${api_env}" LEARN_OPS_CLIENT_ID)"
    CACHED_LEARN_OPS_SECRET_KEY="$(parse_env_value "${api_env}" LEARN_OPS_SECRET_KEY)"
    CACHED_GITHUB_TOKEN="$(parse_env_value "${api_env}" GITHUB_TOKEN)"
    CACHED_SLACK_TOKEN="$(parse_env_value "${api_env}" SLACK_TOKEN)"
    CACHED_GH_USERNAME="$(parse_env_value "${api_env}" INSTRUCTOR_USERNAME)"
    CACHED_SUPERUSER_NAME="$(parse_env_value "${api_env}" LEARN_OPS_SUPERUSER_NAME)"
    CACHED_SUPERUSER_PASSWORD="$(parse_env_value "${api_env}" LEARN_OPS_SUPERUSER_PASSWORD)"
  fi

  if [[ -f "${monarch_env}" ]]; then
    CACHED_SLACK_WEBHOOK_URL="$(parse_env_value "${monarch_env}" SLACK_WEBHOOK_URL)"
  fi

  # If INSTRUCTOR_USERNAME wasn't written to the .env (older setup run), derive it from the token.
  if [[ -z "${CACHED_GH_USERNAME}" && -n "${CACHED_GITHUB_TOKEN}" ]]; then
    CACHED_GH_USERNAME="$(curl -sf -H "Authorization: Bearer ${CACHED_GITHUB_TOKEN}" \
      https://api.github.com/user 2>/dev/null \
      | python3 -c "import json,sys; print(json.load(sys.stdin).get('login',''))" 2>/dev/null || true)"
  fi

  if [[ -n "${CACHED_GH_USERNAME}" || -n "${CACHED_GITHUB_TOKEN}" ]]; then
    ok "Found saved credentials — will offer to reuse them."
  fi
}

#######################################
# Env file writers
#######################################
overwrite_prompt_if_exists() {
  local path="$1"

  if [[ ! -f "${path}" ]]; then
    return 0
  fi

  warn "File already exists: ${path}"
  if confirm_yes_no "Overwrite it?"; then
    return 0
  fi

  return 1
}

write_api_env() {
  local env_path="${API_DIR}/.env"
  local template_path="${API_DIR}/.env.template"

  [[ -f "${template_path}" ]] || die "Missing API template file: ${template_path}"

  if ! overwrite_prompt_if_exists "${env_path}"; then
    warn "Keeping existing API .env"
    return
  fi

  cp "${template_path}" "${env_path}"

  python3 - <<PY
from pathlib import Path

env_path = Path(r"${env_path}")
text = env_path.read_text()

replacements = {
    "LEARN_OPS_CLIENT_ID=": "LEARN_OPS_CLIENT_ID=${LEARN_OPS_CLIENT_ID}",
    "LEARN_OPS_SECRET_KEY=": "LEARN_OPS_SECRET_KEY=${LEARN_OPS_SECRET_KEY}",
    "LEARN_OPS_DJANGO_SECRET_KEY=": "LEARN_OPS_DJANGO_SECRET_KEY=${LEARN_OPS_DJANGO_SECRET_KEY}",
    "LEARN_OPS_SUPERUSER_NAME=": "LEARN_OPS_SUPERUSER_NAME=${LEARN_OPS_SUPERUSER_NAME}",
    "LEARN_OPS_SUPERUSER_PASSWORD=": "LEARN_OPS_SUPERUSER_PASSWORD=${LEARN_OPS_SUPERUSER_PASSWORD}",
    "SLACK_TOKEN=": "SLACK_TOKEN=${SLACK_TOKEN}",
    "GITHUB_TOKEN=": "GITHUB_TOKEN=${GITHUB_TOKEN}",
    "INSTRUCTOR_USERNAME=": "INSTRUCTOR_USERNAME=${GH_USERNAME}",
}

lines = text.splitlines()
updated = []
seen = set()

for line in lines:
    replaced = False
    for prefix, new_value in replacements.items():
        if line.startswith(prefix):
            updated.append(new_value)
            seen.add(prefix)
            replaced = True
            break
    if not replaced:
        updated.append(line)

for prefix, new_value in replacements.items():
    if prefix not in seen:
        updated.append(new_value)

env_path.write_text("\\n".join(updated) + "\\n")
PY

  ok "Created API .env"
}

write_monarch_env() {
  local env_path="${MONARCH_DIR}/.env"
  local template_path="${MONARCH_DIR}/.env.template"

  [[ -f "${template_path}" ]] || die "Missing Monarch template file: ${template_path}"

  if ! overwrite_prompt_if_exists "${env_path}"; then
    warn "Keeping existing Monarch .env"
    return
  fi

  cp "${template_path}" "${env_path}"

  python3 - <<PY
from pathlib import Path

env_path = Path(r"${env_path}")
text = env_path.read_text()

replacements = {
    "GH_PAT=": "GH_PAT=${GITHUB_TOKEN}",
    "SLACK_TOKEN=": "SLACK_TOKEN=${SLACK_TOKEN}",
    "SLACK_WEBHOOK_URL=": "SLACK_WEBHOOK_URL=${SLACK_WEBHOOK_URL}",
}

lines = text.splitlines()
updated = []
seen = set()

for line in lines:
    replaced = False
    for prefix, new_value in replacements.items():
        if line.startswith(prefix):
            updated.append(new_value)
            seen.add(prefix)
            replaced = True
            break
    if not replaced:
        updated.append(line)

for prefix, new_value in replacements.items():
    if prefix not in seen:
        updated.append(new_value)

env_path.write_text("\\n".join(updated) + "\\n")
PY

  ok "Created Monarch .env"
}

collect_user_identity() {
  step "Confirming your identity"

  local git_name git_fname git_lname git_email
  git_name="$(git config --global user.name 2>/dev/null || true)"
  git_fname="$(echo "${git_name}" | awk '{print $1}')"
  git_lname="$(echo "${git_name}" | awk '{print $2}')"
  git_email="$(git config --global user.email 2>/dev/null || true)"

  prompt_with_default USER_FIRST_NAME "First name" "Confirm or update your first name" "${git_fname}"
  prompt_with_default USER_LAST_NAME  "Last name"  "Confirm or update your last name"  "${git_lname}"
  prompt_with_default USER_EMAIL      "Email"      "Confirm or update your email"       "${git_email}"

  if [[ -n "${CACHED_GH_USERNAME}" ]]; then
    prompt_with_default GH_USERNAME "GitHub username" "Your GitHub handle (no @)" "${CACHED_GH_USERNAME}"
  else
    prompt_required GH_USERNAME "GitHub username" "Your GitHub handle (no @)" false
  fi

  section_done "Identity confirmed"
}


prompt_github_pat() {
  if [[ -n "${CACHED_GITHUB_TOKEN}" ]]; then
    prompt_reuse_secret GITHUB_TOKEN \
      "GitHub Personal Access Token" \
      "Paste a new token if you want to replace it (starts with ghp_)" \
      "${CACHED_GITHUB_TOKEN}"
    return
  fi

  echo
  printf "%b\n" "${BOLD}Follow these steps to create your Personal Access Token:${RESET}"
  echo
  printf "   %s\n" "1. Log into your GitHub account"
  printf "   %s\n" "2. Go to your Settings"
  printf "   %s\n" "3. Click Developer Settings (last item, left nav)"
  printf "   %s\n" "4. Click Personal access tokens > Tokens (classic)"
  printf "   %s\n" "5. Click Generate new token > Generate new token (classic)"
  printf "   %s\n" "6. In the Note field, enter: Learning Platform Token"
  printf "   %s\n" "7. Set expiration to 90 days"
  printf "   %s\n" "8. Select these permissions:"
  printf "      %s\n" "- repo"
  printf "      %s\n" "- admin:org"
  printf "      %s\n" "- admin:org_hook"
  printf "   %s\n" "9. Click Generate Token at the bottom — keep the window open!"
  echo

  prompt_required GITHUB_TOKEN "GitHub Personal Access Token" "Paste the token you just generated (starts with ghp_)" true
}

run_oauth_flow() {
  step "GitHub OAuth authorization"

  local auth_url="http://localhost:8000/auth/github/url?cohort=13&v=1"

  substep "This step links your GitHub account to the learning platform."
  substep "The local API will verify your identity through GitHub and create your account."
  echo
  printf "   %b\n" "${BOLD}What to do:${RESET}"
  printf "   %s\n" "  1. Open the link below in your browser"
  printf "   %s\n" "  2. GitHub will ask you to authorize the LearnOps app — click Authorize"
  printf "   %s\n" "  3. After authorizing, the browser will show a spinning globe and appear to hang — this is normal"
  printf "   %s\n" "  4. Go to http://localhost:3000 and sign in"
  printf "   %s\n" "  5. Once you have signed in, come back here and press Y"
  printf "   %s\n" "     (the script will then elevate your role from student to instructor)"
  echo
  printf "   %b\n" "${BOLD}GitHub Authorization — LearnOps API${RESET}"
  printf "   %b\n" "${DIM}${auth_url}${RESET}"
  echo

  if confirm_yes_no "Open the authorization page in your browser?"; then
    open_in_browser "${auth_url}"
  fi

  echo
  printf "   %b\n" "${BOLD}What to expect:${RESET}"
  printf "   %s\n" "  Success: after authorizing, go to http://localhost:3000 and sign in there"
  printf "   %s\n" "  Error page: the API may still be loading — wait 30s and try the link again"
  printf "   %s\n" "  'Invalid client' from GitHub: check that OAuth credentials are set in your .env"
  echo

  confirm_yes_no "Press Y once GitHub has redirected you back to the app"

  section_done "GitHub OAuth"
}

elevate_to_instructor() {
  step "Elevating ${GH_USERNAME} to instructor"

  local container="learning-platform-api"

  if ! docker ps --filter "name=^${container}$" --filter "status=running" \
       --format '{{.Names}}' 2>/dev/null | grep -q "^${container}$"; then
    err "Container '${container}' is not running."
    warn "Start the stack first, then re-run this step."
    die "Cannot elevate instructor — API container is not running."
  fi

  local py_code
  py_code="$(cat <<'PYEOF'
from django.contrib.auth.models import User, Group
u = User.objects.filter(username='__GH_USERNAME__').first()
if u is None:
    raise SystemExit('USER_NOT_FOUND')
g = Group.objects.get(pk=2)
if u.is_staff and u.groups.filter(pk=2).exists():
    print('already an instructor — nothing to do')
else:
    u.is_staff = True
    u.save(update_fields=['is_staff'])
    u.groups.add(g)
    print('elevated: is_staff=True, added to Instructors group')
PYEOF
)"
  py_code="${py_code//__GH_USERNAME__/${GH_USERNAME}}"

  local output
  output="$(docker exec "${container}" python3 manage.py shell -c "${py_code}" 2>&1)" || {
    if printf '%s' "${output}" | grep -q "USER_NOT_FOUND"; then
      err "User '${GH_USERNAME}' was not found in the database."
      warn "OAuth may not have completed — try the authorization URL again, then re-run."
      die "Elevation failed — user not found."
    fi
    err "Elevation failed:"
    printf "   %s\n" "${output}"
    die "Could not elevate ${GH_USERNAME} to instructor."
  }

  ok "  ${GH_USERNAME}: ${output}"
  section_done "Instructor elevation"
}

write_instructor_fixture() {
  step "Patching instructor fixture (if found)"

  local fixture_dir="${API_DIR}/LearningAPI/fixtures"
  local fixture_path="${fixture_dir}/currentuser.json"
  local today
  today="$(date -u +"%Y-%m-%dT%H:%M:%S.000Z")"

  mkdir -p "${fixture_dir}"

  python3 - <<PY
import json, os

fixture_dir = "${fixture_dir}"
cu_path     = "${fixture_path}"
username    = "${GH_USERNAME}"
first_name  = "${USER_FIRST_NAME}"
last_name   = "${USER_LAST_NAME}"
email       = "${USER_EMAIL}"
today       = "${today}"

# Scan existing fixtures for this username and collect used PKs
used_pks   = set()
found_in   = None   # (filepath, data, index)

for fname in sorted(os.listdir(fixture_dir)):
    if fname == "currentuser.json":
        continue
    fpath = os.path.join(fixture_dir, fname)
    try:
        with open(fpath) as f:
            data = json.load(f)
        for i, entry in enumerate(data):
            if not isinstance(entry, dict) or entry.get("model") != "auth.user":
                continue
            used_pks.add(entry["pk"])
            if entry["fields"]["username"] == username:
                found_in = (fpath, data, i)
    except Exception:
        pass

if found_in:
    fpath, data, i = found_in
    entry   = data[i]
    changed = False
    if not entry["fields"].get("is_staff"):
        entry["fields"]["is_staff"] = True
        changed = True
    if 2 not in entry["fields"].get("groups", []):
        entry["fields"].setdefault("groups", []).append(2)
        changed = True
    if changed:
        with open(fpath, "w") as f:
            json.dump(data, f, indent=2)
        print(f"  Patched {os.path.basename(fpath)}: is_staff=True and groups includes 2 for {username}")
    else:
        print(f"  {username} already has is_staff=True and groups includes 2 in {os.path.basename(fpath)}")
    # Remove any stale currentuser.json so loaddata does not see a duplicate
    if os.path.exists(cu_path):
        os.remove(cu_path)
        print(f"  Removed stale currentuser.json")
else:
    print(f"  {username} not found in existing fixtures — will elevate after OAuth login")
PY

  section_done "Instructor fixture patch"
}

collect_config() {
  step "Collecting required configuration"

  substep "A few values are required to wire up GitHub, Slack, and your local Django admin user."
  substep "Instructor-provided values are still needed here; setup cannot invent them for you."

  if [[ -n "${CACHED_LEARN_OPS_CLIENT_ID}" ]]; then
    prompt_with_default \
      LEARN_OPS_CLIENT_ID \
      "Learn Ops Client ID" \
      "Your instructor should provide this value." \
      "${CACHED_LEARN_OPS_CLIENT_ID}"
  else
    prompt_required \
      LEARN_OPS_CLIENT_ID \
      "Learn Ops Client ID" \
      "Your instructor should provide this value."
  fi

  prompt_reuse_secret \
    LEARN_OPS_SECRET_KEY \
    "Learn Ops Secret Key" \
    "Your instructor should provide this value." \
    "${CACHED_LEARN_OPS_SECRET_KEY}"

  prompt_reuse_secret \
    SLACK_TOKEN \
    "Slack Token" \
    "Used by the API and Monarch service for Slack integration." \
    "${CACHED_SLACK_TOKEN}"

  prompt_reuse_secret \
    SLACK_WEBHOOK_URL \
    "Slack Webhook URL" \
    "Used by Monarch to post migration status messages." \
    "${CACHED_SLACK_WEBHOOK_URL}"

  prompt_github_pat

  LEARN_OPS_DJANGO_SECRET_KEY="$(random_alnum)"
  ok "Generated a fresh LEARN_OPS_DJANGO_SECRET_KEY"

  prompt_with_default \
    LEARN_OPS_SUPERUSER_NAME \
    "Local Django Admin Username" \
    "This is only for your local development environment." \
    "${CACHED_SUPERUSER_NAME:-admin}"

  prompt_with_default \
    LEARN_OPS_SUPERUSER_PASSWORD \
    "Local Django Admin Password" \
    "This is only for your local development environment." \
    "${CACHED_SUPERUSER_PASSWORD:-admin}"

  section_done "Configuration collection"
}

write_client_env() {
  local env_path="${CLIENT_DIR}/.env"

  if [[ -f "${env_path}" ]]; then
    ok "Client .env already exists, skipping"
    return
  fi

  cat > "${env_path}" <<'EOF'
REACT_APP_API_URI=http://localhost:8000
REACT_APP_ENV="development"
CHOKIDAR_USEPOLLING=true
GENERATE_SOURCEMAP=false
EOF

  ok "Created client .env"
}

write_env_files() {
  step "Writing environment files"

  write_api_env
  write_monarch_env
  write_client_env

  section_done "Environment files"
}

#######################################
# Validation
#######################################
validate_layout() {
  step "Validating workspace structure"

  local expected=(
    "${ROOT_DIR}"
    "${API_DIR}"
    "${CLIENT_DIR}"
    "${TARGET_INFRA_DIR}"
    "${MONARCH_DIR}"
  )

  for path in "${expected[@]}"; do
    if [[ -e "${path}" ]]; then
      ok "Found ${path}"
    else
      die "Missing expected path: ${path}"
    fi
  done

  if [[ -f "${API_DIR}/.env" ]]; then
    ok "API environment file exists"
  else
    warn "API .env not found"
  fi

  if [[ -f "${MONARCH_DIR}/.env" ]]; then
    ok "Monarch environment file exists"
  else
    warn "Monarch .env not found"
  fi

  if [[ -f "${CLIENT_DIR}/.env" ]]; then
    ok "Client environment file exists"
  else
    warn "Client .env not found"
  fi

  section_done "Workspace validation"
}

#######################################
# Summary / next steps
#######################################
show_summary() {
  step "Setup summary"

  printf "%b\n" "${BOLD}Workspace ready:${RESET} ${ROOT_DIR}"
  echo
  printf "%b\n" "${BOLD}Repositories:${RESET}"
  printf "   • %s\n" "${CLIENT_DIR}"
  printf "   • %s\n" "${API_DIR}"
  printf "   • %s\n" "${TARGET_INFRA_DIR}"
  printf "   • %s\n" "${MONARCH_DIR}"
  echo
  printf "%b\n" "${BOLD}Useful commands:${RESET}"
  printf "   • %s\n" "make setup"
  printf "   • %s\n" "make doctor"
  printf "   • %s\n" "make up"
  printf "   • %s\n" "make logs"
  printf "   • %s\n" "make down"
  echo
  printf "%b\n" "${BOLD}Expected app URLs after startup:${RESET}"
  printf "   • %s\n" "Client: http://localhost:3000"
  printf "   • %s\n" "Admin:  http://localhost:8000/admin"
  echo
  warn "If any Docker services fail to start, rerun 'make up' after fixing the issue."
  section_done "Summary"
}

open_in_browser() {
  local url="$1"
  case "${OS_FAMILY}" in
    macOS) open "${url}" ;;
    WSL)   cmd.exe /c start "${url}" 2>/dev/null || true ;;
    *)     xdg-open "${url}" 2>/dev/null || true ;;
  esac
}

monitor_services() {
  step "Monitoring services"
  substep "The API loads fixtures on first start — this may take a few minutes."
  substep "Waiting for both services to respond before continuing..."
  echo

  local api_url="http://localhost:8000/admin"
  local client_url="http://localhost:3000/"
  local timeout=600
  local interval=5
  local elapsed=0
  local api_up="false"
  local client_up="false"
  local api_code="000"
  local client_code="000"

  while [[ "${elapsed}" -lt "${timeout}" ]]; do
    api_code="$(curl -s -o /dev/null -w "%{http_code}" --max-time 3 "${api_url}" 2>/dev/null)" || true
    client_code="$(curl -s -o /dev/null -w "%{http_code}" --max-time 3 "${client_url}" 2>/dev/null)" || true

    if [[ "${api_code}" == "200" || "${api_code}" == "302" ]]; then api_up="true"; fi
    if [[ "${client_code}" == "200" ]]; then client_up="true"; fi

    if [[ "${api_up}" == "true" && "${client_up}" == "true" ]]; then
      break
    fi

    local api_label client_label
    if   [[ "${api_up}"    == "true" ]]; then api_label="ready"
    else                                      api_label="not ready, retrying..."
    fi
    if   [[ "${client_up}"   == "true" ]]; then client_label="ready"
    else                                        client_label="not ready, retrying..."
    fi

    substep "API: ${api_label}  |  Client: ${client_label}  (${elapsed}s elapsed)"
    sleep "${interval}"
    elapsed=$(( elapsed + interval ))
  done

  echo
  if [[ "${api_up}" == "true" ]]; then
    ok "API is up  →  http://localhost:8000/admin"
  else
    err "API did not respond after ${timeout}s"
    warn "Check logs: cd ${TARGET_INFRA_DIR} && docker compose logs api"
  fi

  if [[ "${client_up}" == "true" ]]; then
    ok "Client is up  →  http://localhost:3000"
  else
    err "Client did not respond after ${timeout}s"
    warn "Check logs: cd ${TARGET_INFRA_DIR} && docker compose logs client"
  fi

  section_done "Services"
}

maybe_start_services() {
  step "Optional: start the stack now"

  substep "The first startup can take a few minutes while Docker builds images."
  substep "This command uses the docker-compose.yml in learn-ops-infrastructure."

  if confirm_yes_no "Start services now?"; then
    (
      cd "${TARGET_INFRA_DIR}"
      docker compose up -d
    )
    ok "Docker services started"
    warn "If your compose file only includes client/api/database today, add Valkey and Monarch there for full-stack startup."

    monitor_services

    if confirm_yes_no "Open the app in your browser?"; then
      open_in_browser "http://localhost:3000"
      open_in_browser "http://localhost:8000/admin"
    fi
  else
    warn "Skipped starting services"
    echo
    printf "%b\n" "${BOLD}When you are ready to start the stack, run:${RESET}"
    printf "   %s\n" "cd ${TARGET_INFRA_DIR} && docker compose up -d"
    echo
    printf "%b\n" "${GREEN}${BOLD}Setup complete.${RESET}"
    printf "%b\n" "${DIM}Your Learning Platform workspace is ready to use.${RESET}"
    echo
    exit 0
  fi

  section_done "Startup option"
}

#######################################
# Docker cleanup
#######################################
cleanup_docker_resources() {
  step "Checking for existing LMS Docker resources"

  local containers=() raw_images=() raw_volumes=() images=() volumes=() networks=()
  local projects=("learn-ops-infrastructure" "service-monarch")

  # Containers — compose label is reliable for all managed containers
  for project in "${projects[@]}"; do
    while IFS= read -r name; do
      [[ -n "$name" ]] && containers+=("$name")
    done < <(docker ps -a --filter "label=com.docker.compose.project=${project}" \
               --format '{{.Names}}' 2>/dev/null || true)
  done

  # From each container: collect the image it used AND its volume mounts.
  # Pulled images (postgres, grafana, prometheus, etc.) have no compose label,
  # so we must look them up via the containers that used them.
  # Anonymous volumes likewise have no compose label.
  for container in "${containers[@]+"${containers[@]}"}"; do
    local img
    img="$(docker inspect --format '{{.Config.Image}}' "$container" 2>/dev/null || true)"
    [[ -n "$img" ]] && raw_images+=("$img")

    while IFS= read -r vol; do
      [[ -n "$vol" ]] && raw_volumes+=("$vol")
    done < <(docker inspect --format \
      '{{range .Mounts}}{{if eq .Type "volume"}}{{.Name}}{{"\n"}}{{end}}{{end}}' \
      "$container" 2>/dev/null || true)
  done

  # Also catch locally built images via label filter (api, client, monarch)
  for project in "${projects[@]}"; do
    while IFS= read -r img; do
      [[ -n "$img" ]] && raw_images+=("$img")
    done < <(docker images --filter "label=com.docker.compose.project=${project}" \
               --format '{{if ne .Repository "<none>"}}{{.Repository}}:{{.Tag}}{{else}}{{.ID}}{{end}}' 2>/dev/null || true)
  done

  # Also catch named volumes directly via compose label (survives container removal)
  for project in "${projects[@]}"; do
    while IFS= read -r vol; do
      [[ -n "$vol" ]] && raw_volumes+=("$vol")
    done < <(docker volume ls \
               --filter "label=com.docker.compose.project=${project}" \
               --format '{{.Name}}' 2>/dev/null || true)
  done

  # Deduplicate images and volumes (docker handles duplicates gracefully, but keep output clean)
  while IFS= read -r item; do
    [[ -n "$item" ]] && images+=("$item")
  done < <(printf '%s\n' "${raw_images[@]+"${raw_images[@]}"}" | sort -u)

  while IFS= read -r item; do
    [[ -n "$item" ]] && volumes+=("$item")
  done < <(printf '%s\n' "${raw_volumes[@]+"${raw_volumes[@]}"}" | sort -u)

  # Network is external (no compose label) — check by name
  if docker network inspect learningplatform >/dev/null 2>&1; then
    networks+=("learningplatform")
  fi

  if [[ ${#containers[@]} -eq 0 && ${#images[@]} -eq 0 && \
        ${#volumes[@]} -eq 0   && ${#networks[@]} -eq 0 ]]; then
    ok "No existing LMS Docker resources found"
    section_done "Docker cleanup check"
    return
  fi

  warn "Found existing LMS Docker resources:"
  [[ ${#containers[@]} -gt 0 ]] && { printf "   Containers:\n"; printf "     • %s\n" "${containers[@]}"; }
  [[ ${#images[@]} -gt 0 ]]    && { printf "   Images:\n";     printf "     • %s\n" "${images[@]}"; }
  [[ ${#volumes[@]} -gt 0 ]]   && { printf "   Volumes:\n";    printf "     • %s\n" "${volumes[@]}"; }
  [[ ${#networks[@]} -gt 0 ]]  && { printf "   Networks:\n";   printf "     • %s\n" "${networks[@]}"; }

  echo
  if ! confirm_yes_no "Delete all of the above before continuing?"; then
    warn "Skipping cleanup — existing resources may conflict with setup"
    section_done "Docker cleanup"
    return
  fi

  [[ ${#containers[@]} -gt 0 ]] && docker rm -f "${containers[@]}"
  [[ ${#images[@]} -gt 0 ]]    && docker rmi -f "${images[@]}"
  [[ ${#volumes[@]} -gt 0 ]]   && docker volume rm "${volumes[@]}"
  [[ ${#networks[@]} -gt 0 ]]  && docker network rm "${networks[@]}"

  ok "Removed all listed LMS Docker resources"
  section_done "Docker cleanup"
}

#######################################
# Doctor mode
#######################################
doctor_mode() {
  header
  detect_platform
  check_prereqs
  check_docker_running
  ensure_workspace_root

  step "Doctor summary"
  ok "Environment looks healthy for setup"
  echo
  printf "%b\n" "${BOLD}If you want to continue:${RESET}"
  printf "   %s\n" "cd ~/workspace/lms/learn-ops-infrastructure"
  printf "   %s\n" "make setup"
  echo
}

#######################################
# Save instructor state to fixture
#######################################
save_instructor_state() {
  step "Saving instructor state for future resets"

  local container="learning-platform-api"
  local out_file="${API_DIR}/LearningAPI/fixtures/instructor_${GH_USERNAME}.json"

  if ! docker ps --filter "name=^${container}$" --filter "status=running" \
       --format '{{.Names}}' 2>/dev/null | grep -q "^${container}$"; then
    warn "API container not running — skipping instructor state save"
    return
  fi

  local py_code
  py_code="$(cat <<'PYEOF'
import json, sys
from django.contrib.auth.models import User
from allauth.socialaccount.models import SocialAccount
from LearningAPI.models.people import NssUser, NssUserCohort
from rest_framework.authtoken.models import Token

username = '__GH_USERNAME__'
u = User.objects.filter(username=username).first()
if not u:
    print(f'User {username!r} not found', file=sys.stderr)
    raise SystemExit(1)

nss_user   = NssUser.objects.filter(user=u).first()
social     = SocialAccount.objects.filter(user=u).first()
cohort_rec = NssUserCohort.objects.filter(nss_user=nss_user).first() if nss_user else None
token      = Token.objects.filter(user=u).first()

data = []

data.append({
    'model': 'auth.user',
    'pk': u.pk,
    'fields': {
        'password': u.password,
        'last_login': u.last_login.isoformat() if u.last_login else None,
        'is_superuser': u.is_superuser,
        'username': u.username,
        'first_name': u.first_name,
        'last_name': u.last_name,
        'email': u.email,
        'is_staff': u.is_staff,
        'is_active': u.is_active,
        'date_joined': u.date_joined.isoformat(),
        'groups': list(u.groups.values_list('pk', flat=True)),
        'user_permissions': [],
    }
})

if nss_user:
    data.append({
        'model': 'LearningAPI.nssuser',
        'pk': nss_user.pk,
        'fields': {
            'user': u.pk,
            'slack_handle': nss_user.slack_handle,
            'github_handle': nss_user.github_handle,
        }
    })

if social:
    extra = social.extra_data if isinstance(social.extra_data, str) else json.dumps(social.extra_data)
    data.append({
        'model': 'socialaccount.socialaccount',
        'pk': social.pk,
        'fields': {
            'user': u.pk,
            'provider': social.provider,
            'uid': social.uid,
            'last_login': social.last_login.isoformat() if social.last_login else None,
            'date_joined': social.date_joined.isoformat(),
            'extra_data': extra,
        }
    })

if cohort_rec:
    data.append({
        'model': 'LearningAPI.nssusercohort',
        'pk': cohort_rec.pk,
        'fields': {
            'nss_user': nss_user.pk,
            'cohort': cohort_rec.cohort.pk,
            'is_github_org_member': cohort_rec.is_github_org_member,
        }
    })

if token:
    data.append({
        'model': 'authtoken.token',
        'pk': token.key,
        'fields': {
            'user': u.pk,
            'created': token.created.isoformat(),
        }
    })

with open('/tmp/instructor_fixture.json', 'w') as f:
    json.dump(data, f, indent=2)
print(f'Fixture written for {username}')
PYEOF
)"
  py_code="${py_code//__GH_USERNAME__/${GH_USERNAME}}"

  docker exec "${container}" python3 manage.py shell -c "${py_code}"
  docker cp "${container}:/tmp/instructor_fixture.json" "${out_file}"

  ok "Saved: ${out_file}"
  warn "This file contains your token — do not commit it to git."
  section_done "Instructor state"
}

#######################################
# Main
#######################################
main() {
  if [[ "${DOCTOR_ONLY}" == "true" ]]; then
    doctor_mode
    exit 0
  fi

  header
  detect_platform
  check_prereqs
  check_docker_running
  cleanup_docker_resources
  check_port_conflicts
  ensure_workspace_root
  normalize_infra_location_if_needed "$@"
  load_cached_credentials
  collect_user_identity
  ensure_github_ssh
  clone_workspace_repos
  collect_config
  setup_student_forks
  write_env_files
  write_instructor_fixture
  validate_layout
  show_summary
  maybe_start_services
  run_oauth_flow
  elevate_to_instructor
  save_instructor_state

  echo
  printf "%b\n" "${GREEN}${BOLD}All done.${RESET}"
  printf "%b\n" "${DIM}Your Learning Platform workspace is ready to use.${RESET}"
  echo
}

main "$@"
