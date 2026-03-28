{
  lib,
  stdenv,
  fetchFromGitHub,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "dmtcp";
  version = "4.1.0";

  src = fetchFromGitHub {
    owner = "dmtcp";
    repo = "dmtcp";
    tag = finalAttrs.version;
    hash = "sha256-5laifZ/8oYJrNO5JOggCbPKmA9XiHEC79C/hk+0TdeQ=";
  };

  patches = [
    # dmtcp needs patching to support the longer ld-linux-*.so file path in nix
    ./ld-linux-so-buffer-size.patch
  ];

  postPatch = ''
    patchShebangs .

    substituteInPlace configure \
      --replace-fail \
        '#define ELF_INTERPRETER \"$interp\"' \
        "#define ELF_INTERPRETER \\\"$(cat $NIX_CC/nix-support/dynamic-linker)\\\""

    substituteInPlace src/restartscript.cpp \
      --replace-fail /bin/bash ${stdenv.shell}

    substituteInPlace util/dmtcp_restart_wrapper.sh \
      --replace-fail /bin/bash ${stdenv.shell}
  '';

  enableParallelBuilding = true;

  # mtcp_restart is statically built w/ no libc
  dontDisableStatic = true;

  doCheck = false;
  doInstallCheck = true;

  # - `dmtcp_* --version` exits with code=1 for whatever reason
  # - checkpointing only appears to work outside a build sandbox or VM test.
  installCheckPhase = ''
    runHook preInstallCheck

    export PATH="$out/bin:$PATH"

    (dmtcp_coordinator --version 2>&1 || true) | grep -q "DMTCP"
    (dmtcp_launch --version 2>&1 || true) | grep -q "DMTCP"
    (dmtcp_restart --version 2>&1 || true) | grep -q "DMTCP"
    (dmtcp_command --version 2>&1 || true) | grep -q "DMTCP"

    dmtcp_coordinator --daemon
    dmtcp_launch --join-coordinator sleep 30 &

    for i in $(seq 0 100); do
      if dmtcp_command --status | grep -q 'RUNNING=yes'; then
        break
      fi
      [[ "$i" = "100" ]] && exit 1
      sleep 0.1
    done

    dmtcp_command --quit

    runHook postInstallCheck
  '';

  meta = {
    description = "Distributed MultiThreaded Checkpointing";
    longDescription = ''
      DMTCP (Distributed MultiThreaded Checkpointing) is a tool for
      transparently checkpointing the state of an arbitrary group of
      programs spread across many machines and connected by sockets. It does
      not modify the user's program or the operating system.
    '';
    homepage = "https://github.com/dmtcp/dmtcp";
    license = lib.licenses.lgpl3Plus;
    mainProgram = "dmtcp_launch";
    # > DMTCP supports:
    # > * most Linux distros
    # > * x86_64, i386, arm64, risc-v
    platforms = lib.intersectLists lib.platforms.linux (
      lib.platforms.x86 ++ lib.platforms.aarch64 ++ lib.platforms.riscv
    );
  };
})
