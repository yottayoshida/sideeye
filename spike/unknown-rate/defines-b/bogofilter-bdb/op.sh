#!/bin/sh
exec bogofilter-bdb -s -d "$TOY_STATE" -I "$TOY_STATE/spam.eml"
