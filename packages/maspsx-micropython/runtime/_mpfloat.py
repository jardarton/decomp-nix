# Correctly rounded decimal-to-double conversion. MicroPython's float() can be
# off by one unit in the last place, and maspsx packs parsed values into
# instruction immediates. Only plain decimal literals are accepted; anything
# else (inf, nan, underscores, non-strings) raises and the launcher hands the
# run to CPython.

import struct

_WHITESPACE = " \t\n\r\x0b\x0c"
_DIGITS = "0123456789"


def _scan_digits(text, i):
    start = i
    while i < len(text) and text[i] in _DIGITS:
        i += 1
    return text[start:i], i


def _bit_length(n):
    # MicroPython integers have no bit_length().
    return len(bin(n)) - 2


def _bits_to_float(bits):
    return struct.unpack(">d", struct.pack(">Q", bits))[0]


def parse(value):
    if not isinstance(value, str):
        raise ValueError("_mpfloat only parses strings")
    text = value.strip(_WHITESPACE)
    i = 0
    negative = False
    if i < len(text) and text[i] in "+-":
        negative = text[i] == "-"
        i += 1
    whole, i = _scan_digits(text, i)
    fraction = ""
    if i < len(text) and text[i] == ".":
        fraction, i = _scan_digits(text, i + 1)
    if not whole and not fraction:
        raise ValueError("could not convert string to float")
    exponent = 0
    if i < len(text) and text[i] in "eE":
        i += 1
        exponent_negative = False
        if i < len(text) and text[i] in "+-":
            exponent_negative = text[i] == "-"
            i += 1
        digits, i = _scan_digits(text, i)
        if not digits:
            raise ValueError("could not convert string to float")
        exponent = int(digits)
        if exponent_negative:
            exponent = -exponent
    if i != len(text):
        raise ValueError("could not convert string to float")

    sign = 1 << 63 if negative else 0
    mantissa_digits = (whole + fraction).lstrip("0")
    if not mantissa_digits:
        return _bits_to_float(sign)
    exponent -= len(fraction)
    # The value is mantissa * 10**exponent, with mantissa < 10**len(digits).
    magnitude = len(mantissa_digits) - 1 + exponent
    if magnitude >= 309:
        return _bits_to_float(sign | 0x7FF << 52)
    if magnitude <= -325:
        return _bits_to_float(sign)

    numerator = int(mantissa_digits)
    denominator = 1
    if exponent >= 0:
        numerator *= 10**exponent
    else:
        denominator = 10**-exponent

    # Find e with 2**52 <= numerator / denominator / 2**e < 2**53.
    e = _bit_length(numerator) - _bit_length(denominator) - 53
    while True:
        if e >= 0:
            q, r = divmod(numerator, denominator << e)
            d = denominator << e
        else:
            q, r = divmod(numerator << -e, denominator)
            d = denominator
        if q >= 1 << 53:
            e += 1
        elif q < 1 << 52:
            e -= 1
        else:
            break

    if e < -1074:
        # Subnormal: fix the exponent and accept fewer significant bits.
        e = -1074
        q, r = divmod(numerator << 1074, denominator)
        d = denominator

    # Round half to even.
    if 2 * r > d or (2 * r == d and q & 1):
        q += 1
        if q == 1 << 53:
            q >>= 1
            e += 1

    if q < 1 << 52:
        return _bits_to_float(sign | q)
    biased = e + 52 + 1023
    if biased >= 0x7FF:
        return _bits_to_float(sign | 0x7FF << 52)
    return _bits_to_float(sign | biased << 52 | (q - (1 << 52)))
