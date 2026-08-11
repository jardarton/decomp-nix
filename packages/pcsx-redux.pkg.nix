{
  alsa-lib,
  capstone,
  curl,
  elfio,
  fetchFromGitHub,
  ffmpeg,
  fmt,
  freetype,
  glfw3,
  gtest,
  imagemagick,
  lib,
  libGL,
  libjack2,
  libpulseaudio,
  libuv,
  libX11,
  libxcb,
  llhttp,
  luajitPackages,
  magic-enum,
  makeWrapper,
  md4c,
  miniaudio,
  multipart-parser-c,
  pkg-config,
  pkgsCross,
  stdenv,
  tl-expected,
  tracy,
  ucl,
  uriparser,
  zip,
  zlib,
}:
let
  mipsToolchain = pkgsCross.mips-embedded.buildPackages.gccWithoutTargetLibc;
  mipsPrefix = lib.removeSuffix "-" mipsToolchain.targetPrefix;

  submodules = [
    {
      path = "zep";
      owner = "grumpycoders";
      repo = "zep";
      rev = "53a89f408854801be5196b18aca791185c28b365";
      hash = "sha256-kSFjU6fpnMJopZ9fsTW5MMICrmYXq9NAWGcxIy4CO/s=";
    }
    {
      path = "nanosvg";
      owner = "grumpycoders";
      repo = "nanosvg";
      rev = "f0a3e1034dd22e2e87e5db22401e44998383124e";
      hash = "sha256-af11kAga6Ru2rPgrfcYswXNy9etvH3J9FX2T0I0++ew=";
    }
    {
      path = "nanovg";
      owner = "grumpycoders";
      repo = "nanovg";
      rev = "7c021819bbd4843a1a3091fe47346d3fcb2a3e1a";
      hash = "sha256-gZHbNuDkLXlLlXZZpLBHcbwzTfeBBkLY7xl4L5yr2lY=";
    }
    {
      path = "imgui_md";
      owner = "mekhontsev";
      repo = "imgui_md";
      rev = "8ca75c5f7663f314821e3d0b2c51011792bee68f";
      hash = "sha256-uxhY81DWLRRCceYn9khk3rwzT+2f9PNMIMT9OrkPfFc=";
    }
    {
      path = "xbyak";
      owner = "herumi";
      repo = "xbyak";
      rev = "2fb843c3287918038c8f76276a590c25cc7ec5ee";
      hash = "sha256-XZce+kEZ7dipI19WY43ycOjzM2dZyANMEN5+GhoNYUk=";
    }
    {
      path = "luafilesystem";
      owner = "nicolasnoble";
      repo = "luafilesystem";
      rev = "7f89bc0c6529497e0bc45b33467bf6cbcf6e989d";
      hash = "sha256-vSP+KFxSzpzG+nJp0+YF+cDo0eddV3PvAm/jyzFDp14=";
    }
    {
      path = "luajit";
      owner = "grumpycoders";
      repo = "LuaJIT";
      rev = "07c36331bb4e1140322a6f8d91d53b9c2767ed46";
      hash = "sha256-UNoib5Kf3NxkIKaerZW9NrQ3lyQn0WXvBFRQT+KJrYs=";
    }
    {
      path = "imgui";
      owner = "ocornut";
      repo = "imgui";
      rev = "368123ab06b2b573d585e52f84cd782c5c006697";
      hash = "sha256-6VOs7a31bEfAG75SQAY2X90h/f/HvqZmN615WXYkUOA=";
    }
    {
      path = "SDL_GameControllerDB";
      owner = "mdqinc";
      repo = "SDL_GameControllerDB";
      rev = "b1e342774cbb35467dfdd3634d4f0181a76cbc89";
      hash = "sha256-LYvO+chDVo6D++fuFbxqSRltGW3y82SESmtFj39TdSA=";
    }
    {
      path = "PEGTL";
      owner = "taocpp";
      repo = "PEGTL";
      rev = "d7b821b1e5ed6ab321625f50427c4ae0b78909d5";
      hash = "sha256-1hTwoTCkfOX7e0unAlZ8TnYva3enkCgfrfriZfx2AoE=";
    }
    {
      path = "stb";
      owner = "nothings";
      repo = "stb";
      rev = "ae721c50eaf761660b4f90cc590453cdb0c2acd0";
      hash = "sha256-BIhbhXV7q5vodJ3N14vN9mEVwqrP6z9zqEEQrfLPzvI=";
    }
    {
      path = "uC-sdk";
      owner = "grumpycoders";
      repo = "uC-sdk";
      rev = "69e06871824e2d62069487a7426ded09090ceb69";
      hash = "sha256-VamLhNtXxilcvd6ch76ronhB7DcKfw2eL7CuLwHFbp8=";
    }
  ]
  ++ lib.optional stdenv.hostPlatform.isAarch64 {
    path = "vixl";
    owner = "grumpycoders";
    repo = "vixl";
    rev = "53ad192b26ddf6edd228a24ae1cffc363b442c01";
    hash = "sha256-p9Z2lFzhqnHnFWfqT6BIJBVw2ZpkVIxykhG3jUHXA84=";
  };

  fetchSubmodule =
    {
      path,
      owner,
      repo,
      rev,
      hash,
    }:
    let
      source = fetchFromGitHub {
        inherit
          owner
          repo
          rev
          hash
          ;
      };
    in
    ''
      cp -ruT --no-preserve=all ${source} third_party/${path}
    '';
