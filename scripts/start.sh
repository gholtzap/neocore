#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/helpers/common.sh"

gum style \
	--foreground 212 --border-foreground 212 --border double \
	--align center --width 50 --margin "1 2" --padding "2 4" \
	'5G CORE' 'Interactive Test Script'

preflight_checks() {
    gum style --foreground 86 --bold "Pre-flight validation..."
    echo ""

    check_docker_installed || exit 1
    check_docker_running || exit 1
    check_docker_memory 16 || exit 1
    echo ""
}

show_menu() {
    choice=$(gum choose --header "Select test mode:" \
        "Quick Start" \
        "Full Rebuild" \
        "Update & Build" \
        "Clean Start" \
        "Custom" \
        "Update Submodules" \
        "Rebuild Web UI" \
        "Publish Images" \
        "Exit")
}

do_quick_start() {
    gum style --foreground 86 --bold "Quick Start Mode"
    echo ""

    check_mongodb
    start_services
}

do_full_rebuild() {
    gum style --foreground 86 --bold "Full Rebuild Mode"
    echo ""

    update_submodules
    commit_push
    rebuild_all_no_cache
    check_mongodb
    start_services
}

do_update_build() {
    gum style --foreground 86 --bold "Update & Build Mode"
    echo ""

    update_submodules
    commit_push

    changed_services=($(detect_changed_submodules))

    if [ ${#changed_services[@]} -gt 0 ]; then
        gum style --foreground 220 "Building updated services with --no-cache: ${changed_services[*]}"
        for service in "${changed_services[@]}"; do
            if ! docker compose build --no-cache "$service"; then
                print_build_failure "$service"
                exit 1
            fi
        done
        gum style --foreground 42 "✓ Updated services rebuilt"
        echo ""
    else
        gum style --foreground 244 "No submodule changes detected"
        echo ""
    fi

    gum style --foreground 220 "Building remaining services..."
    if ! docker compose build; then
        print_build_failure
        exit 1
    fi
    gum style --foreground 42 "✓ Build complete"
    echo ""

    check_mongodb
    start_services
}

do_clean_start() {
    gum style --foreground 86 --bold "Clean Start Mode"
    echo ""

    gum style --foreground 220 "Stopping and removing containers/volumes..."
    docker compose down -v
    gum style --foreground 42 "✓ Containers and volumes removed"
    echo ""

    if gum confirm "Update submodules?"; then
        update_submodules
        commit_push
    fi

    if gum confirm "Rebuild with --no-cache?"; then
        gum style --foreground 220 "Building all services with --no-cache..."
        if ! docker compose build --no-cache; then
            print_build_failure
            exit 1
        fi
    else
        gum style --foreground 220 "Building all services..."
        if ! docker compose build; then
            print_build_failure
            exit 1
        fi
    fi
    gum style --foreground 42 "✓ Build complete"
    echo ""

    check_mongodb
    start_services
}

do_custom() {
    gum style --foreground 86 --bold "Custom Configuration"
    echo ""

    if gum confirm "Update git submodules?"; then
        update_submodules

        if gum confirm "Commit and push changes?"; then
            commit_push
        fi
    fi

    if gum confirm "Stop existing containers?"; then
        if gum confirm "Clean volumes too?"; then
            gum style --foreground 220 "Stopping containers and removing volumes..."
            docker compose down -v
        else
            gum style --foreground 220 "Stopping containers..."
            docker compose down
        fi
        gum style --foreground 42 "✓ Containers stopped"
        echo ""
    fi

    if gum confirm "Rebuild Docker images?"; then
        if gum confirm "Rebuild other services?"; then
            if gum confirm "Use --no-cache for all?"; then
                gum style --foreground 220 "Building all services with --no-cache..."
                if ! docker compose build --no-cache; then
                    print_build_failure
                    exit 1
                fi
            else
                gum style --foreground 220 "Building all services..."
                if ! docker compose build; then
                    print_build_failure
                    exit 1
                fi
            fi
            gum style --foreground 42 "✓ Build complete"
            echo ""
        fi
    fi

    check_mongodb
    start_services
}

do_update_submodules() {
    gum style --foreground 86 --bold "Update Submodules Mode"
    echo ""

    update_submodules
    commit_push
}

do_publish_images() {
    gum style --foreground 86 --bold "Publish Docker Images to GHCR"
    echo ""

    REGISTRY="ghcr.io"
    REPO="gholtzap/5g-core"
    SERVICES=(amf ausf nrf nssf udm smf upf scp sepp smsf web-ui ueransim)

    if ! command -v docker &> /dev/null; then
        gum style --foreground 196 "Docker is not installed"
        exit 1
    fi

    gum style --foreground 220 "Logging in to $REGISTRY..."
    if ! echo "${GHCR_TOKEN}" | docker login "$REGISTRY" -u "${GHCR_USER:-gholtzap}" --password-stdin 2>/dev/null; then
        gum style --foreground 208 "Auto-login failed. Trying interactive login..."
        if ! docker login "$REGISTRY"; then
            gum style --foreground 196 "Login failed. Set GHCR_TOKEN and GHCR_USER env vars, or run: docker login ghcr.io"
            exit 1
        fi
    fi
    gum style --foreground 42 "Logged in to $REGISTRY"
    echo ""

    TAG=$(git rev-parse --short HEAD 2>/dev/null || echo "latest")

    if gum confirm "Build all images before pushing?"; then
        gum style --foreground 220 "Building all services..."
        if ! docker compose build --no-cache; then
            print_build_failure
            exit 1
        fi
        gum style --foreground 42 "Build complete"
        echo ""
    fi

    failed=()
    for service in "${SERVICES[@]}"; do
        local_image="5g-core-${service}"
        remote_image="${REGISTRY}/${REPO}-${service}"

        gum style --foreground 220 "Publishing ${service}..."

        if ! docker image inspect "${local_image}" &>/dev/null; then
            if ! docker image inspect "${service}" &>/dev/null; then
                gum style --foreground 208 "  No local image found for ${service}, skipping"
                failed+=("$service")
                continue
            fi
            local_image="${service}"
        fi

        docker tag "${local_image}" "${remote_image}:${TAG}"
        docker tag "${local_image}" "${remote_image}:latest"

        if docker push "${remote_image}:${TAG}" && docker push "${remote_image}:latest"; then
            gum style --foreground 42 "  ${service} pushed (${TAG} + latest)"
        else
            gum style --foreground 196 "  ${service} push failed"
            failed+=("$service")
        fi
    done

    echo ""
    if [ ${#failed[@]} -eq 0 ]; then
        gum style --foreground 42 --bold "All images published to ${REGISTRY}/${REPO}-*"
    else
        gum style --foreground 208 "Published with failures: ${failed[*]}"
    fi
    gum style --foreground 244 "Tag: ${TAG}"
    echo ""
}

do_rebuild_webui() {
    gum style --foreground 86 --bold "Rebuild Web UI"
    echo ""

    gum style --foreground 220 "Stopping web-ui..."
    docker compose stop web-ui
    gum style --foreground 42 "✓ Web UI stopped"
    echo ""

    gum style --foreground 220 "Rebuilding web-ui with --no-cache..."
    if ! docker compose build --no-cache web-ui; then
        gum style --foreground 196 "✗ Web UI build failed"
        gum style --foreground 208 "Recovery suggestions:"
        gum style --foreground 208 "  1. Check Node.js dependencies in web-ui/"
        gum style --foreground 208 "  2. Clean old images: docker system prune"
        gum style --foreground 208 "  3. Check Docker resources"
        exit 1
    fi
    gum style --foreground 42 "✓ Web UI rebuilt"
    echo ""

    gum style --foreground 220 "Starting web-ui..."
    if ! docker compose up -d web-ui; then
        gum style --foreground 196 "✗ Web UI failed to start"
        gum style --foreground 208 "Check logs: docker compose logs web-ui"
        exit 1
    fi
    gum style --foreground 42 "✓ Web UI started"
    echo ""

    gum style --foreground 86 --bold "Web Dashboard:"
    gum style --foreground 255 "  http://localhost:3001"
    echo ""
}

update_submodules() {
    gum style --foreground 220 "Updating git submodules..."
    git submodule status > /tmp/submodules_before.txt
    git submodule update --remote --merge
    git submodule status > /tmp/submodules_after.txt
    gum style --foreground 42 "✓ Submodules updated"
    echo ""
}

detect_changed_submodules() {
    local changed_services=()

    if [ -f /tmp/submodules_before.txt ] && [ -f /tmp/submodules_after.txt ]; then
        while IFS= read -r line; do
            submodule=$(echo "$line" | awk '{print $2}')
            case "$submodule" in
                amf) changed_services+=("amf") ;;
                ausf) changed_services+=("ausf") ;;
                nrf) changed_services+=("nrf") ;;
                nssf) changed_services+=("nssf") ;;
                scp) changed_services+=("scp") ;;
                sepp) changed_services+=("sepp") ;;
                udm) changed_services+=("udm") ;;
                smf) changed_services+=("smf") ;;
                upf) changed_services+=("upf") ;;
            esac
        done < <(diff /tmp/submodules_before.txt /tmp/submodules_after.txt | grep '^>' | awk '{print $2}')
    fi

    echo "${changed_services[@]}"
}

