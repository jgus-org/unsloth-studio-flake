# Unsloth Studio flake

A Nix flake that packages [Unsloth Studio](https://github.com/unslothai/unsloth), the AGPL-licensed CLI and
web UI for training and running open models, as a Nix-built Python environment with its upstream web console.

## Outputs

- `overlays.default` — the deployment interface. It adds `python3.pkgs.unsloth-studio` and
  `unsloth-studio-frontend` to the package set you apply it to.
- `packages.<system>.default`, `packages.<system>.unsloth-studio` — the packaged application.
- `packages.<system>.unsloth-studio-frontend` — the prebuilt static assets for the web UI, on their own.
- `checks.<system>.dual-stack` — the regression for the IPv6 behaviour described below.

Build hosts are `x86_64-linux` and `aarch64-linux`. The wheelhouse is cut for CPython 3.13 and 3.14; other
interpreter versions have no vendored dependency set and the package does not build against them.

## Consuming it

Apply `overlays.default` to the package set that already provides your GPU stack, then join the two site
trees with `PYTHONPATH`:

```nix
pkgs = import nixpkgs {
  inherit system;
  overlays = [ inputs.unsloth-studio.overlays.default ];
};
pythonEnv = pkgs.python3.withPackages (ps: [ ps.torch ps.torchvision ps.torchaudio ]);
app = pkgs.python3.pkgs.unsloth-studio;

# The vendored tree leads so the application resolves against the dependency set it was cut with;
# the CUDA environment behind it supplies torch and the names it shadows.
environment.PYTHONPATH = "${app}/${pkgs.python3.sitePackages}:${pythonEnv}/${pythonEnv.sitePackages}";
```

The `unsloth` wrapper in `app` prefixes the vendored tree onto whatever `PYTHONPATH` the process already
has, so exporting the CUDA environment as above is enough to run it.

## CUDA is the consumer's

The flake builds no torch, and its vendored wheelhouse deliberately excludes every CUDA-providing
distribution — `torch`, `torchvision`, `torchaudio`, `triton`, `torchao`, `bitsandbytes`, `xformers`,
`nvidia-*` and `cuda-toolkit`. Nothing in the flake's own outputs carries a CUDA version, so the same
producer source builds against whatever `cudaPackages` your deployment selects. `packages.<system>.default`
is the build-verification target for a version bump, not a runnable program: on its own it has no torch.

Do not merge the vendored tree into the torch environment. Both trees ship names like `filelock`, and a
merged tree resolves neither; keep them separate and let `PYTHONPATH` order decide, as above.

## Runtime assumptions

Importing `studio` patches `socket.socket.setsockopt` for the whole Python process so that an IPv6 wildcard
listener stays reachable from IPv4 clients, which `asyncio` would otherwise bind IPv6-only. It suppresses
truthy `IPV6_V6ONLY` requests only: explicit zero values and all other socket options pass through, and the
system's own socket default is unchanged. The patched listener needs the usual Linux default
`net.ipv6.bindv6only=0`. Because the patch is process-wide, it also applies to any other socket that the
application or a library it loads opens in the same process.

`checks.<system>.dual-stack` loads the real entrypoint from the packaged and the upstream source, checks the
service arguments and the `setsockopt` behaviour, and exchanges data over IPv6 and IPv4 loopback. It does
not load the GPU application, build the frontend, or validate inference.

## Licence

Unsloth Studio and its bundled frontend assets are AGPL-3.0-only; shipping the service carries those
obligations. The vendored Python dependencies keep their own licences.
