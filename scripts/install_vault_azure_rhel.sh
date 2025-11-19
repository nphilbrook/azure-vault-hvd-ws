#! /bin/bash

# This script is based on the template that ships with the HVD module for installing Vault on Azure VMs:
# https://github.com/hashicorp/terraform-azurerm-vault-enterprise-hvd/blob/098d644baf6253d705b9aa9b3fee0acaf9372646/templates/custom_data.sh.tpl
# Changes have been made to support using it independently of the module.

set -euo pipefail

# These variables will need to be updated per-environment / location, or for version upgrades
VAULT_TLS_CERT_KEYVAULT_SECRET_ID="https://dev-preqs-kv.vault.azure.net/secrets/vault-cert/3beeabd6a45f4a5eb28fa6746717f20d"
VAULT_TLS_PRIVKEY_KEYVAULT_SECRET_ID="https://dev-preqs-kv.vault.azure.net/secrets/vault-privkey/2fb1471897494fd19e1ff868b5fa1593"
VAULT_TLS_CA_BUNDLE_KEYVAULT_SECRET_ID="NONE"
VAULT_LICENSE_KEYVAULT_SECRET_ID="https://dev-preqs-kv.vault.azure.net/secrets/vault-license/8924840ab4fc41fe9050b0a74b164fac"
VM_DOMAIN_SUFFIX="dev.azure.nick-philbrook.sbx.hashidemos.io"
AUTO_JOIN_CLUSTER_TAG_KEY="VaultCluster"
AUTO_JOIN_CLUSTER_TAG_VALUE="dev"
VAULT_LEADER_TLS_SERVERNAME="vault-primary.dev.azure.nick-philbrook.sbx.hashidemos.io"
VAULT_SEAL_AZUREKEYVAULT_VAULT_NAME="dev-preqs-kv"
VAULT_SEAL_AZUREKEYVAULT_UNSEAL_KEY_NAME="vault-unseal-key-001"
VAULT_VERSION="1.21.0+ent"
# Reference https://developer.hashicorp.com/vault/docs/secrets/databases/oracle#setup for version
ORACLE_CLIENT_MAJOR_VERSION="19"
ORACLE_CLIENT_MINOR_VERSION="26"
ORACLE_VAULT_PLUGIN_VERSION="0.13.0+ent"

# These are unlikely to need to be changed per-env
VAULT_DISABLE_MLOCK="true"
VAULT_ENABLE_UI="true"
VAULT_DEFAULT_LEASE_TTL_DURATION="1h"
VAULT_MAX_LEASE_TTL_DURATION="768h"
VAULT_PORT_API="8200"
VAULT_PORT_CLUSTER="8201"
VAULT_TLS_REQUIRE_AND_VERIFY_CLIENT_CERT="false"
VAULT_TLS_DISABLE_CLIENT_CERTS="false"
VAULT_RAFT_PERFORMANCE_MULTIPLIER="5"
VAULT_SEAL_TYPE="azurekeyvault"

LOGFILE="/var/log/vault-cloud-init.log"
SYSTEMD_DIR="/lib/systemd/system"
VAULT_DIR_CONFIG="/etc/vault.d"
VAULT_DIR_TLS="${VAULT_DIR_CONFIG}/tls"
VAULT_DIR_DATA="/opt/vault/data"
VAULT_DIR_LICENSE="/opt/vault/license"
VAULT_DIR_PLUGINS="/opt/vault/plugins"
VAULT_DIR_LOGS="/var/log/vault"
VAULT_DIR_BIN="/usr/bin"
VAULT_DIR_ORACLE_CLIENT="/opt/oracle"
VAULT_USER="vault"
VAULT_GROUP="vault"
PRODUCT="vault"
VERSION=$VAULT_VERSION
REQUIRED_PACKAGES="unzip"
ADDITIONAL_PACKAGES=""

function log {
  local level="$1"
  local message="$2"
  local timestamp=$(date +"%Y-%m-%d %H:%M:%S")
  local log_entry="$timestamp [$level] - $message"

  echo "$log_entry" | tee -a "$LOGFILE"
}

