#!/bin/bash

######### SET THIS FIRST!! #############################################
SBE_IP="192.168.10.103"
MANIFEST_FILE="./JID22135162-9d33-449a-8fec-40c8e7f83020_manifest.bin"
UNLOCK_CODE="550b7-e2ec0-e43ed-7fbfe-59993"
#########################################################################

DEFAULT_CERT_PEMFILE="snowball_cert.pem"
required_tools=("snowballEdge" "jq")

localSBE="--endpoint https://$SBE_IP --manifest-file $MANIFEST_FILE --unlock-code $UNLOCK_CODE"

# Check if required tools are installed

# Precheck function to verify if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

echo "Starting precheck..."

for tool in "${required_tools[@]}"; do
    if ! command_exists "$tool"; then
        echo "Error: '$tool' is not installed. Please install it before running this script."
        exit 1
    fi
done

echo "Precheck complete! Proceeding..."

#
# MAIN BODY
#

# Check if device is unlocked. If not - unlock it.

# Check if Snowball Edge has been unlocked
status=$(snowballEdge describe-device $localSBE | jq -r '.UnlockStatus.State')
echo "Snowball Edge status:" $status

if [ "$status" != "UNLOCKED" ]; then
    echo "Snowball Edge has not been unlocked. Unlocking it now..."
    snowballEdge unlock-device $localSBE
    exit 1
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
read -p "Do you want to export the certificate to a local file? (y/n): " export_cert

if [ "$export_cert" == "y" ]; then
    # Ask user for custom filename or use default
    read -p "Enter the filename (or press Enter to use default '$DEFAULT_CERT_PEMFILE'): " custom_filename
    export_filename=${custom_filename:-$DEFAULT_CERT_PEMFILE}

    # Export the snowball certificates to a local file
    snowballEdge get-certificate --certificate-arn $SBEcert $localSBE > ./$export_filename
    echo "Certificate exported to $export_filename"
fi

# Uncomment the section below as needed
# Add snowcone certificate to the RHEL system trust store and update
# NOTE: if accessing from Mac use the following procedure
# Open KeyChain Access from the Applications/Utilities folder. Select "System". Drag and drop the certificate into Keychain Access and enter your admin password.

# sudo cp snowcone_cert.pem /etc/pki/ca-trust/source/anchors/snowcone_cert.pem
# sudo chown root.root /etc/pki/ca-trust/source/anchors/snowcone_cert.pem
# sudo chmod 0644 /etc/pki/ca-trust/source/anchors/snowcone_cert.pem
# sudo restorecon -v /etc/pki/ca-trust/source/anchors/snowcone_cert.pem
# sudo update-ca-trust
# sudo update-ca-trust extract

