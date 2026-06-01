#!/usr/bin/env bash
set -Eeuo pipefail

###############################################################################
# Learning Platform Teardown
# Reverses everything that scripts/setup.sh did to this machine.
###############################################################################

#######################################
# Globals
#######################################
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_DIR="$(dirname "${SCRIPT_DIR}")"
ROOT_DIR="${HOME}/workspace/lms"
API_DIR="${ROOT_DIR}/learn-ops-api"
CLIENT_DIR="${ROOT_DIR}/learn-ops-client"
MONARCH_DIR="${ROOT_DIR}/service-monarch"

OS_FAMILY=""
MAC_ARCH=""

#######################################
# Colors / formatting
#######################################
if [[ -t 1 ]]; then
  BOLD="\033[1m"
  RED="\033[0;31m"
  GREEN="\033[0;32m"
  YELLOW="\033[0;33m"
  CYAN="\033[0;36m"
  RESET="\033[0m"
else
  BOLD="" RED="" GREEN="" YELLOW="" CYAN="" RESET=""
fi

step()  { printf "\n%b\n" "${CYAN}${BOLD}▶ $*${RESET}"; }
ok()    { printf "   %b\n" "${GREEN}✔ $*${RESET}"; }
warn()  { printf "   %b\n" "${YELLOW}⚠ $*${RESET}"; }
err()   { printf "   %b\n" "${RED}✖ $*${RESET}"; }
die()   { err "$*"; exit 1; }

hr() { printf "%b\n" "${RED}================================================================${RESET}"; }

#######################################
# Utilities
#######################################
have_cmd() { command -v "$1" >/dev/null 2>&1; }

remove_if_exists() {
  local path="$1"
  if [[ -e "${path}" ]]; then
    rm -rf "${path}"
    ok "Removed: ${path}"
  else
    warn "Already gone: ${path}"
  fi
}

#######################################
# Platform detection
#######################################
detect_platform() {
  local uname_s
  uname_s="$(uname -s)"
  case "${uname_s}" in
    Darwin)
      OS_FAMILY="macOS"
      local uname_m
      uname_m="$(uname -m)"
      [[ "${uname_m}" == "arm64" ]] && MAC_ARCH="arm64" || MAC_ARCH="amd64"
      ;;
    Linux)
      OS_FAMILY="Linux"
      if grep -qi microsoft /proc/version 2>/dev/null || [[ -n "${WSL_DISTRO_NAME:-}" ]]; then
        OS_FAMILY="WSL"
      fi
      ;;
    *)
      die "Unsupported platform: ${uname_s}"
      ;;
  esac
}

#######################################
# Destructive confirmation
#######################################
confirm_teardown() {
  hr
  printf "\n"
  printf "%b\n" "${RED}${BOLD}  !! DESTRUCTIVE OPERATION — READ CAREFULLY !!${RESET}"
  printf "\n"
  printf "%b\n" "${BOLD}  This will permanently:${RESET}"
  printf "    %s\n" "• Stop and delete all Learning Platform Docker containers, volumes, and networks"
  printf "    %s\n" "• Uninstall Docker Desktop / Docker Engine from this machine"
  printf "    %s\n" "• Delete the cloned repos:"
  printf "        %s\n" "${API_DIR}"
  printf "        %s\n" "${CLIENT_DIR}"
  printf "        %s\n" "${MONARCH_DIR}"
  printf "    %s\n" "• Delete all .env files in those repos (your secrets will be gone)"
  printf "    %s\n" "• Prompt you to manually revoke your GitHub Personal Access Token"
  printf "\n"
  printf "%b\n" "${BOLD}  It will NOT delete:${RESET}"
  printf "    %s\n" "• This repo (${INFRA_DIR})"
  printf "    %s\n" "• Your GitHub forks (delete those manually at github.com if desired)"
  printf "\n"
  hr
  printf "\n"
  printf "  Type %b to continue, or anything else to abort: " "${BOLD}teardown${RESET}"
  local answer
  read -r answer
  if [[ "${answer}" != "teardown" ]]; then
    die "Aborted — nothing was changed."
  fi
  printf "\n"
}

