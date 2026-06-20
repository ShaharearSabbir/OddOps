#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/ui.sh"

create_deploy_user() {
    local username="$1"

    if [ -z "${username}" ]; then
        log_error "Target workspace creation account string missing"
        return 1
    fi

    if id "${username}" &>/dev/null; then
        log_warn "Deployment target account '${username}' already registered — skipping"
        return 0
    fi

    log_info "Creating system deployment user account: '${username}'..."
    useradd --create-home --shell /bin/bash "${username}"
    
    # Intelligently assign groups based on platform definitions
    if grep -q '^sudo:' /etc/group; then
        usermod -aG sudo "${username}"
    elif grep -q '^wheel:' /etc/group; then
        usermod -aG wheel "${username}"
    fi

    log_success "Deployment space account structure configured for '${username}'"
}

setup_sudo_access() {
    local username="$1"
    local sudoers_dir="/etc/sudoers.d"
    local sudoers_file="${sudoers_dir}/${username}"

    if [ -f "${sudoers_file}" ]; then
        log_warn "Sudo allocation manifest for '${username}' already exists — skipping"
        return 0
    fi

    log_info "Configuring passwordless sudo execution access map layers..."
    mkdir -p "${sudoers_dir}"
    chmod 750 "${sudoers_dir}"
    
    # Explicit trailing line feed to comply with strict POSIX parsing requirements
    printf "%s ALL=(ALL) NOPASSWD:ALL\n" "${username}" > "${sudoers_file}"
    chmod 440 "${sudoers_file}"
    
    log_success "Sudo execution space mapping authorized without password checks"
}

configure_ssh_key() {
    local username="$1"
    local public_key_payload="${2:-}"
    
    local user_home
    user_home=$(getent passwd "${username}" | cut -d: -f6 || echo "/home/${username}")
    local ssh_dir="${user_home}/.ssh"
    local auth_keys="${ssh_dir}/authorized_keys"

    if [ -f "${auth_keys}" ] && [ -n "${public_key_payload}" ] && grep -qF "${public_key_payload:0:20}" "${auth_keys}" 2>/dev/null; then
        log_warn "Matching target cryptographic public key already present inside authorized matrices"
        return 0
    fi

    log_info "Configuring automated SSH key structural mappings for '${username}'..."
    mkdir -p "${ssh_dir}"
    
    if [ -n "${public_key_payload}" ]; then
        # Automated non-interactive mode pipeline injection
        printf "%s\n" "${public_key_payload}" >> "${auth_keys}"
    else
        # Fallback to interactive mode with a check for an active terminal session
        if [ -t 0 ]; then
            printf "\n"
            log_info "Paste the public SSH key for '${username}' (then press Ctrl+D):"
            cat >> "${auth_keys}"
        else
            log_error "Non-interactive automation pipeline execution blocked: No public key string passed"
            return 1
        fi
    fi

    # Secure internal directory access permissions to prevent OpenSSH key rejections
    chmod 700 "${ssh_dir}"
    chmod 600 "${auth_keys}"
    chown -R "${username}:${username}" "${ssh_dir}"
    
    log_success "SSH authorization profiles updated successfully"
}

disable_root_login() {
    local sshd_config="/etc/ssh/sshd_config"
    set_sshd_option "PermitRootLogin" "no" "${sshd_config}"
    log_success "Administrative base root logins blocked from remote vectors"
}

lock_root_password() {
    local username="${1:-${ODD_DEPLOY_USER:-}}"

    local root_status
    root_status=$(passwd --status root 2>/dev/null | awk '{print $2}' || echo "")
    if [ "${root_status}" = "LK" ] || [ "${root_status}" = "L" ]; then
        log_warn "Systemic root master password state already isolated — skipping"
        return 0
    fi

    log_info "Isolating raw root password visibility profiles..."
    passwd -l root
    log_info "Administrative access must route via sudo loops mapped through standard account spaces"
}

detect_firewall() {
    if command -v ufw &>/dev/null; then
        echo "ufw"
    elif command -v firewall-cmd &>/dev/null; then
        echo "firewalld"
    else
        echo ""
    fi
}

