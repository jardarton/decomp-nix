# argparse.ArgumentParser.parse_known_args for the options maspsx declares:
# long options that either store a string or are store_true flags.
#
# Command lines are accepted only where CPython's argparse is easy to match
# exactly: options spelled out in full, values that do not start with "-",
# and unknown arguments that no declared option could claim. Anything else
# (help, abbreviations, "--", parse errors) raises, and the launcher hands the
# run to CPython, which also prints the real help and error messages.

import sys


class Unsupported(Exception):
    pass


class Namespace:
    pass


class ArgumentParser:
    def __init__(self, *args, **kwargs):
        if args or kwargs:
            raise Unsupported("ArgumentParser options")
        self._options = {}

    def add_argument(self, name, action=None, type=None, default=None):
        if not name.startswith("--") or len(name) < 3 or "=" in name:
            raise Unsupported(name)
        if action == "store_true":
            if type is not None or default is not None:
                raise Unsupported(name)
            default = False
        elif action is not None or type not in (None, str):
            raise Unsupported(name)
        self._options[name] = (name[2:].replace("-", "_"), action == "store_true", default)

    def _claims(self, prefix):
        # Whether argparse would treat prefix as an abbreviation of an option.
        if "--help".startswith(prefix):
            return True
        for name in self._options:
            if name.startswith(prefix):
                return True
        return False

    def parse_known_args(self, args=None, namespace=None):
        if namespace is not None:
            raise Unsupported("namespace")
        args = sys.argv[1:] if args is None else list(args)
        result = Namespace()
        for dest, flag, default in self._options.values():
            setattr(result, dest, default)
        extras = []
        i = 0
        while i < len(args):
            arg = args[i]
            i += 1
            if arg.startswith("--"):
                name, equals, value = arg.partition("=")
                option = self._options.get(name)
                if option is None:
                    if arg == "--" or self._claims(name):
                        raise Unsupported(arg)
                    extras.append(arg)
                    continue
                dest, flag, default = option
                if flag:
                    if equals:
                        raise Unsupported(arg)
                    setattr(result, dest, True)
                elif equals:
                    setattr(result, dest, value)
                else:
                    if i >= len(args) or args[i].startswith("-"):
                        raise Unsupported(arg)
                    setattr(result, dest, args[i])
                    i += 1
            elif arg.startswith("-h"):
                raise Unsupported(arg)
            else:
                extras.append(arg)
        return result, extras
