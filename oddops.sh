#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Relative mapping path pointing directly to your logging framework library
source "${SCRIPT_DIR}/lib/ui.sh"

# Global session configurations
CONFIG_FILE="${SCRIPT_DIR}/config.json"
export ODD_DOCKER_MODE="false"

# ==============================================================================
# PRE-FLIGHT DEPENDENCY CHECKER
# ==============================================================================
preflight_checks() {
    log_info "Running pre-flight system dependency checks..."
    
    if [ ! -f /etc/os-release ]; then
        log_error "Cannot detect operating system: /etc/os-release not found"
        return 1
    fi
    . /etc/os-release

    local REQUIRED_PKGS=("curl" "wget" "git" "gnupg" "sed" "grep" "awk")
    local MISSING_PKGS=()

    for pkg in "${REQUIRED_PKGS[@]}"; do
        if ! command -v "$pkg" &>/dev/null; then
            MISSING_PKGS+=("$pkg")
        fi
    done

    if [ "${#MISSING_PKGS[@]}" -gt 0 ]; then
        log_warn "Missing core dependencies: ${MISSING_PKGS[*]}"
        log_info "Attempting to install missing core utilities natively..."
        
        export DEBIAN_FRONTEND=noninteractive
        
        case "${ID:-}" in
            ubuntu|debian|pop|mint)
                apt-get update -y -qq
                apt-get install -y -qq "${MISSING_PKGS[@]}"
                ;;
            rhel|rocky|almalinux|fedora|centos)
                if command -v dnf &>/dev/null; then
                    dnf install -y -q "${MISSING_PKGS[@]}"
                else
                    yum install -y -q "${MISSING_PKGS[@]}"
                fi
                ;;
            arch|manjaro)
                pacman -Sy --noconfirm -q "${MISSING_PKGS[@]}"
                ;;
            *)
                log_error "Unsupported OS flavor for auto-dependency injection. Please install manually: ${MISSING_PKGS[*]}"
                return 1
                ;;
        esac
        log_success "All pre-flight dependencies successfully installed."
    else
        log_success "System satisfies all pre-flight binary criteria."
    fi
}

detect_os() {
    . /etc/os-release

    ODD_OS_ID="${ID}"
    ODD_OS_VERSION="${VERSION_ID:-}"
    ODD_OS_NAME="${PRETTY_NAME:-$NAME}"
    ODD_OS_ID_LIKE="${ID_LIKE:-}"

    export ODD_OS_ID ODD_OS_VERSION ODD_OS_NAME ODD_OS_ID_LIKE

    log_success "Detected OS: ${ODD_OS_NAME} (${ODD_OS_ID} ${ODD_OS_VERSION})"
}

# ==============================================================================
# CONFIGURATION STORAGE MANIFEST LAYERS (JSON ENGINES)
# ==============================================================================
save_configuration_json() {
    log_info "Serializing state parameters into localized session configuration..."
    
    # Converts bash spaced elements into explicit raw JSON structural arrays safely
    local runtimes_json databases_json
    runtimes_json=$(echo "${ODD_RUNTIME_VERSIONS}" | awk '{printf "["; for(i=1;i<=NF;i++) printf "\"%s\"%s", $i, (i==NF?"":","); printf "]"}')
    databases_json=$(echo "${ODD_DATABASES}" | awk '{printf "["; for(i=1;i<=NF;i++) printf "\"%s\"%s", $i, (i==NF?"":","); printf "]"}')

    cat > "${CONFIG_FILE}" <<EOF
{
  "username": "${ODD_DEPLOY_USER}",
  "ssh_port": "${ODD_SSH_PORT}",
  "domain": "${ODD_DOMAIN:-}",
  "docker_mode": ${ODD_DOCKER_MODE},
  "runtime_versions": ${runtimes_json},
  "databases": ${databases_json}
}
EOF
    log_success "Session snapshot securely stored at ${CONFIG_FILE}"
}

