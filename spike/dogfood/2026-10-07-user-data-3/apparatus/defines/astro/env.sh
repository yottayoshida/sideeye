# Astro refuses Node 20; the box's Node 22 is /opt/node22 (Dockerfile, tenth layer). Its telemetry is off.
export PATH=/opt/node22/bin:$PATH ASTRO_TELEMETRY_DISABLED=1
