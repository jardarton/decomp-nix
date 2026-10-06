"""Rewrite maspsx sources so MicroPython runs them with CPython's semantics.

Usage: python3 rewrite.py SOURCE DESTINATION [SOURCE DESTINATION]...

All sources are rewritten together, so names defined in one count as
Python-defined in all of them.

- MicroPython dictionaries do not keep insertion order, and maspsx emits
  .bss/.sbss symbols in dictionary order. Every dictionary display and
  comprehension becomes an OrderedDict.
- `import re` and `import struct` load the compatibility modules _mpre and
  _mpstruct.
- `float` is shadowed by the correctly rounded parser in _mpfloat.

Constructs this script cannot translate fail the build instead of silently
changing behaviour.
"""

import ast
import sys

COMPAT_MODULES = {"re": "_mpre", "struct": "_mpstruct"}
RESERVED = {"_OrderedDict", "_mpfloat", *COMPAT_MODULES.values()}
# Callables implemented in Python by runtime/, which accept keyword arguments.
PYTHON_CALLABLES = {
    "ArgumentParser",
    "add_argument",
    "parse_known_args",
    "open",
    "Popen",
    "communicate",
    "dataclass",
}


class Rewriter(ast.NodeVisitor):
    def __init__(self, source):
        self.data = source.encode()
        self.line_offsets = [0]
        for line in source.splitlines(keepends=True):
            self.line_offsets.append(self.line_offsets[-1] + len(line.encode()))
        self.edits = []
        self.uses_float = False

    def start(self, node):
        return self.line_offsets[node.lineno - 1] + node.col_offset

    def end(self, node):
        return self.line_offsets[node.end_lineno - 1] + node.end_col_offset

    def text(self, node):
        return self.data[self.start(node) : self.end(node)].decode()

    def replace(self, node, text):
        self.edits.append((self.start(node), self.end(node), text))

    def fail(self, node, message):
        raise SystemExit(f"rewrite.py: line {node.lineno}: {message}")

    def no_nested_dicts(self, *nodes):
        for node in nodes:
            for child in ast.walk(node):
                if isinstance(child, (ast.Dict, ast.DictComp)):
                    self.fail(child, "nested dictionary displays are not translated")
                if isinstance(child, ast.Name):
                    self.visit_Name(child)

    def visit_Import(self, node):
        for alias in node.names:
            if alias.name in COMPAT_MODULES:
                if alias.asname is not None or len(node.names) != 1:
                    self.fail(node, f"unexpected form of import {alias.name}")
                self.replace(
                    node, f"import {COMPAT_MODULES[alias.name]} as {alias.name}"
                )

    def visit_ImportFrom(self, node):
        if node.module == "__future__":
            self.fail(node, "__future__ imports are not supported")
        if node.module in COMPAT_MODULES:
            self.fail(node, f"from {node.module} import is not translated")

    def visit_Dict(self, node):
        if any(key is None for key in node.keys):
            self.fail(node, "dictionary unpacking is not translated")
        self.no_nested_dicts(*node.keys, *node.values)
        pairs = "".join(
            f"({self.text(k)}, {self.text(v)}), " for k, v in zip(node.keys, node.values)
        )
        self.replace(node, f"_OrderedDict(({pairs}))")

    def visit_DictComp(self, node):
        self.no_nested_dicts(node.key, node.value, *node.generators)
        generators = self.data[self.end(node.value) : self.end(node) - 1].decode()
        self.replace(
            node,
            f"_OrderedDict((({self.text(node.key)}, {self.text(node.value)}){generators}))",
        )

    def visit_List(self, node):
        # MicroPython cannot unpack inside a display: [a, *b, c].
        if isinstance(node.ctx, ast.Load) and any(
            isinstance(e, ast.Starred) for e in node.elts
        ):
            self.no_nested_dicts(*node.elts)
            parts = []
            plain = []
            for element in node.elts:
                if isinstance(element, ast.Starred):
                    if plain:
                        parts.append(f"[{', '.join(plain)}]")
                        plain = []
                    parts.append(f"list({self.text(element.value)})")
                else:
                    plain.append(self.text(element))
            if plain:
                parts.append(f"[{', '.join(plain)}]")
            self.replace(node, f"({' + '.join(parts)})")
            return
        self.generic_visit(node)

    def visit_Tuple(self, node):
        self.no_starred_display(node)

    def visit_Set(self, node):
        self.no_starred_display(node)

    def no_starred_display(self, node):
        if isinstance(getattr(node, "ctx", ast.Load()), ast.Load) and any(
            isinstance(e, ast.Starred) for e in node.elts
        ):
            self.fail(node, "unpacking inside a tuple or set display is not translated")
        self.generic_visit(node)

    def visit_Call(self, node):
        # MicroPython's built-in functions and methods take no keyword
        # arguments; Python-defined ones (here and in runtime/) do.
        if node.keywords:
            name = getattr(node.func, "attr", getattr(node.func, "id", None))
            if name in ("split", "rsplit") and isinstance(node.func, ast.Attribute):
                self.split_keywords(node)
                return
            if name not in self.python_callables:
                self.fail(node, f"keyword arguments to {name}() are not translated")
        if isinstance(node.func, ast.Name):
            if node.func.id in ("dict", "vars"):
                self.fail(node, f"{node.func.id}() is not translated")
            if node.func.id == "float":
                if len(node.args) != 1 or node.keywords:
                    self.fail(node, "unexpected float() call")
                self.uses_float = True
                self.visit(node.args[0])
                return
        self.generic_visit(node)

    def split_keywords(self, node):
        args = [self.text(a) for a in node.args]
        keywords = {k.arg: self.text(k.value) for k in node.keywords}
        if len(args) > 2 or set(keywords) - {"sep", "maxsplit"} or any(
            isinstance(a, ast.Starred) for a in node.args
        ):
            self.fail(node, "unexpected split() call")
        if "sep" in keywords:
            if args:
                self.fail(node, "unexpected split() call")
            args.append(keywords["sep"])
        if "maxsplit" in keywords:
            if not args:
                args.append("None")
            args.append(keywords["maxsplit"])
        self.no_nested_dicts(node.func.value, *node.args, *node.keywords)
        self.replace(node, f"{self.text(node.func)}({', '.join(args)})")

    def visit_AnnAssign(self, node):
        # MicroPython does not evaluate annotations.
        self.visit(node.target)
        if node.value is not None:
            self.visit(node.value)

    def visit_arg(self, node):
        pass

    def visit_FunctionDef(self, node):
        for child in node.decorator_list + node.body:
            self.visit(child)
        self.visit(node.args)

    def visit_Name(self, node):
        if node.id in RESERVED:
            self.fail(node, f"name {node.id} is reserved by rewrite.py")
        if node.id == "float":
            self.fail(node, "float is only translated when called")


def main():
    arguments = sys.argv[1:]
    if not arguments or len(arguments) % 2:
        raise SystemExit(__doc__)
    jobs = []
    for source_path, destination_path in zip(arguments[::2], arguments[1::2]):
        with open(source_path, encoding="utf-8") as f:
            source = f.read()
        jobs.append((source, ast.parse(source, source_path), destination_path))

    python_callables = PYTHON_CALLABLES | {
        node.name
        for _, tree, _ in jobs
        for node in ast.walk(tree)
        if isinstance(node, (ast.FunctionDef, ast.ClassDef))
    }

    for source, tree, destination_path in jobs:
        rewriter = Rewriter(source)
        rewriter.python_callables = python_callables
        rewriter.visit(tree)

        data = rewriter.data
        for start, end, text in sorted(rewriter.edits, reverse=True):
            data = data[:start] + text.encode() + data[end:]

        header = "from collections import OrderedDict as _OrderedDict\n"
        if rewriter.uses_float:
            header += "from _mpfloat import parse as float\n"

        with open(destination_path, "w", encoding="utf-8") as f:
            f.write(header + data.decode())


if __name__ == "__main__":
    main()
