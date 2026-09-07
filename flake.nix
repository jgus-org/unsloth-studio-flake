{
  description = "Unsloth Studio: AGPL-licensed CLI + web UI assembled from the unslothai/unsloth source tree.";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    flake-lib = {
      url = "github:jgus-org/flake-lib/v1";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-utils.follows = "flake-utils";
    };
    typer = {
      url = "github:jgus-org/typer-flake";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-utils.follows = "flake-utils";
      inputs.flake-lib.follows = "flake-lib";
    };
    fastapi = {
      url = "github:jgus-org/fastapi-flake";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-utils.follows = "flake-utils";
      inputs.flake-lib.follows = "flake-lib";
    };
    uvicorn = {
      url = "github:jgus-org/uvicorn-flake";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-utils.follows = "flake-utils";
      inputs.flake-lib.follows = "flake-lib";
    };
    pydantic = {
      url = "github:jgus-org/pydantic-flake";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-utils.follows = "flake-utils";
      inputs.flake-lib.follows = "flake-lib";
    };
    packaging = {
      url = "github:jgus-org/packaging-flake";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-utils.follows = "flake-utils";
      inputs.flake-lib.follows = "flake-lib";
    };
    matplotlib = {
      url = "github:jgus-org/matplotlib-flake";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-utils.follows = "flake-utils";
      inputs.flake-lib.follows = "flake-lib";
    };
    pandas = {
      url = "github:jgus-org/pandas-flake";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-utils.follows = "flake-utils";
      inputs.flake-lib.follows = "flake-lib";
    };
    datasets = {
      url = "github:jgus-org/datasets-flake";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-utils.follows = "flake-utils";
      inputs.flake-lib.follows = "flake-lib";
    };
    ddgs = {
      url = "github:jgus-org/ddgs-flake";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-utils.follows = "flake-utils";
      inputs.flake-lib.follows = "flake-lib";
    };
    gguf = {
      url = "github:jgus-org/gguf-flake";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-utils.follows = "flake-utils";
      inputs.flake-lib.follows = "flake-lib";
    };
    sqlite-vec = {
      url = "github:jgus-org/sqlite-vec-flake";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-utils.follows = "flake-utils";
      inputs.flake-lib.follows = "flake-lib";
    };
    nest-asyncio = {
      url = "github:jgus-org/nest-asyncio-flake";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-utils.follows = "flake-utils";
      inputs.flake-lib.follows = "flake-lib";
    };
    diffusers = {
      url = "github:jgus-org/diffusers-flake";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-utils.follows = "flake-utils";
      inputs.flake-lib.follows = "flake-lib";
    };
    transformers = {
      url = "github:jgus-org/transformers-flake";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-utils.follows = "flake-utils";
      inputs.flake-lib.follows = "flake-lib";
    };
    unsloth = {
      url = "github:jgus-org/unsloth-flake";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-utils.follows = "flake-utils";
      inputs.flake-lib.follows = "flake-lib";
    };
  };

  outputs =
    { nixpkgs
    , flake-utils
    , flake-lib
    , typer
    , fastapi
    , uvicorn
    , pydantic
    , packaging
    , matplotlib
    , pandas
    , datasets
    , ddgs
    , gguf
    , sqlite-vec
    , nest-asyncio
    , diffusers
    , transformers
    , unsloth
    , ...
    }:
    let
      pin = import ./pin.nix;
      inherit (pin) version sourceRev sourceHash npmDepsHash;
      source = { type = "github"; owner = "unslothai"; repo = "unsloth"; };

      overlay = final: prev:
        let
          src = final.fetchFromGitHub {
            owner = "unslothai";
            repo = "unsloth";
            rev = sourceRev;
            hash = sourceHash;
          };
          unsloth-studio-frontend = final.callPackage ./pkgs/unsloth-studio-frontend { inherit src version npmDepsHash; };
        in
        {
          inherit unsloth-studio-frontend;
          pythonPackagesExtensions = prev.pythonPackagesExtensions ++ [
            (pyfinal: pyprev:
              let
                packagingInput = packaging.packages.${final.stdenv.hostPlatform.system}.packaging;
                packagingForPython = final.lib.hiPrio (pyfinal.buildPythonPackage {
                  inherit (packagingInput) pname version src;
                  pyproject = true;
                  build-system = [ pyfinal.flit-core ];
                  doCheck = false;
                });
              in
              {
                black = pyprev.black.overridePythonAttrs (oldAttrs: {
                  disabledTests = (oldAttrs.disabledTests or [ ]) ++ [
                    "test_read_pyproject_toml"
                    "test_read_pyproject_toml_from_stdin"
                  ];
                });
                cyclopts = pyprev.cyclopts.overridePythonAttrs (_: {
                  doCheck = false;
                  doInstallCheck = false;
                });
                httpx2 = pyprev.httpx2.overridePythonAttrs (oldAttrs: {
                  disabledTests = (oldAttrs.disabledTests or [ ]) ++ [ "test_download" ];
                });
                inline-snapshot = pyprev.inline-snapshot.overridePythonAttrs (oldAttrs: {
                  disabledTests = (oldAttrs.disabledTests or [ ]) ++ [ "test_empty_sub_snapshot" ];
                });
                mcp = pyprev.mcp.overridePythonAttrs (oldAttrs: {
                  disabledTests = (oldAttrs.disabledTests or [ ]) ++ [
                    "test_sse_client_happy_request_and_response"
                    "test_structured_output_unserializable_type_error"
                  ];
                });
                moto = pyprev.moto.overridePythonAttrs (oldAttrs: {
                  disabledTests = (oldAttrs.disabledTests or [ ]) ++ [ "test_request_certificate_with_optional_arguments" ];
                });
                pyarrow = pyprev.pyarrow.overridePythonAttrs (_: {
                  doCheck = false;
                  doInstallCheck = false;
                });
                sentence-transformers = pyprev.sentence-transformers.overridePythonAttrs (_: {
                  doCheck = false;
                  doInstallCheck = false;
                });
                xformers = pyprev.xformers.overridePythonAttrs (_: {
                  doCheck = false;
                  doInstallCheck = false;
                });
                unsloth-studio = ((pyfinal.callPackage ./pkgs/unsloth-studio {
                  inherit src version unsloth-studio-frontend;
                  inherit (flake-lib.lib) versionMatchesComparison;
                  dependencyOverrides.packaging = packagingForPython;
                }).overridePythonAttrs (oldAttrs: {
                  catchConflicts = false;
                  preInstallPhases = (oldAttrs.preInstallPhases or [ ]) ++ [ "preferPackagingForRuntimeDepsCheck" ];
                  preferPackagingForRuntimeDepsCheck = ''
                    export PYTHONPATH="${packagingForPython}/${pyfinal.python.sitePackages}:''${PYTHONPATH}"
                  '';
                })).overrideAttrs (oldAttrs: {
                  passthru = oldAttrs.passthru // {
                    requiredPythonModules =
                      [ packagingForPython ]
                        ++ final.lib.filter
                        (module: (module.pname or null) != "packaging")
                        oldAttrs.passthru.requiredPythonModules;
                  };
                });
              })
          ];
        };

      composedOverlay = nixpkgs.lib.composeManyExtensions [
        typer.overlays.default
        fastapi.overlays.default
        uvicorn.overlays.default
        pydantic.overlays.default
        matplotlib.overlays.default
        pandas.overlays.default
        datasets.overlays.default
        ddgs.overlays.default
        gguf.overlays.default
        sqlite-vec.overlays.default
        nest-asyncio.overlays.default
        diffusers.overlays.default
        transformers.overlays.default
        unsloth.overlays.default
        overlay
      ];
    in
    flake-utils.lib.eachDefaultSystem
      (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          config.allowUnfree = true;
          overlays = [ composedOverlay ];
        };
        regenArtifacts = pkgs.writeShellApplication {
          name = "regen-artifacts";
          runtimeInputs = [
            pkgs.bash
            pkgs.coreutils
            pkgs.gh
            pkgs.jq
            pkgs.moreutils
            pkgs.prefetch-npm-deps
            (pkgs.python3.withPackages (pythonPackages: [ pythonPackages.packaging ]))
          ];
          text = ''exec ${pkgs.lib.getExe pkgs.bash} ${./regen-artifacts.sh}'';
        };
        pyprojectSibling = reqName: {
          inherit reqName;
          pypiName = reqName;
          flakeRepo = "jgus-org/${reqName}-flake";
          reqFile = "pyproject.toml";
          reqFormat = "pyproject";
          reqGroups = [ "studio" "huggingfacenotorch" ];
        };
        studioRequirementsSibling = reqName: {
          inherit reqName;
          pypiName = reqName;
          flakeRepo = "jgus-org/${reqName}-flake";
          reqFile = "studio/backend/requirements/studio.txt";
          mode = "exact";
        };
      in
      {
        packages = {
          inherit (pkgs) unsloth-studio-frontend;
          inherit (pkgs.python313.pkgs) unsloth-studio;
          update-version = flake-lib.lib.mkUpdateVersion {
            inherit pkgs source;
            buildAttr = "unsloth-studio";
            extraHashes = [ "npmDepsHash" ];
            artifactHook = pkgs.lib.getExe regenArtifacts;
            siblings =
              map pyprojectSibling [
                "typer"
                "fastapi"
                "uvicorn"
                "pydantic"
                "packaging"
                "datasets"
                "ddgs"
                "gguf"
                "sqlite-vec"
                "nest-asyncio"
                "diffusers"
                "transformers"
              ]
              ++ map studioRequirementsSibling [ "matplotlib" "pandas" ];
            siblingRefsInPin = true;
          };
          update-branches = flake-lib.lib.mkUpdateBranches {
            inherit pkgs source;
            pinSchema = "github-npm";
            branchOwnedFiles = [
              "pin.nix"
              "flake.lock"
              "pkgs/unsloth-studio-frontend"
              "pkgs/unsloth-studio/upstream-deps.nix"
            ];
            versionCanon = [ ''s/^0\.1\.([0-9]{2})([0-9])-beta$/0.1.\1.\2-beta/'' ];
          };
          default = pkgs.python313.pkgs.unsloth-studio;
        };
      }) // {
      overlays.default = composedOverlay;
    };
}
