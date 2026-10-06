#!/usr/bin/env bash

# chat-run
#
# Execute shell commands from the clipboard and put their output back
# into the clipboard.
#
# Commands run:
#   - on the machine where chat-run is invoked
#   - from the current working directory
#   - with the exported environment inherited from the calling shell
#   - inside a pseudo-terminal connected directly to /dev/tty
#
# Before execution, the clipboard contents are syntax-checked with bash -n.
# A syntax error aborts execution and leaves the clipboard unchanged.
#
# The live terminal session is not filtered. The recorded PTY transcript is
# cleaned separately before being copied to the clipboard.
#
# Ctrl+C interrupts the running command; output produced before the
# interruption is still copied to the clipboard.

set -u
set -o pipefail

cmdfile="$(mktemp "${TMPDIR:-/tmp}/chat-run-command.XXXXXX")"
typescript="$(mktemp "${TMPDIR:-/tmp}/chat-run-typescript.XXXXXX")"
clean_output="$(mktemp "${TMPDIR:-/tmp}/chat-run-output.XXXXXX")"

cleanup() {
    rm -f "$cmdfile" "$typescript" "$clean_output"
}
trap cleanup EXIT

# Clipboard backend
if command -v wl-paste >/dev/null 2>&1 && command -v wl-copy >/dev/null 2>&1; then
    clipboard_read()  { wl-paste; }
    clipboard_write() { wl-copy; }
elif command -v xclip >/dev/null 2>&1; then
    clipboard_read()  { xclip -selection clipboard -o; }
    clipboard_write() { xclip -selection clipboard; }
elif command -v xsel >/dev/null 2>&1; then
    clipboard_read()  { xsel --clipboard --output; }
    clipboard_write() { xsel --clipboard --input; }
else
    echo "chat-run: no supported clipboard tool found" >&2
    echo "Install wl-clipboard, xclip, or xsel." >&2
    exit 1
fi

# This wrapper is intentionally terminal-oriented.
if [[ ! -r /dev/tty || ! -w /dev/tty ]]; then
    echo "chat-run: no usable controlling terminal (/dev/tty)" >&2
    exit 1
fi

# Read command from clipboard
if ! clipboard_read > "$cmdfile"; then
    echo "chat-run: failed to read the clipboard" >&2
    exit 1
fi

if [[ ! -s "$cmdfile" ]]; then
    echo "chat-run: clipboard is empty" >&2
    exit 1
fi

# Syntax check before execution.
if ! syntax_error="$(bash -n "$cmdfile" 2>&1)"; then
    echo "chat-run: clipboard contents are not valid Bash syntax; not executing" >&2
    if [[ -n "$syntax_error" ]]; then
        printf '%s\n' "$syntax_error" >&2
    fi
    exit 2
fi

echo "──── command ─────────────────────────────────────────────────────"
cat "$cmdfile"
echo
echo "──── output ──────────────────────────────────────────────────────"

# Execute inside a PTY. script(1) reads from and writes directly to the real
# controlling terminal, so interactive rendering is not passed through tee,
# sed, or any other filter. A separate output log is recorded for clipboard
# processing after the command has finished.
interrupted=0
trap 'interrupted=1' INT

CHAT_RUN_CMD_FILE="$cmdfile" \
script \
    --quiet \
    --flush \
    --return \
    --log-out "$typescript" \
    --command 'bash -i "$CHAT_RUN_CMD_FILE"' \
    </dev/tty >/dev/tty 2>/dev/tty
command_status=$?

trap - INT

# Remove script(1) bookkeeping lines, PTY carriage returns, and common ANSI
# SGR colour/style sequences from the clipboard copy only.
if ! sed \
    -e '1{/^Script started on /d;}' \
    -e '${/^Script done on /d;}' \
    "$typescript" \
    | tr -d '\r' \
    | sed $'s/\033\[[0-9;]*m//g' \
    > "$clean_output"
then
    echo >&2
    echo "chat-run: failed to clean captured output; clipboard not changed" >&2
    exit 1
fi

# script(1) leaves a separator newline even when the command produced no
# output. Treat whitespace-only capture as empty and put an explicit note in
# the clipboard instead.
if ! grep -q '[^[:space:]]' "$clean_output"; then
    printf '[chat-run: command produced no output; exit code %d]\n' \
        "$command_status" > "$clean_output"
fi

if ! clipboard_write < "$clean_output"; then
    echo >&2
    echo "chat-run: command finished, but writing to the clipboard failed" >&2
    exit 1
fi

echo "──────────────────────────────────────────────────────────────────"

if (( interrupted )) || (( command_status == 130 )); then
    echo "chat-run: interrupted; captured output copied to clipboard" >&2
else
    echo "chat-run: output copied to clipboard (exit code $command_status)" >&2
fi

exit "$command_status"
