{ lib
, makeWrapper
, stdenv
, src
, version
, unsloth-studio-frontend
, writeText
, python
, uv
, zlib
, wheelhouse
, installWheelhouse
, currentPython
}:
assert python.pythonVersion == currentPython
  || throw "unsloth-studio: no vendored wheelhouse for CPython ${python.pythonVersion} (current: ${currentPython}; readiness: see python-readiness.json)";
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
stdenv.mkDerivation {
  pname = "unsloth-studio";
  inherit version;

  inherit src;

  nativeBuildInputs = [
    makeWrapper
    python
    uv
  ];
  buildInputs = [
    stdenv.cc.cc.lib
    zlib
  ];

  dontBuild = true;
  doInstallCheck = true;

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

  installPhase = ''
    runHook preInstall
    export HOME="$TMPDIR"
    export PYTHONNOUSERSITE=1
    mkdir -p "${siteDir}" "$out/bin"
    ${installWheelhouse { inherit python; target = siteDir; inherit wheelhouse; }}
    export PYTHONPATH="${siteDir}"
    uv pip install \
      --python ${python.interpreter} \
      --target "${siteDir}" \
      --no-index \
      --no-deps \
      --no-build-isolation \
      "$PWD"
    runHook postInstall
  '';

  postInstall = ''
    # Optional multi-node transport/bootstrap plugins (MPI, pmix, libfabric, UCX,
    # IBGDA) whose dependencies nothing in the single-host runtime loads. nvshmem's
    # default bootstrap and the CUDA transport stay.
    rm -f \
      "${siteDir}"/nvidia/nvshmem/lib/nvshmem_bootstrap_mpi.so.3 \
      "${siteDir}"/nvidia/nvshmem/lib/nvshmem_bootstrap_pmix.so.3 \
      "${siteDir}"/nvidia/nvshmem/lib/nvshmem_transport_libfabric.so.3 \
      "${siteDir}"/nvidia/nvshmem/lib/nvshmem_transport_ucx.so.3 \
      "${siteDir}"/nvidia/nvshmem/lib/nvshmem_transport_ibgda.so.3
  '';

  postFixup = ''
    for script in "${siteDir}"/bin/*; do
      name=$(basename "$script")
      makeWrapper "$script" "$out/bin/$name" \
        --set PYTHONNOUSERSITE 1 \
        --set LD_LIBRARY_PATH "${stdenv.cc.cc.lib}/lib:${zlib}/lib:/run/opengl-driver/lib:${siteDir}/torch/lib" \
        --prefix PYTHONPATH : "${siteDir}"
    done
  '';

  # The CLI module is a typer app that imports studio.backend at invoke time; importing it eagerly here pulls in ~200MB of torch/transformers init paths for no real verification value.
  installCheckPhase = ''
    runHook preInstallCheck
    export PYTHONPATH="${siteDir}"
    ${python.interpreter} -c "import unsloth_cli, studio"
    runHook postInstallCheck
  '';

  passthru = {
    inherit src;
    pythonModule = python;
    sitePackages = python.sitePackages;
  };

  meta = {
    description = "Unsloth Studio: web UI + CLI for training and running open models locally";
    homepage = "https://github.com/unslothai/unsloth";
    license = lib.licenses.agpl3Only;
    mainProgram = "unsloth";
    platforms = lib.platforms.linux;
  };
}
