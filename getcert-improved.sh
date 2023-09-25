#!/bin/bash

# Function to check if command exists
command_exists() {
  command -v "$1" >/dev/null 2>&1
}

# Validate IP address 
validate_ip() {
  local ip=$1
  if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
    echo "valid"
  else
    echo "invalid"
  fi
}

# Usage info
show_help() {
cat << EOF
Usage: ${0##*/} [-i IP_ADDRESS] [-m MANIFEST_FILE] [-c UNLOCK_CODE]

Options:
  -h                 Show this help 
  -i IP_ADDRESS      Snowball Edge IP address
  -m MANIFEST_FILE   Manifest file
  -c UNLOCK_CODE     Unlock code
EOF
}

# Function to export certificate
export_certificate() {
  local arn=$1
  local filename=$2
  
  if [ -f "$filename" ]; then
    read -p "$filename already exists. Overwrite? (y/n) " confirm
    if [ "$confirm" != "y" ]; then
      return 1
    fi
  fi  

  snowballEdge get-certificate --certificate-arn "$arn" "$localSBE" > "$filename"

  if [ $? -eq 0 ]; then
    echo "Certificate exported to $filename"
  else
    echo "Error exporting certificate"
    return 1
  fi
}

# Get arguments
while getopts ":i:m:c:h" opt; do
  case $opt in
    i)
      SBE_IP="$OPTARG"
      ;;
    m)
      MANIFEST_FILE="$OPTARG" 
      ;;
    c)
      UNLOCK_CODE="$OPTARG"
      ;;
    h)
      show_help
      exit 0
      ;;
    \?)
      echo "Invalid option: -$OPTARG" >&2
      exit 1
      ;;
  esac
done

# Validate IP address
ip_valid=$(validate_ip "$SBE_IP")
if [[ "$ip_valid" == "invalid" ]]; then
  echo "Invalid IP address"
  exit 1
fi

# Main

# Check required tools
for tool in "snowballEdge" "jq"; do
  if ! command_exists "$tool"; then
    echo "Error: '$tool' is not installed."
    exit 1
  fi  
done

# Unlock device
snowballEdge describe-device "$localSBE" | jq -r '.UnlockStatus.State'
if [[ $? -ne 0 ]]; then
  echo "Error getting unlock status"
  exit 1
fi

if [[ "$status" != "UNLOCKED" ]]; then
  snowballEdge unlock-device "$localSBE"
  if [[ $? -ne 0 ]]; then
    echo "Error unlocking device"
    exit 1
  fi
fi

# Determine the interface id of the physical network adapter
SBEif=`snowballEdge describe-device $localSBE | jq -r '.PhysicalNetworkInterfaces[0].PhysicalNetworkInterfaceId'`
echo "Snowball Edge Physical Network Adapter Interface ID: $SBEif"

# Create a virtual network adapter to attach to EC2 instances
#snowballEdge create-virtual-network-interface --ip-address-assignment dhcp --physical-network-interface-id $SBEif

# Get the certificate off the snowball and display it
SBEcert=`snowballEdge list-certificates $localSBE | jq -r '.Certificates[0].CertificateArn'`
echo "SnowBall Certificate: $SBEcert"

# Check if user wants to export certificate
read -p "Do you want to export the certificate to a local file? (y/n) " do_export

if [ "$do_export" == "y" ]; then

  read -p "Enter filename (or press Enter for default '$DEFAULT_CERT_PEMFILE'): " filename
  
  if [ -z "$filename" ]; then
    filename=$DEFAULT_CERT_PEMFILE
  fi

  export_certificate "$SBEcert" "$filename"

fi

# Add snowball certificate to the system trust store and update. Works for RHEL and MacOS platforms

platform=$(uname)

if [[ "$platform" == "Linux" ]]; then
    if [[ -f /etc/redhat-release ]]; then
        echo "Detected RHEL platform. Adding snowcone certificate to the RHEL system trust store."
        sudo cp snowcone_cert.pem /etc/pki/ca-trust/source/anchors/snowcone_cert.pem
        sudo chown root.root /etc/pki/ca-trust/source/anchors/snowcone_cert.pem
        sudo chmod 0644 /etc/pki/ca-trust/source/anchors/snowcone_cert.pem
        sudo restorecon -v /etc/pki/ca-trust/source/anchors/snowcone_cert.pem
        sudo update-ca-trust
        sudo update-ca-trust extract
    else
        echo "Detected Linux platform, but not RHEL. Please refer to the appropriate documentation for certificate installation."
    fi
elif [[ "$platform" == "Darwin" ]]; then
    echo "Detected Mac platform. Please follow these steps to add the certificate to KeyChain Access:"
    echo "1. Open KeyChain Access from the Applications/Utilities folder."
    echo "2. Select 'System'."
    echo "3. Drag and drop the certificate into Keychain Access and enter your admin password."
else
    echo "Unsupported platform detected. Please refer to the appropriate documentation for certificate installation."
fi
