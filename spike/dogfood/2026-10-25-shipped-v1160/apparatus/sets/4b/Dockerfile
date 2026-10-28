# Set 4's substitute for Navidrome (walled on threads in both its forms, set-4-notes.md): COLMAP
# 4.2.1, the reserve scout 3 put first. Upstream publishes no Linux binary and Debian trixie carries
# 3.10, a major version behind, so it is built here from the 4.2.1 tag without CUDA, its GUI or ONNX (its prebuilt ONNX Runtime does not land where its own cmake looks on arm64).
FROM sideeye-sv1025-s4
RUN apt-get install -y --no-install-recommends libboost-program-options-dev libboost-graph-dev libboost-system-dev \
      libeigen3-dev libceres-dev libgoogle-glog-dev libgflags-dev libsqlite3-dev libmetis-dev libopenimageio-dev \
      libflann-dev libfreeimage-dev libcgal-dev libgmock-dev libgtest-dev libssl-dev openimageio-tools libgl-dev libglx-dev libglew-dev libopengl-dev libopencv-dev > /tmp/apt-colmap.log 2>&1 && echo "OK colmap deps" || { echo "FAILED colmap deps"; tail -5 /tmp/apt-colmap.log; }
RUN set -u; cd /tmp/dl && curl -fsSL -o colmap.tgz https://github.com/colmap/colmap/archive/refs/tags/4.2.1.tar.gz && tar xzf colmap.tgz && cd colmap-4.2.1 && \
    cmake -G Ninja -B build -DCMAKE_BUILD_TYPE=Release -DCUDA_ENABLED=OFF -DGUI_ENABLED=OFF -DOPENGL_ENABLED=OFF -DTESTS_ENABLED=OFF -DONNX_ENABLED=OFF \
          -DCMAKE_INSTALL_PREFIX=/opt/colmap > /tmp/colmap-cmake.log 2>&1 && \
    ninja -C build -j2 > /tmp/colmap-build.log 2>&1 && ninja -C build install > /tmp/colmap-install.log 2>&1 && \
    ln -sf /opt/colmap/bin/colmap /opt/bin/colmap && echo "OK colmap" || { echo "FAILED colmap"; tail -25 /tmp/colmap-cmake.log; tail -25 /tmp/colmap-build.log; }
RUN { cat /versions.txt; echo "colmap $(colmap -h 2>&1 | grep -m1 -i colmap)"; echo "link /opt/bin/colmap: $(file -bL /opt/bin/colmap | cut -c1-90)"; } > /versions.new && mv /versions.new /versions.txt && tail -2 /versions.txt
