set -eu
rm -rf /s/luarocks && mkdir -p /s/luarocks/tree
printf 'rocks_servers = {\n   "https://luarocks.org"\n}\nrocks_trees = {\n   { name = "user", root = "/s/aux/home/.luarocks" }\n}\nvariables = {\n   LUA_INCDIR = "/usr/include/lua5.4"\n}\n' > /s/luarocks/config-5.4.lua
