# OddOps Implementation Checklist

## Phase 1: Core Engine & Visuals

- [x] Task 1.1: Create `/lib/ui.sh` containing `log_info`, `log_error`, `log_success`, and a clean ASCII banner for "OddOps".
- [x] Task 1.2: Create `/oddops.sh` main entry point with OS detection via `/etc/os-release`.

## Phase 2: Interactive Input Wizard

- [x] Task 2.1: Implement choice prompt structures in `/oddops.sh` for deployment username, custom SSH port, target domain, and framework choice.
- [x] Task 2.2: Validate all user inputs (SSH port 22-65535, username POSIX pattern, FQDN domain format).
- [x] Task 2.3: Add pre-flight dependency checker (`curl`, `wget`, `git`, `gnupg`, `sed`, `grep`, `awk`) with auto-install across distros.
- [x] Task 2.4: Implement JSON session persistence — save wizard output to `config.json`, offer restore on re-run.

## Phase 3: System Security & Hardening

- [x] Task 3.1: Build `/lib/security.sh` with modular user account management (sudo/wheel detection, non-interactive SSH key injection).
- [x] Task 3.2: Implement firewall rules switching between `ufw` (Debian/Ubuntu) and `firewalld` (RHEL/Rocky), configuring rules *before* activation.
- [x] Task 3.3: Implement SSH hardening (`sshd_config`): disable root login, key-only auth, rate limiting, session timeouts, disable X11/agent forwarding. Includes `sshd -t` syntax validation before restart.

## Phase 4: Runtime Modules & Proxy

- [x] Task 4.1: Write `/modules/docker.sh` — Docker engine installer via `get.docker.com`, systemd enable, docker group injection.
- [x] Task 4.2: Write `/modules/docker_apps.sh` — Docker Compose engine: bridge network creation, containerized PostgreSQL 16-alpine, app `docker-compose.yml` generator.
- [x] Task 4.3: Write `/modules/nodejs.sh` — Node.js via NodeSource v2 GPG repos, version-aware (LTS auto-maps to 22.x), PM2 global install with systemd startup.
- [x] Task 4.4: Write `/modules/python.sh` — Python 3 installer, venv creator, pip requirements, systemd unit generator with journal logging and user validation.
- [x] Task 4.5: Write `/modules/go.sh` — Go via tarball from `go.dev/dl/?mode=json`, multi-arch support, `/etc/environment` PATH injection.
- [x] Task 4.6: Write `/modules/java.sh` — OpenJDK via package manager, dynamic `JAVA_HOME` detection via `readlink`, `/etc/environment` persistence.
- [x] Task 4.7: Write `/modules/rust.sh` — Rust via `rustup --no-modify-path`, `build-essential` prerequisite install, `$CARGO_HOME/bin` PATH injection.
- [x] Task 4.8: Write `/modules/ruby.sh` — Ruby via package manager, gem compilation prerequisite installs, `gem: --no-document` global config, Bundler with PATH extension.
- [x] Task 4.9: Build `/lib/proxy.sh` with Nginx vhost-scaffolding (creates `sites-available`/`sites-enabled`, injects include into `nginx.conf`), Caddy apt-keyring install, reverse-proxy config writers with rollback on syntax failure, Certbot SSL provisioning.

## Phase 5: Server Reset & Teardown Engine

- [x] Task 5.1: Create `/oddops-clean.sh` entry point with confirmation prompt (type "RESET"), root-user check, and wildcard-based package purging.
- [x] Task 5.2: Implement dynamic runtime/language purging — detects package manager, uses wildcard patterns (`"openjdk-*"`, `"ruby*"`) to cover any installed version, removes tarball Go, removes Rust `$CARGO_HOME`.
- [x] Task 5.3: Dynamic SSH port detection — reads actual `Port` from `/etc/ssh/sshd_config` instead of relying on environment variables, so clean.sh works standalone.

## Phase 6: Multi-Version Selection & Databases

- [x] Task 6.1: Add multi-version selection prompts to `/oddops.sh` wizard — major LTS version per selected runtime (Node 18/20/22/24/26, Java 11/17/21/25, Go 1.22–1.26, Python 3.10–3.14, Ruby 3.1–4.0).
- [x] Task 6.2: Create `/modules/databases.sh` with PostgreSQL, MongoDB 8.0, MySQL/MariaDB, and Redis installers featuring automated hardening (localhost bind, random passwords, app user creation, credential output to `/root/.oddops-credentials`).
- [x] Task 6.3: Update `/oddops-clean.sh` to purge database packages (`postgresql*`, `mysql-server`, `redis-server`, `mongodb-org*`), drop data directories (`/var/lib/postgresql`, `/var/lib/mysql`, etc.), and remove credential files.
- [x] Task 6.4: Add Docker Compose mode — when Docker is selected, `ODD_DOCKER_MODE=true` routes database provisioning through `docker_apps.sh` containerized installs instead of native packages.
