{ runCommand, python, upstreamSrc, src }:
runCommand "unsloth-studio-dual-stack-regression"
{
  nativeBuildInputs = [ (python.withPackages (p: [ p.structlog ])) ];
}
  ''
    export HOME="$TMPDIR/home"
    mkdir -p "$HOME"
    export PYTHONDONTWRITEBYTECODE=1
    export UNSLOTH_STUDIO_DISABLE_PUBLIC_CHECK=1
    unset LD_LIBRARY_PATH
    python ${./dual_stack.py} ${upstreamSrc} upstream -v
    python ${./dual_stack.py} ${src} dual-stack -v
    touch "$out"
  ''
