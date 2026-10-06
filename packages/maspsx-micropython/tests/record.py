"""Run upstream's unit tests on CPython and record what maspsx did.

Usage (from the maspsx source tree):
    python3 record.py PROCESSOR_JSON REGEX_JSON FLOAT_JSON

PROCESSOR_JSON lists every processor the tests ran: its class, constructor
arguments, and either its output or the exception type. REGEX_JSON lists every
distinct (pattern, subject) regular expression call with CPython's result.
FLOAT_JSON holds decimal strings in the forms cc1 and people write, with the
bits CPython's float() and struct.pack(">f") give them. replay.py repeats all
three on MicroPython.
"""

import json
import random
import re
import struct
import sys
import unittest

import maspsx

processor_records = []
regex_records = {}


def record_processor(cls):
    original_init = cls.__init__
    original_process_lines = cls.process_lines

    def __init__(self, lines, *args, **kwargs):
        self._record = {
            "class": cls.__name__,
            "lines": list(lines),
            "args": list(args),
            "kwargs": kwargs,
        }
        original_init(self, lines, *args, **kwargs)

    def process_lines(self):
        record = dict(self._record)
        processor_records.append(record)
        try:
            record["output"] = original_process_lines(self)
        except Exception as e:
            record["error"] = type(e).__name__
            raise
        return record["output"]

    cls.__init__ = __init__
    cls.process_lines = process_lines


class RecordingRe:
    def __getattr__(self, name):
        function = getattr(re, name)
        if name not in ("match", "search"):
            return function

        def call(pattern, string, *args):
            m = function(pattern, string, *args)
            if not args and isinstance(pattern, str) and isinstance(string, str):
                regex_records[(name, pattern, string)] = (
                    None if m is None else list(m.groups())
                )
            return m

        return call


def float_cases():
    rng = random.Random(0)
    values = [0.0, -0.0, 5e-324, 2.2250738585072014e-308, 1.7976931348623157e308,
              3.4028234663852886e38, 3.4028235677973366e38, 1.401298464324817e-45,
              -2.249769341647012e223, 6.03975371e79]
    for _ in range(5000):
        kind = rng.random()
        if kind < 0.4:
            value = struct.unpack(">d", struct.pack(">Q", rng.getrandbits(64)))[0]
        elif kind < 0.7:
            value = struct.unpack(">f", struct.pack(">I", rng.getrandbits(32)))[0]
        else:
            value = rng.randint(-10**6, 10**6) / rng.choice([1, 3, 7, 10, 1000])
        if value == value and abs(value) != float("inf"):
            values.append(value)
    cases = []
    for value in values:
        for text in ("%.20e" % value, repr(value), "%.8e" % value, "%.17g" % value):
            double = struct.unpack(">Q", struct.pack(">d", float(text)))[0]
            try:
                single = struct.unpack(">I", struct.pack(">f", float(text)))[0]
            except OverflowError:
                single = "OverflowError"
            cases.append({"text": text, "double": double, "single": single})
    for text in ("1e400", "-1e400", "1e-400", " 1.5 ", "+.5", "5.", "0e0", "1_0.5", "inf", "nan", "0x10", ""):
        try:
            double = struct.unpack(">Q", struct.pack(">d", float(text)))[0]
        except ValueError:
            double = "ValueError"
        cases.append({"text": text, "double": double, "single": None})
    return cases


def main():
    processor_path, regex_path, float_path = sys.argv[1:]
    record_processor(maspsx.MaspsxProcessor)
    record_processor(maspsx.PassthroughProcessor)
    maspsx.re = RecordingRe()

    suite = unittest.defaultTestLoader.discover("tests", top_level_dir=".")
    result = unittest.TextTestRunner(verbosity=1).run(suite)
    if not result.wasSuccessful():
        raise SystemExit("record.py: upstream tests failed")

    with open(processor_path, "w") as f:
        json.dump(processor_records, f)
    with open(regex_path, "w") as f:
        json.dump(
            [
                {"function": n, "pattern": p, "string": s, "groups": g}
                for (n, p, s), g in sorted(
                    regex_records.items(), key=lambda item: item[0]
                )
            ],
            f,
        )
    floats = float_cases()
    with open(float_path, "w") as f:
        json.dump(floats, f)
    print(
        f"record.py: {len(floats)} float strings, "
        f"{len(processor_records)} processor runs, "
        f"{len(regex_records)} regular expression calls"
    )


if __name__ == "__main__":
    main()
