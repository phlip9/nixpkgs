{
  fetchFromGitHub,
  google-fonts,
  lib,
  makeBinaryWrapper,
  nodejs_22,
  stdenvNoCC,
  yarn-berry_4,
}:

let
  # Match upstream nodejs version
  nodejs = nodejs_22;
  yarn-berry = yarn-berry_4;

  google-fonts' = google-fonts.override {
    fonts = [
      "IBM Plex Mono"
      "Inter"
      "Roboto"
      "Roboto Mono"
    ];
  };

in
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "hyperdx";
  version = "2.28.0";

  src = fetchFromGitHub {
    owner = "hyperdxio";
    repo = "hyperdx";
    tag = "@hyperdx/app@${finalAttrs.version}";
    hash = "sha256-9OY0/IKR8qYCZMwIoBxy+tnarf1kyQA+AKw5X5C/ujY=";
  };

  patches = [
    # Prevents NextJS from attempting to download fonts during build. The fonts
    # directory will be created in the derivation script.
    #
    # See similar patches:
    #   pkgs/by-name/li/linkwarden/01-localfont.patch
    #   pkgs/by-name/ne/nextjs-ollama-llm-ui/0002-use-local-google-fonts.patch
    ./use-local-google-fonts.patch

    # Remove after upstream updates to Yarn 4.14
    # https://github.com/hyperdxio/hyperdx/blob/main/package.json#L69
    ./yarn-4.14-support.patch
  ];

  nativeBuildInputs = [
    makeBinaryWrapper
    nodejs
    yarn-berry
    yarn-berry.yarnBerryConfigHook
  ];

  missingHashes = ./missing-hashes.json;

  offlineCache = yarn-berry.fetchYarnBerryDeps {
    inherit (finalAttrs) src missingHashes patches;
    hash = "sha256-xpON84btZwCoaKe0Ps09TYsicu0o3EzvwVmS7qFmjOc=";
  };

  env = {
    CODE_VERSION = finalAttrs.version;
    NEXT_OUTPUT_STANDALONE = "true";
    NEXT_PUBLIC_IS_LOCAL_MODE = "false";
    NEXT_TELEMETRY_DISABLED = "1";
    NODE_ENV = "production";
    OTEL_RESOURCE_ATTRIBUTES = "service.version=${finalAttrs.version}";
    YARN_ENABLE_SCRIPTS = "false";
  };

  buildPhase = ''
    runHook preBuild

    # Copy fonts
    mkdir ./packages/app/public/fonts
    cp \
      '${google-fonts'}/share/fonts/truetype/IBMPlexMono-Light.ttf' \
      '${google-fonts'}/share/fonts/truetype/IBMPlexMono-Regular.ttf' \
      '${google-fonts'}/share/fonts/truetype/IBMPlexMono-Medium.ttf' \
      '${google-fonts'}/share/fonts/truetype/IBMPlexMono-SemiBold.ttf' \
      '${google-fonts'}/share/fonts/truetype/IBMPlexMono-Bold.ttf' \
      '${google-fonts'}/share/fonts/truetype/RobotoMono[wght].ttf' \
      '${google-fonts'}/share/fonts/truetype/Inter[opsz,wght].ttf' \
      '${google-fonts'}/share/fonts/truetype/Roboto[wdth,wght].ttf' \
      ./packages/app/public/fonts/

    # Mirror upstream Dockerfile. Remove migrations/ and scripts/ so TypeScript
    # infers the right rootDir.
    rm -rf packages/api/migrations packages/api/scripts

    yarn workspace @hyperdx/common-utils run build
    yarn workspace @hyperdx/api run build
    yarn workspace @hyperdx/app run build

    # Docker build copies common-utils/node_modules before focusing; stash it
    # now so we can install it later.
    cp -a packages/common-utils/node_modules "$TMPDIR/common-utils-node_modules"

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p \
      $out/bin \
      $out/share/hyperdx/packages/common-utils \
      $out/share/hyperdx/packages/api \
      $out/share/hyperdx/packages/app

    install -Dm755 docker/hyperdx/entry.prod.sh $out/share/hyperdx/entry.prod.sh
    patchShebangs $out/share/hyperdx/entry.prod.sh

    # Reduce closure size. Remove dev dependencies.
    yarn workspaces focus --production @hyperdx/api
    cp -a node_modules $out/share/hyperdx/node_modules

    cp -a "$TMPDIR/common-utils-node_modules" $out/share/hyperdx/packages/common-utils/node_modules
    cp -a packages/common-utils/dist $out/share/hyperdx/packages/common-utils/dist

    cp -a packages/api/bin $out/share/hyperdx/packages/api/bin
    cp -a packages/api/build $out/share/hyperdx/packages/api/build

    # Match the prod Dockerfile NextJS frontend layout
    cp -a packages/app/.next/standalone/. $out/share/hyperdx/packages/app/
    mkdir -p $out/share/hyperdx/packages/app/packages/app/.next
    cp -a packages/app/.next/static $out/share/hyperdx/packages/app/packages/app/.next/static
    cp -a packages/app/public $out/share/hyperdx/packages/app/packages/app/public

    # NextJS standalone preserves a workspace symlink that points to a path that
    # exists in Docker's /app layout, but not after copying the standalone tree
    # under packages/app. Retarget it to the API tree installed above.
    ln -sfnT ../../../api $out/share/hyperdx/packages/app/node_modules/@hyperdx/api

    # Cleanup this dangling symlink after `yarn workspaces focus`
    rm -f $out/share/hyperdx/node_modules/.bin/which

    # The upstream entry script assumes the working directory is /app. Run it
    # from the installed runtime tree and put the pinned Node 22 on PATH.
    makeWrapper $out/share/hyperdx/entry.prod.sh $out/bin/hyperdx \
      --chdir $out/share/hyperdx \
      --prefix PATH : ${lib.makeBinPath [ nodejs ]}

    runHook postInstall
  '';

  passthru = {
    # fonts = google-fonts';
  };

  meta = {
    description = "HyperDX API and app services";
    homepage = "https://www.hyperdx.io/";
    license = lib.licenses.mit;
    mainProgram = "hyperdx";
    maintainers = with lib.maintainers; [ phlip9 ];
  };
})
