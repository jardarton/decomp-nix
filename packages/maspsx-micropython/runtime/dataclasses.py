# maspsx uses @dataclass for a class of defaulted flags that it only reads and
# assigns, never compares or prints, so the class itself serves unchanged.


def dataclass(cls=None, **options):
    if cls is None:
        return lambda c: c
    return cls