load_configuration_json() {
    log_info "Extracting session elements from existing config profile..."
    
    # Robust sed/awk parsers to safely scrape configurations without requiring outside tools like jq
    ODD_DEPLOY_USER=$(sed -n 's/.*"username": *"\([^"]*\)".*/\1/p' "${CONFIG_FILE}")
    ODD_SSH_PORT=$(sed -n 's/.*"ssh_port": *"\([^"]*\)".*/\1/p' "${CONFIG_FILE}")
    ODD_DOMAIN=$(sed -n 's/.*"domain": *"\([^"]*\)".*/\1/p' "${CONFIG_FILE}")
    ODD_DOCKER_MODE=$(sed -n 's/.*"docker_mode": *\([a-z]*\).*/\1/p' "${CONFIG_FILE}")
    
    # Normalize clean flat multi-variable strings from JSON arrays
    ODD_RUNTIME_VERSIONS=$(sed -n '/"runtime_versions": *\[/,/\]/p' "${CONFIG_FILE}" | sed 's/[][" ,]*//g' | grep -v '^$' | tr '\n' ' ' | sed 's/ $//')
    ODD_DATABASES=$(sed -n '/"databases": *\[/,/\]/p' "${CONFIG_FILE}" | sed 's/[][" ,]*//g' | grep -v '^$' | tr '\n' ' ' | sed 's/ $//')

    export ODD_DEPLOY_USER ODD_SSH_PORT ODD_DOMAIN ODD_DOCKER_MODE ODD_RUNTIME_VERSIONS ODD_DATABASES

    log_success "Profile loaded successfully:"
    printf "  - User: %s\n" "${ODD_DEPLOY_USER}"
    printf "  - SSH Port: %s\n" "${ODD_SSH_PORT}"
    printf "  - Domain: %s\n" "${ODD_DOMAIN:-[None]}"
    printf "  - Docker Core: %s\n" "${ODD_DOCKER_MODE}"
    printf "  - Runtimes Map: %s\n" "${ODD_RUNTIME_VERSIONS}"
    printf "  - Data Warehouses: %s\n" "${ODD_DATABASES}"
}

check_cached_session() {
    if [ -f "${CONFIG_FILE}" ]; then
        printf "\n"
        log_warn "Detected an existing deployment snapshot at: ${CONFIG_FILE}"
        printf "Do you want to re-use this existing setup profile configuration?\n"
        printf "  1) Yes, restore profile data and execute installation\n"
        printf "  2) No, drop cache file and start fresh wizard input routing\n"
        printf "\n"
        
        local cached_choice
        while true; do
            read -r -p "Select option [1]: " cached_choice
            cached_choice="${cached_choice:-1}"
            case "${cached_choice}" in
                1)
                    load_configuration_json
                    return 0 # Skips structural validation loop sequences safely
                    ;;
                2)
                    log_info "Purging deprecated configurations..."
                    rm -f "${CONFIG_FILE}"
                    return 1 # Drops back into manual execution workflows
                    ;;
                *)
                    log_error "Invalid entry target scope — pick 1 or 2"
                    ;;
            esac
        done
    fi
    return 1
}

# ==============================================================================
# DATA ENTRY VALIDATION CORE
# ==============================================================================
validate_username() {
    local user="$1"
    if [ -z "${user}" ]; then
        log_error "Username cannot be empty"
        return 1
    fi
    if ! echo "${user}" | grep -qE '^[a-z_][a-z0-9_-]*$'; then
        log_error "Invalid username '${user}' — must start with lowercase letters/underscores and match POSIX standards"
        return 1
    fi
}

validate_ssh_port() {
    local port="$1"
    if ! echo "${port}" | grep -qE '^[0-9]+$'; then
        log_error "SSH port must be a numerical digit sequence"
        return 1
    fi
    if [ "${port}" -lt 22 ] || [ "${port}" -gt 65535 ]; then
        log_error "SSH port selection must be between 22 and 65535"
        return 1
    fi
}

validate_domain() {
    local domain="$1"
    if ! echo "${domain}" | grep -qE '^([a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}$'; then
        log_error "Invalid FQDN domain string target format: '${domain}'"
        return 1
    fi
}

prompt_for_username() {
    printf "\n"
    while true; do
        read -r -p "Enter deployment username: " ODD_DEPLOY_USER
        if validate_username "${ODD_DEPLOY_USER}"; then
            break
        fi
    done
    export ODD_DEPLOY_USER
}

prompt_for_ssh_port() {
    printf "\n"
    while true; do
        read -r -p "Enter SSH port [22]: " ODD_SSH_PORT
        ODD_SSH_PORT="${ODD_SSH_PORT:-22}"
        if [ "${ODD_SSH_PORT}" = "22" ] || validate_ssh_port "${ODD_SSH_PORT}"; then
            break
        fi
    done
    export ODD_SSH_PORT
}

