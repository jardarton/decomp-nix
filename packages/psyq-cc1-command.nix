{
  binary,
  executable,
  qemu-user,
  stdenv,
  writeShellScriptBin,
}:
# The fetched ELF is a Linux i386 executable. Keep its identity separate from
# the command used by hosts that need emulation or cannot execute it.
if stdenv.hostPlatform.system == "x86_64-linux" then
  # Set command metadata after constructing the binary: setting mainProgram
  # inside mkDerivation adds NIX_MAIN_PROGRAM and changes its store path.
  binary
  // {
    meta = binary.meta // {
      mainProgram = executable;
    };
  }
else if stdenv.hostPlatform.system == "aarch64-linux" then
  writeShellScriptBin executable ''
    exec ${qemu-user}/bin/qemu-i386 ${binary}/bin/${executable} "$@"
  ''
else
  writeShellScriptBin "psyq-cc1-unsupported" "exit 126"
