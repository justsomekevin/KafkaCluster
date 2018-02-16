#!/usr/bin/env python
#

from confluent_kafka import Consumer, TopicPartition, KafkaError, KafkaException
import sys
import getopt
import json
from pprint import pformat

class myConsumer(Consumer):
    def __init__(self, topic, partitionID):
        #brokers = '192.168.100.1:29092,192.168.100.10:29093,192.168.100.11:29094'
        brokers = '172.30.176.117:29092'
        conf = {
            'bootstrap.servers'   : brokers,
            'group.id'            : 'mygroup',
            'session.timeout.ms'  : 6000,
            'default.topic.config': {'auto.offset.reset': 'smallest'},
            'sasl.mechanisms'     : 'PLAIN',
            'security.protocol'   : 'SASL_PLAINTEXT',
            'sasl.username'       : 'confluent',
            'sasl.password'       : 'confluent-secret'
        }
        super().__init__(**conf)
        tp = TopicPartition(topic, partitionID)
        self.assign([tp])

    def consume(self):
        try:
            while True:
                msg = self.poll(timeout=1.0)
                if msg is None:
                    continue
                if msg.error():
                    # Error or event
                    if msg.error().code() == KafkaError._PARTITION_EOF:
                        # End of partition event
                        sys.stderr.write('%% %s [%d] reached end at offset %d\n' %
                                         (msg.topic(), msg.partition(), msg.offset()))
                    elif msg.error():
                        # Error
                        raise KafkaException(msg.error())
                else:
                    # Proper message
                    sys.stderr.write('%% %s [%d] at offset %d with key %s:\n' %
                                     (msg.topic(), msg.partition(), msg.offset(),
                                      str(msg.key())))
                    print(msg.value())

        except KeyboardInterrupt:
            sys.stderr.write('%% Aborted by user\n')

        # Close down consumer to commit final offsets.
        self.close()

def main():
    if len(sys.argv) != 3:
        sys.stderr.write('Usage: %s <topic> <partition id>\n' % sys.argv[0])
        sys.exit(1)
    c = myConsumer(sys.argv[1], int(sys.argv[2]))
    c.consume()


if __name__ == '__main__':
    main()
