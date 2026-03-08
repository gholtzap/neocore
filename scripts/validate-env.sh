#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_ROOT"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

ERRORS=0
WARNINGS=0

print_header() {
    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}  5G CORE Environment Configuration Validator${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
}

print_section() {
    echo ""
    echo -e "${BLUE}[$1] $2${NC}"
    echo ""
}

pass() {
    echo -e "  ${GREEN}✓${NC} $1"
}

fail() {
    echo -e "  ${RED}✗${NC} $1"
    ERRORS=$((ERRORS + 1))
}

warn() {
    echo -e "  ${YELLOW}⚠${NC} $1"
    WARNINGS=$((WARNINGS + 1))
}

info() {
    echo -e "  ${BLUE}ℹ${NC} $1"
}

check_env_files() {
    print_section "1/5" "Checking .env files..."

    REQUIRED_ENV_FILES=".env config/ausf/.env config/udm/.env config/smf/.env config/nssf/.env config/scp/.env"

    for env_file in $REQUIRED_ENV_FILES; do
        if [ -f "$env_file" ]; then
            pass "$env_file exists"
        else
            fail "$env_file is missing"
        fi
    done

    if [ -f ".env" ]; then
        echo ""
        info "Checking required variables in .env..."

        REQUIRED_VARS="NRF_IP AUSF_IP UDM_IP NSSF_IP AMF_IP SMF_IP UPF_IP NR_GNB_IP NR_UE_IP MONGODB_URI MONGODB_DB_NAME"

        for var in $REQUIRED_VARS; do
            value=$(grep "^${var}=" .env 2>/dev/null | cut -d'=' -f2-)
            if [ -n "$value" ] && [ "$value" != "" ]; then
                if [ "$var" = "MONGODB_URI" ]; then
                    case "$value" in
                        *"<username>"*|*"<password>"*|*"<cluster>"*)
                            warn "$var contains placeholder values"
                            ;;
                        *)
                            pass "$var is set"
                            ;;
                    esac
                else
                    pass "$var is set"
                fi
            else
                fail "$var is missing or empty"
            fi
        done
    fi

    echo ""
    info "Checking service-specific .env files..."

    if [ -f "config/ausf/.env" ]; then
        for var in SERVER_HOST SERVER_PORT MONGODB_URI NRF_URI UDM_URI; do
            if grep -q "^${var}=" "config/ausf/.env" 2>/dev/null; then
                pass "AUSF: $var is set"
            else
                fail "AUSF: $var is missing"
            fi
        done
    fi

    if [ -f "config/udm/.env" ]; then
        for var in PORT SERVER_HOST MONGODB_URI NRF_URI; do
            if grep -q "^${var}=" "config/udm/.env" 2>/dev/null; then
                pass "UDM: $var is set"
            else
                fail "UDM: $var is missing"
            fi
        done
    fi

    if [ -f "config/smf/.env" ]; then
        for var in PORT SMF_HOST MONGODB_URI NRF_URI UDM_URI; do
            if grep -q "^${var}=" "config/smf/.env" 2>/dev/null; then
                pass "SMF: $var is set"
            else
                fail "SMF: $var is missing"
            fi
        done
    fi

    if [ -f "config/nssf/.env" ]; then
        for var in PORT SERVER_HOST MONGODB_URI NRF_URI; do
            if grep -q "^${var}=" "config/nssf/.env" 2>/dev/null; then
                pass "NSSF: $var is set"
            else
                fail "NSSF: $var is missing"
            fi
        done
    fi
}

