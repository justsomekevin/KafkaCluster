# FortiExtenderKafka
---

## Table of Contents
---
1. [Pre-Requisites](#pre-requisites)
2. [Default Ports](#default-ports)
3. [Gateway Setup](#gateway-setup)
4. [Kafka Cluster Management](#kafka-cluster-management)
5. [Kafka Producer and Consumer](#kafka-producer-and-consumer)
6. [Logstash](#logstash)
7. [FileBeat](#filebeat)

## Pre-Requisites
---
The following are required on the machine dedicated as the "gateway":
- Python, Docker and Docker-Compose installed
- Ansible installed
- DHCP configured on gateway (for convenience)
- SNAT configured for internal network
  For this example, assume the following:
  - Gateway external IP is 172.30.176.117
  - Gateway internal IP is 192.168.100.1, Kafka broker IPs will start at 192.168.100.10 and so on

## Default Ports
---
Zookeeper : `22181` [on gateway]
Kafka : `19092` (internal), `29092++` (external) [on gateway]
Logstash : `5044 - 5444` [Starts at 5044 per machine]
*Zookeeper and Kafka ports can be manually set in docker-compose.yml

## Gateway Setup
---
### SNAT
Configure SNAT on the gateway such that machines on the internal subnet can access the internet but devices on the external network cannot access machines on the internal subnet. Instructions to do so is outside the scope of this text.

### DHCP
For convenience, it is highly recommended to set up DHCP on the gateway. The steps to set it up are outside the scope of this text. Once DHCP is set up, however, configure `/etc/dhcp/dhcp.conf` with the following:
```
subnet 192.168.100.0 netmask 255.255.252.0 {
  range 192.168.100.10 192.168.100.128;
  option domain-name-servers 8.8.8.8,8.8.4.4;
  option routers 192.168.100.1;
  option broadcast-address 192.168.100.129;
  default-lease-time 600;
  max-lease-time 7200;
}
```
If a different subnet or subnet mask is preferred, modify the above accordingly.

### Configuring Ansible
Follow these [instructions][1] to get Ansible set up. To verify the installation, run:
```
$ ansible -m ping localhost
```
You should see:
```
localhost | SUCCESS => {
    "changed": false, 
    "ping": "pong"
}
```

Then, copy the following files to their corresponding locations:
```
$  sudo cp ansible/conf/hosts /etc/ansible/hosts
$  sudo mkdir -p /etc/ansible/group_vars
$  sudo cp ansible/conf/brokers /etc/ansible/group_vars/brokers
```

Finally, configure the following parameters for the Kafka Cluster accordingly in `hosts/cluster_conf.yml`.
* gatewayIP
* gatewayRootPath
* gatewayPassword
* brokerRootPath
* brokerPassword

### Configuring CA
A CA is required to signed certificates for the SSL protocol implemented between Logstash and its clients (such as FileBeat). Easy-RSA has already been included in this package for convenience. To configure the CA using Easy-RSA:
```
$ ./configureCA.sh 172.30.176.117
```
- The first argument provided is the external IP address of the gateway.
- If the EasyRSA CA was already setup prior to running this script, the previous CA would be removed and a new one would be reinitialized.
- Remember the CA password you've input during the CA setup as it will be needed when generating signed certificates later on.
- This script also generates a key and signed certificate for the primary Logstash container on the gateway. You'll need to input the CA password you've just now created.

### Configuring SASL
SASL authentication is enabled between Zookeeper and its clients (Kafka), as well as between Kafka and its clients (Logstash, producers and consumers). The SASL configuration settings for these containers can be seen in docker-compose.yml. The config files can be found in the `conf` directory. Modify the user/password combinations as necessary.

For example, take a look at the `KafkaServer` section of `conf/broker_jaas.conf`
```
KafkaServer {
   org.apache.kafka.common.security.plain.PlainLoginModule required
   username="peer"
   password="peer-secret" 
   user_peer="peer-secret"
   user_kafka="kafka-secret"
   user_confluent="confluent-secret"
};
```
The username and password fields are the credentials this container uses to authenticate with other Kafka brokers internally. Subsequent `user_X="Y"` lines represent the user (`X`) and password (`Y`) credentials the clients must have in order to be successfully authenticated.
```
KafkaClient {
   org.apache.kafka.common.security.plain.PlainLoginModule required
   username="kafka"
   password="kafka-secret";
};

Client {
   org.apache.kafka.common.security.plain.PlainLoginModule required
   username="zkclient"
   password="zkclient-secret";
};
```
As for the remaining two sections, `KafkaClient` and `Client`, these are the credentials supplied when this host acts as a Kafka client and Zookeeper client, respectively. Notice that the credentials in the `Client` section matches those in `conf/zookeeper_jaas.conf`.

**Note: At the moment, a copy of `conf/kafka_client_jaas.conf` is placed in the `logstash/secrets/` directory for convenience. TODO: Eliminate need for a copy of the `.conf` file.

## Kafka Cluster Management
---
### Start the Kafka Cluster
To start Zookeeper and all Kafka Brokers, simply run the Ansible playbook from the gateway as follows:
```
$ ansible-playbook ansible/start_kafka_cluster.yml
```
Optionally, one can write a script (`init.sh` provided as an example) that fully initializes the Kafka Cluster by:
1. Starting/Restarting Zookeeper and all Kafka containers
2. Create topics with specified partitions and replication factors

and simply run:
```
$ ./init.sh
```

### Stopping the Kafka Cluster
Similarly, to stop Zookeeper and all Kafka Brokers, simply run the Ansible playbook from the gateway as follows:
```
$ ansible-playbook ansible/stop_kafka_cluster.yml
```

### List Topics
The following command lists all existing topics:
```
$ docker-compose exec kafka kafka-topics --list --zookeeper 192.168.100.1:22181
```

### Create a Topic
The following command creates a topic called `foo` with 3 partitions and a replication factor of 3 (requires 3 Kafka brokers to be up beforehand)
```
docker-compose exec kafka kafka-topics --create \
--topic foo --partitions 3 --replication-factor 3 \
--if-not-exists --zookeeper 192.168.100.1:22181
```
The --if-not-exists flag creates the topic if it doesn't already exist. Without it, an error would be thrown whenever you are trying to create a topic that already exists.
Set the number of partitions (--partitions) and replication-factor (--replication-factor) accordingly.
The replication factor cannot exceed the number of brokers.

### Alter partitions
The following command increases the number of partitions of "foo" from 3 to 4:
```
docker-compose exec kafka kafka-topics --zookeeper 192.168.100.1:22181 --topic foo --alter --partitions 4
```
Keep in mind that the number of partitions is only allowed to increase.

### Alter replication factor
The following command alters the replication-factor and assignment of a topic according to specified parameters in a JSON file. Refer to the [Kafka documentation][2] for more info.
```
./reassign-partitions.sh increase-replication-factor.json
```
Refer to increase-replication-factor.json for the required format.

### Force Leader Re-election
```
$docker-compose exec kafka kafka-preferred-replica-election --zookeeper 192.168.100.1:22181
```

### Describe a Topic
```
docker-compose exec kafka kafka-topics --describe --topic foo --zookeeper 192.168.100.1:22181
```

You should see the following:
```
Topic:foo	PartitionCount:3	ReplicationFactor:3	Configs:
	Topic: foo	Partition: 0	Leader: 3	Replicas: 3,1,2	Isr: 3,1,2
	Topic: foo	Partition: 1	Leader: 1	Replicas: 1,2,3	Isr: 1,2,3
	Topic: foo	Partition: 2	Leader: 2	Replicas: 2,3,1	Isr: 2,3,1
```
Omitting the `--topic` field would result in all topics being described.

### Add Kafka Broker
In order to add a kafka broker to the cluster, first install openSSH on the new machine.
```
$ sudo apt-get update
$ sudo apt-get upgrade
$ sudo apt-get install openssh-server
```
Next, run the following Ansible Playbook script from the gateway. In this example, the new machine has an IP address of 192.168.100.12.
```
$ ansible-playbook ansible/add_kafka_host.yml --ask-become-pass --extra-vars "ip=192.168.100.12"
```
You will be prompted for the password for the root user on the gateway.

The following changes will happen throughout the playbook: 
- IP Tables DNAT will be updated on the host machine (previous IP Tables configuration will be backed-up to /etc/iptables.rules.1).
- New machine's IP will be appended to `/etc/ansible/hosts` under the `[brokers]` group
- Python, Docker and Docker-Compose will be installed on the new machine.
- docker-compose.yml and SASL-related .conf files will be configured on the new machine
- Kafka container will be created and started on the new machine

## Kafka Producer and Consumer
---

### Produce Messages to Topic
The command to run (specifically the port number) depends on whether the producer is in the internal or external network.  The port number that should be specified for internal and external producers should be the ones listed as INTERNAL and EXTERNAL under KAFKA_ADVERTISED_LISTENERS in docker-compose.yml, respectively.

Internal:
```
$ python3 pyscripts/producer.py 192.168.100.1:19092 foo
```
External:
```
$ python3 producer.py 172.30.176.117:29092 foo
```

### Consume Messages From Subscribed Topic
Similar to producing messages, the port number to be specified depends on whether the consumer is in the internal or external network.

Internal:
```
$ python3 pyscripts/consumer.py 192.168.100.1:19092 mygroup foo
```
External:
```
$ python3 consumer.py 172.30.176.117:29092 mygroup foo
```

## Logstash
---
One instance of Logstash is brought up along with Zookeeper and Kafka on the gateway. As a Kafka Producer, Logstash requires authentication via SASL credentials as provided by kafka_client_jaas.conf in the logstash/secrets directory. In order to have SSL properly supported for Logstash clients, ensure that the CA is properly configured on the gateway. Refer to section #.# above for more info.

### Adding more Logstash containers
Additional Logstash containers can be brought up on any machine on the external network. If the new container is to be on the gateway, run the following command:
```
$ logstash/setup.sh
```
If the new container is to be hosted on a different machine, provide the __IP address__ and __user__ of the machine and run the following command:
```
$ logstash/setup.sh 172.30.176.118 ubuntu
```
* Note: The new machine would need to have OpenSSH installed.

Once the new Logstash container has been created, note the port number that has been assigned. In the below example, port `5051` on the host machine has been assigned to the newly created Logstash container.
```
CONTAINER ID        IMAGE               COMMAND                  CREATED             STATUS              PORTS                    NAMES
6bfe454b6df4        logstash            "/docker-entrypoint.…"   22 seconds ago      Up 10 seconds       0.0.0.0:5051->5044/tcp   logstash50512469
```

## FileBeat
---
FileBeat is used to ship logs to Logstash, which in turn gets published to Kafka topics. 

### Setting up FileBeat
In order to bring up FileBeat on any machine, Docker containers or virtual machines, first copy the entire filebeat directory onto the machine. Next, generate the key and cert pairs required for SSL by running the following command:
```
$ filebeat/generateKeyAndCert.sh
```
Place the generated .key and .crt files, as well as `easy-rsa/easyrsa3/pki/ca.crt`  into the `filebeat/secrets` directory on the FileBeat host machine. Then, run the following command on the FileBeat host machine:
```
$ ./install_filebeat.sh
```
* This script only supports Linux and Ubuntu machines at the moment

### Testing FileBeat (and Logstash)
Ensure that python is installed on the FileBeat host machine. Instantiate a Kafka Consumer on any machine and run the following command to have Logstash start producing messages to Kafka:
```
$ python run_commands.py -c "echo $RANDOM" -t foo4 -lh 172.30.176.117 -lp 5044
```
* run the script with the -h or --help flag to display usage info
* -lh and -lp options specify the Logstash Host IP and Port, respectively

[1]: <https://www.digitalocean.com/community/tutorials/how-to-install-and-configure-ansible-on-ubuntu-16-04>
[2]: <https://cwiki.apache.org/confluence/display/KAFKA/Replication+tools#Replicationtools-4.ReassignPartitionsTool>
