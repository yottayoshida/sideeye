#!/bin/sh
set -eu
printf 'PUBLIC "-//Seeded//DTD Thing//EN" "thing.dtd"\n' > "$TOY_STATE/ordinary.cat"
: > "$TOY_STATE/central.cat"
