#!/bin/bash

set -e

if ! command -v gum &> /dev/null; then
    echo "Error: This script requires 'gum'. Install from https://github.com/charmbracelet/gum"
    exit 1
fi

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$SCRIPT_DIR/helpers/common.sh"

gum style \
	--foreground 212 --border-foreground 212 --border double \
	--align center --width 50 --margin "1 2" --padding "2 4" \
	'5G CORE' 'Automated Test Script'
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
TEST_DIR="/tmp/5g-core-test-$(date +%s)"

cleanup() {
    if [ -n "$TEST_DIR" ] && [ -d "$TEST_DIR" ]; then
        gum style --foreground 220 "Cleaning up test environment..."
        cd "$REPO_ROOT"
        if [ -d "$TEST_DIR" ]; then
            if [ "${SAVE_LOGS_ON_FAILURE:-false}" = "true" ]; then
                LOG_DIR="$REPO_ROOT/test-logs-$(date +%s)"
                mkdir -p "$LOG_DIR"
                gum style --foreground 220 "Saving logs to $LOG_DIR..."
                (cd "$TEST_DIR" && docker compose logs > "$LOG_DIR/all-services.log" 2>&1)
                gum style --foreground 42 "✓ Logs saved to $LOG_DIR"
            fi
            (cd "$TEST_DIR" && docker compose down -v 2>/dev/null || true)
        fi
        rm -rf "$TEST_DIR"
        gum style --foreground 42 "✓ Test environment cleaned up"
    fi
}

trap cleanup EXIT

gum style --foreground 86 --bold "[1/6] Creating test environment..."
echo ""

gum style --foreground 220 "Checking for existing 5G core services..."
if docker ps --format '{{.Names}}' | grep -qE '^(amf|nrf|ausf|udm|nssf|smf|upf|mongodb|ueransim)'; then
    gum style --foreground 220 "Found running 5G core services. Stopping them first..."
    (cd "$REPO_ROOT" && docker compose down 2>/dev/null || true)
    sleep 2
    gum style --foreground 42 "✓ Existing services stopped"
else
    gum style --foreground 42 "✓ No conflicting services found"
fi
echo ""

gum style --foreground 220 "Creating test directory: $TEST_DIR"
mkdir -p "$TEST_DIR"
gum style --foreground 42 "✓ Test directory created"
echo ""

gum style --foreground 86 --bold "[2/6] Copying repository..."
echo ""

gum style --foreground 220 "Copying current repository state..."
rsync -a --exclude='.git' --exclude='node_modules' --exclude='target' \
    --exclude='UERANSIM' --exclude='Open5GS' --exclude='test-free5gc' \
    --exclude='amf' --exclude='ausf' --exclude='nrf' --exclude='nssf' \
    --exclude='smf' --exclude='udm' --exclude='upf' --exclude='scp' \
    --exclude='sepp' --exclude='smsf' \
    "$REPO_ROOT/" "$TEST_DIR/"
gum style --foreground 42 "✓ Repository copied"
echo ""

cd "$TEST_DIR"

gum style --foreground 220 "Verifying required directories..."
if [ ! -d "docker" ]; then
    gum style --foreground 196 "✗ docker directory was not copied"
    ls -la
    exit 1
fi
if [ ! -d "config" ]; then
    gum style --foreground 196 "✗ config directory was not copied"
    exit 1
fi

gum style --foreground 244 "Copying docker subdirectories..."
DOCKER_SUBDIRS=(amf ausf nrf nssf smf udm upf scp sepp smsf)
for subdir in "${DOCKER_SUBDIRS[@]}"; do
    if [ ! -d "docker/$subdir" ]; then
        if [ -d "$REPO_ROOT/docker/$subdir" ]; then
            cp -r "$REPO_ROOT/docker/$subdir" docker/
            gum style --foreground 42 "✓ Copied docker/$subdir"
        else
            gum style --foreground 196 "✗ docker/$subdir not found in source repo"
            exit 1
        fi
    fi
done

gum style --foreground 42 "✓ Required directories present"
echo ""

gum style --foreground 220 "Verifying and copying config files..."
for nf in ausf udm nssf scp smsf smf amf; do
    if [ -d "$REPO_ROOT/config/$nf" ]; then
        mkdir -p "config/$nf"
        if [ "$(ls -A "$REPO_ROOT/config/$nf" 2>/dev/null)" ]; then
            cp -r "$REPO_ROOT/config/$nf/". "config/$nf/"
            gum style --foreground 42 "✓ Copied config/$nf/ ($(ls -A config/$nf | wc -l | tr -d ' ') files)"
        else
            gum style --foreground 220 "  No files in config/$nf/"
        fi
    else
        gum style --foreground 244 "  Skipping config/$nf/ (not found)"
    fi
