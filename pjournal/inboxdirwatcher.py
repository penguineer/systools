#!/usr/bin/python3

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

import os
import signal
import sys
import time
import logging

WATCHPATH = "/home/tux/tmp/Camera/Cam1/"
WATCHPATH = "/home/tux/Projekte/systools/pjournal/"

MQTT_BROKER = "localhost"
MQTT_TOPIC = "INBOX/Watcher/Photo"


def signal_handler(sig, frame):
    "Exit program on 2nd time SIGINT, otherwise cancel execution loop"
    
    global running
    
    if sig == signal.SIGINT:
        if not running:
            print("SIGINT received, but should already be finished. Leaving now!")
            sys.exit(0)
    
    print("Interrupt signal received, cancel execution loop.")
    running = False


# The callback for when the client receives a CONNACK response from the server.
def on_connect(client, userdata, flags, rc):
    print("Connected with result code "+str(rc))

    # Subscribing in on_connect() means that if we lose the connection and
    # reconnect then subscriptions will be renewed.
    #client.subscribe("$SYS/#")


# The callback for when a PUBLISH message is received from the server.
def on_message(client, userdata, msg):
    print(msg.topic+" "+str(msg.payload))


class NewFilesHandler(watchdog.events.FileSystemEventHandler):
    def __init__(self, mqtt):
        self.mqtt = mqtt

    def on_created(self, event):
        
        if not event.is_directory:
            print("File created at " + event.src_path)
            
            payload = event.src_path
            self.mqtt.publish(MQTT_TOPIC, payload, qos=2)


if __name__ == "__main__":
    global running
    running = True
    
    signal.signal(signal.SIGINT, signal_handler)
    signal.signal(signal.SIGTERM, signal_handler)
    
    mqtt = paho.Client()
    mqtt.on_connect = on_connect
    mqtt.on_message = on_message
    
    mqtt.connect(MQTT_BROKER, 1883, 60)
    
    logging.basicConfig(level=logging.INFO,
                        format='%(asctime)s - %(message)s',
                        datefmt='%Y-%m-%d %H:%M:%S')
    event_handler = NewFilesHandler(mqtt)
    observer = Observer()
    observer.schedule(event_handler, WATCHPATH, recursive=True)
    observer.start()
    
    print("Starting the main loop.")
    
    while running:
        mqtt.loop()
        
    observer.stop()
    observer.join()
    
    mqtt.disconnect()

# kate: space-indent on; indent-width 4; mixedindent off; indent-mode python; indend-pasted-text false; remove-trailing-space off
