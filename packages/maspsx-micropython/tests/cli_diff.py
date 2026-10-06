"""Compare the MicroPython maspsx command with the CPython one, end to end.

Usage: python3 cli_diff.py FAST CPYTHON PROCESSOR_JSON [INPUT_FILE_OR_DIR]...

Every case runs both commands with the same arguments and stdin and compares
stdout, stderr, exit status and the object file, if one is written. The fast
command is run with MASPSX_MICROPYTHON_NO_FALLBACK set first: a case must stay
on MicroPython unless it is expected to fall back, or CPython itself failed
with "MASPSX: An exception occurred" (an error path that falls back by
design). Cases expected to fall back must do so, and are then compared through
the real fallback.

Inputs are the bundled synthetic files below, the assembly upstream's unit
tests feed maspsx (from record.py), and any INPUT files or directories.
"""

import concurrent.futures
import json
import os
import subprocess
import sys
import tempfile

NO_FALLBACK = "MASPSX_MICROPYTHON_NO_FALLBACK"
NO_FALLBACK_STATUS = 125
OBJECT = "@OBJECT@"

VERSIONS = [None, "1.05", "2.05", "2.21", "2.34", "2.56", "2.67", "2.77", "2.81", "2.86"]
FLAG_SETS = [
    [],
    ["--expand-div"],
    ["--dont-expand-li"],
    ["--use-comm-section"],
    ["--use-comm-section", "--use-comm-for-lcomm"],
]

FUNCTION_START = """\t.file\t1 "synthetic.c"
\t.text
\t.align\t2
\t.globl\tf
\t.ent\tf
f:
\t.frame\t$sp,0,$31
\t.mask\t0x00000000,0
\t.fmask\t0x00000000,0
"""
FUNCTION_END = "\tj\t$31\n\t.end\tf\n"

BSS_SYMBOLS = [
    ("zeta", 4, "lcomm"), ("alpha", 2, "lcomm"), ("mid", 8, "comm"),
    ("big_array", 64, "lcomm"), ("b1", 1, "lcomm"), ("q9", 16, "comm"),
    ("x1", 4, "comm"), ("sym_10", 12, "lcomm"), ("sym_2", 3, "lcomm"),
    ("foo", 128, "comm"), ("bar", 6, "lcomm"), ("baz", 4, "lcomm"),
    ("a", 1, "comm"), ("table", 256, "lcomm"), ("p", 8, "lcomm"),
]


def synthetic_inputs():
    body = []
    for i, (name, size, _) in enumerate(BSS_SYMBOLS):
        register = 2 + i % 20
        body.append(f"\tlw\t${register},{name}\n" if size >= 4 else f"\tlb\t${register},{name}\n")
        if size >= 8:
            body.append(f"\tsw\t${register},{name}+4\n")
        body.append(f"\tla\t${register},{name}\n")
    body.append("\tli\t$2,0x12345678\n\taddu\t$2,$2,$4\n\tlw\t$3,0($2)\n\taddu\t$4,$3,$3\n")
    body.append("\tdiv\t$2,$3,$4\n\tmflo\t$5\n\tmult\t$5,$6\n\tmfhi\t$7\n")
    bss = "".join(f"\t.{kind}\t{name},{size}\n" for name, size, kind in BSS_SYMBOLS)
    sdata = "\t.sdata\n\t.align\t2\nsmall:\n\t.word\t1\n\t.size\tsmall,4\n"
    bss_text = FUNCTION_START + "".join(body) + FUNCTION_END + bss + sdata

    floats = [
        "1.00000000000000000000e+00", "-1.23450000000000000000e+00",
        "1.10000002384185791016e-01", "3.40282346638528859812e+38",
        "1.40129846432481707092e-45", "-2.249769341647012e+223", "6.03975371e+79",
        "2.22507385850720138309e-308", "4.94065645841246544177e-324", "0.0", "-0.0",
    ]
    float_text = FUNCTION_START
    for i, value in enumerate(floats):
        float_text += f"\tli.s\t${2 + i % 20},{value}\n" if abs(float(value)) < 3.5e38 else ""
        float_text += f"\tli.d\t${2 + 2 * (i % 10)},{value}\n"
    float_text += FUNCTION_END
    single_overflow = FUNCTION_START + "\tli.s\t$4,3.50000000000000000000e+38\n" + FUNCTION_END

    crlf = bss_text.replace("\n", "\r\n")
    return {
        "bss.s": (bss_text.encode(), False),
        "floats.s": (float_text.encode(), False),
        "single-overflow.s": (single_overflow.encode(), False),
        "crlf.s": (crlf.encode(), False),
        "cr.s": (bss_text.replace("\n", "\r").encode(), False),
        "no-final-newline.s": (bss_text.rstrip("\n").encode(), False),
        "empty-lines.s": (b"\n\n\n", False),
        "non-ascii.s": ((FUNCTION_START + "\t# café\n" + FUNCTION_END).encode(), True),
        "invalid-utf8.s": ((FUNCTION_START + FUNCTION_END).encode() + b"\t# \xff\n", True),
        "control.s": ((FUNCTION_START + "\t# \x1c\n" + FUNCTION_END).encode(), True),
        "nul.s": ((FUNCTION_START + "\t# \x00\n" + FUNCTION_END).encode(), True),
    }