done
gum style --foreground 42 "✓ Config files verified"
echo ""

gum style --foreground 86 --bold "[3/6] Running setup with defaults..."
echo ""

gum style --foreground 220 "Checking prerequisites..."
prerequisites_met=true

check_command docker "Docker" || prerequisites_met=false
check_command git "Git" || prerequisites_met=false

if [ "$prerequisites_met" = false ]; then
    gum style --foreground 196 "✗ Prerequisites check failed"
    exit 1
fi

gum style --foreground 42 "✓ Prerequisites met"
echo ""

gum style --foreground 220 "Cloning required repositories..."
echo ""

clone_repo() {
    local dir="$1"
    local url="$2"
    if [ ! -d "$dir" ]; then
        gum style --foreground 244 "Cloning $dir..."
        git clone --depth 1 "$url" "$dir" 2>&1 | sed 's/^/  /'
        if [ ! -d "$dir" ]; then
            gum style --foreground 196 "✗ Failed to clone $dir"
            exit 1
        fi
    fi
}

clone_repo "UERANSIM" "https://github.com/aligungr/UERANSIM.git"
clone_repo "amf" "https://github.com/gholtzap/amf.git"
clone_repo "ausf" "https://github.com/gholtzap/ausf"
clone_repo "nrf" "https://github.com/gholtzap/nrf.git"
clone_repo "nssf" "https://github.com/gholtzap/nssf"
clone_repo "smf" "https://github.com/gholtzap/smf"
clone_repo "udm" "https://github.com/gholtzap/udm"
clone_repo "upf" "https://github.com/gholtzap/upf"
clone_repo "scp" "https://github.com/gholtzap/scp"
clone_repo "sepp" "https://github.com/gholtzap/SEPP.git"
clone_repo "smsf" "https://github.com/gholtzap/smsf.git"

echo ""
gum style --foreground 42 "✓ All repositories cloned"
echo ""

if [ -f .env.example ] && [ ! -f .env ]; then
    gum style --foreground 220 "Creating .env from template..."
    cp .env.example .env
    gum style --foreground 42 "✓ Environment configured"
    echo ""
fi

gum style --foreground 42 "✓ Setup complete"
echo ""

gum style --foreground 86 --bold "[4/6] Building all services with --no-cache..."
echo ""
gum style --foreground 244 "This may take 10-20 minutes..."
echo ""

gum style --foreground 220 "Building Docker images..."
docker compose build --no-cache
gum style --foreground 42 "✓ Build complete"
echo ""

gum style --foreground 86 --bold "[5/6] Starting all services..."
echo ""

gum style --foreground 220 "Starting MongoDB..."
docker compose up -d mongodb

gum style --foreground 220 "Waiting for MongoDB to be ready..."
wait_for_mongodb 30 || exit 1
echo ""

gum style --foreground 220 "Provisioning test subscriber..."
MONGODB_CONTAINER=$(docker compose ps --format '{{.Name}}' | grep mongodb | head -n 1)
TEMP_SCRIPT=$(mktemp)
cat > "$TEMP_SCRIPT" << 'PROVISION_EOF'
const { MongoClient } = require('mongodb');
const subscriber = {
  supi: 'imsi-999700123456789',
  permanentKey: '465B5CE8B199B49FAA5F0A2EE238A6BC',
  operatorKey: 'E8ED289DEBA952E4283B54E88E6183CA',
  sequenceNumber: '000000000001',
  authenticationMethod: '5G_AKA',
  subscribedData: {
    authenticationSubscription: {
      authenticationMethod: '5G_AKA',
      permanentKey: { permanentKeyValue: '465B5CE8B199B49FAA5F0A2EE238A6BC' },
      sequenceNumber: '000000000001',
      authenticationManagementField: '8000',
      milenage: { op: { opValue: 'E8ED289DEBA952E4283B54E88E6183CA' } }
    },
    amData: {
      gpsis: ['msisdn-0123456789'],
      subscribedUeAmbr: { uplink: '1 Gbps', downlink: '2 Gbps' },
      nssai: { defaultSingleNssais: [{ sst: 1 }] }
    },
    smData: [{
      singleNssai: { sst: 1 },
      dnnConfigurations: {
        internet: {
          pduSessionTypes: { defaultSessionType: 'IPV4' },
          sscModes: { defaultSscMode: 'SSC_MODE_1' },
          '5gQosProfile': { '5qi': 9, arp: { priorityLevel: 8 } },
          sessionAmbr: { uplink: '1 Gbps', downlink: '2 Gbps' }
        }
      }
    }]
  }
};
async function provision() {
  const client = new MongoClient('mongodb://localhost:27017');
  await client.connect();
  const collection = client.db('udm').collection('subscribers');
  await collection.replaceOne({ supi: subscriber.supi }, subscriber, { upsert: true });
  await client.close();
}
provision().catch(console.error);
PROVISION_EOF

