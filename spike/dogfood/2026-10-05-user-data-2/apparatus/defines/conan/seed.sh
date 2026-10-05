set -eu
rm -rf /s/conan /s/conan-in && mkdir -p /s/conan-in
CONAN_HOME=/s/conan conan remote add internal https://artifacts.example.internal/conan > /s/conan-in/seed.log 2>&1
test -s /s/conan/remotes.json
