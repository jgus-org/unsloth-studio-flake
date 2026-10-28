{
  description = "Unsloth Studio: AGPL-licensed CLI + web UI assembled from the unslothai/unsloth source tree.";

  inputs = {
    flake-lib.url = "github:jgus-org/flake-lib/v1";
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
  };

  outputs =
    {
      self,
      flake-lib,
      nixpkgs,
      ...
    }:
    let
      pin = import ./pin.nix;
      inherit (pin)
        npmDepsHash
        sourceHash
        sourceRev
        version
        ;
      source = {
        owner = "unslothai";
        repo = "unsloth";
        type = "github";
      };
      overlay =
        final: prev:
        let
          src = final.fetchFromGitHub {
            hash = sourceHash;
            owner = "unslothai";
            repo = "unsloth";
            rev = sourceRev;
          };
          patchedSrc = final.applyPatches {
            inherit src;
            name = "unsloth-studio-dual-stack-source-${version}";
            patches = [ ./patches/dual-stack-ipv6.patch ];
          };
          unsloth-studio-frontend = final.callPackage ./pkgs/unsloth-studio-frontend {
            inherit npmDepsHash src version;
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
                inherit unsloth-studio-frontend version;
                inherit (flake-lib.lib) mkWheelhouseSiteTree;
                pkgs = final;
                python = pyfinal.python;
                src = patchedSrc;
                wheelhouse =
                  (flake-lib.lib.mkWheelhouse {
                    noEmit = providedByDeployment;
                    pkgs = final;
                    wheels =
                      (flake-lib.lib.wheelhouseArtifactPaths {
                        pythonVersion = pyfinal.python.pythonVersion;
                        root = ./.;
                        system = final.stdenv.hostPlatform.system;
                      }).wheelManifest;
                  }).wheelhouse;
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
          overlays = [ overlay ];
        };
        orgFormatting = flake-lib.lib.mkFormatting {
          inherit self system;
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
          sources = [
            {
              groups = [
                "studio"
                "huggingfacenotorch"
              ];
              kind = "source-pyproject";
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
          systems = flake-lib.lib.defaultLinuxSystems;
        };
        updateVersion = flake-lib.lib.mkUpdateVersion {
          inherit pkgs source;
          artifactFingerprint = pythonWheelhouse.fingerprint;
          artifactHook = flake-lib.lib.mkComposedHook {
            inherit pkgs;
            hooks = [
              (pkgs.lib.getExe frontendRegen)
              (pkgs.lib.getExe pythonWheelhouse.hook)
            ];
          };
          extraHashes = [
            "npmDepsHash"
            "requirementsHash"
            "wheelManifestHash"
          ];
        };
        dualStackRegression = pkgs.callPackage ./tests/dual-stack.nix {
          python = pkgs.python3;
          src = pkgs.python3.pkgs.unsloth-studio.src;
          upstreamSrc = pkgs.unsloth-studio-frontend.src;
        };
      in
      {
        checks = {
          dual-stack = dualStackRegression;
          formatting = orgFormatting.check;
        };
        formatter = orgFormatting.formatter;
        packages = {
          inherit (pkgs) unsloth-studio-frontend;
          inherit (pkgs.python3.pkgs) unsloth-studio;
          default = pkgs.python3.pkgs.unsloth-studio;
          dual-stack-regression = dualStackRegression;
          update-branches = flake-lib.lib.mkUpdateBranches {
            inherit pkgs source;
            extraBranchOwnedFiles = [
              "pkgs/unsloth-studio-frontend/package.json"
              "pkgs/unsloth-studio-frontend/package-lock.json"
            ];
            extraHashes = [
              "npmDepsHash"
              "requirementsHash"
              "wheelManifestHash"
            ];
            minimumTrackingVersion = "0.1.70-beta";
            pinSchema = "github-npm";
            versionCanon = [ ''s/^0\.1\.([0-9]{2})([0-9])-beta$/0.1.\1.\2-beta/'' ];
          };
          # update-branches builds packages.default before each branch's commit or publication; the dual-stack regression is not covered by that build. Run this focused check after every invocation.
          update-version = pkgs.writeShellApplication {
            name = "update-version";
            runtimeInputs = [ pkgs.nix ];
            text = ''
              ${pkgs.lib.getExe updateVersion} "$@"
              nix build --option post-build-hook "" "''${FLAKE_ROOT:-.}#dual-stack-regression" --no-link
            '';
          };
        };
      }
    )
    // {
      overlays.default = overlay;
    };
}
