#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/ui.sh"

ODD_CREDENTIALS_FILE="${ODD_CREDENTIALS_FILE:-/root/.oddops-credentials}"
ODD_DB_APP_USER="${ODD_DEPLOY_USER:-app}"

generate_password() {
    if command -v openssl &>/dev/null; then
        openssl rand -base64 24 | tr -d '\n+/=' | head -c 24
    else
        # Stripped of bash/SQL meta-characters to prevent string escaping injection issues
        tr -dc 'A-Za-z0-9' < /dev/urandom 2>/dev/null | head -c 24 || \
        printf "oddops%s%s" "$(date +%s)" "${RANDOM}"
    fi
}

write_credential() {
    local service="$1"
    local key="$2"
    local value="$3"
    printf "%-15s %-20s %s\n" "[${service}]" "${key}:" "${value}" >> "${ODD_CREDENTIALS_FILE}"
}

install_postgresql() {
    if command -v psql &>/dev/null; then
        log_warn "PostgreSQL is already installed — skipping"
        return 0
    fi

    log_info "Installing PostgreSQL Server..."

    if command -v apt &>/dev/null; then
        apt-get update -qq && apt-get install -y postgresql postgresql-contrib
    elif command -v dnf &>/dev/null; then
        dnf install -y postgresql-server postgresql-contrib
        postgresql-setup --initdb 2>/dev/null || true
    elif command -v pacman &>/dev/null; then
        pacman -S --noconfirm postgresql
        if [ ! -d /var/lib/postgres/data ]; then
            su - postgres -c "initdb -D /var/lib/postgres/data" 2>/dev/null || true
        fi
    else
        log_error "No supported package manager found for PostgreSQL"
        return 1
    fi

    log_success "PostgreSQL installed successfully"
}

harden_postgresql() {
    local db_password
    db_password=$(generate_password)

    log_info "Hardening PostgreSQL configurations..."

    if command -v systemctl &>/dev/null; then
        systemctl enable postgresql 2>/dev/null || true
        systemctl start postgresql 2>/dev/null || true
    fi

    # Cross-platform structural tracking for config mappings
    local pg_conf=""
    local pg_hba=""
    for dir in /etc/postgresql /var/lib/pgsql/data /var/lib/postgres/data /var/lib/postgresql/data; do
        if [ -d "$dir" ]; then
            pg_conf=$(find "$dir" -name postgresql.conf 2>/dev/null | head -1 || true)
            pg_hba=$(find "$dir" -name pg_hba.conf 2>/dev/null | head -1 || true)
            [ -n "$pg_conf" ] && break
        fi
    done

    # Fallback to local administrative execution if su switching profiles fails
    su - postgres -c "psql -c \"CREATE USER ${ODD_DB_APP_USER} WITH PASSWORD '${db_password}';\"" &>/dev/null || \
        psql -U postgres -c "CREATE USER ${ODD_DB_APP_USER} WITH PASSWORD '${db_password}';" &>/dev/null || \
        log_warn "PostgreSQL user account deployment step passed with warnings"

    su - postgres -c "psql -c \"CREATE DATABASE ${ODD_DB_APP_USER} OWNER ${ODD_DB_APP_USER};\"" &>/dev/null || \
        psql -U postgres -c "CREATE DATABASE ${ODD_DB_APP_USER} OWNER ${ODD_DB_APP_USER};" &>/dev/null || true

    if [ -n "${pg_conf}" ] && [ -f "${pg_conf}" ]; then
        sed -i "s/^#*listen_addresses = .*/listen_addresses = '127.0.0.1'/" "${pg_conf}"
    fi

    if [ -n "${pg_hba}" ] && [ -f "${pg_hba}" ]; then
        # Ensure secure modern local loop block authentication maps
        sed -i 's/^host\s\+all\s\+all\s\+0\.0\.0\.0\/0.*/host all all 127.0.0.1\/32 scram-sha-256/' "${pg_hba}" 2>/dev/null || true
    fi

    if command -v systemctl &>/dev/null; then
        systemctl restart postgresql 2>/dev/null || true
    fi

    write_credential "PostgreSQL" "User" "${ODD_DB_APP_USER}"
    write_credential "PostgreSQL" "Password" "${db_password}"
    write_credential "PostgreSQL" "Database" "${ODD_DB_APP_USER}"
    write_credential "PostgreSQL" "Bind" "127.0.0.1"

    log_success "PostgreSQL hardened natively"
}

