#!/usr/bin/python3

# Watch a directory and report changes to an MQTT topic.
#
# Author: Stefan Haun <tux@netz39.de>
#
# SPDX-License-Identifier: MIT
# License-Filename: LICENSES/MIT.txt

# https://pypi.python.org/pypi/paho-mqtt/1.3.1
# Debian: pip3 install paho-mqtt
import paho.mqtt.client as paho

# https://pythonhosted.org/watchdog/
# Debian: aptitude install python3-watchdog
import watchdog
from watchdog.observers import Observer
from watchdog.events import LoggingEventHandler

# https://pypi.python.org/pypi/ConfigArgParse
# Debian: aptitude install python3-configargparse
import configargparse

# https://docs.python.org/3/library/syslog.html
import syslog

import os
import signal
import sys
import time

def signal_handler(sig, frame):
    "Exit program on 2nd time SIGINT, otherwise cancel execution loop"
    
    global running
    
    if sig == signal.SIGINT:
        if not running:
            syslog.syslog("SIGINT received, but should already be finished. Leaving now!")
            sys.exit(1)
    
    syslog.syslog("Interrupt signal received, cancel execution loop.")
    running = False

def renderTopic(base, ext):
    topic = base if base[-1] != '/' else base[:-1];
    
    if ext[0] != '/':
        topic += '/'
    
    topic += ext;
    
    return topic


# The callback for when the client receives a CONNACK response from the server.
def on_connect(client, userdata, flags, rc):
    global mqtt_connected
    mqtt_connected = True
    
    syslog.syslog("Connected with result code "+str(rc))


def on_disconnect(client, userdata, rc):
    global running
    global mqtt_connected
    mqtt_connected = False

    syslog.syslog("Disconnected from broker.")

    # Do we really need this?
    # Seems that PAHO does not reconnect on its own …
    while running and not mqtt_connected:
        syslog.syslog("Reconnecting to broker.")
        
        try:
            time.sleep(1)
            client.reconnect()
            mqtt_connected = True
        except ConnectionRefusedError:
            timeout = 5
            syslog.syslog("Reconnect failed, waiting for " + str(timeout) + "s.")
            time.sleep(timeout)


# The callback for when a PUBLISH message is received from the server.
def on_message(client, userdata, msg):
    print(msg.topic+" "+str(msg.payload))


class NewFilesHandler(watchdog.events.FileSystemEventHandler):
    def __init__(self, mqtt, topic):
        self.mqtt = mqtt
        self.topic = topic

    def on_any_event(self, event):
        
        if not event.is_directory:
            payload = event.src_path
            self.mqtt.publish(renderTopic(self.topic,
                                          event.event_type),
                              payload, qos=2)


if __name__ == "__main__":
    global running
    running = True
    
    syslog.openlog("DirWatcher-" + str(os.getpid()))
    
    # Parse the configuration
    p = configargparse.ArgParser()
    p.add('-c', '--config', required=True, is_config_file=True,
          help = "Config file path")
    p.add('-b', '--broker', required=True,
          help = "MQTT broker host")
    p.add('-t', '--topic', required=True,
          help = "MQTT base topic")
    p.add('-p', '--path',
          help = "Path to watch")
    
    options = p.parse_args()
    
    syslog.syslog("Watching path " + options.path);
    
    signal.signal(signal.SIGINT, signal_handler)
    signal.signal(signal.SIGTERM, signal_handler)
    
    mqtt = paho.Client()
    mqtt.on_connect = on_connect
    mqtt.on_disconnect = on_disconnect
    mqtt.on_message = on_message
    
    try:
        mqtt.connect(options.broker, 1883, 60)
    except ConnectionRefusedError:
        syslog.syslog("Cannot connect to broker, exiting.")
        sys.exit(2)
    
    event_handler = NewFilesHandler(mqtt, options.topic)
    observer = Observer()
    observer.schedule(event_handler, options.path, recursive=True)
    observer.start()
    
    while running:
        mqtt.loop()
        
    observer.stop()
    observer.join()
    
    mqtt.disconnect()
    
    syslog.syslog("Shutdown.");
    syslog.closelog()

# kate: space-indent on; indent-width 4; mixedindent off; indent-mode python; indend-pasted-text false; remove-trailing-space off
