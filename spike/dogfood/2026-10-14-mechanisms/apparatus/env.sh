# Sourced by run.sh and gate-all.sh before the engine runs. Unlike the earlier runs' copy, nothing
# here moves HOME or the XDG directories to a fixed place outside the state: only the state is
# rebuilt between worlds, so a tool file left there by a killed world would change the next one
# (#861's plan, D4). Each define's own env.sh puts them inside its state.
export LC_ALL=C.UTF-8 TZ=UTC
