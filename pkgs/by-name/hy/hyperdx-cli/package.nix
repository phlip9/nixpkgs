{
  hyperdx,
  jq,
  lib,
  makeBinaryWrapper,
  nodejs,
  stdenvNoCC,
  versionCheckHook,
  yarn-berry_4,
}:

let
  yarn-berry = yarn-berry_4;

in
stdenvNoCC.mkDerivation (finalAttrs: {
  inherit (hyperdx)
    missingHashes
    offlineCache
    patches
    src
    ;

  pname = "hyperdx-cli";
  version = "0.5.0";

  nativeBuildInputs = [
    jq
    makeBinaryWrapper
    nodejs
    yarn-berry
    yarn-berry.yarnBerryConfigHook
  ];

  env = {
    CODE_VERSION = finalAttrs.version;
    NODE_ENV = "production";
    YARN_ENABLE_SCRIPTS = 0;
  };

  postPatch = ''
    substituteInPlace packages/cli/src/sourcemaps.ts \
      --replace-fail "require('../package.json')" "{ version: '${finalAttrs.version}' }"
  '';

  buildPhase = ''
    runHook preBuild

    yarn workspace @hyperdx/common-utils run build
    yarn workspace @hyperdx/cli run build

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin $out/share/hyperdx
    cp packages/cli/dist/cli.js $out/share/hyperdx/cli.js

    makeWrapper ${lib.getExe nodejs} "$out/bin/hdx" \
      --add-flags "$out/share/hyperdx/cli.js"

    runHook postInstall
  '';

  doCheck = true;
  checkPhase = ''
    runHook preCheck

    yarn workspace @hyperdx/cli run ci:unit

    runHook postCheck
  '';

  doInstallCheck = true;
  nativeInstallCheckInputs = [ versionCheckHook ];

  meta = {
    description = "Command line interface for HyperDX observability.";
    license = lib.licenses.mit;
    mainProgram = "hdx";
    maintainers = with lib.maintainers; [ phlip9 ];
  };
})
