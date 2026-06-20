#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/ui.sh"

init_docker_network() {
    local network_name="${1:-oddops-network}"

    if ! command -v docker &>/dev/null; then
        log_error "Docker engine is missing from the host machine — cannot configure containers"
        return 1
    fi

    if docker network inspect "${network_name}" &>/dev/null; then
        log_warn "Docker network space '${network_name}' already active — skipping creation"
        return 0
    fi

    log_info "Initializing isolated Docker proxy bridge bridge: ${network_name}..."
    docker network create "${network_name}"
    log_success "Network isolation mesh operational"
}

deploy_container_postgres() {
    local db_name="$1"
    local db_user="$2"
    local db_pass="$3"
    local db_port="${4:-5432}"
    local network_name="${5:-oddops-network}"

    if docker ps -a --format '{{.Names}}' | grep -q "^${db_name}$"; then
        log_warn "Database container instance '${db_name}' already exists — skipping setup"
        return 0
    fi

    log_info "Spooling up containerized PostgreSQL database layer (${db_name}) on port ${db_port}..."
    
    docker run -d \
        --name "${db_name}" \
        --network "${network_name}" \
        -p "${db_port}:5432" \
        -e POSTGRES_DB="${db_name}" \
        -e POSTGRES_USER="${db_user}" \
        -e POSTGRES_PASSWORD="${db_pass}" \
        -v "${db_name}_data:/var/lib/postgresql/data" \
        --restart always \
        postgres:16-alpine

    log_success "PostgreSQL container listening securely on host port ${db_port}"
}

generate_app_compose() {
    local app_name="$1"
    local app_dir="$2"
    local host_port="$3"
    local container_port="$4"
    local node_version="${5:-22-alpine}"

    local compose_file="${app_dir}/docker-compose.yml"

    if [ -f "${compose_file}" ]; then
        log_warn "Docker Compose manifest already exists at ${compose_file} — skipping"
        return 0
    fi

    log_info "Generating localized production Docker Compose blueprint for '${app_name}'..."
    mkdir -p "${app_dir}"

    cat > "${compose_file}" <<EOF
version: '3.8'

services:
  app:
    container_name: ${app_name}-service
    image: node:${node_version}
    working_dir: /usr/src/app
    volumes:
      - .:/usr/src/app
      - /usr/src/app/node_modules
    ports:
      - "${host_port}:${container_port}"
    environment:
      - NODE_ENV=production
      - PORT=${container_port}
    command: sh -c "npm install && npm run build && npm start"
    restart: always
    networks:
      - oddops-network

networks:
  oddops-network:
    external: true
EOF

    log_success "Docker Compose infrastructure definition compiled at ${compose_file}"
}

verify_docker_runtime() {
    if ! command -v docker &>/dev/null; then
        log_error "Docker platform binary targets are missing"
        return 1
    fi

    log_info "Docker Engine Core: $(docker --version)"
    if command -v docker-compose &>/dev/null; then
        log_info "Docker Compose v1 Layer: $(docker-compose --version)"
    elif docker compose version &>/dev/null; then
        log_info "Docker Compose v2 Plugin: $(docker compose version)"
    fi
}