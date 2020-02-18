#!/bin/bash

#######################################################################################################################
##
## Creates EC2 AWS Instances based on an AMI
##
#######################################################################################################################

set -u
set -e

export TERMINATE=${TERMINATE:-"no"}

## Add your VPN here
## By Default the SG will open all ports to your IP
export VPN=${VPN:-"127.0.0.1"}

## Pre-Reqs
export KEYNAME=${KEYNAME:-"vs_workshop"}
export KEYLOCATION=${KEYLOCATION:-"https://raw.githubusercontent.com/vsellappa/workshop/master/keys/workshop.pub"}
export SGNAME=${SGNAME:-"vs_sg_workshop"}

## ec2 instance details
export COUNT=${COUNT:-1}
export IMAGEID=${IMAGEID:-"ami-0bffb4208f934a678"}
export INSTANCETYPE=${INSTANCETYPE:-"m4.4xlarge"}

## Tags
export OWNER=${OWNER:-"venky@cloudera.com"}
export PURPOSE=${PURPOSE:-"Workshop"}
export ENDDATE=${ENDDATE:-$(date -d "+7days" +%m%d%Y)}

## AWS Return codes
SUCCESS=0
SIGINT=130
ERROR=254 # API call succeeds , call condition fails
FAIL=255 # Command failed , errors from the service or the CLI

## Global Variables
KEYID=
KEYFINGERPRINT=
SGID=
INSTANCEID=

## Print functions
print_error() {
    local message="$1"
    txtred=$(tput setaf 1)
    txtreset=$(tput sgr0)

    echo "${txtred} ${message} ${txtreset}"
}

print_warn() {
    local message="$1"
    txtyellow=$(tput setaf 3)
    txtreset=$(tput sgr0)

    echo "${txtyellow} ${message} ${txtreset}"
}

print_info() {
    local message="$1"
    txtgreen=$(tput setaf 2)
    txtreset=$(tput sgr0)

    echo "${txtgreen} ${message} ${txtreset}"
}
## End Print Functions

## create tags for a resource
create_tags(){
    local resourceid="$1"
    local owner="$2"
    local purpose="$3"
    local enddate="$4"
    local name="$5"

    cmd=$(aws ec2 create-tags --resources "${resourceid}" --tags Key=Owner,Value="${owner}" \
        Key=Purpose,Value="${purpose}" \
        Key=EndDate,Value="${enddate}" \
        Key=Name,Value="${name}")

    return "$?"
}

## check if sshkey exists in the region
function key_exists() {
    local keyname="$1"
    
    KEYID=$(aws ec2 describe-key-pairs --output text --key-names "${keyname}" --query "KeyPairs[*].KeyPairId")

    return "$?"
}

## get_keyid()
function get_keyid() {
    local keyname="$1"
    key_exists "${keyname}"
}

## import key
function import_key() {
    local keylocation="$1"
    return_code=$(curl -s -o /tmp/workshop.pub -w "%{http_code}" "${keylocation}")

    if [[ "${return_code}" -ne 200 ]]; then
        print_error "Error in KeyLocation ${keylocation}"
        exit 1
    fi

    ## aws ec2 import-key-pair expects keypair to be base64 encoded
    base64 /tmp/workshop.pub > /tmp/encodedWorkshop.pub

    KEYFINGERPRINT=$(aws ec2 import-key-pair --output text --key-name "${KEYNAME}" --public-key-material file:///tmp/encodedWorkshop.pub --query KeyFingerprint)

    return "$?"
}

## check sg exists
function sg_exists() {
    local sgname="$1"

    SGID=$(aws ec2 describe-security-groups --output text --group-name "${sgname}" --query "SecurityGroups[*].GroupId")

    return "$?"
}

## create security group
function create_sg() {
    local sgname="$1"

    SGID=$(aws ec2 create-security-group --output text --group-name "${sgname}" --description "VS Security Group For Workshops" --query GroupId)
    return "$?"
}

## configure security group
function configure_sg() {
    local sgid="$1"
    local vpn="$2"

    cmd=$(aws ec2 authorize-security-group-ingress --group-id "${sgid}" --protocol all --cidr "${vpn}/32")

    local myip=$(curl https://icanhazip.com)

    if [[ "${vpn}" != "${myip}" ]]; then
        cmd=$(aws ec2 authorize-security-group-ingress --group-id "${sgid}" --protocol all --cidr "${myip}/32") 
    fi

    return "$?"
}

###############################################################################
##
## Creates ec2 instances. Pre-req includes creation of a KeyPair and Valid 
## security group.
## 
## Globals:
##  OWNER
##  PURPOSE
##  ENDDATE
## Arguments:
##
###############################################################################

function create_instances() {
    local imageid="$1"
    local count="$2"
    local instancetype="$3"
    local keyname="$4"
    local sgname="$5"

    ## 
    ##--tag-specifications [{"ResourceType":"instance","Tags":[{"Key":"Owner","Value":"${OWNER}"},{"Key":"Purpose","Value":"${PURPOSE}"}]}] \
    ##

    INSTANCEID=$(aws ec2 run-instances --image-id "${imageid}" --count "${count}" \
    --instance-type "${instancetype}" \
    --tag-specifications 'ResourceType=instance,Tags=[{Key=Owner,Value='"${OWNER}"'},{Key=Purpose,Value='"${PURPOSE}"'},{Key=EndDate,Value='"${ENDDATE}"'}]' \
    --key-name "${keyname}" --security-groups "${sgname}" --output text \
    --query Instances[].[InstanceId])

    echo "${INSTANCEID}" > /tmp/instanceid

    print_info "Newly created Instance Id's at /tmp/instanceid"

    return "$?"
}

## delete all
terminate() {
    ## destroy all ec2 instances
    ## delete key
    ## delete security group
    local sgname="$2"
    ##TODO: Implement me
    ## aws ec2 delete-security-group --group-name "${sgname}"
    echo "Terminating All"
}

## main
main() {
    if [[ "${TERMINATE}" == "yes" ]]; then
        terminate
    fi

    if ! key_exists "${KEYNAME}"; then
        print_info "Importing Key From KeyLocation:${KEYLOCATION}"

        if  ! import_key "${KEYLOCATION}"; then
            print_error "Error in Importing key"
            exit 1
        fi
        get_keyid "${KEYNAME}"
    fi

    print_info "Using KeyName=${KEYNAME}:KeyId=${KEYID}"

    if ! sg_exists "${SGNAME}"; then
        print_info "Creating Security Group : ${SGNAME}"

        if ! create_sg "${SGNAME}"; then
            print_error "Error in Creating Security Group"
            exit 1
        fi

        ## tag it
        create_tags "${SGID}" "${OWNER}" "${PURPOSE}" "${ENDDATE}" "${SGNAME}"

        ## configure sg, if newly created
        if ! configure_sg "${SGID}" "${VPN}"; then
            print_error "Error in configuring Security Group ${SGID}"
            exit 1
        fi
    fi
    print_info "Using Security Group=${SGNAME}"

    ## create ec2 instance
    if ! create_instances "${IMAGEID}" "${COUNT}" "${INSTANCETYPE}" "${KEYNAME}" "${SGNAME}"; then
        print_error "Unable to Create instances"
        exit 1
    fi
}

##
main "$@"
