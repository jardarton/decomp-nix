{
  ant,
  bashNonInteractive,
  fetchFromGitHub,
  ghidra-bin,
  ghidra-extensions,
  gradle,
  lib,
  lndir,
  makeBinaryWrapper,
  openjdk21,
  symlinkJoin,
}:

let
  version = "unstable-2026-09-03";

  psyqSignatures = fetchFromGitHub {
    owner = "lab313ru";
    repo = "psx_psyq_signatures";
    rev = "e9e46e7e133ef275a79bfce650924f98edb086bc";
    hash = "sha256-AG9H24r3xSC7R3DDO8OtMKoNhDisNL1JqLSUTxwadXY=";
  };

  extensionBuilder = (ghidra-extensions.override { ghidra = ghidra-bin; }).buildGhidraExtension;

  ghidraPsxExtension = extensionBuilder {
    pname = "ghidra-psx-loader";
    inherit version;

    src = fetchFromGitHub {
      owner = "lab313ru";
      repo = "ghidra_psx_ldr";
      rev = "6f6be18615d9b42b1ce07740780623c3cf6cbd2c";
      hash = "sha256-gTKxn8i143phvNzrRillrRvw49Odlnk+KSWYtjfY9Cw=";
    };

    postPatch = ''
      rm -rf data/psyq
      cp -R ${psyqSignatures} data/psyq
    '';

    # Ghidra 12.1.2 requires Gradle >= 8.5, and upstream CI uses 8.14.4.
    nativeBuildInputs = [
      ant
      gradle
    ];

    preBuild = ''
      # Upstream carries an SLA compiled by an older Ghidra.  Recompile the
      # custom PSX/GTE language with 12.1.2's architecture-neutral Java tool;
      # otherwise Ghidra rejects it with "Missing SLA format header".
      ant -f data/build.xml \
        -Dghidra.install.dir=${ghidra-bin}/lib/ghidra \
        sleighCompile
    '';

    meta = {
      description = "PlayStation loader, language, overlays, and PsyQ signatures for Ghidra";
      homepage = "https://github.com/lab313ru/ghidra_psx_ldr";
      # Neither upstream repository has a repository-level license grant.
      license = lib.licenses.unfree;
      platforms = ghidra-bin.meta.platforms;
      sourceProvenance = [ lib.sourceTypes.fromSource ];
    };
  };