function determine_os_distro {
  local os_distro_name=$(grep "^NAME=" /etc/os-release | cut -d"\"" -f2)

  case "$os_distro_name" in
    "Ubuntu"*)
      os_distro="ubuntu"
      ;;
    "CentOS Linux"*)
      os_distro="centos"
      ;;
    "Red Hat"*)
      os_distro="rhel"
      ;;
    *)
      log "ERROR" "'$os_distro_name' is not a supported Linux OS distro for BOUNDARY."
      exit_script 1
			;;
  esac

  echo "$os_distro"
}

function detect_architecture {
  local ARCHITECTURE=""
  local OS_ARCH_DETECTED=$(uname -m)

  case "$OS_ARCH_DETECTED" in
    "x86_64"*)
      ARCHITECTURE="linux_amd64"
      ;;
    "aarch64"*)
      ARCHITECTURE="linux_arm64"
      ;;
		"arm"*)
      ARCHITECTURE="linux_arm"
			;;
    *)
      log "ERROR" "Unsupported architecture detected: '$OS_ARCH_DETECTED'. "
		  exit_script 1
			;;
  esac

  echo "$ARCHITECTURE"

}


function install_azcli() {
  local OS_DISTRO="$1"
  local OS_MAJOR_VERSION=$(grep "^VERSION_ID=" /etc/os-release | cut -d"\"" -f2 | cut -d"." -f1)
	log "INFO" "Detected OS major version: $OS_MAJOR_VERSION"

  if command -v az > /dev/null; then
    log "INFO" "Detected 'az' (azure-cli) is already installed. Skipping."
  else
    if [[ "$OS_DISTRO" == "ubuntu" ]]; then
      log "INFO" "Installing Azure CLI for Ubuntu."
      curl -sL https://aka.ms/InstallAzureCLIDeb | bash
    elif [[ "$OS_DISTRO" == "rhel" || "$OS_DISTRO" == "centos" ]]; then
      log "INFO" "Installing Azure CLI for RHEL $OS_MAJOR_VERSION."
      rpm --import https://packages.microsoft.com/keys/microsoft.asc
      dnf install -y https://packages.microsoft.com/config/rhel/$OS_MAJOR_VERSION/packages-microsoft-prod.rpm
      dnf install -y azure-cli
    fi
  fi
}

function prepare_disk() {
  local device_name="$1"
  log "DEBUG" "prepare_disk - device_name; ${device_name}"

  local device_mountpoint="$2"
  log "DEBUG" "prepare_disk - device_mountpoint; ${device_mountpoint}"

  local device_label="$3"
  log "DEBUG" "prepare_disk - device_label; ${device_label}"

	sleep 20

  local device_id=$(readlink -f /dev/disk/azure/scsi1/${device_name})
  log "DEBUG" "prepare_disk - device_id; ${device_id}"
	if [[ -z "${device_id}" ]]; then
    log "ERROR" "No disk device found attached to device ${device_name}"
    exit_script 1
  fi

  mkdir $device_mountpoint

  # exclude quotes on device_label or formatting will fail
  mkfs.ext4 -m 0 -E lazy_itable_init=0,lazy_journal_init=0 -L ${device_label} ${device_id}

  echo "LABEL=${device_label} ${device_mountpoint} ext4 defaults 0 2" >> /etc/fstab

  mount -a
}

function install_packages() {
  local os_distro="$1"

  if [[ "$os_distro" == "ubuntu" ]]; then
    apt-get update -y
    apt-get install -y $REQUIRED_PACKAGES $ADDITIONAL_PACKAGES
  elif [[ "$os_distro" == "centos" ]] || [[ "$os_distro" == "rhel" ]]; then
    dnf install -y $REQUIRED_PACKAGES $ADDITIONAL_PACKAGES
  else
    log "ERROR" "Unable to determine package manager"
  fi
}

function custom_steps() {
  local os_distro="$1"

  if [[ "$os_distro" == "rhel" ]]; then
    if systemctl is-active --quiet firewalld; then
      log "INFO" "Stopping firewalld"
      systemctl stop firewalld
    fi
    if systemctl is-enabled --quiet firewalld; then
      log "INFO" "Disabling firewalld"
      systemctl disable firewalld
    fi
  fi
}

