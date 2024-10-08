# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: 2024 Jiuyang Liu <liu@jiuyang.me>

{ lib
, stdenv
, fetchMillDeps
, makeWrapper
, jdk21

  # chisel deps
, mill
, espresso
, circt-full
, jextract-21
, add-determinism

, projectDependencies

, target
}:

let
  self = stdenv.mkDerivation rec {
    name = "sdram";

    mainClass = "oscc.sdramcontroller.elaborator.${target}Main";

    src = with lib.fileset;
      toSource {
        root = ./../..;
        fileset = unions [
          ./../../build.sc
          ./../../common.sc
          ./../../sdramcontroller
          ./../../elaborator
        ];
      };

    passthru = {
      millDeps = fetchMillDeps {
        inherit name;
        src = with lib.fileset;
          toSource {
            root = ./../..;
            fileset = unions [ ./../../build.sc ./../../common.sc ];
          };
        millDepsHash = "sha256-vG0sLWwKrCcpZuqXolz3UKQTZD1R9jk2p2psNaMiLl0=";
        nativeBuildInputs = [ projectDependencies.setupHook ];
      };

      editable = self.overrideAttrs (_: {
        shellHook = ''
          setupSubmodulesEditable
          mill mill.bsp.BSP/install 0
        '';
      });

      inherit target;
    };

    passthru.elaborateTarget = target;

    shellHook = ''
      setupSubmodules
    '';

    nativeBuildInputs = [
      mill
      circt-full
      jextract-21
      add-determinism
      espresso

      makeWrapper
      passthru.millDeps.setupHook

      projectDependencies.setupHook
    ];

    env.CIRCT_INSTALL_PATH = circt-full;

    outputs = [ "out" "elaborator" ];

    meta.mainProgram = "elaborator";

    buildPhase = ''
      mill -i '__.assembly'
    '';

    installPhase = ''
      mkdir -p $out/share/java

      add-determinism -j $NIX_BUILD_CORES out/elaborator/assembly.dest/out.jar

      mv out/elaborator/assembly.dest/out.jar $out/share/java/elaborator.jar

      mkdir -p $elaborator/bin
      makeWrapper ${jdk21}/bin/java $elaborator/bin/elaborator \
        --add-flags "--enable-preview -Djava.library.path=${circt-full}/lib -cp $out/share/java/elaborator.jar ${mainClass}"
    '';
  };
in
self
