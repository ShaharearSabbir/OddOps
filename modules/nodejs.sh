#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/ui.sh"

install_nodejs() {
    local version="${1:-lts}"

    if command -v node &>/dev/null; then
        log_warn "Node.js environment layer already present — skipping"
        return 0
    fi

    log_info "Configuring Node.js native distribution sources for version: ${version}..."

    if command -v apt &>/dev/null; then
        # Handle NodeSource's modern repository schema (v2) safely
        apt-get update -qq && apt-get install -y ca-certificates gnupg curl
        mkdir -p /etc/apt/keyrings
        
        local ns_version
        if [ "${version}" = "lts" ]; then ns_version="22"; else ns_version="${version}"; fi

        log_info "Injecting NodeSource v${ns_version}.x signing keys..."
        curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg 2>/dev/null || true
        echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_${ns_version}.x nodistro main" > /etc/apt/sources.list.d/nodesource.list
        
        apt-get update -qq && apt-get install -y nodejs
    elif command -v dnf &>/dev/null; then
        local ns_version
        if [ "${version}" = "lts" ]; then ns_version="22"; else ns_version="${version}"; fi
        log_info "Configuring NodeSource RPM layers..."
        curl -fsSL "https://rpm.nodesource.com/setup_${ns_version}.x" | bash -
        dnf install -y nodejs
    elif command -v pacman &>/dev/null; then
        log_info "Syncing Node.js package structures via Pacman core modules..."
        pacman -S --noconfirm nodejs npm
    else
        log_error "No architecture package alignments identified for Node engine setups"
        return 1
    fi

    log_success "Node.js engine installed successfully: $(node --version 2>/dev/null)"
}

install_pm2() {
    if command -v pm2 &>/dev/null; then
        log_warn "PM2 execution paths already registered — skipping global setup"
        return 0
    fi

    log_info "Provisioning PM2 production engine layer globally..."
    # --unsafe-perm ensures running under lifecycle engines doesn't drop scripts on root wrappers
    npm install -g pm2 --unsafe-perm
    log_success "PM2 production manager module configured"
}

setup_pm2_startup() {
    local username="${1:-${ODD_DEPLOY_USER:-app}}"

    if [ -z "${username}" ] || ! id -u "${username}" &>/dev/null; then
        log_warn "Target administrative user account skipped or invalid — bypassing boot registrations"
        return 0
    fi

    log_info "Linking PM2 persistent systemd tracking configurations for user: ${username}..."
    
    # Capture the required environment injection payload string dynamically 
    local startup_cmd
    startup_cmd=$(env PATH="$PATH" pm2 startup systemd -u "${username}" --hp "/home/${username}" | grep "sudo" | awk '{$1=""; print $0}' || echo "")
    
    if [ -n "${startup_cmd}" ]; then
        log_info "Evaluating system level systemd registration links safely..."
        eval "sudo ${startup_cmd}" 2>/dev/null || true
    else
        # Fallback tracking if standard grepping drops cleanly
        pm2 startup systemd -u "${username}" --hp "/home/${username}" 2>/dev/null || true
    fi

    log_success "PM2 systemd process configurations bound to platform boot sequences"
}

verify_nodejs() {
    if ! command -v node &>/dev/null; then
        log_error "Node.js runtime framework elements are missing from structural path targets"
        return 1
    fi

    log_info "Node.js Footprint: $(node --version)"
    log_info "npm Sub-System: v$(npm --version)"

    if command -v pm2 &>/dev/null; then
        log_info "PM2 Process Core: v$(pm2 --version 2>/dev/null)"
    fi
}

describe_nodejs() {
    printf "\n  JavaScript Runtime Environments:\n"
    if command -v node &>/dev/null; then
        printf "    Node.js Engine: operational (%s)\n" "$(node --version 2>/dev/null)"
        printf "    npm Manager: active\n"
    else
        printf "    Node.js Engine: uninstalled\n"
    fi
    
    if command -v pm2 &>/dev/null; then
        printf "    PM2 Daemon Stack: operational\n"
    else
        printf "    PM2 Daemon Stack: uninstalled\n"
    fi
}