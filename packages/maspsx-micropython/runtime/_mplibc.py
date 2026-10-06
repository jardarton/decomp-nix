# libc calls MicroPython's os module lacks. Linux only: flag values are the
# generic Linux ones shared by x86_64 and aarch64.

import ffi
import os
import struct
import uctypes

_libc = ffi.open("libc.so.6")

isatty = _libc.func("i", "isatty", "i")
access = _libc.func("i", "access", "si")
_fork = _libc.func("i", "fork", "")
_execv = _libc.func("i", "execv", "sp")
_execvp = _libc.func("i", "execvp", "sp")
_dup2 = _libc.func("i", "dup2", "ii")
_open = _libc.func("i", "open", "sii")
_close = _libc.func("i", "close", "i")
_exit = _libc.func("v", "_exit", "i")
_waitpid = _libc.func("i", "waitpid", "ipi")
_mkstemp = _libc.func("i", "mkstemp", "p")
_pipe2 = _libc.func("i", "pipe2", "pi")
_read = _libc.func("l", "read", "ipl")
_write = _libc.func("l", "write", "ipl")
_errno_location = _libc.func("p", "__errno_location", "")

X_OK = 1
O_RDONLY = 0
O_WRONLY = 1
O_TRUNC = 0o1000
O_CLOEXEC = 0o2000000
EINTR = 4


def errno():
    return struct.unpack("i", uctypes.bytearray_at(_errno_location(), 4))[0]


def _check(result):
    if result < 0:
        raise OSError(errno())
    return result


def _argv(args):
    """Return (keep-alive list, NULL-terminated char*[] buffer)."""
    strings = [arg.encode() + b"\0" for arg in args]
    pointers = [uctypes.addressof(s) for s in strings] + [0]
    return strings, struct.pack("%dP" % len(pointers), *pointers)


def temporary_file(data=b""):
    """Create a file in TMPDIR holding data and return its path."""
    directory = os.getenv("TMPDIR") or "/tmp"
    template = bytearray(directory.encode() + b"/maspsx-XXXXXX\0")
    fd = _check(_mkstemp(template))
    _close(fd)
    path = bytes(template[:-1]).decode()
    if data:
        with open(path, "wb") as f:
            f.write(data)
    return path


def exec_with_stdin(path, args, stdin_path):
    """Replace this process with path, args; stdin from stdin_path if given."""
    if stdin_path is not None:
        fd = _check(_open(stdin_path, O_RDONLY, 0))
        os.remove(stdin_path)
        _check(_dup2(fd, 0))
        _close(fd)
    keep, argv = _argv(args)
    _execv(path, argv)
    raise OSError(errno())


def _waitpid_status(pid):
    status = bytearray(4)
    while _waitpid(pid, status, 0) < 0:
        if errno() != EINTR:
            raise OSError(errno())
    status = struct.unpack("i", status)[0]
    if status & 0x7F == 0:
        return (status >> 8) & 0xFF
    return -(status & 0x7F)


def run(args, stdin_data):
    """Run args (PATH lookup like execvp) with stdin_data on stdin.

    Return (stdout bytes, stderr bytes, returncode) with CPython's returncode
    convention. Output goes through temporary files, so no pipe can fill up.
    """
    paths = []
    try:
        for data in (stdin_data, b"", b""):
            paths.append(temporary_file(data))
        keep, argv = _argv(args)
        error_pipe = bytearray(8)
        _check(_pipe2(error_pipe, O_CLOEXEC))
        error_read, error_write = struct.unpack("ii", error_pipe)
        pid = _fork()
        if pid == 0:
            try:
                for target, (path, flags) in enumerate(
                    ((paths[0], O_RDONLY), (paths[1], O_WRONLY | O_TRUNC), (paths[2], O_WRONLY | O_TRUNC))
                ):
                    fd = _open(path, flags, 0)
                    if fd < 0 or _dup2(fd, target) < 0:
                        break
                    _close(fd)
                else:
                    _execvp(args[0], argv)
                _write(error_write, struct.pack("i", errno()), 4)
            finally:
                _exit(127)
        _close(error_write)
        if pid < 0:
            _close(error_read)
            raise OSError(errno())
        report = bytearray(4)
        received = _read(error_read, report, 4)
        _close(error_read)
        if received > 0:
            _waitpid_status(pid)
            raise OSError(struct.unpack("i", report)[0])
        returncode = _waitpid_status(pid)
        with open(paths[1], "rb") as f:
            stdout = f.read()
        with open(paths[2], "rb") as f:
            stderr = f.read()
        return stdout, stderr, returncode
    finally:
        for path in paths:
            os.remove(path)