check_ip_subnet_consistency() {
    print_section "2/5" "Checking IP subnet consistency..."

    if [ ! -f ".env" ]; then
        fail "Cannot check IPs: .env file missing"
        return
    fi

    DOCKER_SUBNET=$(grep -E "^\s*-\s*subnet:" docker-compose.yml 2>/dev/null | head -1 | sed 's/.*subnet:\s*//' | tr -d ' ')
    if [ -z "$DOCKER_SUBNET" ]; then
        warn "Could not determine Docker subnet from docker-compose.yml"
        return
    fi

    SUBNET_PREFIX=$(echo "$DOCKER_SUBNET" | cut -d'/' -f1 | rev | cut -d'.' -f2- | rev)
    info "Expected subnet prefix: $SUBNET_PREFIX.*"

    IP_VARS="NRF_IP AUSF_IP UDM_IP NSSF_IP AMF_IP SMF_IP UPF_IP NR_GNB_IP NR_UE_IP SCP_IP SEPP_IP"

    for var in $IP_VARS; do
        value=$(grep "^${var}=" .env 2>/dev/null | cut -d'=' -f2-)
        if [ -n "$value" ]; then
            IP_PREFIX=$(echo "$value" | rev | cut -d'.' -f2- | rev)
            if [ "$IP_PREFIX" = "$SUBNET_PREFIX" ]; then
                pass "$var ($value) is in subnet $DOCKER_SUBNET"
            else
                fail "$var ($value) is NOT in subnet $DOCKER_SUBNET"
            fi
        fi
    done

    echo ""
    info "Checking for duplicate IPs..."

    IP_LIST=""
    for var in $IP_VARS; do
        value=$(grep "^${var}=" .env 2>/dev/null | cut -d'=' -f2-)
        if [ -n "$value" ]; then
            IP_LIST="$IP_LIST $var:$value"
        fi
    done
    IP_LIST="$IP_LIST MONGODB:10.53.1.5"

    DUPLICATES_FOUND=false
    SEEN_IPS=""
    SEEN_VARS=""

    for entry in $IP_LIST; do
        var=$(echo "$entry" | cut -d':' -f1)
        ip=$(echo "$entry" | cut -d':' -f2)

        found=false
        idx=1
        for seen_ip in $SEEN_IPS; do
            if [ "$seen_ip" = "$ip" ]; then
                seen_var=$(echo "$SEEN_VARS" | cut -d' ' -f$idx)
                fail "Duplicate IP: $ip used by both $seen_var and $var"
                DUPLICATES_FOUND=true
                found=true
                break
            fi
            idx=$((idx + 1))
        done

        if [ "$found" = false ]; then
            SEEN_IPS="$SEEN_IPS $ip"
            SEEN_VARS="$SEEN_VARS $var"
        fi
    done

    if [ "$DUPLICATES_FOUND" = false ]; then
        pass "No duplicate IPs found"
    fi

    echo ""
    info "Checking URI consistency with IPs..."

    URI_MAPPINGS="NRF_URI:NRF_IP AUSF_URI:AUSF_IP UDM_URI:UDM_IP NSSF_URI:NSSF_IP AMF_URI:AMF_IP SMF_URI:SMF_IP UPF_URI:UPF_IP"

    for mapping in $URI_MAPPINGS; do
        uri_var=$(echo "$mapping" | cut -d':' -f1)
        ip_var=$(echo "$mapping" | cut -d':' -f2)

        uri_value=$(grep "^${uri_var}=" .env 2>/dev/null | cut -d'=' -f2-)
        ip_value=$(grep "^${ip_var}=" .env 2>/dev/null | cut -d'=' -f2-)

        if [ -n "$uri_value" ] && [ -n "$ip_value" ]; then
            case "$uri_value" in
                *"$ip_value"*)
                    pass "$uri_var contains correct IP ($ip_value)"
                    ;;
                *)
                    fail "$uri_var does not contain $ip_var ($ip_value)"
                    ;;
            esac
        fi
    done
}

check_port_conflicts() {
    print_section "3/5" "Checking for port conflicts..."

    if [ ! -f "docker-compose.yml" ]; then
        fail "docker-compose.yml not found"
        return
    fi

    PORT_LIST=$(grep -E '^\s*-\s*"[0-9]+:[0-9]+' docker-compose.yml | sed 's/.*"\([0-9]*\):.*/\1/' | sort)

    PREV_PORT=""
    PORT_CONFLICTS=false

    for port in $PORT_LIST; do
        if [ "$port" = "$PREV_PORT" ]; then
            fail "Port $port is mapped multiple times in docker-compose.yml"
            PORT_CONFLICTS=true
        fi
        PREV_PORT="$port"
    done

    if [ "$PORT_CONFLICTS" = false ]; then
        pass "No port conflicts in docker-compose.yml"
    fi

    info "Exposed ports by service:"

    current_service=""
    while IFS= read -r line; do
        if echo "$line" | grep -qE '^  [a-z0-9_-]+:$'; then
            current_service=$(echo "$line" | sed 's/://g' | tr -d ' ')
        elif echo "$line" | grep -qE '^\s*-\s*"[0-9]+:[0-9]+'; then
            port=$(echo "$line" | sed 's/.*"\([^"]*\)".*/\1/')
            if [ -n "$current_service" ]; then
                echo "    $current_service: $port"
            fi
        fi
    done < docker-compose.yml

    echo ""
    info "Checking for host port conflicts..."

    HOST_CONFLICTS=false
    UNIQUE_PORTS=$(echo "$PORT_LIST" | sort -u)

    for port in $UNIQUE_PORTS; do
        if command -v lsof &> /dev/null; then
            if lsof -i :"$port" -sTCP:LISTEN &> /dev/null 2>&1; then
                PROCESS=$(lsof -i :"$port" -sTCP:LISTEN 2>/dev/null | tail -1 | awk '{print $1}')
                warn "Port $port is already in use by $PROCESS"
                HOST_CONFLICTS=true
            fi
        elif command -v netstat &> /dev/null; then
            if netstat -an 2>/dev/null | grep -E "LISTEN.*:$port\s" &> /dev/null; then
                warn "Port $port appears to be in use"
                HOST_CONFLICTS=true
            fi
        fi
    done

    if [ "$HOST_CONFLICTS" = false ]; then
        pass "No host port conflicts detected"
    fi
}

