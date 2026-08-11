{
  cmake,
  fetchFromGitHub,
  flac,
  ghc_filesystem,
  lib,
  libogg,
  miniaudio,
  ninja,
  pkg-config,
  stdenv,
  tinyxml-2,
}:
let
  upstreamVersion = "2.30";

  miniaudioHeaders =
    if stdenv.hostPlatform.isDarwin then
      fetchFromGitHub {
        owner = "mackron";
        repo = "miniaudio";
        rev = "9634bedb5b5a2ca38c1ee7108a9358a4e233f14d";
        hash = "sha256-2k346Z/ueINPbaY20P2cbBvRfFXXH0ugdv4d7WaYt2w=";
      }
    else
      "${lib.getDev miniaudio}/include/miniaudio";

  threadpool = fetchFromGitHub {
    owner = "log4cplus";
    repo = "ThreadPool";
    rev = "251db61ff3e3c7b16436c9936c53e6f68ff07720";
    hash = "sha256-0zDPSp6g68Lr9RRcja20vwZBitbWiRkuy+MeSxeWriA=";
  };
in
stdenv.mkDerivation {
  pname = "mkpsxiso";
  version = "2.30-unstable-2026-07-09";

  src = fetchFromGitHub {
    owner = "Lameguy64";
    repo = "mkpsxiso";
    rev = "a6b11ea86e67c189137ac50a4066044b3fdb0525";
    hash = "sha256-MbATvp37ptlTyhwqYWhtD+WzLYHQSSMeJ8Glo17mLBE=";
  };

  patches = [ ./mkpsxiso-system-dependencies.patch ];

  postPatch = ''
    cp -rT --no-preserve=all ${threadpool} threadpool
  '';

  nativeBuildInputs = [
    cmake
    ninja
    pkg-config
  ];

  buildInputs = [
    flac
    ghc_filesystem
    libogg
    tinyxml-2
  ]
  ++ lib.optional (!stdenv.hostPlatform.isDarwin) miniaudio;

  cmakeFlags = [ "-DMINIAUDIO_INCLUDE_DIR=${miniaudioHeaders}" ];

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck

    export HOME="$TMPDIR/home"
    export TZ=UTC
    mkdir -p "$HOME" roundtrip/source roundtrip/dump roundtrip/rebuilt

    find "$out" -type f -print0 | sort -z | xargs -0 sha256sum > store-before.sha256

    for program in mkpsxiso dumpsxiso; do
      programUpper=$(printf '%s' "$program" | tr '[:lower:]' '[:upper:]')
      "$out/bin/$program" --help > "$program-help.log"
      grep -F "$programUpper ${upstreamVersion}" "$program-help.log"
      grep -F "Usage: $program" "$program-help.log"

      "$out/bin/$program" > "$program-version.log"
      grep -F "$programUpper ${upstreamVersion}" "$program-version.log"
    done

    printf '<iso_project><broken></iso_project>\n' > malformed.xml
    if "$out/bin/mkpsxiso" malformed.xml > malformed.log 2>&1; then
      echo "mkpsxiso accepted malformed XML" >&2
      exit 1
    fi
    grep -F 'ERROR:' malformed.log

    if "$out/bin/dumpsxiso" missing.bin > missing.log 2>&1; then
      echo "dumpsxiso accepted a missing image" >&2
      exit 1
    fi
    grep -F 'ERROR: Cannot open file' missing.log

    printf 'Synthetic mkpsxiso round-trip payload.\n' > roundtrip/source/PAYLOAD.TXT
    cat > roundtrip/project.xml <<'XML'
    <?xml version="1.0" encoding="UTF-8"?>
    <iso_project image_name="disc.bin" cue_sheet="disc.cue">
      <track type="data" cdvd_style="false">
        <identifiers system="PLAYSTATION" application="PLAYSTATION"
          volume="SYNTHETIC" volume_set="SYNTHETIC" publisher="HOMEBREW"
          data_preparer="MKPSXISO" copyright="GPL"
          creation_date="2026070900000000" modification_date="2026070900000000"/>
        <directory_tree>
          <dir name="DATA" date="20260709000000">
            <file name="PAYLOAD.TXT" source="source/PAYLOAD.TXT" type="data" date="20260709000000"/>
          </dir>
        </directory_tree>
      </track>
    </iso_project>
    XML

    (
      cd roundtrip
      "$out/bin/mkpsxiso" -y project.xml
      test -s disc.bin
      grep -F 'TRACK 01 MODE2/2352' disc.cue

      "$out/bin/dumpsxiso" --lba -x dump -s dump/project.xml disc.cue
      cmp source/PAYLOAD.TXT dump/DATA/PAYLOAD.TXT
      grep -F '<iso_project' dump/project.xml
      grep -F 'name="DATA"' dump/project.xml
      grep -F 'name="PAYLOAD.TXT"' dump/project.xml
      grep -F 'volume="SYNTHETIC"' dump/project.xml

      # The input project has no license source. The extracted area therefore
      # contains only sectors synthesized by mkpsxiso; omit it on rebuild.
      ! grep -F '<license ' project.xml
      test "$(stat -c %s dump/license_data.dat)" = 28032
      ! grep -aE 'Licensed by|Sony Computer Entertainment' dump/license_data.dat
      sed -i '/<license /d' dump/project.xml
      (
        cd rebuilt
        "$out/bin/mkpsxiso" -y -o disc.bin -c disc.cue ../dump/project.xml
      )
      cmp disc.bin rebuilt/disc.bin
    )

    find "$out" -type f -print0 | sort -z | xargs -0 sha256sum > store-after.sha256
    cmp store-before.sha256 store-after.sha256

    runHook postInstallCheck
  '';

  meta = {
    description = "PlayStation CD image creation and dumping tools";
    homepage = "https://github.com/Lameguy64/mkpsxiso";
    license = lib.licenses.gpl2Only;
    mainProgram = "mkpsxiso";
    platforms = lib.platforms.unix;
  };
}
