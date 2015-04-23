cd src/C/
./build.sh
cp `find -name '*.so'` ../../build/
cd ../..
luajit src/loader.lua $@
#exit
#gdb --directory=src/C/libjit/jit/ \
#    --directory=src/C/ggggc/ \
#    --directory=src/C/runtime.c \
#    --args luajit src/loader.lua
