# The SBCL that `ros config` runs on was fetched at build into /opt/roswell-home (`ros setup`, Dockerfile
# twelfth layer); the define's ROSWELL_HOME holds only the config file, the rest are symlinks to it, so a
# crash world copies 64 bytes rather than 197 MB. Symlinks are compared by target, not followed.
export ROSWELL_HOME=/s/ros/home
