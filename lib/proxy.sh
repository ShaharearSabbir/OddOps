#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/ui.sh"

install_nginx() {
    if command -v nginx &>/dev/null; then
        log_warn "Nginx server routing instance already active — skipping"
        return 0
    fi

    log_info "Provisioning Nginx HTTP base infrastructure engine..."

    if command -v apt &>/dev/null; then
        apt-get update -qq && apt-get install -y nginx
    elif command -v dnf &>/dev/null; then
        dnf install -y nginx
    elif command -v pacman &>/dev/null; then
        pacman -S --noconfirm nginx
    else
        log_error "No architecture package alignments identified for Nginx setup"
        return 1
    fi

    # Ensure vhosts tree environments exist across both Debian and RHEL layouts cleanly
    mkdir -p /etc/nginx/sites-available /etc/nginx/sites-enabled /etc/nginx/conf.d

    # Inject directory scans into the core configuration if it's missing (RHEL compatibility)
    if [ -f /etc/nginx/nginx.conf ] && ! grep -q "sites-enabled" /etc/nginx/nginx.conf; then
        sed -i '/include.*conf\.d/a \    include /etc/nginx/sites-enabled/*;' /etc/nginx/nginx.conf 2>/dev/null || true
    fi

    if command -v systemctl &>/dev/null; then
        log_info "Enabling and kicking off active Nginx system service channels..."
        systemctl daemon-reload
        systemctl enable nginx
        systemctl start nginx
    fi

    log_success "Nginx service infrastructure deployed successfully"
}

install_caddy() {
    if command -v caddy &>/dev/null; then
        log_warn "Caddy edge runtime binary already present — skipping"
        return 0
    fi

    log_info "Configuring verified distribution repos for Caddy Web Server..."

    if command -v apt &>/dev/null; then
        apt-get update -qq && apt-get install -y debian-keyring debian-archive-keyring apt-transport-https gnupg
        mkdir -p /etc/apt/keyrings
        curl -fsSL https://dl.cloudsmith.io/public/caddy/stable/gpg.key | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg 2>/dev/null || true
        curl -fsSL https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt | tee /etc/apt/sources.list.d/caddy-stable.list >/dev/null
        apt-get update -qq && apt-get install -y caddy
    elif command -v dnf &>/dev/null; then
        dnf install -y 'dnf-command(copr)'
        dnf copr enable -y @caddy/caddy
        dnf install -y caddy
    else
        log_error "No distribution architecture alignments found for Caddy engine setups"
        return 1
    fi

    if command -v systemctl &>/dev/null; then
        systemctl daemon-reload
        systemctl enable caddy
        systemctl start caddy
    fi

    log_success "Caddy platform service operational"
}

