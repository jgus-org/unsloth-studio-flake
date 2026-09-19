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
  };

  outputs =
    { nixpkgs
    , flake-utils
    , flake-lib
    , ...
    }:
    let
      pin = import ./pin.nix;
      inherit (pin) version sourceRev sourceHash npmDepsHash;
      source = { type = "github"; owner = "unslothai"; repo = "unsloth"; };
      currentPython = builtins.head flake-lib.lib.pythonPolicy.pythonVersions;
      wheelsFileFor = pythonVersion:
        if pythonVersion == currentPython then ./wheels.json
        else ./. + "/wheels-${pythonVersion}.json";
      vendoredPythonVersions = builtins.filter
        (pythonVersion: pythonVersion == currentPython || builtins.pathExists (wheelsFileFor pythonVersion))
        flake-lib.lib.pythonPolicy.pythonVersions;

      overlay = final: prev:
        let
          src = final.fetchFromGitHub {
            owner = "unslothai";
            repo = "unsloth";
            rev = sourceRev;
            hash = sourceHash;
          };
          patchedSrc = final.applyPatches {
            name = "unsloth-studio-dual-stack-source-${version}";
            inherit src;
            patches = [ ./patches/dual-stack-ipv6.patch ];
          };
          unsloth-studio-frontend = final.callPackage ./pkgs/unsloth-studio-frontend { inherit src version npmDepsHash; };
        in
        {
          inherit unsloth-studio-frontend;
          pythonPackagesExtensions = prev.pythonPackagesExtensions ++ [
            (pyfinal: pyprev: {
              unsloth-studio = pyfinal.callPackage ./pkgs/unsloth-studio {
                inherit version unsloth-studio-frontend;
                src = patchedSrc;
                python = pyfinal.python;
                wheelhouse =
                  if builtins.elem pyfinal.python.pythonVersion vendoredPythonVersions then
                    (flake-lib.lib.mkWheelhouse { pkgs = final; wheels = wheelsFileFor pyfinal.python.pythonVersion; }).wheelhouse
                  else
                    throw "unsloth-studio: no vendored wheelhouse for CPython ${pyfinal.python.pythonVersion} (vendored: ${toString vendoredPythonVersions})";
                inherit (flake-lib.lib) installWheelhouse;
              };
            })
          ];
        };
    in
    flake-utils.lib.eachDefaultSystem
      (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          config.allowUnfree = true;
          overlays = [ overlay ];
        };
        frontendRegen = pkgs.writeShellApplication {
          name = "regen-frontend-artifacts";
          runtimeInputs = [
            pkgs.coreutils
            pkgs.gh
            pkgs.jq
            pkgs.moreutils
            pkgs.prefetch-npm-deps
          ];
          text = ''exec ${pkgs.lib.getExe pkgs.bash} ${./regen-frontend-artifacts.sh}'';
        };
        pythonWheelhouse = flake-lib.lib.mkPythonWheelhouse {
          inherit pkgs;
          sources = [
            { kind = "source-pyproject"; groups = [ "studio" "huggingfacenotorch" ]; }
            { kind = "source-file"; path = "studio/backend/requirements/studio.txt"; }
            { kind = "source-file"; path = "studio/backend/requirements/base.txt"; }
          ];
          extraRequirements = [
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
            "setuptools"
          ];
        };
        updateVersion = flake-lib.lib.mkUpdateVersion {
          inherit pkgs source;
          buildAttr = "unsloth-studio";
          extraHashes = [ "npmDepsHash" "pythonEnvironment" "requirementsHash" "wheelManifestHash" ];
          environmentFingerprint = pythonWheelhouse.currentEnvironment.fingerprint;
          artifactHook = flake-lib.lib.mkComposedHook {
            inherit pkgs;
            hooks = [ (pkgs.lib.getExe frontendRegen) (pkgs.lib.getExe pythonWheelhouse.hook) ];
          };
        };
        dualStackRegression = pkgs.callPackage ./tests/dual-stack.nix {
          python = pkgs.python313;
          upstreamSrc = pkgs.unsloth-studio-frontend.src;
          src = pkgs.python313.pkgs.unsloth-studio.src;
        };
      in
      {
        checks.dual-stack = dualStackRegression;
        packages = {
          inherit (pkgs) unsloth-studio-frontend;
          inherit (pkgs.python313.pkgs) unsloth-studio;
          dual-stack-regression = dualStackRegression;
          # flake-lib skips build verification for unchanged pins. Run this focused check after every invocation, including each branch in update-branches, before its commit or publication.
          update-version = pkgs.writeShellApplication {
            name = "update-version";
            runtimeInputs = [ pkgs.nix ];
            text = ''
              ${pkgs.lib.getExe updateVersion} "$@"
              nix build --option post-build-hook "" "''${FLAKE_ROOT:-.}#dual-stack-regression" --no-link
            '';
          };
          update-branches = flake-lib.lib.mkUpdateBranches {
            inherit pkgs source;
            pinSchema = "github-npm";
            extraHashes = [ "npmDepsHash" "requirementsHash" "wheelManifestHash" ];
            branchOwnedFiles = [
              "pin.nix"
              "flake.lock"
              "pkgs/unsloth-studio-frontend"
              "requirements.in"
              "requirements.lock"
              "requirements-*.lock"
              "wheels.json"
              "wheels-*.json"
              "python-readiness.json"
            ];
            versionCanon = [ ''s/^0\.1\.([0-9]{2})([0-9])-beta$/0.1.\1.\2-beta/'' ];
          };
          default = pkgs.python313.pkgs.unsloth-studio;
        };
      }) // {
      overlays.default = overlay;
    };
}
