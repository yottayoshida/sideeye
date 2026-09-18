#!/bin/sh
exec /usr/bin/autogb -i utf8 -o gb < "$TOY_STATE/in.txt" > "$TOY_STATE/out.txt"
