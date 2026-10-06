# `struct` for maspsx on MicroPython. Packing a float as single precision
# raises OverflowError in CPython when the value rounds to infinity; MicroPython
# silently packs infinity. NaN payload handling also differs, so NaN raises
# and the launcher hands the run to CPython.

from struct import calcsize, unpack
import struct as _struct

_SINGLE_FORMATS = (">f", "<f", "!f", "=f", "f")
_INFINITY_BITS = (0x7F800000, 0xFF800000)


def pack(fmt, *values):
    if "f" in fmt or "e" in fmt:
        if fmt not in _SINGLE_FORMATS or len(values) != 1:
            raise NotImplementedError("_mpstruct: unsupported float format " + fmt)
        value = values[0]
        if value != value:
            raise NotImplementedError("_mpstruct: NaN")
        bits = unpack(">I", _struct.pack(">f", value))[0]
        if bits in _INFINITY_BITS and value not in (float("inf"), float("-inf")):
            raise OverflowError("float too large to pack with f format")
    return _struct.pack(fmt, *values)
