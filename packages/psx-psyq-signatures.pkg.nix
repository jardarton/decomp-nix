{ fetchFromGitHub }:
# Public PsyQ SDK object signatures (relocation-masked byte patterns with
# function labels) and BIOS call tables. Necrompiler embeds them to identify
# SDK library code. Upstream publishes no license file.
(fetchFromGitHub {
  owner = "lab313ru";
  repo = "psx_psyq_signatures";
  rev = "e9e46e7e133ef275a79bfce650924f98edb086bc";
  hash = "sha256-AG9H24r3xSC7R3DDO8OtMKoNhDisNL1JqLSUTxwadXY=";
}).overrideAttrs
  {
    meta = {
      description = "PsyQ SDK library signatures in JSON form";
      homepage = "https://github.com/lab313ru/psx_psyq_signatures";
    };
  }