commit_push() {
    gum style --foreground 220 "Committing and pushing changes..."
    git add .
    if git commit -m "Update submodules" 2>/dev/null; then
        if git push origin dev 2>/dev/null; then
            gum style --foreground 42 "✓ Changes committed and pushed"
        else
            gum style --foreground 208 "⚠ Commit succeeded but push failed"
        fi
    else
        gum style --foreground 244 "No changes to commit"
    fi
    echo ""
}

rebuild_all_no_cache() {
    gum style --foreground 220 "Rebuilding all services with --no-cache..."
    if ! docker compose build --no-cache; then
        print_build_failure
        exit 1
    fi
    gum style --foreground 42 "✓ All services rebuilt"
    echo ""
}

check_mongodb() {
    if docker compose ps mongodb 2>/dev/null | grep -q "Up"; then
        gum style --foreground 42 "✓ MongoDB already running"
        echo ""
    else
        gum style --foreground 220 "Starting MongoDB..."
        docker compose up -d mongodb
        gum style --foreground 220 "Waiting for MongoDB to be ready..."
        wait_for_mongodb 30 || return 1
        echo ""
    fi
}

start_services() {
    provision="Yes"
    if ! gum confirm "Provision/update subscriber?" --default=true; then
        provision="No"
    fi

    if [[ $provision == "Yes" ]]; then
        if [ -f ./scripts/helpers/provision-subscriber-local.sh ]; then
            ./scripts/helpers/provision-subscriber-local.sh
        else
            gum style --foreground 208 "⚠ provision-subscriber-local.sh not found, skipping..."
        fi
        echo ""
    fi

    start_webui="Yes"
    if ! gum confirm "Start web dashboard?" --default=true; then
        start_webui="No"
    fi

    gum style --foreground 220 "Starting all services..."
    echo ""

    run_mode=$(gum choose --header "Run mode:" "Background" "Foreground (show logs)")

    if [[ $run_mode == "Foreground (show logs)" ]]; then
        if [[ $start_webui == "No" ]]; then
            if ! docker compose up --scale web-ui=0; then
                print_start_failure true
                exit 1
            fi
        else
            if ! docker compose up; then
                print_start_failure true
                exit 1
            fi
        fi
    else
        if [[ $start_webui == "No" ]]; then
            if ! docker compose up -d --scale web-ui=0; then
                print_start_failure false
                exit 1
            fi
        else
            if ! docker compose up -d; then
                print_start_failure false
                exit 1
            fi
        fi

        gum style --foreground 42 --bold "✓ All services started in background"
        echo ""

        if [[ $start_webui == "Yes" ]]; then
            gum style --foreground 86 --bold "Web Dashboard:"
            gum style --foreground 255 "  http://localhost:3001"
            echo ""
        fi

        gum style --foreground 244 "Useful commands:"
        gum style --foreground 255 "  View logs: docker compose logs -f [service-name]"
        gum style --foreground 255 "  View all logs: ./scripts/helpers/view-logs.sh"
        gum style --foreground 255 "  Check status: docker compose ps"
        gum style --foreground 255 "  Stop services: docker compose down"
        gum style --foreground 255 "  Start test: ./scripts/helpers/start-test.sh"
    fi
}

preflight_checks

while true; do
    show_menu

    case $choice in
        "Quick Start") do_quick_start; break ;;
        "Full Rebuild") do_full_rebuild; break ;;
        "Update & Build") do_update_build; break ;;
        "Clean Start") do_clean_start; break ;;
        "Custom") do_custom; break ;;
        "Update Submodules") do_update_submodules; break ;;
        "Rebuild Web UI") do_rebuild_webui; break ;;
        "Publish Images") do_publish_images; break ;;
        "Exit")
            gum style --foreground 244 "Exiting..."
            exit 0
            ;;
        *)
            gum style --foreground 196 "Invalid choice. Please try again."
            echo ""
            ;;
    esac
done

echo ""
gum style \
    --foreground 42 --border-foreground 42 --border double \
    --align center --width 50 --margin "1 2" --padding "2 4" \
    '5G Core Started!'
echo ""
