set -eu
# Set 3's vcpkg define (explored at 12:48 under the name `vcpkg`, before set 2's define of the same name
# replaced it; transcripts/explore/vcpkg-s3). A vcpkg install root as `vcpkg install nlohmann-json
# utfcpp` left it at the box's build: the installed files and vcpkg's own package database
# (installed/vcpkg/status, the updates journal, the per-package file lists). `vcpkg remove utfcpp`
# deletes that port's files and records the removal in the database.
rm -rf /s/vcpkg && cp -a /opt/vcpkg-installed /s/vcpkg
