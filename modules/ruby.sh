#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/ui.sh"

install_ruby() {
    local ruby_version="${1:-}"

    if command -v ruby &>/dev/null; then
        log_warn "Ruby runtime environment already active — skipping"
        return 0
    fi

    log_info "Installing Ruby interpreter and development dependencies..."

    if command -v apt &>/dev/null; then
        apt-get update -qq
        # Install compiler chains to prevent native gem extension compilation crashes
        apt-get install -y build-essential zlib1g-dev libssl-dev libreadline-dev libyaml-dev
        
        if [ -n "${ruby_version}" ]; then
            apt-get install -y "ruby${ruby_version}" "ruby${ruby_version}-dev" 2>/dev/null || \
            apt-get install -y ruby ruby-dev
        else
            apt-get install -y ruby ruby-dev
        fi
    elif command -v dnf &>/dev/null; then
        dnf groupinstall -y "Development Tools"
        dnf install -y ruby ruby-devel libyaml-devel
    elif command -v pacman &>/dev/null; then
        pacman -S --noconfirm ruby base-devel
    else
        log_error "No architecture package alignments identified for Ruby setups"
        return 1
    fi

    # Disable documentation generation globally to significantly accelerate gem installations
    if [ ! -f /etc/gemrc ]; then
        printf "gem: --no-document\n" > /etc/gemrc
    fi

    log_success "Ruby language stack installed successfully: $(ruby --version 2>/dev/null | head -n1)"
}

install_ruby_bundler() {
    if command -v bundle &>/dev/null; then
        log_warn "Bundler execution path already registered — skipping"
        return 0
    fi

    log_info "Provisioning global system Bundler module..."
    
    # --no-document prevents slow manual installations
    gem install bundler --no-document
    
    # Force system execution path reconfiguration check
    local gem_bin
    gem_bin=$(ruby -e 'print Gem.user_dir' 2>/dev/null || echo "")
    if [ -n "${gem_bin}" ] && [ -d "${gem_bin}/bin" ] && ! echo "${PATH}" | grep -q "${gem_bin}/bin"; then
        export PATH="${PATH}:${gem_bin}/bin"
    fi

    log_success "Bundler configuration completed"
}

verify_ruby() {
    if ! command -v ruby &>/dev/null; then
        log_error "Ruby binaries missing from active system session context profiles"
        return 1
    fi

    log_info "Ruby Core: $(ruby --version 2>/dev/null | head -n1)"

    if command -v gem &>/dev/null; then
        log_info "RubyGems Engine: v$(gem --version 2>/dev/null)"
    fi

    if command -v bundle &>/dev/null; then
        log_info "Bundler Manager: v$(bundle --version 2>/dev/null | head -n1 | awk '{print $3}')"
    fi
}

describe_ruby() {
    printf "\n  Ruby Production Environments:\n"
    if command -v ruby &>/dev/null; then
        printf "    Ruby Engine: operational (%s)\n" "$(ruby --version 2>/dev/null | head -n1 | awk '{print $2}')"
        command -v bundle &>/dev/null && printf "    Bundler Subsystem: active\n"
    else
        printf "    Ruby Engine: uninstalled\n"
    fi
}