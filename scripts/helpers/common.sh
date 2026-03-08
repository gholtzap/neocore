#!/bin/bash

check_command() {
    if command -v $1 &> /dev/null; then
        gum style --foreground 42 "✓ $2 is installed"
        return 0
    else
        gum style --foreground 196 "✗ $2 is not installed"
        return 1
    fi
}

check_docker_installed() {
    if ! command -v docker &> /dev/null; then
        gum style --foreground 196 "✗ Docker is not installed"
        gum style --foreground 208 "  Install from: https://www.docker.com/get-started"
        return 1
    fi
    return 0
}

check_docker_running() {
    if ! docker info &> /dev/null; then
        gum style --foreground 196 "✗ Docker daemon is not running"
        gum style --foreground 208 "  Start Docker Desktop and try again"
        return 1
    fi
    return 0
}

get_docker_memory_gb() {
    local mem_bytes=$(docker info --format '{{.MemTotal}}' 2>/dev/null || echo "0")
    echo $((mem_bytes / 1000 / 1000 / 1000))
}

check_docker_memory() {
    local min_gb=${1:-16}
    local mem_bytes=$(docker info --format '{{.MemTotal}}' 2>/dev/null || echo "0")
    local min_bytes=$((min_gb * 1000 * 1000 * 1000))
    local mem_gb=$((mem_bytes / 1000 / 1000 / 1000))

    if [ "$mem_bytes" -lt "$min_bytes" ]; then
        gum style --foreground 196 "✗ Docker memory is too low: ${mem_gb}GB (${min_gb}GB+ required)"
        gum style --foreground 208 "  Configure Docker Desktop → Settings → Resources → Memory"
        gum style --foreground 208 "  Set memory to at least ${min_gb}GB to avoid build failures"
        return 1
    fi
    gum style --foreground 42 "✓ Docker is running with ${mem_gb}GB memory"
    return 0
}

wait_for_mongodb() {
    local max_attempts=${1:-30}
    local attempt=0

    while [ $attempt -lt $max_attempts ]; do
        local health_status=$(docker inspect --format='{{.State.Health.Status}}' mongodb 2>/dev/null || echo "")
        if [ "$health_status" = "healthy" ]; then
            gum style --foreground 42 "✓ MongoDB ready"
            return 0
        fi
        attempt=$((attempt + 1))
        sleep 1
    done

    gum style --foreground 196 "✗ MongoDB failed to become ready after ${max_attempts}s"
    gum style --foreground 208 "Recovery suggestions:"
    gum style --foreground 208 "  1. Check logs: docker compose logs mongodb"
    gum style --foreground 208 "  2. Restart MongoDB: docker compose restart mongodb"
    gum style --foreground 208 "  3. Clean volumes: docker compose down -v"
    return 1
}

print_build_failure() {
    local service=${1:-""}
    gum style --foreground 196 "✗ Docker build failed${service:+ for $service}"
    gum style --foreground 208 "Recovery suggestions:"
    gum style --foreground 208 "  1. Check Docker resources (CPU/Memory/Disk)"
    gum style --foreground 208 "  2. Try: docker compose build --no-cache${service:+ $service}"
    gum style --foreground 208 "  3. Clean old images: docker system prune"
}

print_start_failure() {
    local foreground=${1:-false}
    gum style --foreground 196 "✗ Services failed to start"
    gum style --foreground 208 "Recovery suggestions:"
    if [ "$foreground" = true ]; then
        gum style --foreground 208 "  1. Check logs above for specific errors"
    else
        gum style --foreground 208 "  1. Check logs: docker compose logs"
    fi
    gum style --foreground 208 "  2. Check service health: docker compose ps"
    gum style --foreground 208 "  3. Try: docker compose down && ./scripts/start.sh"
}
