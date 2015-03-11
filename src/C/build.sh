# Builds and places the appropriate library objects in build/
ROOT="`pwd`"

args="$@"
function buildGggcAndRuntime() {
    echo "Building GGGGC"
    cd ggggc/ && make $args && cp libggggc.so "$ROOT"/../../build
    cd "$ROOT"
}

function buildLibJit() {
    echo "Building LibJIT"
    cd libjit/ && ./auto_gen.sh && ./configure && make $args && cp ./jit/.libs/libjit.so ../../build
    cd "$ROOT"
}

buildGggcAndRuntime
#buildLibJit
