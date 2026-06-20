#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/ui.sh"

install_go() {
    local requested_version="${1:-}"

    if command -v go &>/dev/null; then
        log_warn "Go binary layer already detected in system paths — skipping"
        return 0
    fi

    log_info "Resolving system architecture and Go upstream releases..."

    # Dynamic platform architecture lookup mapping
    local sys_arch
    sys_arch=$(uname -m)
    case "${sys_arch}" in
        x86_64)  sys_arch="amd64" ;;
        aarch64) sys_arch="arm64" ;;
        armv7l)  sys_arch="armv6l" ;;
        *)       log_error "Unsupported hardware deployment architecture: ${sys_arch}"; return 1 ;;
    case

    local go_version go_tarball go_json
    # Relying on curl as guaranteed by our entrypoint
    go_json=$(curl -fsSL "https://go.dev/dl/?mode=json" 2>/dev/null || echo "")

    if [ -z "${go_json}" ]; then
        log_error "Unable to poll distribution indices from go.dev upstream backend API"
        return 1
    fi

    # Highly portable cross-platform stream parsing replacing fragile grep -P flags
    if [ -n "${requested_version}" ]; then
        go_version=$(echo "${go_json}" | sed -n 's/.*"version": *"\([^"]*\)".*/\1/p' | grep "^go${requested_version}" | head -n1 || true)
    fi

    if [ -z "${go_version}" ]; then
        go_version=$(echo "${go_json}" | sed -n 's/.*"version": *"\([^"]*\)".*/\1/p' | head -n1)
    fi

    go_tarball="${go_version}.linux-${sys_arch}.tar.gz"
    log_info "Downloading stable build package: ${go_version} (${sys_arch})..."

    curl -fsSL "https://go.dev/dl/${go_tarball}" -o "/tmp/${go_tarball}"

    log_info "Extracting payload files to runtime target directory /usr/local..."
    rm -rf /usr/local/go 2>/dev/null || true # Prevent merging headers with corrupt old instances
    tar -C /usr/local -xzf "/tmp/${go_tarball}"
    rm -f "/tmp/${go_tarball}"

    # Persistent global cross-session mapping injection
    if ! grep -q '/usr/local/go/bin' /etc/profile 2>/dev/null; then
        printf '\nexport PATH=$PATH:/usr/local/go/bin\n' >> /etc/profile
    fi

    # Ensuring standard systemic service profiles capture it without terminal restarts
    if [ -f /etc/environment ] && ! grep -q '/usr/local/go/bin' /etc/environment; then
        sed -i 's|PATH="\(.*\)"|PATH="\1:/usr/local/go/bin"|' /etc/environment 2>/dev/null || true
    fi

    # Push into current session instance space
    export PATH="${PATH}:/usr/local/go/bin"

    log_success "${go_version} engine setup completed successfully"
}

verify_go() {
    # Ensure toolchain visibility check inside the wrapper logic path directly
    export PATH="${PATH}:/usr/local/go/bin"
    
    if ! command -v go &>/dev/null; then
        log_error "Go engine footprint is missing from system executable scopes"
        return 1
    fi

    local live_v
    live_v=$(go version 2>/dev/null || echo "unknown runtime status")
    log_info "Active Version: ${live_v}"
}

describe_go() {
    printf "\n  Go Runtime Profiles:\n"
    if [ -x /usr/local/go/bin/go ] || command -v go &>/dev/null; then
        local current_v
        current_v=$(/usr/local/go/bin/go version 2>/dev/null | awk '{print $3}' || go version 2>/dev/null | awk '{print $3}' || echo "active")
        printf "    Go Language: operational\n"
        printf "    Release Core Tag: %s\n" "${current_v}"
    else
        printf "    Go Language: uninstalled\n"
    fi
}