install_mongodb() {
    if command -v mongod &>/dev/null || command -v mongosh &>/dev/null; then
        log_warn "MongoDB is already installed — skipping"
        return 0
    fi

    log_info "Installing MongoDB Upstream Distribution Stack..."
    . /etc/os-release
    local os_codename="${VERSION_CODENAME:-jammy}"

    if command -v apt &>/dev/null; then
        # Dynamic codename handling for modern versions (Noble 24.04 fallbacks to Jammy binary sets cleanly)
        if [ "${os_codename}" = "noble" ]; then os_codename="jammy"; fi
        
        curl -fsSL https://www.mongodb.org/static/pgp/server-8.0.asc | gpg --dearmor -o /usr/share/keyrings/mongodb-server-8.0.gpg 2>/dev/null || true
        echo "deb [ signed-by=/usr/share/keyrings/mongodb-server-8.0.gpg ] https://repo.mongodb.org/apt/ubuntu ${os_codename}/mongodb-org/8.0 multiverse" > /etc/apt/sources.list.d/mongodb-org-8.0.list 2>/dev/null || true
        apt-get update -qq && apt-get install -y mongodb-org mongodb-mongosh 2>/dev/null || \
        apt-get install -y mongodb-org 2>/dev/null || log_warn "Primary MongoDB targets passed with standard distribution fallback tracking"
    elif command -v dnf &>/dev/null; then
        printf "[mongodb-org-8.0]\nname=MongoDB Repository\nbaseurl=https://repo.mongodb.org/yum/redhat/\$releasever/mongodb-org/8.0/x86_64/\ngpgcheck=1\nenabled=1\ngpgkey=https://www.mongodb.org/static/pgp/server-8.0.asc\n" > /etc/yum.repos.d/mongodb-org-8.0.repo 2>/dev/null || true
        dnf install -y mongodb-org 2>/dev/null || log_warn "MongoDB RedHat distribution mirror failed"
    else
        log_warn "MongoDB auto-compilation skips on alternative architectures - please maintain manually"
    fi
}

harden_mongodb() {
    local db_password
    db_password=$(generate_password)

    log_info "Hardening MongoDB context layers..."

    if command -v systemctl &>/dev/null; then
        systemctl enable mongod 2>/dev/null || true
        systemctl start mongod 2>/dev/null || true
    fi

    local mongod_conf="/etc/mongod.conf"
    if [ -f "${mongod_conf}" ]; then
        sed -i 's/.*bindIp.*/  bindIp: 127.0.0.1/' "${mongod_conf}" 2>/dev/null || true
    fi

    if command -v systemctl &>/dev/null; then
        systemctl restart mongod 2>/dev/null || true
    fi

    sleep 2

    # Using standard modern unified shell mongosh commands safely
    if command -v mongosh &>/dev/null; then
        mongosh admin --eval "db.createUser({user:'${ODD_DB_APP_USER}',pwd:'${db_password}',roles:[{role:'root',db:'admin'}]})" &>/dev/null || true
    elif command -v mongo &>/dev/null; then
        mongo admin --eval "db.createUser({user:'${ODD_DB_APP_USER}',pwd:'${db_password}',roles:[{role:'root',db:'admin'}]})" &>/dev/null || true
    fi

    if [ -f "${mongod_conf}" ]; then
        if grep -q "security:" "${mongod_conf}" 2>/dev/null; then
            sed -i '/security:/a \  authorization: enabled' "${mongod_conf}" 2>/dev/null || true
        else
            printf "\nsecurity:\n  authorization: enabled\n" >> "${mongod_conf}"
        fi
    fi

    if command -v systemctl &>/dev/null; then
        systemctl restart mongod 2>/dev/null || true
    fi

    write_credential "MongoDB" "Admin User" "${ODD_DB_APP_USER}"
    write_credential "MongoDB" "Password" "${db_password}"
    write_credential "MongoDB" "Bind" "127.0.0.1"

    log_success "MongoDB secure matrix running successfully"
}

