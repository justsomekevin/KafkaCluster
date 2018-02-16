#!/bin/bash

#Get path relative to this script
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

die() { echo "$*" 1>&2 ; exit 1; }

function genFileBeatName {
	name=filebeat${RANDOM}
	echo ">> Generated container name: $name"
}

function genKeyAndCert {
	echo ">> Generating key and certificate"
	cd $DIR/../easy-rsa/easyrsa3
	./easyrsa gen-req $name nopass
	./easyrsa sign-req client $name
	cd -
}

function main {

	genFileBeatName
	genKeyAndCert
}

main






