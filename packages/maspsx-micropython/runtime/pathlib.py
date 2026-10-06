# Path.is_file() as maspsx uses it: follows symlinks, False on any error.

import os

_S_IFMT = 0o170000
_S_IFREG = 0o100000


class Path:
    def __init__(self, path):
        if not isinstance(path, str):
            raise NotImplementedError("pathlib: only str paths")
        self._path = path or "."

    def __str__(self):
        return self._path

    def is_file(self):
        try:
            return os.stat(self._path)[0] & _S_IFMT == _S_IFREG
        except (OSError, ValueError):
            return False
