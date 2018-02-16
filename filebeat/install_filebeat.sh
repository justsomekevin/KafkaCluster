#!/bin/bash

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

if [ "$(uname)" == "Darwin" ]; then
    curl -L -O https://artifacts.elastic.co/downloads/beats/filebeat/filebeat-6.1.3-darwin-x86_64.tar.gz
    tar xzvf filebeat-6.1.3-darwin-x86_64.tar.gz
    rm filebeat-6.1.3-darwin-x86_64.tar.gz
    mkdir -p /etc/filebeat/logs
    mkdir -p /etc/filebeat/conf
    echo -e $CONF > /etc/filebeat/conf/filebeat.yml
    cp $DIR/filebeat.yml /etc/filebeat/conf/
    cp $DIR/logstash.crt /etc/filebeat/conf/
elif [ "$(expr substr $(uname -s) 1 5)" == "Linux" ]; then
    curl -L -O https://artifacts.elastic.co/downloads/beats/filebeat/filebeat-6.1.3-amd64.deb
    dpkg -i filebeat-6.1.3-amd64.deb
    rm filebeat-6.1.3-amd64.deb
    mkdir -p /etc/filebeat/logs
    mkdir -p /etc/filebeat/conf
    cp $DIR/filebeat.yml /etc/filebeat/conf/
    cp $DIR/secrets/* /etc/filebeat/conf/
elif [ "$(expr substr $(uname -s) 1 10)" == "MINGW32_NT" ]; then
    # Do something under 32 bits Windows NT platform
    echo "Windows 32-bit unsupported"
elif [ "$(expr substr $(uname -s) 1 10)" == "MINGW64_NT" ]; then
    # Do something under 64 bits Windows NT platform
    echo "Windows 64-bit unsupported"
fi
