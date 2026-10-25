set -eu
# A world whose players are still in the old `files` backend — one file per player under players/,
# each with its position, health and inventory — the layout a world kept since before sqlite3
# became the default carries. The devtest game ships in Luanti's source tree.
[ -f /opt/luanti/share/luanti/games/devtest/game.conf ] || { rm -rf /opt/luanti/share/luanti/games; mkdir -p /opt/luanti/share/luanti/games; cp -a /tmp/dl/luanti-5.17.0/games/devtest /opt/luanti/share/luanti/games/; }
w=/s/world
rm -rf $w && mkdir -p $w/players
printf 'enable_damage = true\ncreative_mode = false\nauth_backend = sqlite3\nplayer_backend = files\nbackend = sqlite3\ngameid = devtest\nworld_name = keep\n' > $w/world.mt
i=0
for p in alice bob carol dave eve; do
    i=$((i + 1))
    cat > $w/players/$p <<P
breath = 10
extended_attributes = {"home":"($i,$((i * 2)),$((i * 3)))"}
hp = $((10 + i))
name = $p
pitch = 0
position = ($((i * 100)),$((i * 10 + 5)),$((i * 50)))
version = 1
yaw = $((i * 30))
PlayerArgsEnd
List main 32
Width 0
Item basenodes:dirt $((i * 7))
Item basenodes:stone $((i * 3))
Empty
Empty
Empty
Empty
Empty
Empty
Empty
Empty
Empty
Empty
Empty
Empty
Empty
Empty
Empty
Empty
Empty
Empty
Empty
Empty
Empty
Empty
Empty
Empty
Empty
Empty
Empty
Empty
Empty
Empty
EndInventoryList
List craft 9
Width 3
Empty
Empty
Empty
Empty
Empty
Empty
Empty
Empty
Empty
EndInventoryList
EndInventory
P
done
for f in check.sh recover.sh; do install -m 755 /ap/defines/luanti/$f /s/luanti-$f; done
