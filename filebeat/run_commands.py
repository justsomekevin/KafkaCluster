# -*- coding: utf-8 -*-

#-------------- run_commands.py --------------
#  Executes commands specified in a json file
#  and logs the output.
#
#  Written By    : Kevin Lee
#  Modified By   : Kevin Lee
#  Date Created  : 1/29/2018
#  Date Modified : 1/30/2018
#  Rev           : 2
#
#----------------------------------------------
#  Change History:
#  1 - Initial revision.
#  2 - Support more command line args
#      Allow single command, topic and logstash
#        params to be passed via command line 
#

from datetime import datetime   #to generate file name based on timestamp
import os
import sys
import argparse     #to handle command line arguments
import time         #to add time delay
import json         #to parse json files
import subprocess   #to generate subprocess for running bash commands
import shlex        #to parse shell-like syntax

VERSION = 2         #code version number
DEBUG = False       #debug mode

#-------------- parseArgs --------------
#  Parses command line arguments.
#  args: None
#  return:
#    (int) mode: 0 - version
#                1 - single command
#                2 - multiple commands (from file)
#    mode=0:
#      (None) command_args: None
#    mode=1:
#      (string) command: command to execute
#      (string) topic  : Kafka topic to publish to
#      (string) key    : Kafka key to publish with
#    mode=2:
#      (string) commands_file: name of commands .json file
#    (string, string, string) logstash_params
#      logstash_host    : Logstash host
#      logstash_port    : Logstash port number
#      logstash_shipper : Logstash shipper name
#
def parseArgs():
    parser = argparse.ArgumentParser(description='Run command(s) and dumps output into log file')
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument('-v', '--version', dest='version', action='store_const',
                    const=True, default=False,
                    help='version of script')
    group.add_argument('-c', '--command', dest='command', action='store',
                    default=None,
                    help='single command to execute')
    group.add_argument('-f', '--commands-file', dest='commands_file', action='store',
                    default=None,
                    help='json file consisting of commands to execute')
    parser.add_argument('-t', '--topic', dest='topic', action='store',
                    default=None,
                    help='topic to publish to')
    parser.add_argument('-k', '--key', dest='key', action='store',
                    default='',
                    help='key to publish with')
    parser.add_argument('-lh', '--logstash-host', dest='logstash_host', action='store',
                    default='172.30.176.117',
                    help='logstash host')
    parser.add_argument('-lp', '--logstash-port', dest='logstash_port', action='store',
                    default='5044',
                    help='logstash port')
    parser.add_argument('-ls', '--logstash-shipper', dest='logstash_shipper', action='store',
                    default='elastic',
                    help='logstash shipper')


    args = parser.parse_args()
    logstash_params = (args.logstash_host, args.logstash_port, args.logstash_shipper)

    if args.version:
        mode = 0
        return mode, None, logstash_params
    elif args.commands_file :
        mode = 2
        return mode, args.commands_file, logstash_params
    elif args.command:
        mode = 1
        return mode, (args.command, args.topic,args.key), logstash_params

    parser.print_usage()
    raise SystemExit()


#-------------- generateDumpFileName --------------
#  Generates a file name based on the current date
#  and time (format: YYYYMMDDhhmmss).
#  args:
#    (string) ext: extension
#  return:
#    (string) filename: generated file name
#
def generateDumpFileName(ext):
    return datetime.strftime(datetime.now(), "%Y%m%d%H%M%S") + ext