in
stdenv.mkDerivation {
  pname = "pcsx-redux";
  version = "unstable-2026-08-09";

  src = fetchFromGitHub {
    owner = "grumpycoders";
    repo = "pcsx-redux";
    rev = "9a1c92a894a3c6bf9a1b681548161b49f384d872";
    hash = "sha256-CBns5H3Q7uZYHC6gD8Oq6c9Woix1HhNiz9OXDYVZXAM=";
  };

  preConfigure = ''
    cp -ruT --no-preserve=all ${tracy.src} third_party/tracy
  ''
  + builtins.concatStringsSep "\n" (map fetchSubmodule submodules);

  nativeBuildInputs = [
    imagemagick
    makeWrapper
    mipsToolchain.bintools.bintools
    mipsToolchain.cc
    pkg-config
    zip
  ];

  buildInputs = [
    capstone
    curl.dev
    elfio
    ffmpeg.dev
    fmt
    freetype.dev
    glfw3
    gtest
    libuv
    libX11
    libxcb
    llhttp
    luajitPackages.libluv
    magic-enum
    md4c
    miniaudio
    multipart-parser-c
    tl-expected
    tracy
    ucl
    uriparser
    zlib
  ];

  makeFlags = [
    "openbios"
    "pcsx-redux"
    "PREFIX=${mipsPrefix}"
  ];

  installFlags = [
    "install"
    "install-openbios"
    "DESTDIR=$(out)"
  ];

  enableParallelBuilding = true;

  postInstall = ''
    substituteInPlace "$out/share/applications/pcsx-redux.desktop" \
      --replace-fail "Exec=/usr/bin/pcsx-redux" "Exec=pcsx-redux"

    cat > "$out/share/pcsx-redux/resources/version.json" <<'JSON'
    {
      "version": "unstable-2026-08-09",
      "changeset": "9a1c92a894a3c6bf9a1b681548161b49f384d872",
      "timestamp": 1786317567
    }
    JSON

    wrapProgram "$out/bin/pcsx-redux" \
      --prefix LD_LIBRARY_PATH : ${
        lib.makeLibraryPath [
          alsa-lib
          libGL
          libjack2
          libpulseaudio
        ]
      }
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck

    export HOME="$TMPDIR/home"
    mkdir -p "$HOME"
    unset DISPLAY WAYLAND_DISPLAY

    $out/bin/pcsx-redux -version | tee version.log
    grep -F '"version": "unstable-2026-08-09"' version.log
    grep -F '"changeset": "9a1c92a894a3c6bf9a1b681548161b49f384d872"' version.log

    $out/bin/pcsx-redux -dumpproto > schema.proto
    grep -F "syntax = \"proto3\"" schema.proto

    openbios="$out/share/pcsx-redux/resources/openbios.bin"
    test -f "$openbios"
    test "$(stat -c %s "$openbios")" -eq 524288
    grep -a -F "OpenBIOS" "$openbios"

    test -f "$out/share/applications/pcsx-redux.desktop"
    test -f "$out/share/icons/hicolor/256x256/apps/pcsx-redux.png"
    test -f "$out/share/pcsx-redux/resources/pcsx-redux.ico"
    test -f "$out/share/pcsx-redux/resources/gamecontrollerdb.txt"
    test -n "$(find "$out/share/pcsx-redux/fonts" -type f -print -quit)"
    test -n "$(find "$out/share/pcsx-redux/i18n" -name '*.po' -print -quit)"

    runHook postInstallCheck
  '';

  passthru = {
    componentLicenses = {
      emulator = lib.licenses.gpl2Plus;
      openbios = lib.licenses.mit;
    };
    inherit submodules;
  };

  meta = {
    description = "PlayStation 1 emulator and debugger with OpenBIOS";
    longDescription = ''
      PCSX-Redux is a GPL-2.0-or-later PlayStation emulator and debugger.
      This package includes its separately MIT-licensed OpenBIOS firmware.
    '';
    homepage = "https://pcsx-redux.consoledev.net";
    license = [
      lib.licenses.gpl2Plus
      lib.licenses.mit
    ];
    mainProgram = "pcsx-redux";
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
    ];
  };
}
