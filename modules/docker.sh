#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/ui.sh"

install_docker() {
    if command -v docker &>/dev/null; then
        log_warn "Docker is already installed — skipping"
        return 0
    fi

    log_info "Installing Docker Engine via official upstream utility..."

    # Pre-flight guarantees presence of curl natively
    curl -fsSL https://get.docker.com | sh

    # Smart Init System Manager Verification Check
    if command -v systemctl &>/dev/null && systemctl read-only &>/dev/null; then
        log_info "Enabling and kicking off Docker daemon process channels..."
        systemctl daemon-reload
        systemctl enable docker
        systemctl start docker
    else
        log_warn "Systemd is completely unavailable or inactive (Sandbox Environment)."
        log_info "Launching the dockerd daemon runner manually into a background process loop..."
        if ! pgrep -x "dockerd" &>/dev/null; then
            dockerd > /var/log/dockerd.log 2>&1 &
            # Give the process socket 3 seconds to spin up and bind
            sleep 3
        fi
    fi

    # Grant execution capabilities to our configuration username space
    local target_user="${ODD_DEPLOY_USER:-}"
    if [ -n "${target_user}" ] && id -u "${target_user}" &>/dev/null; then
        log_info "Injecting user '${target_user}' into the docker system group permissions socket map..."
        groupadd -f docker
        usermod -aG docker "${target_user}"
    fi

    log_success "Docker Engine and platform space components installed successfully"
}

verify_docker() {
    if ! command -v docker &>/dev/null; then
        log_error "Docker binary footprint not detected in system workspace path arrays"
        return 1
    fi

    local version
    version=$(docker --version 2>/dev/null)
    log_info "Docker client instance matching payload version: ${version}"

    if docker info &>/dev/null; then
        log_success "Docker running daemon active and responding to standard socket requests"
    else
        log_warn "Docker service daemon is down — attempting automated restoration loop..."
        
        # Smart Recovery Check
        if command -v systemctl &>/dev/null && systemctl read-only &>/dev/null; then
            systemctl start docker 2>/dev/null || true
        else
            log_info "Sandbox detected. Retrying manual dockerd background invocation..."
            if ! pgrep -x "dockerd" &>/dev/null; then
                dockerd > /var/log/dockerd.log 2>&1 &
                sleep 3
            fi
        fi

        if docker info &>/dev/null; then
            log_success "Docker daemon recovered successfully"
        else
            log_error "Docker daemon execution failed. Run manually: systemctl status docker or check /var/log/dockerd.log"
            return 1
        fi
    fi
}

describe_docker() {
    printf "\n   Container Architecture Profiles:\n"
    if command -v docker &>/dev/null; then
        printf "    Docker Engine: operational\n"
        printf "    Active Core Stack: %s\n" "$(docker --version 2>/dev/null | awk '{print $3}' | tr -d ',')"
    else
        printf "    Docker Engine: uninstalled\n"
    fi
}