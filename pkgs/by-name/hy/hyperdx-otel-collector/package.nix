{
  buildGoModule,
  fetchFromGitHub,
  go,
  hyperdx,
  lib,
  opentelemetry-collector-builder,
  stdenvNoCC,
}:

let
  # An opentelemetry collector distribution uses `ocb`
  # (opentelemetry-collector-builder) to codegen a go project. This fixed-output
  # derivation contains the generated source + go.sum lockfile.
  otelcolSrc = stdenvNoCC.mkDerivation (finalAttrs: {
    pname = "otelcol-hyperdx-source";
    inherit (hyperdx) version src;
    otelCollectorVersion = "0.151.0";

    setSourceRoot = ''
      sourceRoot=$(echo */packages/otel-collector)
    '';

    nativeBuildInputs = [
      go
      opentelemetry-collector-builder
    ];

    outputHash = "sha256-I9FucFk2yZPl97FjAKZ27+e1lQNuvb+ey7DpkfdwmzM=";
    outputHashMode = "recursive";
    outputHashAlgo = if finalAttrs.outputHash == "" then "sha256" else null;

    configurePhase = ''
      runHook preConfigure
      export HOME=$NIX_BUILD_TOP/home

      otelCollectorVersionSrc="$(grep -oP '^OTEL_COLLECTOR_VERSION=\K.*' ../../.env)"
      otelCollectorCoreVersion="$(grep -oP '^OTEL_COLLECTOR_CORE_VERSION=\K.*' ../../.env)"

      if [[ "$otelCollectorVersion" != "$otelCollectorVersionSrc" ]]; then
        echo >&2 "error(nixpkgs): opentelemetry-collector version doesn't match"
        echo >&2 "    repo .env: $otelCollectorVersionSrc"
        echo >&2 "  nix package: $otelCollectorVersion"
        exit 1
      fi

      substituteInPlace builder-config.yaml \
        --replace-fail "__OTEL_COLLECTOR_VERSION__" "$otelCollectorVersion" \
        --replace-fail "__OTEL_COLLECTOR_CORE_VERSION__" "$otelCollectorCoreVersion" \
        --replace-fail "output_path: /build/output" "output_path: $out/"

      runHook postConfigure
    '';

    env.CGO_ENABLED = 0;

    buildPhase = ''
      runHook preBuild
      ocb --config=builder-config.yaml --skip-compilation
      runHook postBuild
    '';
  });

  # The ClickHouse schema migration binary
  migrate = buildGoModule (finalAttrs: {
    inherit (hyperdx) version src;

    pname = "hyperdx-otel-collector-migrate";

    modRoot = "./packages/otel-collector";

    vendorHash = "sha256-I2KOIDzWHgnS32NKnyf2R7YQ9J39oZJzvh47Ki6RiQs=";

    env.CGO_ENABLED = "0";
    ldflags = [
      "-s"
      "-w"
    ];
  });

  # Build the `opampsupervisor` from the opentelemetry contrib repo with the
  # right version. This is an optional component.
  opampsupervisor = buildGoModule (finalAttrs: {
    pname = "opampsupervisor";
    version = otelcolSrc.otelCollectorVersion;

    src = fetchFromGitHub {
      owner = "open-telemetry";
      repo = "opentelemetry-collector-contrib";
      tag = "v${finalAttrs.version}";
      hash = "sha256-FzjtVsmaiaC3W93QgXv8SdjwAVx6QQozsMOITHrntgU=";
    };

    modRoot = "./cmd/opampsupervisor";

    vendorHash = "sha256-hjVPT3Q1Vfs+6iV4zpg7GN+mcQAe558QVxRGpAUDjig=";

    env.CGO_ENABLED = 0;
    ldflags = [
      "-s"
      "-w"
    ];
  });

in
# The main HyperDX opentelemetry-collector distribution binary
buildGoModule (finalAttrs: {
  pname = "hyperdx-otel-collector";
  inherit (hyperdx) version;

  src = otelcolSrc;
  hyperdxSrc = hyperdx.src;

  vendorHash = "sha256-iZPN6AKElXHHQ08q8AAxkNsGEkSEiwlZI4CVEnKW1/I=";

  env.CGO_ENABLED = "0";
  ldflags = [
    "-s"
    "-w"
  ];

  postInstall = ''
    mkdir -p $out/share/otelcol-contrib $out/share/otel

    mv $out/bin/builder $out/bin/otelcontribcol
    ln -s ${migrate}/bin/migrate $out/bin/
    ln -s ${opampsupervisor}/bin/opampsupervisor $out/bin/

    install -Dm644 $hyperdxSrc/docker/otel-collector/config.yaml $out/share/otelcol-contrib/config.yaml
    install -Dm644 $hyperdxSrc/docker/otel-collector/config.standalone.yaml $out/share/otelcol-contrib/standalone-config.yaml
    install -Dm644 $hyperdxSrc/docker/otel-collector/config.standalone.auth.yaml $out/share/otelcol-contrib/standalone-auth-config.yaml

    install -Dm644 $hyperdxSrc/docker/otel-collector/supervisor_docker.yaml.tmpl $out/share/otel/supervisor.yaml.tmpl
    cp -a $hyperdxSrc/docker/otel-collector/schema $out/share/otel/
  '';

  passthru = {
    inherit migrate opampsupervisor;
  };

  meta = {
    description = "HyperDX opentelemetry-collector distribution";
    homepage = "https://www.hyperdx.io/";
    licenses = with lib.licenses; [
      mit
      asl20
    ];
    mainProgram = "otelcontribcol";
    maintainers = with lib.maintainers; [ phlip9 ];
  };
})