prompt_for_domain() {
    printf "\n"
    while true; do
        read -r -p "Enter target domain (e.g. example.com): " ODD_DOMAIN
        if [ -z "${ODD_DOMAIN}" ]; then
            log_warn "No domain provided — skipping reverse proxy and SSL infrastructure configurations"
            break
        fi
        if validate_domain "${ODD_DOMAIN}"; then
            break
        fi
    done
    export ODD_DOMAIN
}

get_version_choices() {
    local runtime="$1"
    case "${runtime}" in
        "Node.js") echo "18 20 22 24 26" ;;
        "Python")  echo "3.10 3.11 3.12 3.13 3.14" ;;
        "Go")      echo "1.22 1.23 1.24 1.25 1.26" ;;
        "Java")    echo "11 17 21 25" ;;
        "Ruby")    echo "3.1 3.2 3.3 3.4 4.0" ;;
        *)         echo "" ;;
    esac
}

prompt_for_runtimes() {
    local runtimes=("Docker" "Node.js" "Python" "Go" "Java" "Rust" "Ruby")
    local selected=()
    local choice

    printf "\n"
    print_step "Runtime Environment Matrix Selection"
    printf "Select runtimes to provision (enter numbers separated by spaces, or 'a' for full orchestration):\n"
    for i in "${!runtimes[@]}"; do
        printf "  %d) %s\n" "$((i + 1))" "${runtimes[$i]}"
    done
    printf "  a) All runtimes\n"
    printf "\n"

    read -r -p "Choice(s): " choice
    choice=$(echo "${choice}" | tr ',' ' ')

    if [ "${choice}" = "a" ]; then
        selected=("${runtimes[@]}")
        ODD_DOCKER_MODE="true"
    else
        for num in ${choice}; do
            local idx="$((num - 1))"
            if [ "${idx}" -ge 0 ] && [ "${idx}" -lt "${#runtimes[@]}" ]; then
                local selected_runtime="${runtimes[$idx]}"
                selected+=("${selected_runtime}")
                if [ "${selected_runtime}" = "Docker" ]; then
                    ODD_DOCKER_MODE="true"
                fi
            fi
        done
    fi

    export ODD_DOCKER_MODE

    if [ "${#selected[@]}" -eq 0 ]; then
        log_warn "No language platforms selected — skipping execution driver tasks"
        export ODD_RUNTIME_VERSIONS=""
        return
    fi

    prompt_for_runtime_versions "${selected[@]}"
}

prompt_for_runtime_versions() {
    local selected_runtimes=("$@")
    local final=()

    for runtime in "${selected_runtimes[@]}"; do
        if [ "${runtime}" = "Docker" ]; then
            final+=("Docker:latest")
            continue
        fi

        local versions
        versions=$(get_version_choices "${runtime}")

        if [ -z "${versions}" ]; then
            final+=("${runtime}:latest")
            continue
        fi

        local version_list=(${versions})
        local version_choice

        printf "\n"
        log_info "Select deployment target execution version for ${runtime}:"
        for i in "${!version_list[@]}"; do
            printf "  %d) %s\n" "$((i + 1))" "${version_list[$i]}"
        done
        printf "\n"

        while true; do
            read -r -p "Choice [1]: " version_choice
            version_choice="${version_choice:-1}"
            local v_idx="$((version_choice - 1))"
            if [ "${v_idx}" -ge 0 ] && [ "${v_idx}" -lt "${#version_list[@]}" ]; then
                final+=("${runtime}:${version_list[$v_idx]}")
                break
            fi
            log_error "Invalid parameter selection — choose a number between 1 and ${#version_list[@]}"
        done
    done

    ODD_RUNTIME_VERSIONS="${final[*]}"
    export ODD_RUNTIME_VERSIONS
}