def recorded_inputs(path):
    with open(path) as f:
        records = json.load(f)
    inputs = {}
    for record in records:
        text = "".join(line if line.endswith("\n") else line + "\n" for line in record["lines"])
        inputs.setdefault(text, f"upstream-test-{len(inputs)}.s")
    return {name: (text.encode(), False) for text, name in inputs.items()}


def file_inputs(paths):
    inputs = {}
    for path in paths:
        files = [path]
        if os.path.isdir(path):
            files = sorted(
                os.path.join(root, name)
                for root, _, names in os.walk(path)
                for name in names
            )
        for file in files:
            with open(file, "rb") as f:
                inputs[os.path.relpath(file, os.path.dirname(path))] = (f.read(), False)
    return inputs


def version_args(version):
    return [] if version is None else [f"--aspsx-version={version}"]


def matrix_cases(inputs, versions, g_values, flag_sets):
    for name, (data, expect_fallback) in inputs.items():
        for version in versions:
            for g in g_values:
                for flags in flag_sets:
                    args = version_args(version) + [g] + flags
                    yield (f"{name} {' '.join(args)}", args, data, expect_fallback)


def argument_cases(data, missing_path, input_path):
    fast = False
    fallback = True
    run_as = ["--run-assembler", "-EL", "-march=r3000", "-o", OBJECT]
    cases = [
        (["--aspsx-version", "2.81", "-G8"], data, fast),
        (["--aspsx-version=2.81", "-G8", "--expand-div"], data, fast),
        (["--bogus", "-G8", "positional"], data, fast),
        (["--no-macro-inc", "--expand-li", "-G8"], data, fast),
        (["--print-input", "--print-output", "-G8"], data, fast),
        (["--macro-inc", "-G8"], data, fast),
        (["--passthrough"], data, fast),
        (["--force-stdin"], b"", fast),
        (["-G8", input_path.replace("input.s", "input-cr.s")], b"", fast),
        ([], b"", fast),
        (["-G8", input_path], b"", fast),
        ([input_path, "-G8"], b"", fallback),
        ([missing_path], b"", fallback),
        (["--aspsx", "2.81"], data, fallback),
        (["--help"], data, fallback),
        (["-h"], data, fallback),
        (["--", "-G8"], data, fallback),
        (["--aspsx-version"], data, fallback),
        (["--aspsx-version", "-G8"], data, fallback),
        (["--aspsx-version=bogus"], data, fallback),
        (["--aspsx-version="], data, fallback),
        (["-Gx"], data, fallback),
        (["--run-assembler=1"], data, fallback),
        (run_as + ["--aspsx-version=2.81", "-G8", "-mtune=r3000", "-no-pad-sections", "-O1"], data, fast),
        (run_as + ["-mcpu=r3000", "-KPIC"], data, fast),
        (run_as + ["--dont-force-G0", "-G8"], data, fast),
        (run_as + ["-al"], data, fast),
        (run_as, b"\tthis is not an instruction\n", fast),
        (["--run-assembler", "--gnu-as-path", "false"], data, fast),
        (["--run-assembler", "--gnu-as-path", "/nonexistent/as"], data, fast),
        (["--run-assembler", "--gnu-as-path", "sh", "-c", "echo out; echo err >&2; exit 3"], data, fast),
        (["--run-assembler", "--gnu-as-path", "sh", "-c", "kill -SEGV $$"], data, fast),
    ]
    for args, stdin, expect_fallback in cases:
        yield (f"args {' '.join(args)}", args, stdin, expect_fallback)