# scrape_vm_info gets the required information needed from the cloud's API
function scrape_vm_info {
  # https://docs.microsoft.com/en-us/azure/virtual-machines/linux/instance-metadata-service?tabs=linux
  SUBSCRIPTION_ID=$(curl -s -H Metadata:true "http://169.254.169.254/metadata/instance/compute/subscriptionId?api-version=2021-02-01&format=text")
  SCALE_SET_NAME=$(curl -s -H Metadata:true "http://169.254.169.254/metadata/instance/compute/vmScaleSetName?api-version=2021-02-01&format=text")
  RESOURCE_GROUP_NAME=$(curl -s -H Metadata:true "http://169.254.169.254/metadata/instance/compute/resourceGroupName?api-version=2021-02-01&format=text")
  NODE_NAME=$(curl -s -H Metadata:true 'http://169.254.169.254/metadata/instance/compute/osProfile/computerName?api-version=2023-11-15&format=text')
  AVAILABILITY_ZONE=$(curl -s -H Metadata:true 'http://169.254.169.254/metadata/instance/compute/zone?api-version=2023-11-15&format=text')
}

# user_create creates a dedicated linux user for Vault
function user_group_create {
  # Create the dedicated as a system group
  sudo groupadd --system $VAULT_GROUP

  # Create a dedicated user as a system user
  sudo useradd --system -m -d $VAULT_DIR_CONFIG -g $VAULT_GROUP $VAULT_USER
}

# directory_creates creates the necessary directories for Vault
function directory_create {
  # Define all directories needed as an array
  directories=( $VAULT_DIR_CONFIG $VAULT_DIR_DATA $VAULT_DIR_PLUGINS $VAULT_DIR_TLS $VAULT_DIR_LICENSE $VAULT_DIR_LOGS $VAULT_DIR_ORACLE_CLIENT )

  # Loop through each item in the array; create the directory and configure permissions
  for directory in "${directories[@]}"; do
    mkdir -p $directory
    sudo chown $VAULT_USER:$VAULT_GROUP $directory
    sudo chmod 750 $directory
  done
}

function checksum_verify {
  local OS_ARCH="$1"

  # https://www.hashicorp.com/en/trust/security
  # checksum_verify downloads the product binary and verifies its integrity
  log "INFO" "Verifying the integrity of the ${PRODUCT} binary."
  export GNUPGHOME=./.gnupg
  log "INFO" "Importing HashiCorp GPG key."
  sudo curl -s https://www.hashicorp.com/.well-known/pgp-key.txt | gpg --import

	log "INFO" "Downloading ${PRODUCT} binary"
  sudo curl -Os https://releases.hashicorp.com/"${PRODUCT}"/"${VERSION}"/"${PRODUCT}"_"${VERSION}"_"${OS_ARCH}".zip
	log "INFO" "Downloading ${PRODUCT}  Enterprise binary checksum files"
  sudo curl -Os https://releases.hashicorp.com/"${PRODUCT}"/"${VERSION}"/"${PRODUCT}"_"${VERSION}"_SHA256SUMS
	log "INFO" "Downloading ${PRODUCT}  Enterprise binary checksum signature file"
  sudo curl -Os https://releases.hashicorp.com/"${PRODUCT}"/"${VERSION}"/"${PRODUCT}"_"${VERSION}"_SHA256SUMS.sig
  log "INFO" "Verifying the signature file is untampered."
  gpg --verify "${PRODUCT}"_"${VERSION}"_SHA256SUMS.sig "${PRODUCT}"_"${VERSION}"_SHA256SUMS
	if [[ $? -ne 0 ]]; then
		log "ERROR" "Gpg verification failed for SHA256SUMS."
		exit_script 1
	fi
  if [ -x "$(command -v sha256sum)" ]; then
		log "INFO" "Using sha256sum to verify the checksum of the ${PRODUCT} binary."
		sha256sum -c "${PRODUCT}"_"${VERSION}"_SHA256SUMS --ignore-missing
	else
		log "INFO" "Using shasum to verify the checksum of the ${PRODUCT} binary."
		shasum -a 256 -c "${PRODUCT}"_"${VERSION}"_SHA256SUMS --ignore-missing
	fi
	if [[ $? -ne 0 ]]; then
		log "ERROR" "Checksum verification failed for the ${PRODUCT} binary."
		exit_script 1
	fi

	log "INFO" "Checksum verification passed for the ${PRODUCT} binary."
	log "INFO" "Removing the downloaded files to clean up"
	sudo rm -f "${PRODUCT}"_"${VERSION}"_SHA256SUMS "${PRODUCT}"_"${VERSION}"_SHA256SUMS.sig

}