docker cp "$TEMP_SCRIPT" "$MONGODB_CONTAINER:/tmp/provision.js"

gum style --foreground 244 "Installing Node.js in MongoDB container..."
if ! docker exec "$MONGODB_CONTAINER" sh -c "which npm > /dev/null 2>&1 || (apt-get update -qq && apt-get install -y -qq nodejs npm)"; then
    gum style --foreground 196 "✗ Failed to install Node.js"
    exit 1
fi

gum style --foreground 244 "Installing mongodb npm package..."
docker exec "$MONGODB_CONTAINER" sh -c "cd /tmp && npm init -y > /dev/null 2>&1"
if ! docker exec "$MONGODB_CONTAINER" sh -c "cd /tmp && npm install mongodb@4 > /dev/null 2>&1"; then
    gum style --foreground 196 "✗ Failed to install mongodb package"
    exit 1
fi

gum style --foreground 244 "Running provisioning script..."
if ! docker exec "$MONGODB_CONTAINER" sh -c "cd /tmp && node provision.js"; then
    gum style --foreground 196 "✗ Provisioning script failed"
    docker exec "$MONGODB_CONTAINER" rm /tmp/provision.js || true
    rm "$TEMP_SCRIPT"
    exit 1
fi

docker exec "$MONGODB_CONTAINER" rm /tmp/provision.js
rm "$TEMP_SCRIPT"
gum style --foreground 42 "✓ Subscriber provisioned"
echo ""

gum style --foreground 220 "Starting all services..."
docker compose up -d --scale web-ui=0 --scale sepp=0
gum style --foreground 42 "✓ Services started"
echo ""

gum style --foreground 86 --bold "[6/6] Monitoring for errors..."
echo ""

gum style --foreground 220 "Waiting 60 seconds for services to stabilize..."
sleep 60
gum style --foreground 42 "✓ Wait complete"
echo ""

gum style --foreground 220 "Checking Docker logs for errors..."
echo ""

services=$(docker compose ps --services)
error_found=false

for service in $services; do
    if [ "$service" = "sepp" ] || [ "$service" = "web-ui" ]; then
        gum style --foreground 244 "Skipping $service (not required for test)"
        continue
    fi

    gum style --foreground 244 "Checking $service..."

    if ! docker compose ps "$service" | grep -q "Up"; then
        gum style --foreground 196 "✗ $service is not running"
        gum style --foreground 244 "Last 30 lines of $service logs:"
        docker compose logs --tail=30 "$service" 2>&1 | sed 's/^/  /'
        echo ""
        error_found=true
        continue
    fi

    error_logs=$(docker compose logs "$service" 2>&1 | grep -iE "error|fatal|panic|exception" | grep -viE "error_code.*0|no error|Sessions collection is not set up|NamespaceNotFound.*config.system.sessions|Constraint check result: 0|Opening WiredTiger|Cell selection failure, no suitable or acceptable cell found" || true)

    if [ -n "$error_logs" ]; then
        gum style --foreground 196 "✗ Errors found in $service:"
        echo "$error_logs" | head -20
        echo ""
        error_found=true
    else
        gum style --foreground 42 "✓ $service: no errors"
    fi
done

echo ""

if [ "$error_found" = true ]; then
    SAVE_LOGS_ON_FAILURE=true
    gum style \
        --foreground 196 --border-foreground 196 --border double \
        --align center --width 50 --margin "1 2" --padding "2 4" \
        'Test Failed' 'Errors detected in logs'
    echo ""
    exit 1
else
    gum style \
        --foreground 42 --border-foreground 42 --border double \
        --align center --width 50 --margin "1 2" --padding "2 4" \
        'Test Passed' 'No errors detected'
    echo ""
    exit 0
fi
