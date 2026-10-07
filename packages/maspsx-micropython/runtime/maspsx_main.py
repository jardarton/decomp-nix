# Run upstream maspsx (rewritten by rewrite.py) on MicroPython.
#
# The run either completes exactly as upstream main() would, or is handed in
# full to the CPython build before anything is written: all output is
# buffered until main() returns. A hand-off happens on any exception other
# than SystemExit, including MemoryError and the deliberate refusals in the
# compatibility modules, and on input that is not plain ASCII.
#
# The CPython build is named by MASPSX_CPYTHON, which bin/maspsx sets: these
# modules are frozen into an interpreter that is built before the package and
# cannot refer to it. Setting MASPSX_MICROPYTHON_NO_FALLBACK makes a hand-off
# exit with status 125 instead; the package tests use it to prove that runs
# take the fast path.

import sys

NO_FALLBACK_STATUS = 125


class Fallback(BaseException):
    pass


class _Buffer:
    def __init__(self, stream):
        self._stream = stream
        self._parts = []

    def write(self, text):
        if not isinstance(text, str):
            raise Fallback("non-str write")
        self._parts.append(text)
        return len(text)

    def flush(self):
        pass

    def drain(self):
        for part in self._parts:
            self._stream.write(part)
        self._parts = []


def _lines(data, universal_newlines):
    """Decode input like CPython: UTF-8, lines split at "\n".

    open() translates "\r\n" and "\r" to "\n"; sys.stdin does not on POSIX.
    """
    text = data.decode()
    if len(text) != len(data):
        raise Fallback("non-ASCII input")
    for c in "\x00\x1c\x1d\x1e\x1f":
        if c in text:
            raise Fallback("control character in input")
    if universal_newlines and "\r" in text:
        text = text.replace("\r\n", "\n").replace("\r", "\n")
    lines = text.split("\n")
    last = lines.pop()
    lines = [line + "\n" for line in lines]
    if last:
        lines.append(last)
    return lines


class _Stdin:
    def __init__(self):
        self.data = None

    def isatty(self):
        # Pipes and regular files are never terminals; only character devices
        # (a terminal, but also /dev/null) need isatty(3).
        import os

        try:
            if os.stat("/dev/stdin")[0] & 0o170000 != 0o020000:
                return False
        except OSError:
            pass
        import _mplibc

        return _mplibc.isatty(0) == 1

    def readlines(self):
        self.data = sys.stdin.buffer.read()
        return _lines(self.data, False)


class _File:
    def __init__(self, lines):
        self._lines = lines

    def __enter__(self):
        return self

    def __exit__(self, *exception):
        return False

    def readlines(self):
        return self._lines


def _open(path, mode="r", encoding=None, **options):
    if mode != "r" or options or encoding not in ("utf", "utf8", "utf-8", "UTF-8"):
        raise Fallback("open() arguments")
    with open(path, "rb") as f:
        return _File(_lines(f.read(), True))


class _Sys:
    def __init__(self):
        self.stdin = _Stdin()
        self.stdout = _Buffer(sys.stdout)
        self.stderr = _Buffer(sys.stderr)

    def __getattr__(self, name):
        return getattr(sys, name)


def _guarded(processor_class):
    # Upstream reports exceptions from process_lines() with their message,
    # which can differ between runtimes; hand those runs to CPython instead.
    class Guarded(processor_class):
        def process_lines(self):
            try:
                return processor_class.process_lines(self)
            except Exception:
                raise Fallback("exception in process_lines")

    return Guarded


def _run(proxy):
    import maspsx_cli

    maspsx_cli.sys = proxy
    maspsx_cli.open = _open
    maspsx_cli.MaspsxProcessor = _guarded(maspsx_cli.MaspsxProcessor)
    maspsx_cli.PassthroughProcessor = _guarded(maspsx_cli.PassthroughProcessor)
    try:
        maspsx_cli.main()
    except SystemExit as e:
        code = e.args[0] if e.args else None
        if code is not None and not isinstance(code, int):
            raise Fallback("non-integer exit status")
        return code
    return None


def _fallback(proxy, reason):
    import os

    cpython = os.getenv("MASPSX_CPYTHON")
    if os.getenv("MASPSX_MICROPYTHON_NO_FALLBACK") or not cpython:
        sys.stderr.write("maspsx: MicroPython fallback: %r\n" % (reason,))
        sys.exit(NO_FALLBACK_STATUS)

    import _mplibc

    stdin_path = None
    if proxy.stdin.data is not None:
        stdin_path = _mplibc.temporary_file(proxy.stdin.data)
    _mplibc.exec_with_stdin(cpython, [cpython] + sys.argv[1:], stdin_path)


def main():
    while "" in sys.path:
        sys.path.remove("")
    proxy = _Sys()
    try:
        code = _run(proxy)
    except KeyboardInterrupt:
        raise
    except BaseException as e:
        _fallback(proxy, e)
    proxy.stderr.drain()
    proxy.stdout.drain()
    if code:
        sys.exit(code)


main()