# install_vault_binary downloads the Vault binary and puts it in dedicated bin directory
function install_vault_binary {
  local OS_ARCH="$1"

  log "INFO" "Deploying Vault Enterprise binary to $VAULT_DIR_BIN unzip and set permissions"
  sudo unzip "${PRODUCT}"_"${VAULT_VERSION}"_"${OS_ARCH}".zip  vault -d $VAULT_DIR_BIN
  sudo unzip "${PRODUCT}"_"${VAULT_VERSION}"_"${OS_ARCH}".zip -x vault -d $VAULT_DIR_LICENSE
  sudo rm -f "${PRODUCT}"_"${VAULT_VERSION}"_"${OS_ARCH}".zip

	log "INFO" "Deploying Vault $VAULT_DIR_BIN set permissions"
  sudo chmod 0755 $VAULT_DIR_BIN/vault
  sudo chown $VAULT_USER:$VAULT_GROUP $VAULT_DIR_BIN/vault

  log "INFO" "Deploying Vault create symlink "
  sudo ln -sf $VAULT_DIR_BIN/vault /usr/local/bin/vault

  log "INFO" "Vault binary installed successfully at $VAULT_DIR_BIN/vault"
}

# Install Oracle client libraries and the Vault plugin
function install_oracle_plugin {
  log "INFO" "Installing Oracle client libraries and dependencies"
  sudo curl --fail-with-body -s --output-dir $VAULT_DIR_ORACLE_CLIENT -O https://download.oracle.com/otn_software/linux/instantclient/${ORACLE_CLIENT_MAJOR_VERSION}${ORACLE_CLIENT_MINOR_VERSION}000/instantclient-basic-linux.x64-${ORACLE_CLIENT_MAJOR_VERSION}.${ORACLE_CLIENT_MINOR_VERSION}.0.0.0dbru.zip
  sudo unzip -o $VAULT_DIR_ORACLE_CLIENT/instantclient-basic-linux.x64-${ORACLE_CLIENT_MAJOR_VERSION}.${ORACLE_CLIENT_MINOR_VERSION}.0.0.0dbru.zip -d $VAULT_DIR_ORACLE_CLIENT
  sudo rm $VAULT_DIR_ORACLE_CLIENT/instantclient-basic-linux.x64-${ORACLE_CLIENT_MAJOR_VERSION}.${ORACLE_CLIENT_MINOR_VERSION}.0.0.0dbru.zip
  sudo chown -R $VAULT_USER:$VAULT_GROUP $VAULT_DIR_ORACLE_CLIENT
  sudo dnf install -y libnsl libaio glibc
  
  log "INFO" "Installing Vault Oracle database plugin"
  sudo curl --fail-with-body -s --output-dir $VAULT_DIR_PLUGINS -O https://releases.hashicorp.com/vault-plugin-database-oracle/${ORACLE_VAULT_PLUGIN_VERSION}/vault-plugin-database-oracle_${ORACLE_VAULT_PLUGIN_VERSION}_linux_amd64.zip
  # This is the new Enterprise plugin directory structure required
  sudo mkdir -p $VAULT_DIR_PLUGINS/vault-plugin-database-oracle_${ORACLE_VAULT_PLUGIN_VERSION}_linux_amd64
  sudo unzip -o $VAULT_DIR_PLUGINS/vault-plugin-database-oracle_${ORACLE_VAULT_PLUGIN_VERSION}_linux_amd64.zip -d $VAULT_DIR_PLUGINS/vault-plugin-database-oracle_${ORACLE_VAULT_PLUGIN_VERSION}_linux_amd64
  sudo rm $VAULT_DIR_PLUGINS/vault-plugin-database-oracle_${ORACLE_VAULT_PLUGIN_VERSION}_linux_amd64.zip
  sudo chown -R $VAULT_USER:$VAULT_GROUP $VAULT_DIR_PLUGINS/vault-plugin-database-oracle_${ORACLE_VAULT_PLUGIN_VERSION}_linux_amd64

  # Once the Vault cluster is running, this command must be run as well:
  # vault plugin register -version=v0.13.0+ent database vault-plugin-database-oracle
}

