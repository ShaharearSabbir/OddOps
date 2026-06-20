#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/ui.sh"

install_rust() {
    if command -v rustc &>/dev/null && command -v cargo &>/dev/null; then
        log_warn "Rust and Cargo toolchains already available — skipping"
        return 0
    fi

    log_info "Ensuring system compiler toolchains exist..."
    if command -v apt &>/dev/null; then
        apt-get update -qq && apt-get install -y build-essential gcc
    elif command -v dnf &>/dev/null; then
        dnf groupinstall -y "Development Tools"
    elif command -v pacman &>/dev/null; then
        pacman -S --noconfirm base-devel
    fi

    log_info "Downloading and executing rustup upstream installer pipelines..."
    # --no-modify-path is bypassed since we manually track profile injection reliably
    # -y skips interactive confirmation blocks completely
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --no-modify-path

    # Account for standard configuration location shifts or running within sudo contexts
    local cargo_home="${CARGO_HOME:-${HOME}/.cargo}"
    if [ ! -d "${cargo_home}" ] && [ -d "/root/.cargo" ]; then
        cargo_home="/root/.cargo"
    fi

    local env_file="${cargo_home}/env"
    if [ -f "${env_file}" ]; then
        log_info "Sourcing active system environment targets from ${env_file}..."
        set +u
        source "${env_file}"
        set -u
    fi

    # Inject paths permanently into global fallback spaces to avoid terminal isolation bugs
    if [ -d "${cargo_home}/bin" ]; then
        if ! grep -q "${cargo_home}/bin" /etc/profile 2>/dev/null; then
            printf '\nexport PATH="$PATH:%s"\n' "${cargo_home}/bin" >> /etc/profile
        fi
        export PATH="${PATH}:${cargo_home}/bin"
    fi

    log_success "Rust ecosystem modules installed successfully"
}

verify_rust() {
    # Ensure current script shell gains local execution access parameters 
    local cargo_home="${CARGO_HOME:-${HOME}/.cargo}"
    [ -d "${cargo_home}/bin" ] && export PATH="${PATH}:${cargo_home}/bin"

    if ! command -v rustc &>/dev/null; then
        log_error "Rust compile engine footprints are missing from systemic environment trees"
        return 1
    fi

    log_info "Compiler Core: $(rustc --version 2>/dev/null)"
    log_info "Cargo Manager: $(cargo --version 2>/dev/null)"
}

describe_rust() {
    printf "\n  Rust Lang Infrastructure:\n"
    
    local cargo_home="${CARGO_HOME:-${HOME}/.cargo}"
    if command -v rustc &>/dev/null || [ -x "${cargo_home}/bin/rustc" ]; then
        local raw_v
        raw_v=$("${cargo_home}/bin/rustc" --version 2>/dev/null | awk '{print $2}' || rustc --version 2>/dev/null | awk '{print $2}' || echo "Operational")
        printf "    Rust Stack: operational (%s)\n" "${raw_v}"
        printf "    Cargo Ecosystem: active\n"
    else
        printf "    Rust Stack: uninstalled\n"
    fi
}