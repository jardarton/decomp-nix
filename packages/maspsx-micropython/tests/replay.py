# Replay record.py's recordings on MicroPython and compare with CPython.
#
# Usage: MICROPYPATH=<library> micropython replay.py PROCESSOR_JSON REGEX_JSON FLOAT_JSON
#
# A processor run must give CPython's output, or raise where CPython raised
# (the launcher then hands the run to CPython). Raising where CPython did not
# is reported too: it would be correct but slow, and upstream's own tests
# should never need the fallback.

import json
import sys

import _mpfloat
import _mpre
import _mpstruct
import maspsx
import struct


def ascii_only(lines):
    for line in lines:
        if len(line.encode()) != len(line):
            return False
        for c in "\x00\x1c\x1d\x1e\x1f":
            if c in line:
                return False
    return True


def replay_processors(path):
    with open(path) as f:
        records = json.load(f)
    failures = 0
    skipped = 0
    for i, record in enumerate(records):
        if not ascii_only(record["lines"]):
            skipped += 1
            continue
        cls = getattr(maspsx, record["class"])
        try:
            output = cls(record["lines"], *record["args"], **record["kwargs"]).process_lines()
            error = None
        except Exception as e:
            output = None
            error = e
        if "error" in record:
            if error is None:
                print("processor %d: CPython raised %s, MicroPython did not" % (i, record["error"]))
                failures += 1
        elif error is not None:
            print("processor %d: MicroPython raised %r" % (i, error))
            failures += 1
        elif output != record["output"]:
            print("processor %d: output differs" % i)
            for a, b in zip(record["output"], output):
                if a != b:
                    print("  CPython:     %r\n  MicroPython: %r" % (a, b))
                    break
            else:
                print("  lengths %d and %d" % (len(record["output"]), len(output)))
            failures += 1
    print("replay.py: %d processor runs, %d non-ASCII skipped, %d failures" % (len(records), skipped, failures))
    return failures


def replay_regexes(path):
    with open(path) as f:
        records = json.load(f)
    failures = 0
    for record in records:
        function = getattr(_mpre, record["function"])
        try:
            m = function(record["pattern"], record["string"])
            groups = None if m is None else list(m.groups())
        except Exception as e:
            print("regex %r on %r: MicroPython raised %r" % (record["pattern"], record["string"], e))
            failures += 1
            continue
        if groups != record["groups"]:
            print(
                "regex %r on %r: CPython %r, MicroPython %r"
                % (record["pattern"], record["string"], record["groups"], groups)
            )
            failures += 1
    print("replay.py: %d regular expression calls, %d failures" % (len(records), failures))
    return failures


def replay_floats(path):
    # Unsupported spellings (inf, nan, underscores) must raise so the run
    # falls back; plain decimals must give CPython's bits exactly.
    with open(path) as f:
        records = json.load(f)
    failures = 0
    for record in records:
        try:
            value = _mpfloat.parse(record["text"])
        except ValueError:
            continue
        double = struct.unpack(">Q", struct.pack(">d", value))[0]
        if record["double"] != double:
            print("float %r: CPython %r, MicroPython %r" % (record["text"], record["double"], double))
            failures += 1
            continue
        if record["single"] is None:
            continue
        try:
            single = struct.unpack(">I", _mpstruct.pack(">f", value))[0]
        except OverflowError:
            single = "OverflowError"
        if record["single"] != single:
            print("single %r: CPython %r, MicroPython %r" % (record["text"], record["single"], single))
            failures += 1
    print("replay.py: %d float strings, %d failures" % (len(records), failures))
    return failures


def main():
    processor_path, regex_path, float_path = sys.argv[1:]
    failures = (
        replay_processors(processor_path)
        + replay_regexes(regex_path)
        + replay_floats(float_path)
    )
    if failures:
        sys.exit(1)


main()