def run(command, args, stdin, directory, env):
    output = os.path.join(directory, "out.o")
    args = [output if arg == OBJECT else arg for arg in args]
    result = subprocess.run(
        [command] + args, input=stdin, capture_output=True, cwd=directory, env=env
    )
    obj = None
    if os.path.exists(output):
        with open(output, "rb") as f:
            obj = f.read()
        os.remove(output)
    return result.returncode, result.stdout, result.stderr, obj


def check(case, fast, cpython, base_env):
    label, args, stdin, expect_fallback = case
    with tempfile.TemporaryDirectory() as a, tempfile.TemporaryDirectory() as b:
        expected = run(cpython, args, stdin, a, base_env)
        strict = run(fast, args, stdin, b, dict(base_env, **{NO_FALLBACK: "1"}))
        fell_back = strict[0] == NO_FALLBACK_STATUS and strict[2].startswith(
            b"maspsx: MicroPython fallback"
        )
        if fell_back:
            by_design = expected[0] != 0 and b"MASPSX: An exception occurred" in expected[2]
            if not (expect_fallback or by_design):
                return f"{label}: unexpected fallback: {strict[2].decode(errors='replace').strip()}"
            actual = run(fast, args, stdin, b, base_env)
        else:
            if expect_fallback:
                return f"{label}: expected a fallback, ran on MicroPython"
            actual = strict
    if actual != expected:
        names = ("exit status", "stdout", "stderr", "object")
        differences = [n for n, x, y in zip(names, expected, actual) if x != y]
        detail = ""
        if "stderr" in differences:
            detail = f"\n  CPython stderr: {expected[2][:300]!r}\n  fast stderr:    {actual[2][:300]!r}"
        elif "exit status" in differences:
            detail = f" ({expected[0]} vs {actual[0]})"
        return f"{label}: {', '.join(differences)} differ{detail}"
    return "fallback" if fell_back else None


def main():
    fast, cpython, processor_json, *paths = sys.argv[1:]
    synthetic = synthetic_inputs()
    recorded = recorded_inputs(processor_json)
    extra = file_inputs(paths)

    work = tempfile.mkdtemp()
    input_path = os.path.join(work, "input.s")
    with open(input_path, "wb") as f:
        f.write(synthetic["bss.s"][0])
    with open(os.path.join(work, "input-cr.s"), "wb") as f:
        f.write(synthetic["cr.s"][0])

    cases = list(argument_cases(synthetic["bss.s"][0], os.path.join(work, "missing.s"), input_path))
    cases += matrix_cases(synthetic, VERSIONS, ["-G0", "-G8"], FLAG_SETS)
    cases += matrix_cases(extra, VERSIONS, ["-G0", "-G8"], FLAG_SETS[:2])
    cases += matrix_cases(recorded, [None, "1.05", "2.21", "2.56", "2.81"], ["-G0", "-G8"], [[]])

    base_env = dict(os.environ)
    base_env.pop(NO_FALLBACK, None)
    jobs = int(os.environ.get("NIX_BUILD_CORES") or 0) or os.cpu_count() or 1
    failures = []
    fallbacks = 0
    with concurrent.futures.ThreadPoolExecutor(max_workers=jobs) as pool:
        for result in pool.map(lambda c: check(c, fast, cpython, base_env), cases):
            if result == "fallback":
                fallbacks += 1
            elif result is not None:
                failures.append(result)
    for failure in failures:
        print(failure)
    print(
        f"cli_diff.py: {len(cases)} cases, {len(cases) - fallbacks} on MicroPython, "
        f"{fallbacks} through the fallback, {len(failures)} failures"
    )
    if failures:
        sys.exit(1)


if __name__ == "__main__":
    main()
