import socket
import base64
import struct
import os
import time
import subprocess
import sys
import threading

CONNECTION_COUNTS = [10, 100, 500, 1000]

def get_container_memory(container_name):
    """get memory usage of a docker container in MB"""
    try:
        result = subprocess.run(
            ["docker", "stats", container_name, "--no-stream", "--format", "{{.MemUsage}}"],
            capture_output=True, text=True, timeout=5
        )
        usage = result.stdout.strip().split("/")[0].strip()
        if "GiB" in usage:
            return float(usage.replace("GiB", "").strip()) * 1024
        elif "MiB" in usage:
            return float(usage.replace("MiB", "").strip())
        elif "KiB" in usage:
            return float(usage.replace("KiB", "").strip()) / 1024
        return 0
    except:
        return 0

def get_process_memory(pid):
    """get memory usage of a process in MB (macOS)"""
    try:
        result = subprocess.run(
            ["ps", "-o", "rss=", "-p", str(pid)],
            capture_output=True, text=True, timeout=5
        )
        kb = int(result.stdout.strip())
        return kb / 1024
    except:
        return 0

def find_zphp_pid():
    """find the zphp serve process"""
    try:
        result = subprocess.run(
            ["pgrep", "-f", "zphp serve"],
            capture_output=True, text=True, timeout=5
        )
        pids = result.stdout.strip().split("\n")
        return int(pids[0]) if pids[0] else None
    except:
        return None

def ws_connect(host, port):
    """connect a websocket client, return socket"""
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.settimeout(10)
    sock.connect((host, port))

    key = base64.b64encode(os.urandom(16)).decode()
    req = f"GET / HTTP/1.1\r\nHost: {host}\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: {key}\r\nSec-WebSocket-Version: 13\r\n\r\n"
    sock.send(req.encode())

    resp = b""
    while b"\r\n\r\n" not in resp:
        chunk = sock.recv(4096)
        if not chunk:
            raise ConnectionError("no handshake response")
        resp += chunk

    if b"101" not in resp:
        raise ConnectionError("handshake failed")

    # drain welcome frame if present
    idx = resp.index(b"\r\n\r\n") + 4
    extra = resp[idx:]
    if extra:
        # consume the welcome frame
        while len(extra) < 2:
            extra += sock.recv(4096)
        length = extra[1] & 0x7F
        hs = 2
        if length == 126: hs = 4
        elif length == 127: hs = 10
        total = hs + length
        while len(extra) < total:
            extra += sock.recv(4096)

    sock.settimeout(5)
    return sock

def ws_send_text(sock, msg):
    """send a masked text frame"""
    data = msg.encode() if isinstance(msg, str) else msg
    mask = os.urandom(4)
    frame = bytearray([0x81, 0x80 | len(data)]) + mask
    for i, b in enumerate(data):
        frame.append(b ^ mask[i % 4])
    sock.send(bytes(frame))

def ws_close(sock):
    """send close frame"""
    mask = os.urandom(4)
    payload = struct.pack("!H", 1000)
    frame = bytearray([0x88, 0x82]) + mask
    for i, b in enumerate(payload):
        frame.append(b ^ mask[i % 4])
    try:
        sock.send(bytes(frame))
    except:
        pass
    sock.close()

def batch_connect(host, port, count):
    """connect count websocket clients, return list of sockets"""
    sockets = []
    errors = 0
    lock = threading.Lock()

    def connect_one():
        nonlocal errors
        try:
            s = ws_connect(host, port)
            with lock:
                sockets.append(s)
        except Exception as e:
            with lock:
                errors += 1

    threads = []
    batch_size = min(50, count)
    for i in range(0, count, batch_size):
        batch = min(batch_size, count - i)
        for _ in range(batch):
            t = threading.Thread(target=connect_one)
            t.start()
            threads.append(t)
        for t in threads:
            t.join()
        threads = []

    return sockets, errors

def run_ws_bench(name, host, port, get_memory_fn, counts):
    print(f"\n  {name}:")
    print(f"  {'connections':>12s}  {'connected':>10s}  {'errors':>7s}  {'memory':>10s}  {'per conn':>10s}")

    baseline_mem = get_memory_fn()

    for target_count in counts:
        sockets, errors = batch_connect(host, port, target_count)
        connected = len(sockets)

        time.sleep(1)  # let memory settle

        current_mem = get_memory_fn()
        delta = current_mem - baseline_mem
        per_conn = (delta / connected * 1024) if connected > 0 and delta > 0 else 0

        print(f"  {target_count:>12d}  {connected:>10d}  {errors:>7d}  {current_mem:>8.1f}MB  {per_conn:>8.1f}KB")

        # close all
        for s in sockets:
            ws_close(s)
        time.sleep(0.5)

    print()

# find zphp pid
zphp_pid = find_zphp_pid()

# run benchmarks
print()

if zphp_pid:
    run_ws_bench(
        "zphp",
        "127.0.0.1", 9083,
        lambda: get_process_memory(zphp_pid),
        CONNECTION_COUNTS
    )
else:
    print("  zphp: not running, skipping")

# swoole
run_ws_bench(
    "swoole",
    "127.0.0.1", 9082,
    lambda: get_container_memory("swoole_ws"),
    CONNECTION_COUNTS
)