check_mongodb_credentials() {
    print_section "4/5" "Checking MongoDB credentials..."

    if [ ! -f ".env" ]; then
        fail "Cannot check MongoDB: .env file missing"
        return
    fi

    MONGODB_URI=$(grep "^MONGODB_URI=" .env 2>/dev/null | cut -d'=' -f2-)

    if [ -z "$MONGODB_URI" ]; then
        fail "MONGODB_URI is not set"
        return
    fi

    case "$MONGODB_URI" in
        *"<username>"*|*"<password>"*)
            fail "MONGODB_URI contains placeholder values - update with real credentials"
            return
            ;;
    esac

    case "$MONGODB_URI" in
        mongodb+srv://*)
            pass "MONGODB_URI uses MongoDB Atlas format (mongodb+srv://)"

            username=$(echo "$MONGODB_URI" | sed 's|mongodb+srv://\([^:]*\):.*|\1|')
            cluster=$(echo "$MONGODB_URI" | sed 's|mongodb+srv://[^@]*@\([^/]*\).*|\1|')

            if [ -n "$username" ] && [ "$username" != "$MONGODB_URI" ]; then
                pass "MongoDB username: $username"
            fi
            if [ -n "$cluster" ] && [ "$cluster" != "$MONGODB_URI" ]; then
                pass "MongoDB cluster: $cluster"
            fi

            info "Testing MongoDB Atlas connection..."

            if command -v mongosh &> /dev/null; then
                if timeout 10 mongosh "$MONGODB_URI" --eval "db.adminCommand('ping')" &> /dev/null; then
                    pass "MongoDB Atlas connection successful"
                else
                    warn "MongoDB Atlas connection failed - check credentials or network"
                fi
            elif command -v mongo &> /dev/null; then
                if timeout 10 mongo "$MONGODB_URI" --eval "db.adminCommand('ping')" &> /dev/null; then
                    pass "MongoDB Atlas connection successful"
                else
                    warn "MongoDB Atlas connection failed - check credentials or network"
                fi
            else
                info "mongosh/mongo not installed - skipping connection test"
                info "Install MongoDB Shell to enable connection testing"
            fi
            ;;

        mongodb://*)
            pass "MONGODB_URI uses standard MongoDB format"
            info "Local/Docker MongoDB connection configured"
            ;;

        *)
            fail "MONGODB_URI has invalid format"
            ;;
    esac

    echo ""
    info "Checking service MongoDB configurations..."

    SERVICE_ENVS="config/ausf/.env config/udm/.env config/smf/.env config/nssf/.env config/scp/.env"

    for env_file in $SERVICE_ENVS; do
        if [ -f "$env_file" ]; then
            service_mongo=$(grep "^MONGODB_URI=" "$env_file" 2>/dev/null | cut -d'=' -f2-)
            service_name=$(echo "$env_file" | cut -d'/' -f2 | tr '[:lower:]' '[:upper:]')

            if [ -n "$service_mongo" ]; then
                case "$service_mongo" in
                    mongodb://*)
                        pass "$service_name uses Docker-internal MongoDB"
                        ;;
                    mongodb+srv://*)
                        pass "$service_name uses MongoDB Atlas"
                        ;;
                    *)
                        warn "$service_name has unusual MongoDB URI format"
                        ;;
                esac
            fi
        fi
    done
}

