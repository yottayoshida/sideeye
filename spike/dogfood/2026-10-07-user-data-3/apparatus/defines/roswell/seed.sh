set -eu
rm -rf /s/ros /s/ros-in && mkdir -p /s/ros/home /s/ros-in
for e in /opt/roswell-home/*; do n=$(basename "$e"); [ "$n" = config ] || ln -s "$e" "/s/ros/home/$n"; done
cp /opt/roswell-home/config /s/ros/home/config
ROSWELL_HOME=/s/ros/home ros config set setup.time 1 > /s/ros-in/seed.log 2>&1
grep -q '^setup.time' /s/ros/home/config