#-------------- configureFileBeat --------------
#  Initializes appropriate env vars and initiates
#  FileBeat with corresponding env vars.
#  args:
#    (string, string, string) logstash_params
#      logstash_host    : Logstash host
#      logstash_port    : Logstash port number
#      logstash_shipper : Logstash shipper name
#    (string) dump_file: File to dump command output
#      to and be picked up by FileBeat
#  return: None
#
def configureFileBeat(logstash_params, dump_file):
    host, port, shipper = logstash_params

    #Set env variables
    os.environ["LOGSTASH_HOST"] = host
    os.environ["LOGSTASH_PORT"] = port
    os.environ["SHIPPER_NAME"] = shipper
    os.environ["DUMP_FILE"] = dump_file

    try:
        if DEBUG:
            command = 'echo $LOGSTASH_HOST $LOGSTASH_PORT $DUMP_FILE'
            output = os.system(command)
            print(output)

        #Start FileBeat
        command = 'filebeat -c filebeat.yml --path.config /etc/filebeat/conf'
        process = subprocess.Popen(command.split(), stdout=subprocess.PIPE)
        #process = subprocess.Popen(shlex.split(command), stdout=subprocess.PIPE)
        #output, error = process.communicate()
        #print("PID:", process.pid)
        #return process.pid
        return process

    except OSError as err:
        raise SystemExit(err)


#-------------- loadFromJSON --------------
#  Loads a value from a JSON data structure.
#  args:
#    json_data: JSON data structure
#    parameter: name of key/parameter
#    default  : default value if parameter
#      cannot be read
#  return:
#    (any) value: value read or default value
#
def loadFromJSON(json_data, parameter, default):
    if parameter in json_data:
        return json_data[parameter]
    return default


def processSingleCommand(command, topic, key, dump_file):

    try:
        process = subprocess.Popen(command.split(), stdout=subprocess.PIPE)
        #process = subprocess.Popen(shlex.split(command), stdout=subprocess.PIPE)
        while True:
            output = process.stdout.readline()
            #print output.encode('string-escape')
            if output == '' and process.poll() is not None:
                break
            if output:
                data = {
                    "topicId" : topic,
                    "key"     : key,
                    "message" : output,
                    #"message" : output.encode('string-escape'),
                }

                with open(dump_file, 'a') as outfile:
                    json.dump(data, outfile)
                    outfile.write('\n')
        rc = process.poll()
        return rc
    except OSError as err:
        raise SystemExit(err)


def processCommandsFromFile(commands_file, dump_file):

    try:
        json_data = json.load(open(commands_file))
    except IOError as err:
        raise SystemExit(err)


    defaultTopic = loadFromJSON(json_data, "DEFAULT_TOPIC", "MyTopic")
    defaultKey   = loadFromJSON(json_data, "DEFAULT_KEY", "MyKey")
    msDelay      = loadFromJSON(json_data, "MS_DELAY", 0.0)
    commands     = loadFromJSON(json_data, "COMMANDS", [])

    for command in commands:
        if "cmd" not in command:
            continue

        topicId = loadFromJSON(command, "topicId", defaultTopic)
        key     = loadFromJSON(command, "key", defaultKey)

        processSingleCommand(command["cmd"], topicId, key, dump_file)

        if msDelay > 0:
            time.sleep(msDelay * 1.0 / 1000)


def main():
    mode, cmd_args, logstash_params = parseArgs()

    if mode == 0:
        raise SystemExit("Version: " + str(VERSION))

    dump_file = '/etc/filebeat/logs/' + generateDumpFileName(ext=".log")

    #Configure and start a FileBeat process
    process = configureFileBeat(logstash_params, dump_file)

    try:
        if mode == 1:
            command, topic, key = cmd_args
            processSingleCommand(command, topic, key, dump_file)

        elif mode == 2:
            commands_file = cmd_args
            processCommandsFromFile(commands_file, dump_file)
        else:
            print("Unknown mode="+mode)
    except KeyboardInterrupt:
        print("\nInterrupted by user")

    
    #Allow time for FileBeat to transmit logs before killing FileBeat
    secondsUntilTerminate = 10
    start = time.time()
    print(str(secondsUntilTerminate) + " seconds until FileBeat terminates")
    while(time.time() - start < secondsUntilTerminate):
        try:
            time.sleep(secondsUntilTerminate)
        except KeyboardInterrupt:
            print("This process cannot be interrupted")

    #Kill FileBeat process
    if DEBUG:
        print("Killing FileBeat process")
    process.kill()
    print("FileBeat terminated")


if __name__ == "__main__":
    main()


