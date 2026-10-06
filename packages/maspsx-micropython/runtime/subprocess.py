# subprocess.Popen as maspsx --run-assembler uses it: all three streams piped,
# input written once through communicate().

PIPE = -1


class Popen:
    def __init__(self, args, stdout=None, stdin=None, stderr=None):
        if (stdout, stdin, stderr) != (PIPE, PIPE, PIPE):
            raise NotImplementedError("subprocess: only fully piped Popen")
        self.args = [str(arg) for arg in args]
        self.returncode = None

    def __enter__(self):
        return self

    def __exit__(self, *exception):
        return False

    def communicate(self, input=None):
        import _mplibc

        stdout, stderr, self.returncode = _mplibc.run(self.args, input or b"")
        return stdout, stderr
