if [$DEBUG] ; then 
    gdb --args luajit loader.lua
else 
    luajit loader.lua
fi