in
symlinkJoin {
  pname = "ghidra-psx";
  name = "ghidra-psx-${version}";
  inherit version;
  paths = [
    ghidra-bin
    ghidraPsxExtension
  ];
  nativeBuildInputs = [
    lndir
    makeBinaryWrapper
  ];

  postBuild = ''
    ghidraHome="$out/lib/ghidra"

    # symlinkJoin can preserve Ghidra as one directory symlink because the
    # binary distribution contains an empty Extensions directory.  Replace it
    # with a merged directory tree so the extension is part of the application
    # root discovered by the unpatched upstream binary.
    rm -rf "$ghidraHome/Ghidra"
    mkdir "$ghidraHome/Ghidra"
    lndir -silent ${ghidra-bin}/lib/ghidra/Ghidra "$ghidraHome/Ghidra"
    lndir -silent ${ghidraPsxExtension}/lib/ghidra/Ghidra "$ghidraHome/Ghidra"
    chmod u+w "$ghidraHome/Ghidra"

    # Ghidra derives its primary application root from Utility.jar's location.
    # Keep that one jar in the composed tree rather than as a symlink back to
    # ghidra-bin, otherwise the unpatched binary discovers only the base root
    # and silently ignores the composed Extensions directory.
    utilityJar="$ghidraHome/Ghidra/Framework/Utility/lib/Utility.jar"
    chmod u+w "$(dirname "$utilityJar")"
    rm "$utilityJar"
    cp ${ghidra-bin}/lib/ghidra/Ghidra/Framework/Utility/lib/Utility.jar "$utilityJar"

    # ghidra-bin is an upstream binary distribution and therefore lacks the
    # NIX_GHIDRAHOME source patch.  Make the three launcher scripts real files
    # in the composed tree so they resolve the merged application root rather
    # than following symlinks back to the unextended ghidra-bin store path.
    rm "$ghidraHome/ghidraRun" \
      "$ghidraHome/support/analyzeHeadless" \
      "$ghidraHome/support/launch.sh"
    cp --dereference ${ghidra-bin}/lib/ghidra/ghidraRun "$ghidraHome/ghidraRun"
    cp --dereference ${ghidra-bin}/lib/ghidra/support/analyzeHeadless \
      "$ghidraHome/support/analyzeHeadless"
    cp ${ghidra-bin}/lib/ghidra/support/.launch.sh-wrapped \
      "$ghidraHome/support/launch.sh"
    chmod +x "$ghidraHome/ghidraRun" \
      "$ghidraHome/support/analyzeHeadless" \
      "$ghidraHome/support/launch.sh"

    # Prevent Ghidra from trying to create extension discovery lock files in
    # the immutable Nix store.
    test -e "$ghidraHome/Ghidra/.dbDirLock" || touch "$ghidraHome/Ghidra/.dbDirLock"

    rm -rf "$out/bin"
    mkdir -p "$out/bin" "$out/libexec"
    cat > "$out/libexec/ghidra-psx-launcher" <<'EOF'
    #!@bash@/bin/bash
    case "''${1-}" in
      -h|--help)
        echo "Usage: ghidra [Ghidra options]"
        echo "Launch the Ghidra 12.1.2 GUI with the PSX extension enabled."
        exit 0
        ;;
    esac
    exec "@ghidraRun@" "$@"
    EOF
    substituteInPlace "$out/libexec/ghidra-psx-launcher" \
      --replace-fail @bash@ ${bashNonInteractive} \
      --replace-fail @ghidraRun@ "$ghidraHome/ghidraRun"
    chmod +x "$out/libexec/ghidra-psx-launcher"
    makeWrapper "$out/libexec/ghidra-psx-launcher" "$out/bin/ghidra" \
      --set NIX_GHIDRAHOME "$ghidraHome/Ghidra" \
      --prefix PATH : ${lib.makeBinPath [ openjdk21 ]}
    makeWrapper "$ghidraHome/support/analyzeHeadless" \
      "$out/bin/ghidra-analyzeHeadless" \
      --set NIX_GHIDRAHOME "$ghidraHome/Ghidra" \
      --prefix PATH : ${lib.makeBinPath [ openjdk21 ]}

    extensionHome="$ghidraHome/Ghidra/Extensions/ghidra-psx-loader"
    grep -q '^application.version=12.1.2$' "$ghidraHome/Ghidra/application.properties"
    grep -q '^name=ghidra-psx-loader$' "$extensionHome/extension.properties"
    test "$(head -c 3 "$extensionHome/data/languages/mips32le.sla")" = sla
    test -f "$extensionHome/data/gte_macro.json"
    test -f "$extensionHome/data/languages/gtemac.sinc"
    test -f "$extensionHome/data/psyq260.gdt"
    test -f "$extensionHome/data/psyq470.gdt"
    test -f "$extensionHome/data/psyq/260/LIBGTE.LIB.json"
    test -f "$extensionHome/data/psyq/3611/LIBGPU.LIB.json"
    test -f "$extensionHome/data/psyq/470/LIBGTE.LIB.json"
    test -f "$extensionHome/ghidra_scripts/CreateGteMacSegment.java"
    test -f "$extensionHome/ghidra_scripts/ImportPSX_SYM.java"
    test -x "$out/bin/ghidra"
    test -x "$out/bin/ghidra-analyzeHeadless"
  '';

  passthru = {
    ghidra = ghidra-bin;
    extension = ghidraPsxExtension;
    inherit psyqSignatures;
  };

  meta = ghidra-bin.meta // {
    pname = "ghidra-psx";
    inherit version;
    description = "Ghidra 12.1.2 composed with PlayStation loader and PsyQ support";
    homepage = "https://github.com/lab313ru/ghidra_psx_ldr";
    mainProgram = "ghidra";
    # Ghidra itself is Apache-2.0, but the extension and signatures have no
    # repository-level license grant.  Conservatively treat the composition
    # as unfree rather than claiming Apache-2.0 for the whole result.
    license = lib.licenses.unfree;
    sourceProvenance = with lib.sourceTypes; [
      binaryBytecode
      fromSource
    ];
  };
}
