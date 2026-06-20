# OddOps Architecture Blueprint

## System Constraints & Rules

- **Language:** Strictly POSIX-compliant Bash/Shell (`#!/bin/bash`). No external language runtimes (Python/Go/Node) allowed for the core engine.
- **Error Handling:** Every shell script must include `set -euo pipefail` at the top. Exception: `lib/ui.sh` is a sourced library and relies on the caller to enforce this.
- **No Placeholders:** Never generate incomplete code, todo comments, or placeholder blocks. Every function must be fully implemented.
- **Multi-Distro Awareness:** All code paths must dynamically read `/etc/os-release` and route execution to the correct package manager (`apt`, `dnf`, or `pacman`).
- **Idempotency:** Every function must check if a configuration or change already exists before executing (e.g., check if a user exists before adding them, use grep/sed safely).
- **Security Standards:** Absolute minimum privileges, strict UFW/firewalld rules, non-root application execution environments.
- **Universal Runtime Support:** OddOps is designed to support ANY runtime/language stack — Go, Java, Rust, Ruby, Node.js, Python, Docker, and more — via a uniform modular interface.
- **Dynamic Upstream Versioning:** No module may hardcode specific minor or patch version numbers, static tarball URLs, or pinned release hashes. Every installer must dynamically resolve the latest stable release at runtime via official upstream APIs, version endpoints, or LTS repository streams.
- **Multi-Version Selection Matrix:** The setup wizard prompts the user to choose a specific major LTS version for each selected runtime. Each module accepts a version parameter (e.g., `install_nodejs "22"`) and resolves the latest patch within that stream.
- **Database Auto-Hardening:** Every provisioned database must be automatically secured: bind to 127.0.0.1 only, generate a cryptographically random master password, create a dedicated application user, and output credentials at the end of execution.
- **Root Execution Required:** All OddOps scripts verify `$EUID` at startup and abort if not running as root.
- **JSON Session Persistence:** The wizard saves the full configuration to `config.json` and offers to restore it on re-runs, enabling skip-the-wizard workflows.
- **Docker Compose Mode:** When Docker is selected, `ODD_DOCKER_MODE=true` triggers containerized database provisioning via `docker_apps.sh` instead of native package installs.
- **Pre-Flight Dependency Checker:** `oddops.sh` verifies core CLI tools (`curl`, `wget`, `git`, `gnupg`, `sed`, `grep`, `awk`) and auto-installs missing ones via the native package manager before any operations.

## Directory Structure Design

The agent must strictly adhere to and generate code inside this exact directory layout:

- `/oddops.sh` — Main entrypoint: pre-flight checks, OS detection, cached-session restore, interactive wizard (username, SSH port, domain, runtime+version matrix, database selection), JSON config serialization, and dynamic module orchestrator.
- `/oddops-clean.sh` — Server reset/teardown utility. Reverses all OddOps actions: purges runtime packages, databases, proxy configs, services, and firewall rules. Requires explicit "RESET" confirmation and runs as root.
- `/config.json` — Serialized session snapshot written by oddops.sh at the end of the wizard. Re-read on subsequent runs for skip-the-wizard deployments.
- `/lib/ui.sh` — Logging format utilities, terminal colors (tput with ANSI fallback), UTF-8-aware ASCII banner, progress wrappers. Sourced by every other script.
- `/lib/security.sh` — Firewalls (ufw/firewalld), SSH hardening, user creation (sudo/wheel group detection), SSH key injection (interactive or non-interactive), passwordless sudo setup.
- `/lib/proxy.sh` — Nginx installation with vhost directory scaffolding, Caddy installation via official repos, Nginx/Caddy reverse-proxy config writers, Certbot SSL provisioning.
- `/modules/` — Universal runtime module directory.
  - `/modules/docker.sh` — Upstream standalone Docker engine installer via `get.docker.com`. Enables and starts systemd service. Adds deploy user to `docker` group.
  - `/modules/docker_apps.sh` — Docker Compose container deployment engine. Creates isolated bridge networks, deploys containerized PostgreSQL, generates `docker-compose.yml` for Node.js apps.
  - `/modules/nodejs.sh` — Node.js LTS installer via NodeSource v2 GPG-keyed repos. Accepts version parameter for any active stream. Installs PM2 globally with systemd startup hook.
  - `/modules/python.sh` — Python 3 installer with optional versioned `python3.x` package fallback. Virtual environment creator, pip requirements installer, systemd unit generator (with `After=network.target`, journal logging).
  - `/modules/go.sh` — Go language tarball installer. Resolves version from `go.dev/dl/?mode=json` JSON API. Supports `amd64`, `arm64`, `armv6l` architectures. Injects PATH into `/etc/profile` and `/etc/environment`.
  - `/modules/java.sh` — OpenJDK installer with version parameter. Dynamically computes `JAVA_HOME` from `readlink -f $(which javac)` and persists to `/etc/environment`.
  - `/modules/rust.sh` — Rust toolchain installer via `rustup` (`--no-modify-path`). Installs `build-essential`/`base-devel` prerequisites first. Injects `$CARGO_HOME/bin` into `/etc/profile`.
  - `/modules/ruby.sh` — Ruby runtime installer with optional versioned package fallback. Installs `build-essential` and libyaml prerequisites for native gem compilation. Sets `gem: --no-document` globally. Bundler install with PATH extension.
  - `/modules/databases.sh` — Database & Services sub-system. Provisions and hardens PostgreSQL, MongoDB 8.0, MySQL/MariaDB, and Redis. Generates secure random passwords (openssl with urandom fallback), binds to localhost, creates app users, writes credentials to `/root/.oddops-credentials`. Includes Docker-aware orchestration mode.

## Module Contract

Every module in `/modules/` must implement the following interface:

- `install_<language>(version)` — Idempotent install of the runtime. Accepts an optional version parameter (e.g., `"22"` for Node.js, `"1.22"` for Go) to select a specific major stream.
- `verify_<language>()` — Verify the installation and output version info.
- `describe_<language>()` — Print a summary of what was configured.

The `databases.sh` module additionally exposes:

- `install_databases(db_list)` — Iterates over a space-separated list of database names and calls the corresponding `install_<db>()` + `harden_<db>()` pair for each.
- `generate_password()` — Outputs a cryptographically random 24-character alphanumeric string.
- `write_credential(service, key, value)` — Appends a credential line to `/root/.oddops-credentials`.

The `docker_apps.sh` module exposes:

- `init_docker_network([network_name])` — Creates an isolated Docker bridge network.
- `deploy_container_postgres(name, user, pass, [port], [network])` — Runs PostgreSQL 16-alpine in a Docker container with volume persistence.
- `generate_app_compose(name, dir, host_port, container_port, [node_version])` — Generates a production Docker Compose file for a Node.js app.
- `verify_docker_runtime()` — Checks Docker and Docker Compose versions.
