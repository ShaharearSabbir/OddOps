#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/ui.sh"

BOLD=""
RED=""
YELLOW=""
RESET=""

if [ -t 1 ]; then
    if command -v tput >/dev/null 2>&1; then
        BOLD=$(tput bold 2>/dev/null || true)
        RED=$(tput setaf 1 2>/dev/null || true)
        YELLOW=$(tput setaf 3 2>/dev/null || true)
        RESET=$(tput sgr0 2>/dev/null || true)
    fi
fi

confirm_reset() {
    printf "\n"
    printf "%s╔══════════════════════════════════════════════════════════════╗%s\n" "${RED}" "${RESET}"
    printf "%s║                    !!!  DANGER  !!!                          ║%s\n" "${BOLD}${RED}" "${RESET}"
    printf "%s║                                                              ║%s\n" "${RED}" "${RESET}"
    printf "%s║  This will PERMANENTLY remove OddOps-installed packages,      ║%s\n" "${RED}" "${RESET}"
    printf "%s║  databases, configurations, services, and firewall rules     ║%s\n" "${RED}" "${RESET}"
    printf "%s║  from this server. This action CANNOT be undone.              ║%s\n" "${RED}" "${RESET}"
    printf "%s║                                                              ║%s\n" "${RED}" "${RESET}"
    printf "%s║  To confirm, type:  %sRESET%s                                ║%s\n" "${RED}" "${BOLD}${YELLOW}" "${RED}" "${RESET}"
    printf "%s╚══════════════════════════════════════════════════════════════╝%s\n" "${RED}" "${RESET}"
    printf "\n"

    local response
    read -r -p "> " response

    if [ "${response}" != "RESET" ]; then
        log_warn "Teardown cancelled by user"
        exit 0
    fi

    printf "\n"
    log_warn "Teardown confirmed — proceeding with reset..."
    printf "\n"
}

detect_package_manager() {
    if command -v apt &>/dev/null; then
        echo "apt"
    elif command -v dnf &>/dev/null; then
        echo "dnf"
    elif command -v pacman &>/dev/null; then
        echo "pacman"
    else
        echo ""
    fi
}