write_nginx_config() {
    local domain="$1"
    local proxy_port="$2"
    
    # Use sites-available as base with seamless symbolic link fallback mappings
    local config_file="/etc/nginx/sites-available/${domain}"
    
    # Fallback structure option directly linking into conf.d if directories are locked
    if [ ! -d /etc/nginx/sites-available ]; then
        config_file="/etc/nginx/conf.d/${domain}.conf"
    fi

    log_info "Generating structural reverse proxy map matrices for ${domain}..."

    cat > "${config_file}" <<EOF
server {
    listen 80;
    listen [::]:80;
    server_name ${domain};

    location / {
        proxy_pass http://127.0.0.1:${proxy_port};
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_cache_bypass \$http_upgrade;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF

    # Establish link maps safely if operating inside standard multi-directory frameworks
    if [ -d /etc/nginx/sites-enabled ] && [ "${config_file}" != "/etc/nginx/conf.d/${domain}.conf" ]; then
        ln -sf "${config_file}" "/etc/nginx/sites-enabled/${domain}"
    fi

    if nginx -t &>/dev/null; then
        systemctl reload nginx 2>/dev/null || systemctl restart nginx
        log_success "Nginx site proxy channels linked and active for ${domain}"
    else
        log_error "Nginx configuration syntax check broke — rollback executed for ${domain}"
        rm -f "${config_file}" "/etc/nginx/sites-enabled/${domain}" 2>/dev/null || true
        return 1
    fi
}

write_caddy_config() {
    local domain="$1"
    local proxy_port="$2"
    local config_file="/etc/caddy/Caddyfile"

    mkdir -p /etc/caddy

    # Safely initialize Caddyfile baseline structures if not present
    if [ ! -f "${config_file}" ]; then
        touch "${config_file}"
    fi

    log_info "Injecting reverse proxy network block rules for ${domain}..."

    # Drop old records matching the target configuration domain to avoid configuration syntax crashes
    if grep -q "${domain}" "${config_file}" 2>/dev/null; then
        log_warn "Discovered old routing matrix structures for ${domain} — rebuilding block..."
        # Extract file content safely while stripping the stale block context mapping out
        local tmp_caddy
        tmp_caddy=$(mktemp)
        sed "/${domain} {/,/}/d" "${config_file}" > "${tmp_caddy}" || true
        cat "${tmp_caddy}" > "${config_file}"
        rm -f "${tmp_caddy}"
    fi

    # Append fresh block payload mappings neatly
    cat >> "${config_file}" <<EOF

${domain} {
    reverse_proxy 127.0.0.1:${proxy_port}
}
EOF

    if command -v systemctl &>/dev/null; then
        systemctl reload caddy 2>/dev/null || systemctl restart caddy 2>/dev/null || true
    fi
    log_success "Caddyfile routes expanded and deployed safely for ${domain}"
}

install_certbot_nginx() {
    if command -v certbot &>/dev/null; then
        log_warn "Certbot letsencrypt binaries already detected — skipping package setups"
        return 0
    fi

    log_info "Provisioning automated SSL Certbot clients and plugin modules..."

    if command -v apt &>/dev/null; then
        apt-get update -qq && apt-get install -y certbot python3-certbot-nginx
    elif command -v dnf &>/dev/null; then
        dnf install -y certbot python3-certbot-nginx
    elif command -v pacman &>/dev/null; then
        pacman -S --noconfirm certbot certbot-nginx
    else
        log_error "No matching systemic package architectures identified for Certbot installations"
        return 1
    fi

    log_success "Certbot stack installed cleanly"
}

provision_ssl() {
    local domain="$1"

    if [ -d "/etc/letsencrypt/live/${domain}" ] || [ -d "/etc/letsencrypt/live/${domain}-0001" ]; then
        log_warn "SSL cryptographic key infrastructure already active for ${domain} — skipping"
        return 0
    fi

    if ! command -v certbot &>/dev/null; then
        log_error "Certbot validation dependencies missing from server systems path arrays"
        return 1
    fi

    log_info "Requesting signed upstream Let's Encrypt certificates via automated Nginx challenge validation..."
    
    # Trigger system validations safely without script execution hang points
    certbot --nginx -d "${domain}" --non-interactive --agree-tos --email "admin@${domain}" || \
    certbot --nginx -d "${domain}" --register-unsafely-without-email --non-interactive --agree-tos

    log_success "SSL transportation channels verified and secured via HTTPS for ${domain}"
}

verify_proxy() {
    if command -v nginx &>/dev/null; then
        log_info "Nginx Core Version: $(nginx -v 2>&1 | awk -F '/' '{print $2}' || echo "active")"
    fi

    if command -v caddy &>/dev/null; then
        log_info "Caddy Core Version: $(caddy version 2>/dev/null | awk '{print $1}' || echo "active")"
    fi

    if command -v certbot &>/dev/null; then
        log_info "Certbot Automation Binary: active"
    fi
}

describe_proxy() {
    printf "\n  Ingress Proxy Profiles & Layer Services:\n"
    if command -v nginx &>/dev/null; then
        printf "    Nginx Engine: operational\n"
    else
        printf "    Nginx Engine: uninstalled\n"
    fi
    
    if command -v caddy &>/dev/null; then
        printf "    Caddy Edge: operational\n"
    else
        printf "    Caddy Edge: uninstalled\n"
    fi

    if command -v certbot &>/dev/null; then
        printf "    Certbot TLS: operational\n"
    else
        printf "    Certbot TLS: uninstalled\n"
    fi
}