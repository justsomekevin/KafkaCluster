#!/usr/bin/env python
#
# Copyright 2016 Confluent Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

#
# Example Kafka Producer.
# Reads lines from stdin and sends to Kafka.
#

from confluent_kafka import Producer
import sys
#import time

if __name__ == '__main__':
    if len(sys.argv) != 3:
        sys.stderr.write('Usage: %s <bootstrap-brokers> <topic>\n' % sys.argv[0])
        sys.exit(1)

    broker = sys.argv[1]
    topic = sys.argv[2]

    if broker == 'internal':
        broker = '192.168.100.1:29092,192.168.100.10:29093,192.168.100.11:29094'
    if broker == 'external':
        broker = '172.30.176.117:29092'

    # Producer configuration
    # See https://github.com/edenhill/librdkafka/blob/master/CONFIGURATION.md
    conf = {
        'bootstrap.servers': broker,
        'sasl.mechanisms'  : 'PLAIN',
        'security.protocol': 'SASL_PLAINTEXT',
        'sasl.username'    : "confluent",
        'sasl.password'    : "confluent-secret"
    }

    # Create Producer instance
    p = Producer(**conf)

    # Optional per-message delivery callback (triggered by poll() or flush())
    # when a message has been successfully delivered or permanently
    # failed delivery (after retries).
    def delivery_callback(err, msg):
        if err:
            sys.stderr.write('%% Message failed delivery: %s\n' % err)
        else:
            sys.stderr.write('%% Message %s:%s delivered to %s [%d] @ %o\n' %
                             (msg.key(), msg.value(), msg.topic(), msg.partition(), msg.offset()))

    # Read lines from stdin, produce each line to Kafka
    for line in sys.stdin:
    #while True:
    #    line = sys.stdin.readline()
        try:
            item = line.split(':')
            if len(item) == 1:
                 # Produce line (without newline)
                p.produce(topic, value = item[0].rstrip(), callback=delivery_callback)
            else:
                # Produce line (without newline)
                p.produce(topic, key = item[0], value = item[1].rstrip(), callback=delivery_callback)

        except BufferError as e:
            sys.stderr.write('%% Local producer queue is full (%d messages awaiting delivery): try again\n' %
                             len(p))

        # Serve delivery callback queue.
        # NOTE: Since produce() is an asynchronous API this poll() call
        #       will most likely not serve the delivery callback for the
        #       last produce()d message.
        p.poll(0)
    #    time.sleep(0.1)

    # Wait until all messages have been delivered
    sys.stderr.write('%% Waiting for %d deliveries\n' % len(p))
    p.flush()
