# shutil.which() with CPython's POSIX semantics for a str command.

import os

_S_IFMT = 0o170000
_S_IFDIR = 0o040000


def _split(path):
    i = path.rfind("/") + 1
    head, tail = path[:i], path[i:]
    if head and head != "/" * len(head):
        head = head.rstrip("/")
    return head, tail


def _join(directory, name):
    if not directory or directory.endswith("/"):
        return directory + name
    return directory + "/" + name


def _usable(path):
    try:
        mode = os.stat(path)[0]
    except (OSError, ValueError):
        return False
    import _mplibc

    return _mplibc.access(path, _mplibc.X_OK) == 0 and mode & _S_IFMT != _S_IFDIR


def which(cmd, mode=None, path=None):
    if not isinstance(cmd, str) or mode is not None or path is not None:
        raise NotImplementedError("shutil.which: only which(str)")
    directory, cmd = _split(cmd)
    if directory:
        directories = [directory]
    else:
        search = os.getenv("PATH")
        if search is None:
            search = "/bin:/usr/bin"
        if not search:
            return None
        directories = search.split(":")
    seen = set()
    for directory in directories:
        if directory in seen:
            continue
        seen.add(directory)
        name = _join(directory, cmd)
        if _usable(name):
            return name
    return None