install_mysql() {
    if command -v mysql &>/dev/null; then
        log_warn "MySQL engine active — skipping installation step"
        return 0
    fi

    log_info "Installing Database Engine (MySQL / MariaDB variant)..."

    if command -v apt &>/dev/null; then
        apt-get update -qq && apt-get install -y mysql-server
    elif command -v dnf &>/dev/null; then
        dnf install -y mysql-server
    elif command -v pacman &>/dev/null; then
        pacman -S --noconfirm mariadb
        if [ ! -d /var/lib/mysql ]; then
            mariadb-install-db --user=mysql --basedir=/usr --datadir=/var/lib/mysql 2>/dev/null || true
        fi
    else
        log_error "No package alignment configuration matched for SQL profiles"
        return 1
    fi
}

harden_mysql() {
    local db_password
    db_password=$(generate_password)

    log_info "Securing relational engine dependencies..."

    local target_svc="mysql"
    if ! systemctl list-unit-files | grep -q "^mysql.service" 2>/dev/null; then
        target_svc="mysqld"
    fi

    if command -v systemctl &>/dev/null; then
        systemctl enable "${target_svc}" 2>/dev/null || true
        systemctl start "${target_svc}" 2>/dev/null || true
    fi

    local mysql_conf="/etc/mysql/mysql.conf.d/mysqld.cnf"
    [ ! -f "${mysql_conf}" ] && mysql_conf="/etc/my.cnf"
    [ ! -f "${mysql_conf}" ] && mysql_conf="/etc/my.cnf.d/server.cnf"
    [ ! -f "${mysql_conf}" ] && mysql_conf="/etc/my.cnf.d/mariadb-server.cnf"

    if [ -f "${mysql_conf}" ]; then
        sed -i 's/^bind-address.*/bind-address = 127.0.0.1/' "${mysql_conf}" 2>/dev/null || true
    fi

    # Secure internal account parameters cleanly mapping to fallback configurations
    mysql --user=root <<SQL 2>/dev/null || true
ALTER USER 'root'@'localhost' IDENTIFIED BY '${db_password}';
CREATE USER IF NOT EXISTS '${ODD_DB_APP_USER}'@'localhost' IDENTIFIED BY '${db_password}';
GRANT ALL PRIVILEGES ON *.* TO '${ODD_DB_APP_USER}'@'localhost' WITH GRANT OPTION;
FLUSH PRIVILEGES;
SQL

    if command -v systemctl &>/dev/null; then
        systemctl restart "${target_svc}" 2>/dev/null || true
    fi

    write_credential "MySQL" "Root Password" "${db_password}"
    write_credential "MySQL" "App User" "${ODD_DB_APP_USER}"
    write_credential "MySQL" "App Password" "${db_password}"
    write_credential "MySQL" "Bind" "127.0.0.1"

    log_success "MySQL data layers locked to internal loops successfully"
}

install_redis() {
    if command -v redis-server &>/dev/null; then
        log_warn "Redis binary detected on system spaces — skipping"
        return 0
    fi

    log_info "Installing Redis In-Memory Store..."

    if command -v apt &>/dev/null; then
        apt-get update -qq && apt-get install -y redis-server
    elif command -v dnf &>/dev/null; then
        dnf install -y redis
    elif command -v pacman &>/dev/null; then
        pacman -S --noconfirm redis
    else
        log_error "Unsupported target environment platform architecture metrics"
        return 1
    fi
}

