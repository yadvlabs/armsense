#!/usr/bin/env python3
"""Drive the test VM's serial console over QEMU's unix socket.

usage: console.py [-t SECONDS] [-w PROMPT_REGEX] CMD...
Each CMD is sent followed by a newline; after the last one the script reads
until PROMPT_REGEX matches (default: a shell prompt '# ' or 'login: ') or the
timeout expires, and prints everything received.  Everything read is also
appended to serial-console.log.
"""
import os, re, socket, sys, time

here = os.path.dirname(os.path.abspath(__file__))
instance = os.environ.get("INSTANCE", "test")
sock_path = os.path.join(here, f"serial-{instance}.sock")
log_path = os.path.join(here, f"serial-console-{instance}.log")

timeout = 20.0
prompt = r"(\$ |# |login: |Password:|Enter an option: )$"
args = sys.argv[1:]
while args and args[0] in ("-t", "-w"):
    if args[0] == "-t":
        timeout = float(args[1])
    else:
        prompt = args[1]
    args = args[2:]

s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
s.connect(sock_path)
s.settimeout(0.5)

def drain(until=None, limit=timeout):
    buf = b""
    end = time.time() + limit
    while time.time() < end:
        try:
            chunk = s.recv(65536)
            if not chunk:
                break
            buf += chunk
            if until and re.search(until, buf.decode("utf-8", "replace").replace("\r", "")):
                break
        except socket.timeout:
            if until is None:
                break
    return buf

out = drain(limit=1.0)  # anything pending
for i, cmd in enumerate(args):
    s.sendall(cmd.encode() + b"\n")
    out += drain(until=prompt, limit=timeout) if i == len(args) - 1 else drain(until=prompt, limit=timeout)
text = out.decode("utf-8", "replace").replace("\r", "")
with open(log_path, "a") as f:
    f.write(text)
# strip ANSI escapes for readability
print(re.sub(r"\x1b\[[0-9;?]*[A-Za-z]", "", text))
