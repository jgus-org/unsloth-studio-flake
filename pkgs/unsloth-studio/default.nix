{
  lib,
  makeWrapper,
  mkWheelhouseSiteTree,
  pkgs,
  python,
  src,
  unsloth-studio-frontend,
  version,
  wheelhouse,
  writeText,
}:
let
  siteDir = "$out/${python.sitePackages}";
  # Replaces upstream's pyproject.toml so we drop:
  #   - the dynamic version attr that read unsloth.models._utils.__version__ (we rm the unsloth/ subtree below)
  #   - everything except the unsloth_cli + studio packages
  #   - upstream's dependency list entirely: the runtime closure is the vendored wheelhouse
  pyprojectFile = writeText "pyproject.toml" ''
    [build-system]
    requires = ["setuptools"]
    build-backend = "setuptools.build_meta"

    [project]
    name = "unsloth-studio"
    version = "${version}"
    description = "Unsloth Studio: web UI for training and running open models"
    readme = "README.md"
    license = "AGPL-3.0-only"
    requires-python = ">=3.9,<3.15"
    dependencies = []

    [project.scripts]
    unsloth = "unsloth_cli:app"

    [tool.setuptools]
    include-package-data = true

    [tool.setuptools.packages.find]
    include = ["unsloth_cli*", "studio", "studio.backend*"]
    exclude = ["tests*"]

    [tool.setuptools.package-data]
    studio = [
      "*.sh",
      "*.ps1",
      "*.bat",
      "frontend/dist/**/*",
      "frontend/*.json",
      "frontend/*.html",
      "backend/requirements/**/*",
      "backend/plugins/**/*",
      "backend/assets/**/*",
      "backend/core/data_recipe/oxc-validator/*.json",
      "backend/core/data_recipe/oxc-validator/*.mjs",
    ]
  '';
in
mkWheelhouseSiteTree {
  inherit
    pkgs
    python
    src
    version
    wheelhouse
    ;
  # The CUDA stack — torch and what is built against it — comes from the deployment's own
  # package set beside this tree, so these are the native modules this tree ships.
  checkImports = [
    "numpy"
    "scipy"
    "pandas"
    "matplotlib"
    "av"
    "PIL.Image"
    "aiohttp"
    "msgspec"
    "pydantic_core"
    "regex"
    "safetensors"
    "tokenizers"
    "tiktoken"
  ];
  dontBuild = true;
  meta = {
    description = "Unsloth Studio: web UI + CLI for training and running open models locally";
    homepage = "https://github.com/unslothai/unsloth";
    license = lib.licenses.agpl3Only;
    mainProgram = "unsloth";
    platforms = lib.platforms.linux;
  };
  nativeBuildInputs = [ makeWrapper ];
  passthru = {
    inherit src;
    pythonModule = python;
    sitePackages = python.sitePackages;
  };
  pname = "unsloth-studio";
  postFixup = ''
    for script in "${siteDir}"/bin/*; do
      name=$(basename "$script")
      makeWrapper "$script" "$out/bin/$name" \
        --set PYTHONNOUSERSITE 1 \
        --prefix PYTHONPATH : "${siteDir}"
    done
  '';
  postInstall = ''
    export HOME="$TMPDIR"
    export PYTHONNOUSERSITE=1
    export PYTHONPATH="${siteDir}"
    mkdir -p "$out/bin"
    uv pip install \
      --python ${python.interpreter} \
      --target "${siteDir}" \
      --no-index \
      --no-deps \
      --no-build-isolation \
      "$PWD"
  '';
  postPatch = ''
    # Strip out upstream pieces we don't ship from this derivation:
    #   unsloth/        — the PyPI unsloth wheel in the wheelhouse supplies it
    #   tests/          — not relevant to a runtime image
    #   images/         — repo-level docs assets
    #   scripts/        — local-dev helpers
    #   src-tauri/      — desktop wrapper (we run headless)
    #   build.sh / cli.py / unsloth-cli.py — entry shims, replaced by setuptools
    rm -rf \
      unsloth \
      tests \
      images \
      scripts \
      src-tauri \
      build.sh \
      cli.py \
      unsloth-cli.py

    # Overlay the nix-built frontend assets onto studio/frontend/dist.
    rm -rf studio/frontend/dist
    cp -r ${unsloth-studio-frontend} studio/frontend/dist
    chmod -R u+w studio/frontend/dist

    cp ${pyprojectFile} pyproject.toml
  '';
}