clean_proxy() {
    print_step "Cleaning Proxy Configurations"

    if command -v nginx &>/dev/null; then
        log_info "Removing Nginx site configurations..."
        for conf in /etc/nginx/sites-enabled/*; do
            if [ -e "$conf" ]; then
                local name
                name=$(basename "${conf}")
                if [ "${name}" != "default" ]; then
                    rm -f "/etc/nginx/sites-enabled/${name}" 2>/dev/null || true
                    rm -f "/etc/nginx/sites-available/${name}" 2>/dev/null || true
                    log_info "  Removed: ${name}"
                fi
            fi
        done

        if nginx -t 2>/dev/null; then
            systemctl reload nginx 2>/dev/null || true
            log_success "Nginx reloaded"
        fi
    fi

    if command -v caddy &>/dev/null; then
        log_info "Resetting Caddyfile to default..."
        if [ -f /etc/caddy/Caddyfile ]; then
            cp /etc/caddy/Caddyfile /etc/caddy/Caddyfile.oddops-backup 2>/dev/null || true
            printf "# OddOps reset — default Caddyfile\n\n:80 {\n\trespond \"Hello from Caddy\"\n}\n" > /etc/caddy/Caddyfile
            systemctl reload caddy 2>/dev/null || systemctl restart caddy 2>/dev/null || true
            log_success "Caddyfile reset to default"
        fi
    fi

    if command -v certbot &>/dev/null; then
        log_info "Removing Certbot SSL certificates..."
        certbot revoke --non-interactive --delete-after-revoke 2>/dev/null || true
        log_info "Certbot certificates revoked"
    fi
}

clean_services() {
    print_step "Stopping and Disabling Services"

    if command -v pm2 &>/dev/null; then
        log_info "Stopping PM2 daemon..."
        pm2 kill 2>/dev/null || true
        pm2 unstartup 2>/dev/null || true
        log_success "PM2 stopped"
    fi

    if command -v docker &>/dev/null && docker info &>/dev/null; then
        log_info "Stopping Docker containers..."
        local active_containers
        active_containers=$(docker ps -q 2>/dev/null)
        if [ -n "$active_containers" ]; then
            docker stop $active_containers 2>/dev/null || true
        fi
        docker system prune -a --volumes -f 2>/dev/null || true
        log_success "Docker containers stopped and pruned"
    fi

    log_info "Disabling custom systemd units..."
    for unit in /etc/systemd/system/*.service; do
        if [ -f "$unit" ]; then
            local name
            name=$(basename "${unit}")
            if grep -q "OddOps" "${unit}" 2>/dev/null || grep -q "Created by OddOps" "${unit}" 2>/dev/null; then
                systemctl stop "${name}" 2>/dev/null || true
                systemctl disable "${name}" 2>/dev/null || true
                rm -f "${unit}" 2>/dev/null || true
                log_info "  Removed custom service daemon: ${name}"
            fi
        fi
    done
    systemctl daemon-reload 2>/dev/null || true
}

purge_runtime_packages() {
    print_step "Purging Runtime Packages & Multi-Version Stacks"

    local pm
    pm=$(detect_package_manager)

    case "${pm}" in
        apt)
            log_info "Purging packages via apt (wildcard matched)..."
            # Using wildcards ensuring that any version choice (Node 18/20/22, Java 11/17/21) is captured dynamically
            apt-get remove -y --purge --auto-remove \
                nodejs "openjdk-*" "ruby*" \
                docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin \
                nginx nginx-common caddy certbot python3-certbot-nginx \
                postgresql* mysql-server redis-server 2>/dev/null || true
            apt-get remove -y --purge --auto-remove mongodb-org* 2>/dev/null || true
            apt-get autoremove -y 2>/dev/null || true
            ;;
        dnf)
            log_info "Removing packages via dnf..."
            dnf remove -y \
                nodejs "java-*" "ruby*" \
                docker-ce docker-ce-cli containerd.io \
                nginx caddy certbot python3-certbot-nginx \
                "postgresql*" mysql-server redis 2>/dev/null || true
            dnf remove -y mongodb-org* 2>/dev/null || true
            ;;
        pacman)
            log_info "Removing packages via pacman..."
            pacman -Rns --noconfirm \
                nodejs npm "jdk*-openjdk" ruby \
                docker containerd nginx caddy certbot certbot-nginx \
                postgresql mysql redis 2>/dev/null || true
            pacman -Rns --noconfirm mongodb 2>/dev/null || true
            ;;
        *)
            log_warn "No supported package manager detected — skipping package purge"
            ;;
    esac

    if [ -d /usr/local/go ]; then
        log_info "Removing Go tarball installation at /usr/local/go..."
        rm -rf /usr/local/go
        log_success "Go removed"
    fi

    if [ -d "${HOME}/.cargo" ]; then
        log_info "Removing Rust toolchain..."
        rm -rf "${HOME}/.cargo" "${HOME}/.rustup" 2>/dev/null || true
        log_success "Rust toolchain removed"
    fi
}

clean_databases() {
    print_step "Purging Databases and System Tables"

    for svc in postgresql mongod mysql redis-server redis; do
        systemctl stop "${svc}" 2>/dev/null || true
        systemctl disable "${svc}" 2>/dev/null || true
    done

    log_info "Erasing state folders and data directories..."
    rm -rf /var/lib/postgresql /var/lib/mongodb /var/lib/mysql /var/lib/redis /etc/mysql /etc/postgresql 2>/dev/null || true

    if [ -f /root/.oddops-credentials ]; then
        log_info "Removing OddOps credentials key file..."
        rm -f /root/.oddops-credentials
        log_success "Credentials safe removed"
    fi
}

reset_firewall() {
    print_step "Resetting Firewall Rules"

    # Dynamic lookup fallback for custom port recovery since execution variables don't persist across fresh environments
    local DETECTED_CUSTOM_PORT
    DETECTED_CUSTOM_PORT=$(grep -i "^Port " /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}' || echo "22")

    if command -v ufw &>/dev/null; then
        if ufw status | grep -q "Status: active"; then
            log_info "Resetting UFW to system defaults..."
            ufw --force reset
            log_success "UFW firewall reset to default state (disabled)"
        fi
    fi

    if command -v firewall-cmd &>/dev/null; then
        if firewall-cmd --state 2>/dev/null | grep -q "running"; then
            log_info "Resetting firewalld system spaces..."
            if [ "${DETECTED_CUSTOM_PORT}" != "22" ]; then
                firewall-cmd --zone=public --remove-port="${DETECTED_CUSTOM_PORT}/tcp" --permanent 2>/dev/null || true
                firewall-cmd --reload 2>/dev/null || true
                log_info "Custom port rule (${DETECTED_CUSTOM_PORT}) stripped from firewalld config safely"
            fi
            firewall-cmd --set-default-zone=public 2>/dev/null || true
        fi
    fi
}

main() {
    # Ensure script runs as root
    if [ "$EUID" -ne 0 ]; then
        echo "[ERROR] This script must be run as root (or via sudo execution)." >&2
        exit 1
    fi

    oddops_banner
    confirm_reset
    clean_services
    clean_databases
    clean_proxy
    purge_runtime_packages
    reset_firewall
    printf "\n"
    log_success "OddOps teardown complete — server clean up finished"
}

main "$@"