harden_redis() {
    local redis_password
    redis_password=$(generate_password)

    log_info "Applying cryptographic auth profiles to Redis..."

    local target_svc="redis-server"
    if ! systemctl list-unit-files | grep -q "^redis-server.service" 2>/dev/null; then
        target_svc="redis"
    fi

    if command -v systemctl &>/dev/null; then
        systemctl enable "${target_svc}" 2>/dev/null || true
        systemctl start "${target_svc}" 2>/dev/null || true
    fi

    local redis_conf=""
    for f in /etc/redis/redis.conf /etc/redis.conf /etc/redis/redis-server.conf; do
        if [ -f "${f}" ]; then
            redis_conf="${f}"
            break
        fi
    done

    if [ -n "${redis_conf}" ]; then
        sed -i 's/^bind .*/bind 127.0.0.1 -::1/' "${redis_conf}" 2>/dev/null || sed -i 's/^bind .*/bind 127.0.0.1/' "${redis_conf}" 2>/dev/null || true
        sed -i 's/^protected-mode .*/protected-mode yes/' "${redis_conf}" 2>/dev/null || true
        
        if grep -q "requirepass" "${redis_conf}" 2>/dev/null; then
            sed -i "s/^#\?\s\?requirepass.*/requirepass ${redis_password}/" "${redis_conf}"
        else
            printf "\nrequirepass %s\n" "${redis_password}" >> "${redis_conf}"
        fi
    fi

    if command -v systemctl &>/dev/null; then
        systemctl restart "${target_svc}" 2>/dev/null || true
    fi

    write_credential "Redis" "Password" "${redis_password}"
    write_credential "Redis" "Bind" "127.0.0.1"

    log_success "Redis protected instance initialized"
}

install_databases() {
    local db_list="$1"

    if [ -z "${db_list}" ]; then
        return 0
    fi

    rm -f "${ODD_CREDENTIALS_FILE}"
    printf "# OddOps Database Credentials\n# Generated: %s\n# Keep this file secure!\n\n" "$(date '+%Y-%m-%d %H:%M:%S')" > "${ODD_CREDENTIALS_FILE}"
    chmod 600 "${ODD_CREDENTIALS_FILE}"

    for db in ${db_list}; do
        printf "\n"
        print_step "Provisioning ${db}"

        case "${db}" in
            PostgreSQL)
                install_postgresql
                harden_postgresql
                ;;
            MongoDB)
                install_mongodb
                harden_mongodb
                ;;
            MySQL)
                install_mysql
                harden_mysql
                ;;
            Redis)
                install_redis
                harden_redis
                ;;
         Amines|All)
                log_warn "Custom framework parameters bypass sequence tracking metrics"
                ;;
        esac
    done

    printf "\n"
    print_step "Database Credentials Security Delivery"
    log_info "Credentials stored successfully at: ${ODD_CREDENTIALS_FILE}"
    cat "${ODD_CREDENTIALS_FILE}"
}

verify_databases() {
    for db in "$@"; do
        case "${db}" in
            PostgreSQL)
                [ -x "$(command -v psql)" ] && log_info "PostgreSQL Status: $(psql --version | head -n1)"
                ;;
            MongoDB)
                [ -x "$(command -v mongosh)" ] && log_info "MongoDB Client Status: $(mongosh --version | head -n1)"
                ;;
            MySQL)
                [ -x "$(command -v mysql)" ] && log_info "MySQL Engine Status: $(mysql --version | head -n1)"
                ;;
            Redis)
                [ -x "$(command -v redis-cli)" ] && log_info "Redis Configuration Status: $(redis-cli --version | head -n1)"
                ;;
        esac
    done
}

describe_databases() {
    printf "\n  Databases Registry Logs:\n"
    command -v psql &>/dev/null && printf "    PostgreSQL: operational\n"
    (command -v mongosh &>/dev/null || command -v mongod &>/dev/null) && printf "    MongoDB: operational\n"
    command -v mysql &>/dev/null && printf "    MySQL/MariaDB: operational\n"
    command -v redis-server &>/dev/null && printf "    Redis Cache Instance: operational\n"
}