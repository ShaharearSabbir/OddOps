#!/bin/bash
# High-portability CLI interface utility kit for the OddOps engine framework

# Ensure variables are initialized cleanly as empty fallback targets
RED="" GREEN="" YELLOW="" BLUE="" CYAN="" BOLD="" RESET=""

# Intelligently negotiate terminal capabilities even through pipes or logging targets
if [ -t 1 ] || [ -n "${TERM:-}" ] && [ "${TERM}" != "dumb" ]; then
    if command -v tput >/dev/null 2>&1; then
        # terminfo lookup wrappers with safe error handling drops
        RED=$(tput setaf 1 2>/dev/null || true)
        GREEN=$(tput setaf 2 2>/dev/null || true)
        YELLOW=$(tput setaf 3 2>/dev/null || true)
        BLUE=$(tput setaf 4 2>/dev/null || true)
        CYAN=$(tput setaf 6 2>/dev/null || true)
        BOLD=$(tput bold 2>/dev/null || true)
        RESET=$(tput sgr0 2>/dev/null || true)
    else
        # Reliable fallback ANSI scape sequence maps if tput binary is stripped
        RED=$'\e[31m'
        GREEN=$'\e[32m'
        YELLOW=$'\e[33m'
        BLUE=$'\e[34m'
        CYAN=$'\e[36m'
        BOLD=$'\e[1m'
        RESET=$'\e[0m'
    fi
fi

log_info() {
    printf "%s%s %s%s\n" "${BLUE}${BOLD}" "[INFO]" "${RESET}" "$*"
}

log_success() {
    printf "%s%s %s%s\n" "${GREEN}${BOLD}" "[ OK ]" "${RESET}" "$*"
}

log_warn() {
    printf "%s%s %s%s\n" "${YELLOW}${BOLD}" "[WARN]" "${RESET}" "$*"
}

log_error() {
    # Ensure standard error output target streams are prioritized consistently
    printf "%s%s %s%s\n" "${RED}${BOLD}" "[ERR ]" "${RESET}" "$*" >&2
}

oddops_banner() {
    # Detect active locale configuration to safely handle character arrays
    local active_lang
    active_lang=$(env | grep -E '^(LANG|LC_ALL)=' | head -n1 || echo "")
    
    printf "\n"
    if echo "${active_lang}" | grep -qi "utf"; then
        # Crisp modern box frames for valid unicode configuration states
        printf "  %s╔══════════════════════════════════════════════╗%s\n" "${CYAN}${BOLD}" "${RESET}"
        printf "  %s║               OddOps v1.0                    ║%s\n" "${CYAN}${BOLD}" "${RESET}"
        printf "  %s║     Universal VPS Bootstrapping CLI          ║%s\n" "${CYAN}${BOLD}" "${RESET}"
        printf "  %s╚══════════════════════════════════════════════╝%s\n" "${CYAN}${BOLD}" "${RESET}"
    else
        # Clean ASCII alternate structure arrays to prevent unreadable text strings
        printf "  %s+----------------------------------------------+%s\n" "${CYAN}${BOLD}" "${RESET}"
        printf "  %s|               OddOps v1.0                    |%s\n" "${CYAN}${BOLD}" "${RESET}"
        printf "  %s|     Universal VPS Bootstrapping CLI          |%s\n" "${CYAN}${BOLD}" "${RESET}"
        printf "  %s+----------------------------------------------+%s\n" "${CYAN}${BOLD}" "${RESET}"
    fi
    printf "\n"
}

print_step() {
    printf "\n%s>>> %s%s\n" "${CYAN}${BOLD}" "$*" "${RESET}"
}