check_docker_resources() {
    print_section "5/5" "Checking Docker resource limits..."

    if ! command -v docker &> /dev/null; then
        fail "Docker is not installed"
        return
    fi

    if ! docker info &> /dev/null 2>&1; then
        fail "Docker daemon is not running"
        return
    fi

    pass "Docker daemon is running"

    MEM_BYTES=$(docker info --format '{{.MemTotal}}' 2>/dev/null || echo "0")
    MEM_GB=$((MEM_BYTES / 1024 / 1024 / 1024))

    if [ "$MEM_GB" -ge 16 ]; then
        pass "Docker memory: ${MEM_GB}GB (16GB+ recommended)"
    elif [ "$MEM_GB" -ge 8 ]; then
        warn "Docker memory: ${MEM_GB}GB (16GB+ recommended for full stack)"
    else
        fail "Docker memory: ${MEM_GB}GB (minimum 8GB required, 16GB+ recommended)"
    fi

    CPUS=$(docker info --format '{{.NCPU}}' 2>/dev/null || echo "0")

    if [ "$CPUS" -ge 4 ]; then
        pass "Docker CPUs: $CPUS cores"
    elif [ "$CPUS" -ge 2 ]; then
        warn "Docker CPUs: $CPUS cores (4+ recommended)"
    else
        fail "Docker CPUs: $CPUS cores (minimum 2 required)"
    fi

    if command -v df &> /dev/null; then
        case "$OSTYPE" in
            darwin*)
                DISK_AVAIL=$(df -g "$HOME" 2>/dev/null | tail -1 | awk '{print $4}')
                ;;
            *)
                DOCKER_ROOT=$(docker info --format '{{.DockerRootDir}}' 2>/dev/null || echo "/var/lib/docker")
                DISK_AVAIL=$(df -BG "$DOCKER_ROOT" 2>/dev/null | tail -1 | awk '{print $4}' | tr -d 'G')
                ;;
        esac

        if [ -n "$DISK_AVAIL" ] && [ "$DISK_AVAIL" -ge 20 ] 2>/dev/null; then
            pass "Available disk space: ${DISK_AVAIL}GB"
        elif [ -n "$DISK_AVAIL" ] && [ "$DISK_AVAIL" -ge 10 ] 2>/dev/null; then
            warn "Available disk space: ${DISK_AVAIL}GB (20GB+ recommended)"
        elif [ -n "$DISK_AVAIL" ] 2>/dev/null; then
            fail "Available disk space: ${DISK_AVAIL}GB (minimum 10GB required)"
        fi
    fi

    DRIVER=$(docker info --format '{{.Driver}}' 2>/dev/null || echo "unknown")
    info "Storage driver: $DRIVER"

    IMAGES=$(docker images --format "{{.Repository}}:{{.Tag}}" 2>/dev/null | grep "5g-core" 2>/dev/null | wc -l | tr -d ' ')
    info "5G Core images built: $IMAGES"

    CONTAINERS=$(docker ps -a --format "{{.Names}}" 2>/dev/null | wc -l | tr -d ' ')
    RUNNING=$(docker ps --format "{{.Names}}" 2>/dev/null | wc -l | tr -d ' ')
    info "Containers: $RUNNING running / $CONTAINERS total"
}

print_summary() {
    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}  Validation Summary${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""

    if [ "$ERRORS" -eq 0 ] && [ "$WARNINGS" -eq 0 ]; then
        echo -e "  ${GREEN}✓ All checks passed!${NC}"
        echo ""
        echo -e "  Your environment is correctly configured."
        echo -e "  Run ${BLUE}./scripts/start.sh${NC} to start the 5G Core."
    elif [ "$ERRORS" -eq 0 ]; then
        echo -e "  ${YELLOW}⚠ $WARNINGS warning(s) found${NC}"
        echo ""
        echo -e "  Your environment should work but may have issues."
        echo -e "  Review warnings above before proceeding."
    else
        echo -e "  ${RED}✗ $ERRORS error(s) and $WARNINGS warning(s) found${NC}"
        echo ""
        echo -e "  Please fix the errors above before starting the 5G Core."
    fi

    echo ""
}

print_header
check_env_files
check_ip_subnet_consistency
check_port_conflicts
check_mongodb_credentials
check_docker_resources
print_summary

exit $ERRORS
