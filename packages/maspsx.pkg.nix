{
  fetchFromGitHub,
  file,
  lib,
  makeWrapper,
  pkgsCross,
  python3,
  stdenvNoCC,
}:
let
  mipsBinutils = pkgsCross.mips-embedded.buildPackages.binutils-unwrapped;
  mipsAssembler = "${mipsBinutils}/bin/${mipsBinutils.targetPrefix}as";
in
stdenvNoCC.mkDerivation {
  pname = "maspsx";
  version = "unstable-2026-09-23";

  src = fetchFromGitHub {
    owner = "mkst";
    repo = "maspsx";
    rev = "7686f845a181700534c83c0419183e38aeb3e49c";
    hash = "sha256-Q6NDNesXDj79mBeM24h+RhSZQG5fo4JuVPexQVSqnIQ=";
  };

  postPatch = ''
    substituteInPlace maspsx.py \
      --replace-fail 'default="mipsel-linux-gnu-as"' 'default="${mipsAssembler}"'
  '';

  nativeBuildInputs = [ makeWrapper ];
  nativeCheckInputs = [
    file
    mipsBinutils
    python3
  ];

  dontBuild = true;

  doCheck = true;
  checkPhase = ''
    runHook preCheck

    python -m unittest --verbose 2>&1 | tee unit-tests.log
    grep -F "Ran 151 tests" unit-tests.log
    grep -Fx "OK" unit-tests.log

    runHook postCheck
  '';

  installPhase = ''
    runHook preInstall

    appDir="$out/share/maspsx"
    moduleDir="$appDir/maspsx"
    mkdir -p "$appDir" "$moduleDir" "$out/bin"
    install -Dm644 maspsx.py "$appDir/maspsx.py"
    install -Dm644 maspsx/__init__.py "$moduleDir/__init__.py"
    install -Dm644 LICENSE README.md -t "$appDir"
    mkdir -p "$out/${python3.sitePackages}"
    ln -s "$moduleDir" "$out/${python3.sitePackages}/maspsx"

    makeWrapper ${python3}/bin/python "$out/bin/maspsx" \
      --add-flags "$appDir/maspsx.py" \
      --set PYTHONDONTWRITEBYTECODE 1 \
      --prefix PYTHONPATH : "$out/${python3.sitePackages}"

    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck

    export HOME="$TMPDIR"
    export PYTHONDONTWRITEBYTECODE=1
    cd "$TMPDIR"

    $out/bin/maspsx --help | grep -F -- "--run-assembler"
    PYTHONPATH="$out/${python3.sitePackages}" \
      ${python3}/bin/python -c 'from maspsx import MaspsxProcessor'

    cat > smoke.s <<'ASM'
    .text
    .set noreorder
    .globl smoke
    .ent smoke
    smoke:
        li      $2,0x12345678
        addu    $2,$2,$4
        jr      $31
        nop
    .end smoke
    ASM

    $out/bin/maspsx \
      --aspsx-version=2.81 \
      --run-assembler \
      -EL \
      -march=r3000 \
      -o smoke.o \
      < smoke.s

    test -s smoke.o
    ${file}/bin/file smoke.o | tee file.log
    grep -F "ELF 32-bit LSB relocatable, MIPS" file.log
    ${mipsBinutils}/bin/${mipsBinutils.targetPrefix}readelf -h smoke.o | tee readelf.log
    grep -F "Data:" readelf.log | grep -F "little endian"
    grep -F "Machine:" readelf.log | grep -F "MIPS R3000"

    runHook postInstallCheck
  '';

  meta = {
    description = "Modern replacement for the PsyQ ASPSX assembly preprocessor";
    homepage = "https://github.com/mkst/maspsx";
    license = lib.licenses.mit;
    mainProgram = "maspsx";
    platforms = lib.platforms.unix;
  };
}
