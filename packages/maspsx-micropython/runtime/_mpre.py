# `re` for maspsx on MicroPython, restricted to patterns whose meaning is the
# same in CPython's re and MicroPython's re1.5 engine.
#
# Differences handled here:
# - CPython's `$` also matches before a final newline; a trailing `$` is
#   rewritten to `\n?$`, which accepts exactly the same positions.
# - MicroPython match objects lack multi-argument group() and groups().
# Any other construct raises, which makes the launcher hand the whole run to
# CPython. Input is ASCII without \x00 or \x1c-\x1f (enforced by the
# launcher), so \d, \s and \w agree between the engines.

import re as _re

_ESCAPES = "dDsSwW.^$|?*+()[]\\"
_CLASS_ESCAPES = "^$.()[]\\-"
_QUANTIFIERS = "*+?"

_cache = {}


class UnsupportedPattern(Exception):
    pass


def _translate(pattern):
    """Return (compiled, group count, whether `$` was rewritten)."""
    if not isinstance(pattern, str):
        raise UnsupportedPattern(pattern)
    n = len(pattern)
    groups = 0
    depth = 0
    dollar = False
    out = []
    # What the previous token was: None (start, "(" or "|"), "atom", "group"
    # or "quantifier".
    previous = None
    i = 0
    while i < n:
        c = pattern[i]
        if c == "\\":
            if i + 1 >= n or pattern[i + 1] not in _ESCAPES:
                raise UnsupportedPattern(pattern)
            out.append(pattern[i : i + 2])
            i += 2
            previous = "atom"
        elif c == "[":
            j = i + 1
            if j < n and pattern[j] == "^":
                j += 1
            if j >= n or pattern[j] in "]-":
                raise UnsupportedPattern(pattern)
            while j < n and pattern[j] != "]":
                if pattern[j] == "\\":
                    if j + 1 >= n or pattern[j + 1] not in _CLASS_ESCAPES:
                        raise UnsupportedPattern(pattern)
                    j += 2
                elif pattern[j] in "[&~|" or pattern[j : j + 2] == "--":
                    raise UnsupportedPattern(pattern)
                else:
                    j += 1
            if j >= n or pattern[j - 1] == "-":
                raise UnsupportedPattern(pattern)
            out.append(pattern[i : j + 1])
            i = j + 1
            previous = "atom"
        elif c == "(":
            if pattern.startswith("(?:", i):
                out.append("(?:")
                i += 3
            elif pattern.startswith("(?", i):
                raise UnsupportedPattern(pattern)
            else:
                groups += 1
                out.append("(")
                i += 1
            depth += 1
            previous = None
        elif c == ")":
            if depth == 0 or previous is None:
                raise UnsupportedPattern(pattern)
            depth -= 1
            out.append(")")
            i += 1
            previous = "group"
        elif c == "|":
            if previous is None:
                raise UnsupportedPattern(pattern)
            out.append("|")
            i += 1
            previous = None
        elif c in _QUANTIFIERS:
            if previous not in ("atom", "group") or (previous == "group" and c != "?"):
                raise UnsupportedPattern(pattern)
            if i + 1 < n and pattern[i + 1] == "?":
                out.append(pattern[i : i + 2])
                i += 2
            else:
                out.append(c)
                i += 1
            if i < n and pattern[i] in "*+{":
                raise UnsupportedPattern(pattern)
            previous = "quantifier"
        elif c == "^":
            if i != 0:
                raise UnsupportedPattern(pattern)
            out.append("^")
            i += 1
        elif c == "$":
            if i != n - 1:
                raise UnsupportedPattern(pattern)
            out.append("\n?$")
            dollar = True
            i += 1
        elif c in "{}" or ord(c) < 0x20 or ord(c) > 0x7E:
            raise UnsupportedPattern(pattern)
        else:
            out.append(c)
            i += 1
            previous = "atom"
    if depth != 0 or (previous is None and not dollar):
        raise UnsupportedPattern(pattern)
    return _re.compile("".join(out)), groups, dollar


def _prepare(pattern, flags):
    if flags:
        raise UnsupportedPattern(pattern)
    entry = _cache.get(pattern)
    if entry is None:
        entry = _cache[pattern] = _translate(pattern)
    return entry


class _Match:
    def __init__(self, match, groups, dollar):
        self._match = match
        self._groups = groups
        self._dollar = dollar

    def _group(self, index):
        if not isinstance(index, int) or index < 0 or index > self._groups:
            raise IndexError("no such group")
        if index == 0 and self._dollar:
            raise UnsupportedPattern("group 0 may include a rewritten newline")
        return self._match.group(index)

    def group(self, *indices):
        if len(indices) == 1:
            return self._group(indices[0])
        if not indices:
            return self._group(0)
        return tuple(self._group(i) for i in indices)

    def groups(self, default=None):
        result = []
        for i in range(1, self._groups + 1):
            value = self._match.group(i)
            result.append(default if value is None else value)
        return tuple(result)

    def __getitem__(self, index):
        return self._group(index)


def _check_subject(string):
    if not isinstance(string, str):
        raise UnsupportedPattern(string)


def match(pattern, string, flags=0):
    compiled, groups, dollar = _prepare(pattern, flags)
    _check_subject(string)
    m = compiled.match(string)
    return None if m is None else _Match(m, groups, dollar)


def search(pattern, string, flags=0):
    compiled, groups, dollar = _prepare(pattern, flags)
    _check_subject(string)
    m = compiled.search(string)
    return None if m is None else _Match(m, groups, dollar)
