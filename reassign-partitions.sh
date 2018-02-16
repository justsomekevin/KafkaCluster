#!/bin/sh
if [ "$#" -ne 1 ] || ! [ -e "$1" ]; then
  echo "Usage: $0 .json file" >&2
  exit 1
fi

DIR=`pwd`
zookeeper="192.168.100.1:22181"
broker="kafka"
PRE_CMD="docker-compose exec ${broker}"

echo "Copying .json file into container";
`docker cp $1 multimachineclustersasl_${broker}_1:/tmp/$1`;

echo "Re-assigning partitions";
CMD="$PRE_CMD kafka-reassign-partitions --zookeeper $zookeeper --reassignment-json-file /tmp/$1 --execute";
$CMD;

echo "Verifying...";
CMD="$PRE_CMD kafka-reassign-partitions --zookeeper $zookeeper --reassignment-json-file /tmp/$1 --verify";
$CMD;

echo "Removing .json file from container";
`$PRE_CMD rm /tmp/$1`

echo "Done!";