#######################################
# Step 1 — Docker services
#######################################
teardown_docker_services() {
  step "Stopping Docker services"

  if ! have_cmd docker; then
    warn "Docker not found — skipping service teardown"
    return
  fi

  if ! docker info >/dev/null 2>&1; then
    warn "Docker daemon is not running — skipping service teardown"
    return
  fi

  (cd "${INFRA_DIR}" && docker compose down -v --remove-orphans 2>/dev/null) \
    && ok "Compose stack stopped and volumes removed" \
    || warn "Compose down failed or nothing was running"

  if docker network inspect learningplatform >/dev/null 2>&1; then
    docker network rm learningplatform >/dev/null \
      && ok "Removed Docker network: learningplatform" \
      || warn "Could not remove learningplatform network (may still have attached endpoints)"
  else
    warn "Docker network 'learningplatform' not found — already gone"
  fi
}

#######################################
# Step 2 — Uninstall Docker
#######################################
uninstall_docker_macos() {
  # Try the official Docker Desktop uninstaller first
  local uninstaller="/Applications/Docker.app/Contents/MacOS/uninstall"
  if [[ -x "${uninstaller}" ]]; then
    warn "Running Docker Desktop uninstaller — you may be prompted for your password"
    sudo "${uninstaller}" --accept 2>/dev/null \
      && ok "Docker Desktop uninstalled via official uninstaller" \
      && return
  fi

  # Manual fallback
  warn "Official uninstaller not found — removing files manually"
  local -a docker_paths=(
    "/Applications/Docker.app"
    "${HOME}/.docker"
    "${HOME}/Library/Application Support/Docker Desktop"
    "${HOME}/Library/Containers/com.docker.docker"
    "${HOME}/Library/Group Containers/group.com.docker"
    "${HOME}/Library/Logs/Docker Desktop"
    "${HOME}/Library/Saved Application State/com.electron.docker-frontend.savedState"
    "${HOME}/Library/Preferences/com.docker.docker.plist"
  )
  for path in "${docker_paths[@]}"; do
    remove_if_exists "${path}"
  done
}

uninstall_docker_linux() {
  if have_cmd apt-get; then
    warn "Removing Docker packages (requires sudo)"
    sudo apt-get purge -y \
      docker-ce docker-ce-cli containerd.io \
      docker-buildx-plugin docker-compose-plugin \
      docker-ce-rootless-extras 2>/dev/null || true
    sudo apt-get autoremove -y 2>/dev/null || true
    sudo rm -rf /var/lib/docker /var/lib/containerd
    ok "Docker Engine removed"
  else
    warn "apt-get not found — remove Docker manually for your distro:"
    warn "See: https://docs.docker.com/engine/install/ubuntu/#uninstall-docker-engine"
  fi
}

uninstall_docker_wsl() {
  if ! have_cmd powershell.exe; then
    warn "powershell.exe not found — cannot reach the Windows host from this WSL environment"
    warn "To uninstall manually: Windows → Settings → Apps → Docker Desktop → Uninstall"
    return
  fi

  # Try the Docker Desktop installer's built-in uninstall command first.
  # Docker Desktop is installed at this path on the Windows host by default.
  local installer_wsl="/mnt/c/Program Files/Docker/Docker/Docker Desktop Installer.exe"
  if [[ -f "${installer_wsl}" ]]; then
    warn "Launching Docker Desktop uninstaller on Windows (a UAC prompt will appear)..."
    if powershell.exe -Command \
      "Start-Process -FilePath 'C:\Program Files\Docker\Docker\Docker Desktop Installer.exe' -ArgumentList 'uninstall' -Verb RunAs -Wait"; then
      ok "Docker Desktop uninstalled from Windows"
      return
    fi
    warn "Installer-based uninstall did not complete — trying winget..."
  fi

  # Fall back to winget if available.
  if powershell.exe -NoProfile -Command "Get-Command winget -ErrorAction SilentlyContinue" 2>/dev/null | grep -q winget; then
    warn "Uninstalling Docker Desktop via winget (a UAC prompt may appear)..."
    if powershell.exe -Command "winget uninstall --id Docker.DockerDesktop --silent --accept-source-agreements"; then
      ok "Docker Desktop uninstalled via winget"
      return
    fi
    warn "winget uninstall failed"
  fi

  warn "Automated uninstall was not possible. To remove Docker Desktop manually:"
  warn "  Windows → Settings → Apps → Docker Desktop → Uninstall"
  warn "  OR run in an elevated PowerShell: winget uninstall Docker.DockerDesktop"
}

