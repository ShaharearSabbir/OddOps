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

    if command -v systemctl &>/dev/null; then
        log_info "Enabling and kicking off Docker daemon process channels..."
        systemctl daemon-reload
        systemctl enable docker
        systemctl start docker
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
        systemctl start docker 2>/dev/null || true
        if docker info &>/dev/null; then
            log_success "Docker daemon recovered successfully"
        else
            log_error "Docker daemon execution failed. Run manually: systemctl status docker"
            return 1
        fi
    fi
}

describe_docker() {
    printf "\n  Container Architecture Profiles:\n"
    if command -v docker &>/dev/null; then
        printf "    Docker Engine: operational\n"
        printf "    Active Core Stack: %s\n" "$(docker --version 2>/dev/null | awk '{print $3}' | tr -d ',')"
    else
        printf "    Docker Engine: uninstalled\n"
    fi
}