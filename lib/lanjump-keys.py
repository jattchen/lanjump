#!/usr/bin/env python3
"""Fallback Shift+Enter rewriter when the C helper is not compiled.

Reads STDIN/STDOUT only (never /dev/tty) so it can run inside `grok wrap`.

Apple Terminal: CR+Shift → CSI-u Shift+Enter.
Ghostty: CSI-u Shift+Enter → Alt+Enter (ESC CR). Grok often prints
"[13;2u" if that CSI-u sequence is passed through. ESC+CR is left as-is.
"""
from __future__ import print_function

import ctypes
import errno
import fcntl
import os
import pty
import select
import signal
import struct
import sys
import termios
import tty

CSI_S_ENTER = b"\x1b[13;2u"
ALT_ENTER = b"\x1b\r"
VK_SHIFT = 56
VK_RIGHT_SHIFT = 60
COMBINED = 0
ST_NORM, ST_ESC, ST_CSI = 0, 1, 2

_cg = None
_rw_st = ST_NORM
_csi = bytearray()


def _shift_down():
    global _cg
    if os.environ.get("LANJUMP_FORCE_SHIFT") == "1":
        return True
    if _cg is None:
        _cg = ctypes.CDLL(
            "/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics"
        )
        _cg.CGEventSourceKeyState.argtypes = [ctypes.c_uint32, ctypes.c_uint16]
        _cg.CGEventSourceKeyState.restype = ctypes.c_bool
    return _cg.CGEventSourceKeyState(COMBINED, VK_SHIFT) or _cg.CGEventSourceKeyState(
        COMBINED, VK_RIGHT_SHIFT
    )


def _csi_shift_enter(buf):
    if len(buf) < 6 or buf[0] != 0x5B or buf[-1] != 0x75:
        return False
    if not (buf[1] == 0x31 and buf[2] == 0x33 and buf[3] == 0x3B and buf[4] == 0x32):
        return False
    if len(buf) == 6:
        return True
    return len(buf) == 8 and buf[5] == 0x3B and buf[6] in (0x31, 0x32)


def _csi_final(b):
    return 0x40 <= b <= 0x7E


def _rewrite(data):
    global _rw_st, _csi
    if not data:
        return data
    out = bytearray()
    shift = None
    i = 0
    while i < len(data):
        b = data[i]
        if _rw_st == ST_NORM:
            if b == 0x1B:
                _rw_st = ST_ESC
                i += 1
                continue
            if b in (10, 13):
                if shift is None:
                    shift = _shift_down()
                if shift:
                    out.extend(CSI_S_ENTER)
                    i += 1
                    continue
            out.append(b)
            i += 1
            continue
        if _rw_st == ST_ESC:
            if b == 0x5B:
                _rw_st = ST_CSI
                _csi = bytearray(b"[")
                i += 1
                continue
            out.append(0x1B)
            _rw_st = ST_NORM
            if b == 0x1B:
                _rw_st = ST_ESC
                i += 1
                continue
            if b in (10, 13):
                out.append(b)
                i += 1
                continue
            continue
        if len(_csi) < 24:
            _csi.append(b)
        if len(_csi) == 24 or _csi_final(b):
            if _csi_shift_enter(_csi):
                out.extend(ALT_ENTER)
            else:
                out.append(0x1B)
                out.extend(_csi)
            _rw_st = ST_NORM
            _csi = bytearray()
        i += 1
    return bytes(out)


def _winsize(fd):
    try:
        return fcntl.ioctl(fd, termios.TIOCGWINSZ, b"\0" * 8)
    except OSError:
        return struct.pack("HHHH", 24, 80, 0, 0)


def _set_winsize(fd, packed):
    try:
        fcntl.ioctl(fd, termios.TIOCSWINSZ, packed)
    except OSError:
        pass


def main(argv):
    if len(argv) >= 2 and argv[1] == "--selftest":
        print("ok shift=%d" % (1 if _shift_down() else 0))
        return 0
    if len(argv) >= 2 and argv[1] == "--rewrite":
        while True:
            data = os.read(sys.stdin.fileno(), 512)
            if not data:
                return 0
            os.write(sys.stdout.fileno(), _rewrite(data))
        return 0
    if len(argv) < 2:
        print(
            "usage: lanjump-keys [--selftest|--rewrite] <command> [args...]",
            file=sys.stderr,
        )
        return 2

    in_fd = sys.stdin.fileno()
    if not os.isatty(in_fd):
        os.execvp(argv[1], argv[1:])

    orig = termios.tcgetattr(in_fd)
    child_pid = None
    master = None

    def restore(_signum=None, _frame=None):
        try:
            termios.tcsetattr(in_fd, termios.TCSANOW, orig)
        except termios.error:
            pass
        if _signum is not None and child_pid:
            try:
                os.kill(child_pid, _signum)
            except OSError:
                pass

    def on_winch(_signum, _frame):
        if master is not None:
            _set_winsize(master, _winsize(in_fd))

    signal.signal(signal.SIGTERM, restore)
    signal.signal(signal.SIGINT, restore)
    signal.signal(signal.SIGHUP, restore)
    signal.signal(signal.SIGWINCH, on_winch)

    master, slave = pty.openpty()
    _set_winsize(master, _winsize(in_fd))
    child_pid = os.fork()
    if child_pid == 0:
        os.close(master)
        os.setsid()
        fcntl.ioctl(slave, termios.TIOCSCTTY, 0)
        os.dup2(slave, 0)
        os.dup2(slave, 1)
        os.dup2(slave, 2)
        if slave > 2:
            os.close(slave)
        os.execvp(argv[1], argv[1:])
        os._exit(127)

    os.close(slave)
    tty.setraw(in_fd, termios.TCSANOW)
    status = 0
    try:
        while True:
            try:
                pid, status = os.waitpid(child_pid, os.WNOHANG)
            except OSError:
                break
            if pid == child_pid:
                child_pid = None
                break
            try:
                ready, _, _ = select.select([in_fd, master], [], [], 0.2)
            except InterruptedError:
                continue
            if in_fd in ready:
                try:
                    data = os.read(in_fd, 512)
                except OSError as exc:
                    if exc.errno == errno.EINTR:
                        continue
                    break
                if not data:
                    break
                try:
                    os.write(master, _rewrite(data))
                except OSError:
                    break
            if master in ready:
                try:
                    data = os.read(master, 512)
                except OSError as exc:
                    if exc.errno == errno.EINTR:
                        continue
                    break
                if not data:
                    break
                try:
                    os.write(sys.stdout.fileno(), data)
                except OSError:
                    break
    finally:
        restore()
        if child_pid is not None:
            try:
                _pid, status = os.waitpid(child_pid, 0)
            except OSError:
                pass

    if os.WIFEXITED(status):
        return os.WEXITSTATUS(status)
    if os.WIFSIGNALED(status):
        return 128 + os.WTERMSIG(status)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
