{ lib
, buildPythonPackage
, setuptools
, src
, version
, unsloth-studio-frontend
, writeText
, python
, hostPlatform
, evalMarkerTree
, dependencyOverrides ? { }
}:
# Combined unsloth_cli + studio Python package, AGPL. The two are tightly coupled (CLI imports studio.backend) so we ship them together. The Apache-licensed `unsloth/` python lib is supplied by nixpkgs and stripped from our source tree to avoid duplication.
let
  upstreamRequirements = import ./upstream-deps.nix;
  upstreamNames = map (requirement: requirement.name) upstreamRequirements;
  extraDeps = [
    "aiohttp"
    "python-multipart"
    "sse-starlette"
    "starlette"
    "websockets"

    "hf-xet"
    "safetensors"
    "tokenizers"

    "tiktoken"

    "torch"
    "torchaudio"
    "torchvision"
    "triton"

    "pillow"
    "scikit-learn"
    "scipy"

    "gitpython"
    "jinja2"
    "msgspec"
    "requests"
    "tabulate"
    "unsloth"
  ];
  markerBindings = {
    sys_platform = "linux";
    platform_machine = hostPlatform.parsed.cpu.name;
    python_version = python.pythonVersion;
  };
  markerApplies = marker: evalMarkerTree markerBindings marker;
  activeUpstreamRequirements = lib.filter (requirement: markerApplies requirement.marker) upstreamRequirements;
  dependencyFor = name: dependencyOverrides.${name} or python.pkgs.${name};
  projectRequirements =
    map (requirement: requirement.requirement) upstreamRequirements
    ++ lib.filter (name: !(builtins.elem name upstreamNames)) extraDeps;
  # Replaces upstream's pyproject.toml so we drop:
  #   - the dynamic version attr that read unsloth.models._utils.__version__ (we rm the unsloth/ subtree below)
  #   - everything except the unsloth_cli + studio packages
  #   - obsolete runtime dep version pins
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
    dependencies = ${builtins.toJSON projectRequirements}

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
buildPythonPackage {
  pname = "unsloth-studio";
  inherit version;
  pyproject = true;

  inherit src;

  postPatch = ''
    # Strip out upstream pieces we don't ship from this derivation:
    #   unsloth/        — nixpkgs Apache lib supplies it
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

  build-system = [ setuptools ];

  dependencies = map dependencyFor (lib.unique (map (requirement: requirement.name) activeUpstreamRequirements ++ extraDeps));

  # The CLI module is a typer app that imports studio.backend at invoke time; importing it eagerly here pulls in ~200MB of torch/transformers init paths for no real verification value.
  pythonImportsCheck = [ "unsloth_cli" "studio" ];

  meta = {
    description = "Unsloth Studio: web UI + CLI for training and running open models locally";
    homepage = "https://github.com/unslothai/unsloth";
    license = lib.licenses.agpl3Only;
    mainProgram = "unsloth";
    platforms = lib.platforms.linux;
  };
}
