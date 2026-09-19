#!/usr/bin/env -S nix shell nixpkgs#bash nixpkgs#gh nixpkgs#jq nixpkgs#prefetch-npm-deps nixpkgs#moreutils nixpkgs#coreutils --command bash

# flake-lib artifactHook piece for unsloth-studio's vendored frontend: regenerates
# package.json/package-lock.json from upstream@NEW_REV and prints `npmDepsHash=<hash>`.
# Composed with flake-lib's python wheelhouse hook by mkComposedHook.

set -euo pipefail

FRONTEND="${FLAKE_ROOT}/pkgs/unsloth-studio-frontend"

echo "Regenerating frontend package.json + package-lock.json..." >&2
WORK=$(mktemp -d)
trap 'rm -rf "${WORK}"' EXIT
(
  cd "${WORK}"
  gh api "/repos/${GH_OWNER}/${GH_REPO}/contents/studio/frontend/package.json?ref=${NEW_REV}" \
    --jq '.content' | base64 -d > package.json
  gh api "/repos/${GH_OWNER}/${GH_REPO}/contents/studio/frontend/package-lock.json?ref=${NEW_REV}" \
    --jq '.content' | base64 -d > package-lock.json
  # `react-is` is recharts' peerDependency; rolldown/vite's strict resolver fails to find it via peers, so add it as a direct dep matching the range upstream uses for `react`.
  REACT_RANGE=$(jq -r '.dependencies.react' package.json)
  jq \
    --arg reactRange "${REACT_RANGE}" \
    '.dependencies["react-is"] = $reactRange' \
    package.json | sponge package.json
  jq \
    --arg reactRange "${REACT_RANGE}" \
    '.packages[""].dependencies["react-is"] = $reactRange' \
    package-lock.json | sponge package-lock.json
)
cp "${WORK}/package.json" "${FRONTEND}/package.json"
cp "${WORK}/package-lock.json" "${FRONTEND}/package-lock.json"

echo "Computing npm deps hash..." >&2
NPM_HASH=$(prefetch-npm-deps "${FRONTEND}/package-lock.json")

echo "npmDepsHash=${NPM_HASH}"