prompt_for_databases() {
    local databases=("None" "PostgreSQL" "MongoDB" "MySQL" "Redis")
    local selected=()
    local choice

    printf "\n"
    print_step "Database Provisioning Array Configuration"
    
    if [ "${ODD_DOCKER_MODE}" = "true" ]; then
        log_info "Container system active — database storage nodes will drop inside dockerized boundaries"
    fi
    
    printf "Select storage platforms to build (enter numbers separated by spaces):\n"
    for i in "${!databases[@]}"; do
        printf "  %d) %s\n" "$((i + 1))" "${databases[$i]}"
    done
    printf "\n"

    read -r -p "Choice(s): " choice
    choice=$(echo "${choice}" | tr ',' ' ')

    for num in ${choice}; do
        local idx="$((num - 1))"
        if [ "${idx}" -ge 0 ] && [ "${idx}" -lt "${#databases[@]}" ]; then
            local name="${databases[$idx]}"
            if [ "${name}" != "None" ]; then
                if [ "${ODD_DOCKER_MODE}" = "true" ]; then
                    selected+=("${name}:docker")
                else
                    selected+=("${name}:native")
                fi
            fi
        fi
    done

    if [ "${#selected[@]}" -eq 0 ]; then
        log_warn "No database persistence elements flagged — skipping setup tasks"
        export ODD_DATABASES=""
    else
        ODD_DATABASES="${selected[*]}"
        export ODD_DATABASES
    fi
}

main() {
    if [ "$EUID" -ne 0 ]; then
        echo "[ERROR] Core pipeline authentication failure: This script must be run as root." >&2
        exit 1
    fi

    preflight_checks
    oddops_banner
    detect_os
    
    # Evaluate caching layers before initiating wizard routing
    if ! check_cached_session; then
        print_step "Configuration Wizard Realignment Initialization"
        prompt_for_username
        prompt_for_ssh_port
        prompt_for_domain
        prompt_for_runtimes
        prompt_for_databases
        
        # Lock snapshot immediately down to filesystem once configuration loop concludes
        save_configuration_json
    fi
    
    printf "\n"
    log_success "Configurations successfully linked into automation arrays — executing deployment loops..."
    printf "\n"

    # ==============================================================================
    # DYNAMIC MODULE EXECUTION ORCHESTRATOR
    # ==============================================================================
    print_step "Executing Modular Deployment Sequence"

    # 1. Base Machine Level Hardening
    if [ -f "${SCRIPT_DIR}/modules/security.sh" ]; then
        source "${SCRIPT_DIR}/modules/security.sh"
        create_deploy_user "${ODD_DEPLOY_USER}"
        setup_sudo_access "${ODD_DEPLOY_USER}"
        configure_firewall "${ODD_SSH_PORT}"
        harden_ssh "${ODD_SSH_PORT}"
    fi

    # 2. Ingress & Edge Proxy Setup
    if [ -n "${ODD_DOMAIN:-}" ] && [ -f "${SCRIPT_DIR}/modules/proxy.sh" ]; then
        source "${SCRIPT_DIR}/modules/proxy.sh"
        install_nginx 
    fi

    # 3. Dedicated Database Orchestration Engine Layer
    if [ -n "${ODD_DATABASES:-}" ]; then
        for db_entry in ${ODD_DATABASES}; do
            local db_name="${db_entry%%:*}"
            local db_type="${db_entry##*:}"

            if [ "${db_type}" = "docker" ]; then
                if [ -f "${SCRIPT_DIR}/modules/docker_apps.sh" ]; then
                    source "${SCRIPT_DIR}/modules/docker_apps.sh"
                    init_docker_network
                    deploy_container_postgres "${db_name,,}" "oddadmin" "supersecretpass"
                fi
            else
                if [ -f "${SCRIPT_DIR}/modules/${db_name,,}.sh" ]; then
                    source "${SCRIPT_DIR}/modules/${db_name,,}.sh"
                fi
            fi
        done
    fi

    # 4. Applications and Compilers Execution Runtimes
    if [ -n "${ODD_RUNTIME_VERSIONS:-}" ]; then
        for runtime_entry in ${ODD_RUNTIME_VERSIONS}; do
            local rt_name="${runtime_entry%%:*}"
            local rt_version="${runtime_entry##*:}"

            log_info "Processing configuration runtime target setup: ${rt_name} (Version: ${rt_version})"

            if [ "${rt_name}" = "Docker" ]; then
                if [ -f "${SCRIPT_DIR}/modules/docker.sh" ]; then
                    source "${SCRIPT_DIR}/modules/docker.sh"
                fi
            elif [ "${ODD_DOCKER_MODE}" = "false" ] || [ "${ODD_DOCKER_MODE}" = "false" ]; then
                if [ -f "${SCRIPT_DIR}/modules/${rt_name,,}.sh" ]; then
                    source "${SCRIPT_DIR}/modules/${rt_name,,}.sh"
                fi
            fi
        done
    fi

    log_success "OddOps provisioning complete! Infrastructure is secured and configured."
}

main "$@"