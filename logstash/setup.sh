#!/bin/bash

#------------------ setup.sh ------------------
#  Sets up a Logstash Docker container
#  on a host machine and starts the container.
#  The host machine can be the gateway itself
#  or a remote machine, but this script is to
#  be run on the gateway machine specifically.
#
#  Usage:
#    Gateway as host: ./setup.sh
#    Remote machine as host: ./setup.sh <ip> <user>
#
#----------------------------------------------
#
#  Written By    : Kevin Lee
#  Modified By   : Kevin Lee
#  Date Created  : 02/05/2018
#  Date Modified : 02/12/2018
#  Rev           : 2
#
#----------------------------------------------
#  Change History:
#  1 - Initial revision.
#  2 - Added support for remote host.
#

gatewayIP='172.30.176.117'

#Get path relative to this script
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

#Parse command line args
if [ $# -eq 0 ]; then
    host='localhost'
else
    host=$1
    user=$2
fi

die() { echo "$*" 1>&2 ; exit 1; }

function getAvailablePort {
	for ((port=$2; port<=$3; port++)); do
		(echo >/dev/tcp/$1/$port)> /dev/null 2>&1 || break
        done
	echo $port
}

function verifyDockerInstallation {
	echo ">> Verifying docker installation..."
	which docker
	if [ $? -eq 0 ]; then
		echo '>> Docker installed.'
	else
		die ">> Docker not installed on $host. Install docker then try again."
	fi
}

function genLogstashName {
	name=logstash${port}${RANDOM}
	echo ">> Generated container name: $name"
}

function genKeyAndCert {
	echo ">> Generating certificates"
	cd $DIR/../easy-rsa/easyrsa3
	./easyrsa --batch --dn-mode=org --req-c=US --req-st=CA --req-city=Sunnyvale --req-org=FortiExtender --req-email=example@fortinet.com --req-ou="Web Application Team" --req-cn=$name gen-req $name nopass
	./easyrsa --subject-alt-name="IP:$host" sign-req server $name
	cd -
}

function setupLogstashLocal {
	
	verifyDockerInstallation

	genLogstashName

	echo ">> Creating logstash container"
	docker create --name $name --restart always -p $port:5044 logstash logstash -f /etc/logstash/logstash.conf

	genKeyAndCert

	echo ">> Copying files"
	mkdir $DIR/tmp_secrets
	cp $DIR/../easy-rsa/easyrsa3/pki/ca.crt $DIR/tmp_secrets/ca.crt
	cp $DIR/../easy-rsa/easyrsa3/pki/private/${name}.key $DIR/tmp_secrets/logstash.key
	cp $DIR/../easy-rsa/easyrsa3/pki/issued/${name}.crt $DIR/tmp_secrets/logstash.crt
	cp $DIR/secrets/kafka_client_jaas.conf $DIR/tmp_secrets/kafka_client_jaas.conf
	chmod 755 $DIR/tmp_secrets/*
	docker cp $DIR/logstash.conf $name:/etc/logstash
	docker cp $DIR/tmp_secrets $name:/etc/logstash/secrets
	rm -r $DIR/tmp_secrets

	echo ">> Starting logstash container"
	docker start $name

	echo ">> Wait for 10 seconds..."
	sleep 10

	docker ps -f name=$name
}

function setupLogstashRemote {

	#echo "Attempting to verify Docker installation on $host. Please enter password again."
	$SSH_CMD "$(typeset -f verifyDockerInstallation); verifyDockerInstallation"

	genLogstashName

	#echo "Creating logstash container. Please enter password again."
	$SSH_CMD "docker create --name $name --restart always -p $port:5044 logstash logstash -f /etc/logstash/logstash.conf"

	genKeyAndCert

	echo ">> Creating temporary dir on $host"
	$SSH_CMD "mkdir -p /tmp/logstash"
	
	echo ">> Copying files over to $host"
	$SCP_CMD $DIR/logstash.conf $user@$host:/tmp/logstash.conf
	$SCP_CMD $DIR/../easy-rsa/easyrsa3/pki/ca.crt $user@$host:/tmp/logstash/ca.crt
	$SCP_CMD $DIR/../easy-rsa/easyrsa3/pki/private/${name}.key $user@$host:/tmp/logstash/logstash.key
	$SCP_CMD $DIR/../easy-rsa/easyrsa3/pki/issued/${name}.crt $user@$host:/tmp/logstash/logstash.crt
	$SCP_CMD $DIR/secrets/kafka_client_jaas.conf $user@$host:/tmp/logstash/kafka_client_jaas.conf
	$SSH_CMD chmod 755 /tmp/logstash/*

	echo ">> Copying files into docker container"
	$SSH_CMD "
		docker cp /tmp/logstash.conf $name:/etc/logstash
		docker cp /tmp/logstash $name:/etc/logstash/secrets
	"
	
	echo ">> Deleting temporary files"
	$SSH_CMD "
		rm /tmp/logstash.conf
		rm -r /tmp/logstash
	"

	echo ">> Starting logstash container"
	$SSH_CMD docker start $name

	echo ">> Wait for 10 seconds..."
	sleep 10;
	$SSH_CMD docker ps -f name=$name
}

function establishMasterSSH {

	SSHSOCKET=~/.ssh/${user}@${host}
	SSH_CMD="ssh -o ControlPath=$SSHSOCKET -tt $user@$host"
	SCP_CMD="scp -o ControlPath=$SSHSOCKET"

	echo ">> Attempting to establish SSH connection to ${host}."
	#The options have the following meaning:
	#  -M instructs SSH to become the master, i.e. to create a master
	#   socket that will be used by the slave connections
	#  -f makes SSH to go into the background after the authentication
	#  -N tells SSH not to execute any command or to expect an input
	#   from the user; that’s good because we want it only to manage
	#   and keep open the master connection and nothing else
	#  -o ControlPath=$SSHSOCKET – this defines the name to be used
	#   for the socket that represents the master connection; the
	#   slaves will use the same value to connect via it
	#Thanks to -N and -f the SSH master connection will get out of the
	#way but will stay open and such usable by subsequent ssh/scp
	#invocations. This is exactly what we need in a shell script. 
	ssh -M -f -N -o ControlPath=$SSHSOCKET $user@$host
	if [ $? -eq 0 ]; then
		echo ">> Successfully connected to $host"
	else
		die ">> Unable to establish SSH connection to $host."
	fi
}

function main {

	echo ">> Setting up logstash on $host"
	if [ $host == 'localhost' ] || [ $host == $gatewayIP ]; then
	    host=$gatewayIP

	    #Assigns next available port to $port
	    port=`getAvailablePort localhost 5044 5444`
	    echo ">> Selected port: $port"

	    #Sets up logstash container
	    setupLogstashLocal

	else
	    establishMasterSSH

	    #Assigns next available port to $port
	    echo ">> Attempting to retrieve available port on $host."
	    port=`$SSH_CMD "$(typeset -f getAvailablePort); getAvailablePort localhost 5044 5444"`
	    port=`echo $port | sed 's/\\r//g'`	#strips trailing '\r' character
	    echo ">> Selected port: $port"

	    #Sets up logstash container on remote machine
	    setupLogstashRemote

	    #Close the master SSH connection
	    ssh -S $SSHSOCKET -O exit $user@$host
	fi
}

main






