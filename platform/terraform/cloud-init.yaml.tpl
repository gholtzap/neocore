#cloud-config

package_update: true
package_upgrade: true

packages:
  - docker.io
  - docker-compose-plugin
  - git
  - lksctp-tools
  - curl
  - jq

runcmd:
  - systemctl enable docker
  - systemctl start docker
  - modprobe sctp
  - echo "sctp" >> /etc/modules-load.d/sctp.conf
  - sysctl -w net.ipv4.ip_forward=1
  - echo "net.ipv4.ip_forward=1" >> /etc/sysctl.d/99-5gcore.conf

  - mkdir -p /opt/5g-core
  - git clone --recursive https://github.com/gholtzap/5g-core.git /opt/5g-core
  - cd /opt/5g-core

  - |
    PUBLIC_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null || curl -s http://169.254.169.254/hetzner/v1/metadata/public-ipv4 2>/dev/null || hostname -I | awk '{print $1}')

    cat > /opt/5g-core/.env <<ENVEOF
    MCC=${mcc}
    MNC=${mnc}
    TAC=000001

    NRF_IP=10.53.1.40
    AUSF_IP=10.53.1.30
    UDM_IP=10.53.1.60
    NSSF_IP=10.53.1.50
    SCP_IP=10.53.1.80
    SEPP_IP=10.53.1.90
    SMSF_IP=10.53.1.95
    AMF_IP=10.53.1.10
    SMF_IP=10.53.1.20
    UPF_IP=10.53.1.70

    NR_GNB_IP=10.53.1.100
    NR_UE_IP=10.53.1.101

    MONGODB_URI=mongodb://mongodb:27017
    MONGODB_DB_NAME=5gcore

    IMSI=999700000000001
    MSISDN=1234567890
    KEY=00000000000000000000000000000000
    OPC=00000000000000000000000000000000
    AMF_VALUE=8000

    NRF_URI=http://10.53.1.40:8080/
    AUSF_URI=http://10.53.1.30:8080/
    UDM_URI=http://10.53.1.60:8080/
    NSSF_URI=http://10.53.1.50:8080/
    SCP_URI=http://10.53.1.80:7777/
    SEPP_URI=http://10.53.1.90:8080/
    SMSF_URI=http://10.53.1.95:8080/
    AMF_URI=http://10.53.1.10:8000/
    SMF_URI=http://10.53.1.20:8080/
    UPF_URI=http://10.53.1.70:8080/

    PUBLIC_IP=$PUBLIC_IP
    HOME_PLMN=${mcc}${mnc}
    ALLOWED_PLMNS=${mcc}${mnc}

    RUST_LOG=info
    NODE_ENV=production
    ENVEOF

  - cd /opt/5g-core && docker compose pull --ignore-pull-failures
  - cd /opt/5g-core && docker compose build
  - cd /opt/5g-core && docker compose up -d

  - |
    cat > /opt/5g-core/health.sh <<'HEALTHEOF'
    #!/bin/bash
    healthy=0
    total=0
    for svc in nrf ausf udm nssf amf smf upf scp sepp smsf web-ui; do
      total=$((total + 1))
      if docker compose -f /opt/5g-core/docker-compose.yml ps "$svc" 2>/dev/null | grep -q "Up"; then
        healthy=$((healthy + 1))
      fi
    done
    echo "{\"healthy\":$healthy,\"total\":$total}"
    HEALTHEOF
    chmod +x /opt/5g-core/health.sh

write_files:
  - path: /etc/systemd/system/5g-core.service
    content: |
      [Unit]
      Description=5G Core
      After=docker.service
      Requires=docker.service

      [Service]
      Type=oneshot
      RemainAfterExit=yes
      WorkingDirectory=/opt/5g-core
      ExecStart=/usr/bin/docker compose up -d
      ExecStop=/usr/bin/docker compose down

      [Install]
      WantedBy=multi-user.target

  - path: /opt/5g-core/tenant.json
    content: |
      {
        "tenant_id": "${tenant_id}",
        "provisioned_at": "PROVISION_TIME"
      }

final_message: "5G Core for tenant ${tenant_id} is ready. Took $UPTIME seconds."
