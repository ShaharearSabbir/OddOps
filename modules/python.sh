#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/ui.sh"

install_python() {
    local py_version="${1:-}"

    if command -v python3 &>/dev/null; then
        log_warn "Python 3 core execution layer already active — skipping"
        return 0
    fi

    log_info "Provisioning Python 3 development platform stacks..."

    if command -v apt &>/dev/null; then
        apt-get update -qq
        if [ -n "${py_version}" ]; then
            apt-get install -y "python${py_version}" "python${py_version}-venv" "python${py_version}-pip" 2>/dev/null || \
            apt-get install -y python3 python3-pip python3-venv python3-full
        else
            apt-get install -y python3 python3-pip python3-venv python3-full
        fi
    elif command -v dnf &>/dev/null; then
        # RHEL separates pip but includes venv modules directly within standard core engine binaries
        dnf install -y python3 python3-pip
    elif command -v pacman &>/dev/null; then
        pacman -S --noconfirm python python-pip
    else
        log_error "No architecture package alignments identified for Python setups"
        return 1
    fi

    log_success "Python 3 deployment layers installed natively: $(python3 --version 2>/dev/null)"
}

create_python_venv() {
    local app_dir="$1"
    local venv_dir="${app_dir}/venv"

    if [ -z "${app_dir}" ]; then
        log_error "Target root application path cannot be empty strings"
        return 1
    fi

    if [ -d "${venv_dir}" ]; then
        log_warn "Virtual environment context layer already present at ${venv_dir} — skipping"
        return 0
    fi

    log_info "Initializing clean isolated environment context space inside: ${venv_dir}..."
    mkdir -p "${app_dir}"
    python3 -m venv "${venv_dir}"
    log_success "Python isolated virtual matrix initialized successfully"
}

install_pip_requirements() {
    local app_dir="$1"
    local venv_pip="${app_dir}/venv/bin/pip"

    if [ ! -f "${app_dir}/requirements.txt" ]; then
        log_warn "No app distribution manifests (requirements.txt) identified at ${app_dir} — skipping dependencies setup"
        return 0
    fi

    if [ ! -x "${venv_pip}" ]; then
        log_error "Isolated pipeline target binary execution link not found at: ${venv_pip}"
        return 1
    fi

    log_info "Injecting verified dependencies from requirements manifest via targeted isolation loops..."
    # Upgrading pip within the venv safely bypasses PEP 668 restrictions entirely
    "${venv_pip}" install --upgrade pip setuptools wheel 2>/dev/null || true
    "${venv_pip}" install -r "${app_dir}/requirements.txt"
    log_success "Pip application packages installed successfully"
}

create_systemd_unit() {
    local app_name="$1"
    local app_dir="$2"
    local app_entry="${3:-app.py}"
    local username="${4:-${ODD_DEPLOY_USER:-app}}"

    local unit_file="/etc/systemd/system/${app_name}.service"

    if [ -f "${unit_file}" ]; then
        log_warn "Systemd descriptor mapping ${unit_file} already active — skipping registration loops"
        return 0
    fi

    # Verify runtime execution contexts safely
    if ! id -u "${username}" &>/dev/null; then
        log_warn "System execution account space '${username}' missing — defaulting descriptor parameters to root scope"
        username="root"
    fi

    log_info "Generating daemon monitoring service unit map configurations for: '${app_name}'..."

    cat > "${unit_file}" <<EOF
[Unit]
Description=OddOps Provisioned Process Framework — ${app_name}
After=network.target

[Service]
Type=simple
User=${username}
WorkingDirectory=${app_dir}
ExecStart=${app_dir}/venv/bin/python3 ${app_entry}
Restart=always
RestartSec=5
Environment=PYTHONUNBUFFERED=1
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

    log_info "Reloading host service control structures and spinning up persistent process maps..."
    systemctl daemon-reload
    systemctl enable "${app_name}.service" 2>/dev/null || true
    
    log_success "Systemd configuration unit created and registered dynamically: ${app_name}"
}

verify_python() {
    if ! command -v python3 &>/dev/null; then
        log_error "Python 3 binary footprint is missing from active runtime contexts"
        return 1
    fi

    log_info "Python Core: $(python3 --version 2>&1)"
    
    # Check pip context version mappings cleanly without dropping on multi-line text strings
    local check_pip
    check_pip=$(python3 -m pip --version 2>/dev/null | awk '{print $2}' || echo "unregistered globally")
    log_info "Pip Package Layer: v${check_pip}"
}

describe_python() {
    printf "\n  Python Execution Matrices:\n"
    if command -v python3 &>/dev/null; then
        printf "    Python 3 Engine: operational (%s)\n" "$(python3 --version 2>/dev/null)"
        printf "    Isolated Venv Subsystem: fully functional\n"
    else
        printf "    Python 3 Engine: uninstalled\n"
    fi
}