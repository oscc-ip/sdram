{ lib
, stdenv
, fetchMillDeps
, makeWrapper
, jdk21

, mill
, espresso
, circt-full
, jextract-21
, strip-nondeterminism

, submodules
}:

let
  self = stdenv.mkDerivation rec {
    name = "oscc-ip";

    src = with lib.fileset; toSource {
      root = ./..;
      fileset = unions [
        ./../build.sc
        ./../common.sc
        ./../sdramcontroller
      ];
    };

    passthru.millDeps = fetchMillDeps {
      inherit name;
      src = with lib.fileset; toSource {
        root = ./..;
        fileset = unions [
          ./../build.sc
          ./../common.sc
        ];
      };
      millDepsHash = "sha256-z6fEcvmOlkmP8nGPgVSYOPyXaSqgrjYqHrJ5ipB2Xsc=";
      nativeBuildInputs = [ submodules.setupHook ];
    };

    passthru.editable = self.overrideAttrs (_: {
      shellHook = ''
        setupSubmodulesEditable
        mill mill.bsp.BSP/install 0
      '';
    });

    shellHook = ''
      setupSubmodules
    '';

    nativeBuildInputs = [
      mill
      circt-full
      jextract-21
      strip-nondeterminism

      makeWrapper
      passthru.millDeps.setupHook

      submodules.setupHook
    ];

    env.CIRCT_INSTALL_PATH = circt-full;

    outputs = [ "out" "elaborator" ];

    buildPhase = ''
      mill -i '__.assembly'
      mill -i t1package.sourceJar
      mill -i t1package.chiselPluginJar
    '';

    installPhase = ''
      mkdir -p $out/share/java
      strip-nondeterminism out/elaborator/assembly.dest/out.jar
      makeWrapper ${jdk21}/bin/java $elaborator/bin/elaborator --add-flags "--enable-preview -Djava.library.path=${circt-full}/lib -jar $out/share/java/elaborator.jar"
    '';
  };
in
self