teardown_docker_install() {
  step "Uninstalling Docker"
  case "${OS_FAMILY}" in
    macOS) uninstall_docker_macos ;;
    Linux) uninstall_docker_linux ;;
    WSL)   uninstall_docker_wsl ;;
  esac
}

#######################################
# Step 3 — .env files
#######################################
teardown_env_files() {
  step "Deleting .env files (contain your secrets)"
  remove_if_exists "${API_DIR}/.env"
  remove_if_exists "${CLIENT_DIR}/.env"
  remove_if_exists "${MONARCH_DIR}/.env"
}

#######################################
# Step 4 — Cloned repos
#######################################
teardown_repos() {
  step "Deleting cloned repositories"
  remove_if_exists "${API_DIR}"
  remove_if_exists "${CLIENT_DIR}"
  remove_if_exists "${MONARCH_DIR}"

  # Offer to remove the workspace root if it's now empty
  if [[ -d "${ROOT_DIR}" ]]; then
    local remaining
    remaining="$(ls -A "${ROOT_DIR}" 2>/dev/null | wc -l | tr -d ' ')"
    if [[ "${remaining}" -eq 0 ]]; then
      remove_if_exists "${ROOT_DIR}"
    else
      warn "${ROOT_DIR} still has ${remaining} item(s) — leaving it in place"
      warn "  Remaining: $(ls "${ROOT_DIR}" | tr '\n' ' ')"
    fi
  fi
}

#######################################
# Step 5 — GitHub PAT instructions
#######################################
teardown_github_pat() {
  step "Revoke your GitHub Personal Access Token"
  printf "\n"
  printf "   %b\n" "${BOLD}Your PAT cannot be deleted automatically — follow these steps:${RESET}"
  printf "     %s\n" "1. Go to: https://github.com/settings/tokens"
  printf "     %s\n" "2. Find 'Learning Platform Token'"
  printf "     %s\n" "3. Click Delete"
  printf "\n"
  printf "   %b\n" "${YELLOW}⚠ Your token was also stored in the .env files that were just deleted,${RESET}"
  printf "   %b\n" "${YELLOW}  so revoking it on GitHub completes the cleanup.${RESET}"
  printf "\n"
  printf "   %b\n" "${BOLD}If you also want to delete your GitHub forks:${RESET}"
  printf "     %s\n" "• github.com/<your-username>/learn-ops-api → Settings → Delete this repository"
  printf "     %s\n" "• github.com/<your-username>/learn-ops-client → Settings → Delete this repository"
  printf "     %s\n" "• github.com/<your-username>/service-monarch → Settings → Delete this repository"
  printf "     %s\n" "• github.com/<your-username>/learn-ops-infrastructure → Settings → Delete this repository"
}

#######################################
# Main
#######################################
main() {
  detect_platform
  confirm_teardown
  teardown_docker_services
  teardown_docker_install
  teardown_env_files
  teardown_repos
  teardown_github_pat

  printf "\n"
  hr
  printf "%b\n" "${GREEN}${BOLD}  Teardown complete.${RESET}"
  printf "  %s\n" "Remember to revoke your GitHub PAT at https://github.com/settings/tokens"
  hr
  printf "\n"
}

main "$@"
