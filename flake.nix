{
  description = "Unsloth Studio: AGPL-licensed CLI + web UI assembled from the unslothai/unsloth source tree.";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    flake-lib = {
      url = "github:jgus-org/flake-lib/v1";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      treefmt-nix,
      flake-lib,
      ...
    }:
    let
      pin = import ./pin.nix;
      inherit (pin)
        version
        sourceRev
        sourceHash
        npmDepsHash
        ;
      source = {
        type = "github";
        owner = "unslothai";
        repo = "unsloth";
      };
      overlay =
        final: prev:
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
          unsloth-studio-frontend = final.callPackage ./pkgs/unsloth-studio-frontend {
            inherit src version npmDepsHash;
          };
          # torch and everything linked against it come from the deployment's own package set,
          # which is where CUDA lives. The lock resolved them so its dependents resolved against
          # their metadata; installing a second copy beside a built torch would let PYTHONPATH
          # order decide which one imports.
          providedByDeployment =
            name:
            final.lib.hasPrefix "nvidia-" name
            || final.lib.elem name [
              "bitsandbytes"
              "cuda-toolkit"
              "torch"
              "torchao"
              "torchaudio"
              "torchvision"
              "triton"
              "xformers"
            ];
        in
        {
          inherit unsloth-studio-frontend;
          pythonPackagesExtensions = prev.pythonPackagesExtensions ++ [
            (pyfinal: pyprev: {
              unsloth-studio = pyfinal.callPackage ./pkgs/unsloth-studio {
                inherit version unsloth-studio-frontend;
                src = patchedSrc;
                python = pyfinal.python;
                pkgs = final;
                wheelhouse =
                  (flake-lib.lib.mkWheelhouse {
                    pkgs = final;
                    wheels =
                      (flake-lib.lib.wheelhouseArtifactPaths {
                        root = ./.;
                        pythonVersion = pyfinal.python.pythonVersion;
                        system = final.stdenv.hostPlatform.system;
                      }).wheelManifest;
                    noEmit = providedByDeployment;
                  }).wheelhouse;
                inherit (flake-lib.lib) mkWheelhouseSiteTree;
              };
            })
          ];
        };
    in
    flake-lib.lib.eachDefaultLinuxSystem (
      system:
      let
        pkgs = import nixpkgs {
          inherit system;
          config.allowUnfree = true;
          overlays = [ overlay ];
        };
        treefmtEval = treefmt-nix.lib.evalModule pkgs {
          projectRootFile = "flake.nix";
          programs.nixfmt.enable = true;
          programs.shfmt.enable = true;
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
          text = "exec ${pkgs.lib.getExe pkgs.bash} ${./regen-frontend-artifacts.sh}";
        };
        pythonWheelhouse = flake-lib.lib.mkPythonWheelhouse {
          inherit pkgs;
          systems = flake-lib.lib.defaultLinuxSystems;
          sources = [
            {
              kind = "source-pyproject";
              groups = [
                "studio"
                "huggingfacenotorch"
              ];
            }
            {
              kind = "source-file";
              path = "studio/backend/requirements/studio.txt";
            }
            {
              kind = "source-file";
              path = "studio/backend/requirements/base.txt";
            }
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
          extraHashes = [
            "npmDepsHash"
            "requirementsHash"
            "wheelManifestHash"
          ];
          artifactFingerprint = pythonWheelhouse.fingerprint;
          artifactHook = flake-lib.lib.mkComposedHook {
            inherit pkgs;
            hooks = [
              (pkgs.lib.getExe frontendRegen)
              (pkgs.lib.getExe pythonWheelhouse.hook)
            ];
          };
        };
        dualStackRegression = pkgs.callPackage ./tests/dual-stack.nix {
          python = pkgs.python3;
          upstreamSrc = pkgs.unsloth-studio-frontend.src;
          src = pkgs.python3.pkgs.unsloth-studio.src;
        };
      in
      {
        checks.dual-stack = dualStackRegression;
        checks.formatting = treefmtEval.config.build.check self;
        formatter = treefmtEval.config.build.wrapper;
        packages = {
          inherit (pkgs) unsloth-studio-frontend;
          inherit (pkgs.python3.pkgs) unsloth-studio;
          dual-stack-regression = dualStackRegression;
          # update-branches builds packages.default before each branch's commit or publication; the dual-stack regression is not covered by that build. Run this focused check after every invocation.
          update-version = pkgs.writeShellApplication {
            name = "update-version";
            runtimeInputs = [ pkgs.nix ];
            text = ''
              ${pkgs.lib.getExe updateVersion} "$@"
              nix build --option post-build-hook "" "''${FLAKE_ROOT:-.}#dual-stack-regression" --no-link
            '';
          };
          update-branches = flake-lib.lib.mkUpdateBranches {
            minimumTrackingVersion = "0.1.70-beta";
            inherit pkgs source;
            pinSchema = "github-npm";
            extraHashes = [
              "npmDepsHash"
              "requirementsHash"
              "wheelManifestHash"
            ];
            extraBranchOwnedFiles = [
              "pkgs/unsloth-studio-frontend/package.json"
              "pkgs/unsloth-studio-frontend/package-lock.json"
            ];
            versionCanon = [ ''s/^0\.1\.([0-9]{2})([0-9])-beta$/0.1.\1.\2-beta/'' ];
          };
          default = pkgs.python3.pkgs.unsloth-studio;
        };
      }
    )
    // {
      overlays.default = overlay;
    };
}
