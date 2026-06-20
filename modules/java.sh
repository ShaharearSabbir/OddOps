#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/ui.sh"

install_java() {
    local java_version="${1:-21}"

    if command -v java &>/dev/null; then
        log_warn "Java runtime configuration already available — skipping"
        return 0
    fi

    log_info "Provisioning OpenJDK development stack version ${java_version}..."

    if command -v apt &>/dev/null; then
        apt-get update -qq
        # Handle structural dependencies cleanly
        apt-get install -y "openjdk-${java_version}-jdk" "openjdk-${java_version}-jre-headless" || \
        apt-get install -y "openjdk-${java_version}-jdk"
    elif command -v dnf &>/dev/null; then
        dnf install -y "java-${java_version}-openjdk-devel"
    elif command -v pacman &>/dev/null; then
        pacman -S --noconfirm "jdk${java_version}-openjdk"
    else
        log_error "Unsupported target environment platform architecture metrics"
        return 1
    fi

    # Dynamically extract and establish systemic JAVA_HOME environment routes
    log_info "Configuring global environment variables and system home trees..."
    local calculated_java_home=""
    
    if command -v javac &>/dev/null; then
        calculated_java_home=$(readlink -f "$(command -v javac)" | sed "s|/bin/javac||")
    elif command -v java &>/dev/null; then
        calculated_java_home=$(readlink -f "$(command -v java)" | sed "s|/bin/java||" | sed "s|/jre||")
    fi

    if [ -n "${calculated_java_home}" ] && [ -d "${calculated_java_home}" ]; then
        # Inject persistency profiles across system spaces
        if [ -f /etc/environment ] && ! grep -q "JAVA_HOME" /etc/environment; then
            printf '\nJAVA_HOME="%s"\n' "${calculated_java_home}" >> /etc/environment
        fi
        export JAVA_HOME="${calculated_java_home}"
        log_success "Environment variable set: JAVA_HOME=${calculated_java_home}"
    fi

    log_success "OpenJDK ${java_version} pipeline layers installed successfully"
}

verify_java() {
    if ! command -v java &>/dev/null; then
        log_error "Java binaries missing from active system session context profiles"
        return 1
    fi

    local v_tag
    v_tag=$(java -version 2>&1 | awk -F '"' '/version/ {print $2}' || java --version 2>/dev/null | head -n1)
    log_info "Active Instance Version: ${v_tag}"
    
    if command -v javac &>/dev/null; then
        log_info "Compiler Workspace Link: $(javac --version 2>/dev/null)"
    fi
}

describe_java() {
    printf "\n  Java Virtual Machine Profiles:\n"
    if command -v java &>/dev/null; then
        local raw_v
        raw_v=$(java -version 2>&1 | awk -F '"' '/version/ {print $2}' | awk -F '.' '{print $1}' || echo "Operational")
        # Handle newer version string formats (e.g. 17 instead of 1.7) cleanly
        [ "${raw_v}" = "1" ] && raw_v=$(java -version 2>&1 | awk -F '"' '/version/ {print $2}' | awk -F '.' '{print $2}')
        printf "    OpenJDK Runtime: operational\n"
        printf "    Core Release Version: %s\n" "${raw_v}"
    else
        printf "    OpenJDK Runtime: uninstalled\n"
    fi
}