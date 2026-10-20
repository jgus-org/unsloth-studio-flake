{ lib
, buildNpmPackage
, src
, version
, npmDepsHash
, nodejs
, python3        # node-gyp builds in @swc/* etc. expect python on PATH
, ...
}:
buildNpmPackage {
  pname = "unsloth-studio-frontend";
  inherit src version npmDepsHash;
  sourceRoot = "${src.name}/studio/frontend";

  postPatch = ''
    cp ${./package.json} ./package.json
    cp ${./package-lock.json} ./package-lock.json
  '';

  # Upstream's package.json sometimes pins a dep at a version that doesn't satisfy a transitive peer (e.g. v0.1.41-beta and v0.1.405-beta pin `@assistant-ui/tap@0.5.10` while a transitive `@assistant-ui/store@0.2.11` peer-requires `^0.5.11`). update-version.sh already passes this flag when generating the lockfile; we need it again here so `npm ci` doesn't try to re-resolve the peer against the (offline) registry and ENOTCACHED-fail.
  npmFlags = [ "--legacy-peer-deps" ];

  npmBuildScript = "build";

  inherit nodejs;
  nativeBuildInputs = [ python3 ];

  installPhase = ''
    runHook preInstall
    cp -r dist $out
    runHook postInstall
  '';

  meta = {
    description = "Prebuilt static assets for the Unsloth Studio web UI";
    homepage = "https://github.com/unslothai/unsloth";
    license = lib.licenses.agpl3Only;
    platforms = lib.platforms.linux;
  };
}
