{
  binutils,
  elfio,
  fetchFromGitHub,
  file,
  fmt,
  lib,
  magic-enum,
  stdenv,
  zlib,
}:
stdenv.mkDerivation {
  pname = "psyq-obj-parser";
  version = "unstable-2026-09-27";

  src = fetchFromGitHub {
    owner = "grumpycoders";
    repo = "pcsx-redux";
    rev = "264f2a6865466fd0846ab12808d0260fe012d35a";
    hash = "sha256-XeBJVeTBLKC1pzUGXHoKinbm4rAPRpNd3GKOS23mPqE=";
  };

  buildInputs = [
    elfio
    fmt
    magic-enum
    zlib
  ];

  nativeCheckInputs = [
    binutils
    file
  ];

  # The upstream tools target links every shared PCSX-Redux support object and
  # is static. Compile only the parser and the file abstraction it actually
  # uses, with the three header/library dependencies supplied by nixpkgs.
  buildPhase = ''
    runHook preBuild

    $CXX -std=c++2b -O2 \
      -I. \
      -Isrc \
      -Ithird_party \
      tools/psyq-obj-parser/psyq-obj-parser.cc \
      src/support/file.cc \
      -lfmt \
      -o psyq-obj-parser

    runHook postBuild
  '';

  doCheck = true;
  checkPhase = ''
    runHook preCheck

    set +e
    ./psyq-obj-parser --help > help.log 2>&1
    helpStatus=$?
    set -e
    test "$helpStatus" -eq 255
    grep -F "Usage:" help.log
    grep -F -- "-o output.o" help.log

    # Legal synthetic PsyQ LNK v2 fixture constructed from the parser's
    # documented opcode layout: program type, .text section, R3000 code, and
    # one exported symbol. It contains no PsyQ SDK material.
    printf '%b' \
      '\x4c\x4e\x4b\x02'\
      '\x2e\x07'\
      '\x10\x01\x00\x00\x00\x04\x05.text'\
      '\x06\x01\x00'\
      '\x02\x10\x00'\
      '\x2a\x00\x02\x24\x21\x10\x44\x00\x08\x00\xe0\x03\x00\x00\x00\x00'\
      '\x0c\x01\x00\x01\x00\x00\x00\x00\x00\x05smoke'\
      '\x00' \
      > synthetic.obj

    ./psyq-obj-parser synthetic.obj -d | tee parse.log
    grep -F ".text" parse.log
    grep -F "smoke" parse.log

    ./psyq-obj-parser synthetic.obj -o synthetic.o | tee conversion.log
    grep -F "Conversion completed" conversion.log
    ${file}/bin/file synthetic.o | tee file.log
    grep -F "ELF 32-bit LSB relocatable, MIPS" file.log
    ${binutils}/bin/readelf -h synthetic.o | tee readelf.log
    grep -F "Data:" readelf.log | grep -F "little endian"
    grep -F "Type:" readelf.log | grep -F "REL (Relocatable file)"
    grep -F "Machine:" readelf.log | grep -F "MIPS R3000"

    printf 'NOT-A-LNK' > malformed.obj
    if ./psyq-obj-parser malformed.obj > malformed.log 2>&1; then
      echo "malformed input unexpectedly succeeded" >&2
      exit 1
    fi
    grep -F "Wrong signature" malformed.log

    runHook postCheck
  '';

  installPhase = ''
    runHook preInstall

    install -Dm755 psyq-obj-parser "$out/bin/psyq-obj-parser"
    install -Dm644 LICENSE tools/psyq-obj-parser/README.md -t "$out/share/doc/psyq-obj-parser"

    runHook postInstall
  '';

  meta = {
    description = "Parser and ELF converter for PsyQ LNK object files";
    homepage = "https://github.com/grumpycoders/pcsx-redux/tree/master/tools/psyq-obj-parser";
    license = lib.licenses.gpl2Plus;
    mainProgram = "psyq-obj-parser";
    platforms = lib.platforms.unix;
  };
}
