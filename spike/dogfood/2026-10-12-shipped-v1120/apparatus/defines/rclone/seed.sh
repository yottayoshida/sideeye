set -eu
# Every remote a user has configured, credentials included (fakes here), in the one file rclone
# keeps them in; `config update` rewrites it to change one key of one remote.
rm -rf /s/rclone && mkdir -p /s/rclone
cat > /s/rclone/rclone.conf <<'EOF'
[backup]
type = local

[s3prod]
type = s3
provider = AWS
access_key_id = example-access-key-id
secret_access_key = example-secret-access-key
region = us-east-1
acl = private

[photos]
type = sftp
host = nas.home.example
user = media
key_file = ~/.ssh/nas_ed25519
shell_type = unix

[crypt]
type = crypt
remote = s3prod:archive-bucket/vault
filename_encryption = standard
directory_name_encryption = true
EOF
chmod 0600 /s/rclone/rclone.conf
