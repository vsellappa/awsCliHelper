#!/bin/bash

##
## Changes the "Name" of a running AWS Instance filtering on the specified "owner" tag as owner@cloudera.com
##

set -u
set -e

if [ $# != 2 ]; then
  echo "Syntax: $0 <owner> <prefix>"
  exit 1
fi

OWNER=$1
PREFIX=$2

INSTANCES=($(aws ec2 describe-instances --filters "Name=tag:owner,Values=$OWNER@cloudera.com" "Name=instance-state-name,Values=running" --query "Reservations[].Instances[].InstanceId" --output text))

for i in "${!INSTANCES[@]}"; do 
    cmd=(aws ec2 create-tags --resources ${INSTANCES[$i]} --tags Key=Name,Value=${PREFIX}_${i})
    echo "Running cmd = ${cmd[@]}"
    ${cmd[@]}
done