configure_firewall_ufw() {
    local ssh_port="$1"

    log_info "Configuring rules for UFW before final structural daemon activation..."
    # ALWAYS configure rules BEFORE enabling the firewall to prevent immediate lockouts
    ufw default deny incoming
    ufw default allow outgoing
    ufw allow "${ssh_port}/tcp" comment 'SSH Core Access Port'

    if ufw status | grep -q "Status: active"; then
        log_warn "UFW is already active — synchronization completed"
    else
        log_info "Activating UFW security matrix engines..."
        ufw --force enable
    fi

    log_success "UFW network boundaries applied successfully"
}

configure_firewall_firewalld() {
    local ssh_port="$1"
    local zone="public"

    if ! systemctl is-active firewalld &>/dev/null; then
        log_info "Starting firewalld engine spaces..."
        systemctl start firewalld
        systemctl enable firewalld
    fi

    log_info "Mapping access holes for target port ${ssh_port} inside zone: ${zone}..."
    firewall-cmd --zone="${zone}" --add-port="${ssh_port}/tcp" --permanent 2>/dev/null || true
    firewall-cmd --reload
    
    log_success "Firewalld layer mappings updated safely"
}

configure_firewall() {
    local ssh_port="${1:-22}"
    local firewall
    firewall=$(detect_firewall)

    case "${firewall}" in
        ufw)
            log_info "Detected active network package wrapper: UFW"
            configure_firewall_ufw "${ssh_port}"
            ;;
        firewalld)
            log_info "Detected active network package wrapper: Firewalld"
            configure_firewall_firewalld "${ssh_port}"
            ;;
        *)
            log_warn "No system firewall package profiles identified — skipping network isolation steps"
            return 0
            ;;
    esac
}

set_sshd_option() {
    local key="$1"
    local value="$2"
    local file="${3:-/etc/ssh/sshd_config}"

    # Standardize spaces and handles commented variants out cleanly
    if grep -qE "^\s*#?\s*${key}\s+" "${file}" 2>/dev/null; then
        sed -i "s/^\s*#?\s*${key}\s\+.*/${key} ${value}/" "${file}"
    else
        printf "\n%s %s\n" "${key}" "${value}" >> "${file}"
    fi
}

harden_ssh() {
    local ssh_port="${1:-22}"
    local sshd_config="/etc/ssh/sshd_config"

    log_info "Injecting hardened OpenSSH baseline infrastructure configurations..."

    disable_root_login

    if [ "${ssh_port}" -ne 22 ]; then
        log_info "Re-routing network traffic to custom listen port: ${ssh_port}..."
        set_sshd_option "Port" "${ssh_port}" "${sshd_config}"
    fi

    set_sshd_option "PasswordAuthentication" "no" "${sshd_config}"
    set_sshd_option "PermitEmptyPasswords" "no" "${sshd_config}"
    set_sshd_option "UsePAM" "yes" "${sshd_config}"
    set_sshd_option "MaxAuthTries" "3" "${sshd_config}"
    set_sshd_option "MaxSessions" "10" "${sshd_config}"
    set_sshd_option "ClientAliveInterval" "300" "${sshd_config}"
    set_sshd_option "ClientAliveCountMax" "2" "${sshd_config}"
    set_sshd_option "X11Forwarding" "no" "${sshd_config}"
    set_sshd_option "AllowAgentForwarding" "no" "${sshd_config}"
    set_sshd_option "IgnoreRhosts" "yes" "${sshd_config}"

    # Modern cross-generation fallback support mapping for OpenSSH keyboard interaction parameters
    set_sshd_option "ChallengeResponseAuthentication" "no" "${sshd_config}" 2>/dev/null || true
    set_sshd_option "KbdInteractiveAuthentication" "no" "${sshd_config}" 2>/dev/null || true

    log_info "Validating configuration file syntax parameters before reboot steps..."
    if sshd -t -f "${sshd_config}" &>/dev/null; then
        log_info "Syntax verified — restarting active sshd processing units..."
        if command -v systemctl &>/dev/null; then
            systemctl restart sshd
        else
            service ssh restart
        fi
        log_success "SSH engine configuration hardened successfully"
    else
        log_error "SSH configuration syntax error detected — skipping service reload to avoid remote lockout"
        return 1
    fi
}