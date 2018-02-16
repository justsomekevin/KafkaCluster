#!/bin/bash

#-------------- configureCA.sh --------------
#  Configures Easy-RSA's CA and generates
#  a key & cert pair for Logstash.
#  Written By    : Kevin Lee
#  Modified By   : Kevin Lee
#  Date Created  : 02/15/2018
#  Date Modified : 02/15/2018
#  Rev           : 1
#
#----------------------------------------------
#  Change History:
#  1 - Initial revision.
#

#Get path relative to this script
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
EASYRSA_DIR="$SCRIPT_DIR/easy-rsa/easyrsa3"
SECRETS_DIR="$SCRIPT_DIR/logstash/secrets"

#Parse command line args
if [ $# -ne 1 ]; then
	echo "Usage: $DIR/configureCA.sh <gateway ipaddr>"
	exit 0
fi

gatewayIP=$1

function buildCA {
	echo ">> Configuring CA for EasyRSA"
	cd $EASYRSA_DIR
	./easyrsa init-pki
	./easyrsa build-ca
	cd -
}

function genLogstashKeyAndCert {
	echo ">> Generating Logstash certificates"
	cd $EASYRSA_DIR
	./easyrsa --batch --dn-mode=org --req-c=US --req-st=CA --req-city=Sunnyvale --req-org=FortiExtender --req-email=example@fortinet.com --req-ou="Web Application Team" --req-cn=logstash gen-req logstash nopass
	./easyrsa --subject-alt-name="IP:$gatewayIP" sign-req server logstash
	cd -
}

function copyLogstashKeyAndCert {
	echo ">> Transferring Logstash certificates"
	cp $EASYRSA_DIR/pki/ca.crt $SECRETS_DIR/ca.crt
	cp $EASYRSA_DIR/pki/private/logstash.key $SECRETS_DIR/logstash.key
	cp $EASYRSA_DIR/pki/issued/logstash.crt $SECRETS_DIR/logstash.crt
}

buildCA
genLogstashKeyAndCert
copyLogstashKeyAndCert
