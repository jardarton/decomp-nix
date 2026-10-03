{
  fetchPypi,
  python3Packages,
  rabbitizer,
  spimdisasm,
  pylibyaml,
}:
python3Packages.buildPythonApplication {
  pname = "splat64";
  version = "0.50.0";
  pyproject = true;
  src = fetchPypi {
    pname = "splat64";
    version = "0.50.0";
    hash = "sha256-9TvDo/7NG3oBNnUJvs51ScWOjLmEmASr2eDzD34Vywo=";
  };
  # Splat imports optional N64 codecs eagerly even for PS1 inputs.
  # Keep this closure PS1-only; platform modules remain dynamic.
  postPatch = ''
    substituteInPlace src/splat/segtypes/__init__.py \
      --replace-fail 'from . import n64 as n64' ""
    substituteInPlace src/splat/util/__init__.py \
      --replace-fail 'from . import palettes as palettes' ""
    sed -i '/if options.opts.is_mode_active("img"):/,+1d' src/splat/scripts/split.py
    substituteInPlace src/splat/scripts/split.py \
      --replace-fail 'from ..util import conf, log, options, palettes, symbols, relocs' \
                     'from ..util import conf, log, options, symbols, relocs'
  '';
  build-system = [ python3Packages.hatchling ];
  dependencies = with python3Packages; [
    colorama
    intervaltree
    pylibyaml
    pyyaml
    rabbitizer
    spimdisasm
    tqdm
  ];
  pythonRelaxDeps = true;
}
