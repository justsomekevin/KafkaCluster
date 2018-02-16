#!/bin/bash

#-------------- init.sh --------------
#  Initializes the Kafka cluster by
#  restarting containers, then setting
#  up topics.
#
#  Written By    : Kevin Lee
#  Modified By   : Kevin Lee
#  Date Created  : 01/16/2018
#  Date Modified : 02/15/2018
#  Rev           : 3
#
#----------------------------------------------
#  Change History:
#  1 - Initial revision.
#  2 - Replaced raw 'ansible' functions with
#      calls to Ansible playbooks.
#  3 - Integrated docker-compose up/down of
#      localhost into the ansible playbooks.
#

#Store directory of script
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

echo "Stopping existing containers";
ansible-playbook $DIR/ansible/stop_kafka_cluster.yml

echo "Starting containers";
ansible-playbook $DIR/ansible/start_kafka_cluster.yml

echo "Waiting for 20 seconds"
sleep 20;

echo "Creating topics";
docker-compose exec kafka kafka-topics --create --topic foo --partitions 1 --replication-factor 3 --if-not-exists --zookeeper 192.168.100.1:22181
docker-compose exec kafka kafka-topics --create --topic foo2 --partitions 8 --replication-factor 2 --if-not-exists --zookeeper 192.168.100.1:22181
docker-compose exec kafka kafka-topics --create --topic foo3 --partitions 4 --replication-factor 3 --if-not-exists --zookeeper 192.168.100.1:22181
docker-compose exec kafka kafka-topics --create --topic foo4 --partitions 8 --replication-factor 3 --if-not-exists --zookeeper 192.168.100.1:22181

echo "Viewing topics"; 
docker-compose exec kafka kafka-topics --describe --topic foo --zookeeper 192.168.100.1:22181;
docker-compose exec kafka kafka-topics --describe --topic foo2 --zookeeper 192.168.100.1:22181;
docker-compose exec kafka kafka-topics --describe --topic foo3 --zookeeper 192.168.100.1:22181;
docker-compose exec kafka kafka-topics --describe --topic foo4 --zookeeper 192.168.100.1:22181;
