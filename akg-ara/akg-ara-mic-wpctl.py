#!/usr/bin/env python3
#
# Capture volume key events from the AGK Ara USB microphone and set the
# matching microphone volume in wireplumber instead.
#
# Author: Stefan Haun <mail@tuxathome.de>

from evdev import InputDevice, list_devices, ecodes
import subprocess
import sys
import re

# Substring of the input device name as shown by evtest/lsinput
INPUT_NAME_MATCH = "C-Media Electronics Inc. AKG Ara USB Microphone"

# Substring of the PipeWire source name as shown by `wpctl status` under Sources
PW_SOURCE_NAME_MATCH = "AKG Ara USB Microphone Mono"

STEP = "5%"  # volume step

def run(cmd: list[str]) -> str:
    """Run a shell command and return stdout as text."""
    result = subprocess.run(cmd,
                            check=False,
                            text=True,
                            stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT)
    return result.stdout.strip()

def find_input_device() -> InputDevice:
    """Find the AKG Ara input device by name substring."""
    for path in list_devices():
        dev = InputDevice(path)
        if INPUT_NAME_MATCH in dev.name:
            return dev
    print(f"Error: could not find input device matching '{INPUT_NAME_MATCH}'", file=sys.stderr)
    sys.exit(1)


def find_pw_source_id() -> str:
    """
    Parse `wpctl status` and return the ID of the audio source whose name
    contains PW_SOURCE_NAME_MATCH.
    """
    status = run(["wpctl", "status"])
    lines = status.splitlines()

    in_audio = False
    in_sources = False

    for line in lines:
        stripped = line.strip()

        # Track top-level sections
        if stripped == "Audio":
            in_audio = True
            in_sources = False
            continue
        if stripped in ("Video", "Settings"):
            in_audio = False
            in_sources = False
            continue

        if not in_audio:
            continue

        # Enter / leave the Audio -> Sources section
        if "Sources:" in line:
            in_sources = True
            continue

        if in_sources and (stripped == "" or not stripped.startswith("│")):
            in_sources = False
            continue

        if not in_sources:
            continue

        # Matches lines like:
        # │      44. C920 PRO HD Webcam Analog Stereo    [vol: 1.00 MUTED]
        # │  *   96. AKG Ara USB Microphone Mono         [vol: 1.00 MUTED]
        m = re.match(r"^\s*│\s*(?:\*\s*)?(\d+)\.\s+(.*)$", line)
        if not m:
            continue

        source_id, rest = m.groups()
        if PW_SOURCE_NAME_MATCH in rest:
            return source_id

    print(
        f"Error: could not find PipeWire source matching '{PW_SOURCE_NAME_MATCH}'",
        file=sys.stderr,
    )
    sys.exit(1)

def handle_key(code: int, value: int, source_id: str) -> None:
    # value: 1=press, 0=release, 2=autorepeat
    if value != 1:
        return  # act only on key press

    if code == ecodes.KEY_VOLUMEUP:
        run(["wpctl", "set-volume", source_id, f"{STEP}+"])
    elif code == ecodes.KEY_VOLUMEDOWN:
        run(["wpctl", "set-volume", source_id, f"{STEP}-"])
    elif code in (ecodes.KEY_MICMUTE, ecodes.KEY_MUTE):
        run(["wpctl", "set-mute", source_id, "toggle"])

def main() -> int:
    # Resolve the PipeWire source ID at startup
    source_id = find_pw_source_id()
    print(f"Using PipeWire source ID: {source_id}")

    # Find the AKG Ara input device by name
    dev = find_input_device()
    print(f"Listening on {dev.path} ({dev.name})")

    # Grab the device so the events do not also reach the desktop/system
    try:
        dev.grab()
        print(f"Grabbed {dev.path} exclusively")

        try:
            for event in dev.read_loop():
                if event.type == ecodes.EV_KEY:
                    handle_key(event.code, event.value, source_id)
        except KeyboardInterrupt:
            print("Interrupted, shutting down gracefully.")
            return 130

    finally:
        try:
            dev.ungrab()
            print(f"Released {dev.path}")
        except OSError as e:
            print(e, file=sys.stderr)

    return 0

if __name__ == "__main__":
    sys.exit(main())