function retrieve_certs_from_kv() {
  log "INFO" "Retrieving TLS certificate '$VAULT_TLS_CERT_KEYVAULT_SECRET_ID' from Key Vault."
  az keyvault secret show --id "$VAULT_TLS_CERT_KEYVAULT_SECRET_ID" --query value --output tsv | base64 -d > $VAULT_DIR_TLS/cert.pem && echo $'\n' >> $VAULT_DIR_TLS/cert.pem

  log "INFO" "Retrieving TLS private key '$VAULT_TLS_PRIVKEY_KEYVAULT_SECRET_ID' from Key Vault."
  az keyvault secret show --id "$VAULT_TLS_PRIVKEY_KEYVAULT_SECRET_ID" --query value --output tsv | base64 -d > $VAULT_DIR_TLS/key.pem

  if [[ "$VAULT_TLS_CA_BUNDLE_KEYVAULT_SECRET_ID" != "NONE" ]]; then
    log "INFO" "Retrieving TLS CA bundle '$VAULT_TLS_CA_BUNDLE_KEYVAULT_SECRET_ID' from Key Vault."
    az keyvault secret show --id "$VAULT_TLS_CA_BUNDLE_KEYVAULT_SECRET_ID" --query value --output tsv | base64 -d > $VAULT_DIR_TLS/ca.pem
  fi

  log "INFO" "Setting certificate file permissions and ownership"
  sudo chown $VAULT_USER:$VAULT_GROUP $VAULT_DIR_TLS/*
  sudo chmod 600 $VAULT_DIR_TLS/*.pem
}

function retrieve_license_from_kv() {
  log "INFO" "Retrieving Vault license '$VAULT_LICENSE_KEYVAULT_SECRET_ID' from Key Vault."
  az keyvault secret download --id "$VAULT_LICENSE_KEYVAULT_SECRET_ID" --file $VAULT_DIR_LICENSE/license.hclic
  log "INFO" "Setting license file permissions and ownership"
  sudo chown $VAULT_USER:$VAULT_GROUP $VAULT_DIR_LICENSE/license.hclic
  sudo chmod 660 $VAULT_DIR_LICENSE/license.hclic
}

function generate_vault_config {
  if [[ "$VM_DOMAIN_SUFFIX" == "NONE" ]]; then
    FULL_HOSTNAME="$(hostname -f)"
  else
    FULL_HOSTNAME="$(hostname -s).$VM_DOMAIN_SUFFIX"
  fi

  # Determine leader_tls_servername
  if [[ -n "$VAULT_LEADER_TLS_SERVERNAME" ]]; then
    LEADER_TLS_SERVERNAME="$VAULT_LEADER_TLS_SERVERNAME"
  else
    LEADER_TLS_SERVERNAME="$FULL_HOSTNAME"
  fi

  sudo bash -c "cat > $VAULT_DIR_CONFIG/server.hcl" <<EOF
disable_mlock = $VAULT_DISABLE_MLOCK
ui            = $VAULT_ENABLE_UI

default_lease_ttl = "$VAULT_DEFAULT_LEASE_TTL_DURATION"
max_lease_ttl     = "$VAULT_MAX_LEASE_TTL_DURATION"

listener "tcp" {
  address       = "[::]:$VAULT_PORT_API"
  tls_cert_file = "$VAULT_DIR_TLS/cert.pem"
  tls_key_file  = "$VAULT_DIR_TLS/key.pem"

  tls_require_and_verify_client_cert = $VAULT_TLS_REQUIRE_AND_VERIFY_CLIENT_CERT
  tls_disable_client_certs           = $VAULT_TLS_DISABLE_CLIENT_CERTS
}

storage "raft" {
  path    = "$VAULT_DIR_DATA"
  node_id = "$NODE_NAME"

  performance_multiplier = $VAULT_RAFT_PERFORMANCE_MULTIPLIER

  autopilot_redundancy_zone = "zone-$AVAILABILITY_ZONE"
  retry_join {
    auto_join             = "provider=azure subscription_id=$SUBSCRIPTION_ID tag_name=$AUTO_JOIN_CLUSTER_TAG_KEY tag_value=$AUTO_JOIN_CLUSTER_TAG_VALUE https=true"
    auto_join_scheme      = "https"
EOF

  # Conditionally add leader_ca_cert_file if CA bundle is provided
  if [[ "$VAULT_TLS_CA_BUNDLE_KEYVAULT_SECRET_ID" != "NONE" ]]; then
    sudo bash -c "cat >> $VAULT_DIR_CONFIG/server.hcl" <<EOF
    leader_ca_cert_file   = "$VAULT_DIR_TLS/ca.pem"
EOF
  fi

  # Add leader_tls_servername
  sudo bash -c "cat >> $VAULT_DIR_CONFIG/server.hcl" <<EOF
    leader_tls_servername = "$LEADER_TLS_SERVERNAME"
  }
}

license_path = "$VAULT_DIR_LICENSE/license.hclic"

EOF

  # Conditionally add seal stanza if using azurekeyvault
  if [[ "$VAULT_SEAL_TYPE" == "azurekeyvault" ]]; then
    sudo bash -c "cat >> $VAULT_DIR_CONFIG/server.hcl" <<EOF
seal "azurekeyvault" {
  vault_name = "$VAULT_SEAL_AZUREKEYVAULT_VAULT_NAME"
  key_name   = "$VAULT_SEAL_AZUREKEYVAULT_UNSEAL_KEY_NAME"
}

EOF
  fi

  # Add api_addr, cluster_addr, and plugin_directory
  sudo bash -c "cat >> $VAULT_DIR_CONFIG/server.hcl" <<EOF
api_addr      = "https://$FULL_HOSTNAME:$VAULT_PORT_API"
cluster_addr  = "https://$FULL_HOSTNAME:$VAULT_PORT_CLUSTER"

plugin_directory = "$VAULT_DIR_PLUGINS"
EOF

  log "INFO" "Setting Vault server config file permissions and ownership"
  sudo chmod 600 $VAULT_DIR_CONFIG/server.hcl
  sudo chown $VAULT_USER:$VAULT_GROUP $VAULT_DIR_CONFIG/server.hcl
}

function generate_vault_systemd_unit_file {
  local kill_cmd=$(which kill)
  sudo bash -c "cat > $SYSTEMD_DIR/vault.service" <<EOF
[Unit]
Description="HashiCorp Vault - A tool for managing secrets"
Documentation=https://www.vaultproject.io/docs/
Requires=network-online.target
After=network-online.target
ConditionFileNotEmpty=$VAULT_DIR_CONFIG/server.hcl
StartLimitIntervalSec=60
StartLimitBurst=3

[Service]
User=$VAULT_USER
Group=$VAULT_GROUP
ProtectSystem=full
ProtectHome=read-only
PrivateTmp=yes
PrivateDevices=yes
SecureBits=keep-caps
AmbientCapabilities=CAP_IPC_LOCK
CapabilityBoundingSet=CAP_SYSLOG CAP_IPC_LOCK
NoNewPrivileges=yes
ExecStart=$VAULT_DIR_BIN/vault server -config=$VAULT_DIR_CONFIG/server.hcl
ExecReload=${kill_cmd} --signal HUP \$MAINPID
KillMode=process
KillSignal=SIGINT
Restart=on-failure
RestartSec=5
TimeoutStopSec=30
LimitNOFILE=65536
LimitMEMLOCK=infinity
StandardOutput=append:/var/log/vault/operational.log
StandardError=append:/var/log/vault/operational.log
[Install]
WantedBy=multi-user.target
EOF

  sudo chmod 644 $SYSTEMD_DIR/vault.service

  mkdir /etc/systemd/system/vault.service.d
  bash -c "cat > /etc/systemd/system/vault.service.d/override.conf" <<EOF
[Service]
Environment="VAULT_ENABLE_FILE_PERMISSIONS_CHECK=true"
Environment=LD_LIBRARY_PATH=/opt/oracle/instantclient_${ORACLE_CLIENT_MAJOR_VERSION}_${ORACLE_CLIENT_MINOR_VERSION}
EOF
  chmod 0600 /etc/systemd/system/vault.service.d/override.conf
}

function generate_vault_logrotate {
  bash -c "cat > /etc/logrotate.d/vault" <<-EOF
  # NOTE: the file pattern defined here for audit logs must match
  # how audit logs are enabled after the cluster is initialized.
  # E.g.: vault audit enable file file_path=/var/log/vault/audit.log
  /var/log/vault/*audit*.log {
    daily
    size 100M
    rotate 32
    dateext
    dateformat .%Y%m%d_%H%M%S
    missingok
    notifempty
    nocreate
    compress
    delaycompress
    sharedscripts
    postrotate
      systemctl reload vault > /dev/null 2>&1 || true
    endscript
  }

  # This file pattern is defined in the install script
  # and in the systemd unit file and should be good
  /var/log/vault/operational.log {
    daily
    # This is required as systemd doesn't respect the SIGHUP
    copytruncate
    size 100M
    rotate 32
    dateext
    dateformat .%Y%m%d_%H%M%S
    missingok
    notifempty
    nocreate
    compress
    delaycompress
    sharedscripts
  }
EOF
}

function start_enable_vault {
  sudo systemctl daemon-reload
  sudo systemctl enable vault
  sudo systemctl start vault
}

function configure_vault_cli {
  sudo bash -c "cat > /etc/profile.d/99-vault-cli-config.sh" <<EOF
export VAULT_ADDR=https://127.0.0.1:8200
EOF

  # Conditionally add VAULT_TLS_SERVER_NAME if leader_tls_servername is set
  if [[ -n "$VAULT_LEADER_TLS_SERVERNAME" ]]; then
    sudo bash -c "cat >> /etc/profile.d/99-vault-cli-config.sh" <<EOF
export VAULT_TLS_SERVER_NAME="$VAULT_LEADER_TLS_SERVERNAME"
EOF
  fi

  sudo bash -c "cat >> /etc/profile.d/99-vault-cli-config.sh" <<EOF
complete -C $VAULT_DIR_BIN/vault vault
EOF
}

function exit_script {
  if [[ "$1" == 0 ]]; then
    log "INFO" "Vault custom_data script finished successfully!"
  else
    log "ERROR" "Vault custom_data script finished with error code $1."
  fi

  exit "$1"
}

main() {
  log "INFO" "Beginning custom_data script."
  OS_DISTRO=$(determine_os_distro)
  log "INFO" "Detected OS distro is '$OS_DISTRO'."

  OS_ARCH=$(detect_architecture)
  log "INFO" "Detected system architecture is '$OS_ARCH'."

  log "INFO" "Scraping VM metadata required for Vault configuration"
  scrape_vm_info

  log "INFO" "Installing software dependencies"
  install_azcli "$OS_DISTRO"

  log "INFO" "Running 'az login'."
  az login --identity

  log "INFO" "Preparing Vault data disk"
  prepare_disk "lun0" "/opt/vault" "vault-data"

  log "INFO" "Installing $REQUIRED_PACKAGES $ADDITIONAL_PACKAGES"
  install_packages "$OS_DISTRO"

  log "INFO" "Performing custom steps"
  custom_steps "$OS_DISTRO"

  log "INFO" "Creating Vault system user and group"
  user_group_create

  log "INFO" "Creating directories for Vault config and data"
  directory_create

  checksum_verify $OS_ARCH
  log "INFO" "Checksum verification completed for Vault binary."

  log "INFO" "Installing Vault"
  install_vault_binary $OS_ARCH

  log "INFO" "Installing Oracle plugin and dependencies"
  install_oracle_plugin

  log "INFO" "Retrieving Vault license file from Key Vault"
  retrieve_license_from_kv

  log "INFO" "Retrieving Vault API TLS certificates from Key Vault"
  retrieve_certs_from_kv

  log "INFO" "Generating Vault server configuration file"
  generate_vault_config

  log "INFO" "Generating Vault systemd unit file and overrides.conf"
  generate_vault_systemd_unit_file

  log "INFO" "Generating audit log rotation script"
  generate_vault_logrotate

  log "INFO" "Starting Vault"
  start_enable_vault

  log "INFO" "Configuring Vault CLI"
  configure_vault_cli

  exit_script 0
}

main "$@"
