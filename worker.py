"""Bounded, non-GUI reads for Konoview. No shell, disk cache or network access."""
import ctypes
import json
import math
import os
import re
import selectors
import signal
import subprocess
import sys
import time

CLIENT_BYTES = 1024 * 1024
PASTE_BYTES = 4096
MAX_WINDOWS = 128


class ReadFailure(Exception):
    pass


def child_setup():
    # Kill the producer even if the supervisor is forcibly killed/unloaded.
    parent = os.getppid()
    libc = ctypes.CDLL(None, use_errno=True)
    if libc.prctl(1, signal.SIGKILL, 0, 0, 0) != 0 or os.getppid() != parent or parent == 1:
        os._exit(125)


def bounded_read(argv, limit, seconds):
    deadline = time.monotonic() + seconds  # absolute, never extended by output
    process = None
    selector = selectors.DefaultSelector()
    data = bytearray()
    try:
        process = subprocess.Popen(argv, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                                   stderr=subprocess.DEVNULL, start_new_session=True,
                                   preexec_fn=child_setup)
        os.set_blocking(process.stdout.fileno(), False)
        selector.register(process.stdout, selectors.EVENT_READ)
        while True:
            left = deadline - time.monotonic()
            if left <= 0:
                raise ReadFailure("Timed out")
            if not selector.select(left):
                raise ReadFailure("Timed out")
            chunk = os.read(process.stdout.fileno(), min(16384, limit + 1 - len(data)))
            if not chunk:
                break
            data.extend(chunk)
            if len(data) > limit:
                raise ReadFailure("Reply too large")
        left = deadline - time.monotonic()
        if left <= 0:
            raise ReadFailure("Timed out")
        if process.wait(timeout=left) != 0:
            raise ReadFailure("Command failed")
        return bytes(data)
    except FileNotFoundError as error:
        raise ReadFailure("Required command unavailable") from error
    except (OSError, subprocess.TimeoutExpired) as error:
        raise ReadFailure("Command failed or timed out") from error
    finally:
        selector.close()
        if process is not None:
            # Also terminate descendants retaining the output pipe after exit.
            try:
                os.killpg(process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            process.wait()
            process.stdout.close()


def label(value, limit):
    if not isinstance(value, str):
        return ""
    return re.sub(r"[\x00-\x1f\x7f-\x9f\u202a-\u202e\u2066-\u2069]", " ", value[:limit])


def integer(value, default=0):
    return value if type(value) is int and abs(value) <= 2147483647 else default


def clients_reply(raw):
    source = json.loads(raw)
    if not isinstance(source, list):
        raise ReadFailure("Invalid window list")
    clients = []
    seen = set()
    for w in source:
        if not isinstance(w, dict) or w.get("mapped") is not True:
            continue
        address = w.get("address")
        size = w.get("size")
        workspace = w.get("workspace")
        if (not isinstance(address, str) or not re.fullmatch(r"0x[0-9a-fA-F]{1,16}", address)
                or address in seen or not isinstance(workspace, dict)
                or not isinstance(size, list) or len(size) != 2
                or any(type(n) not in (int, float) or not math.isfinite(n) or not 1 <= n <= 32768 for n in size)):
            continue
        seen.add(address)
        clients.append({"address": address, "pid": integer(w.get("pid")), "mapped": True,
                        "title": label(w.get("title"), 512), "class": label(w.get("class"), 256),
                        "workspace": {"id": integer(workspace.get("id")), "name": label(workspace.get("name"), 128)},
                        "size": size, "focusHistoryID": integer(w.get("focusHistoryID"), 2147483647)})
    clients.sort(key=lambda w: w["focusHistoryID"])
    return {"clients": clients[:MAX_WINDOWS], "total": len(clients)}


def run(mode, args):
    if mode == "paste" and args in (["clipboard"], ["primary"]):
        command = ["/usr/bin/wl-paste", "--no-newline", "--type", "text"]
        if args[0] == "primary":
            command.append("--primary")
        raw = bounded_read(command, PASTE_BYTES, 1.0)
        return {"text": label(raw.decode("utf-8", errors="replace"), 256)}
    if mode == "clients" and not args:
        return clients_reply(bounded_read(["/usr/bin/hyprctl", "clients", "-j"], CLIENT_BYTES, 1.5))
    if mode == "rounding" and not args:
        value = json.loads(bounded_read(["/usr/bin/hyprctl", "getoption", "decoration:rounding", "-j"], 4096, 1.5))
        return {"rounding": max(0, min(100, integer(value.get("int"))))}
    if mode == "rule" and len(args) == 1 and len(args[0]) <= 2048:
        result = bounded_read(["/usr/bin/hyprctl", "eval", args[0]], 4096, 1.5)
        if result.strip() != b"ok":
            raise ReadFailure("Layer rule failed")
        return {}
    raise ReadFailure("Invalid operation")


def main():
    def cancelled(*_):
        raise ReadFailure("Cancelled")
    signal.signal(signal.SIGTERM, cancelled)
    signal.signal(signal.SIGINT, cancelled)
    try:
        result = {"ok": True, "value": run(sys.argv[1], sys.argv[2:])}
    except (ReadFailure, ValueError, TypeError, KeyError, IndexError):
        # Never reflect command output / clipboard contents in errors.
        result = {"ok": False, "error": "Read failed (unavailable, oversized, invalid or timed out)"}
    print(json.dumps(result, ensure_ascii=True, separators=(",", ":")))


if __name__ == "__main__":
    main()
