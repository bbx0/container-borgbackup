# Example: Backup Caddy volumes with BorgBackup

Use a companion BorgBackup container to backup the volumes of a Caddy container with a systemd timer.

This example uses rootless containers but avoids any complexity with `userns` or `uid`s. Be very careful with bind mounts (volumes) when using rootless containers or the user ids in your backup will be scrambled.

By intention the `--volumes-from` flag is not used in the example to make the process more explicit.

In a real world scenario you want to have the repo in a remote location. (Not in a volume in the same storage!) You can make use of `BORG_REPO='ssh://user@host:port/path/to/repo'` or mount a remote volume to the BorgBackup container.

## Backup

```bash
# Let's assume we have Caddy container with three volumes:
podman create --name caddy --read-only \
--volume=caddy-data:/data \
--volume=caddy-config:/config \
--volume=caddy-etc:/etc/caddy \
docker.io/library/caddy:latest

# Generate a BORG_PASSPHRASE for the new repo and store it as secret
head -c 24 /dev/random | base64 --ignore-garbage --wrap=0 >borgbackup-caddy.passphrase
podman secret create BORG_PASSPHRASE borgbackup-caddy.passphrase
# Make sure to store the BORG_PASSPHRASE in a secure remote location and then delete the file `borgbackup-caddy.passphrase`.

# Init a new repository (Please save your backup key.)
podman run \
--name borgbackup-caddy \
--rm \
--read-only \
--volume=borgbackup-caddy:/borg \
--volume=borgbackup-caddy-repo:/mnt/repo \
--env=BORG_REPO=/mnt/repo \
--env=BORG_HOST_ID="borgbackup-caddy@$(hostname --fqdn)" \
--secret=BORG_PASSPHRASE,type=env \
ghcr.io/bbx0/borgbackup:1.2-distroless \
init --encryption=repokey

# Create a first backup manually to test the repo.
# Note: The volumes from Caddy are mounted read-only under the `--workdir`.
# Note: The create command names all three mount points `data`, `config`, `etc/caddy` with a relative path.
# Note: The `z` flag is (optionally) provided to gain shared access to a volume when using selinux.
podman run \
--name borgbackup-caddy \
--rm \
--read-only \
--volume=borgbackup-caddy:/borg \
--volume=borgbackup-caddy-repo:/mnt/repo \
--workdir=/mnt/src \
--volume=caddy-data:/mnt/src/data:z,ro \
--volume=caddy-config:/mnt/src/config:z,ro \
--volume=caddy-etc:/mnt/src/etc/caddy:z,ro \
--env=BORG_REPO=/mnt/repo \
--env=BORG_HOST_ID="borgbackup-caddy@$(hostname --fqdn)" \
--secret=BORG_PASSPHRASE,type=env \
ghcr.io/bbx0/borgbackup:1.2-distroless \
create ::{now} data config etc/caddy

# Let's create a service to create Backups on a regular basis (use the same command as in the test before but with `podman create`)
# Note: This container is just a template to the systemd service unit
podman create \
--name borgbackup-caddy \
--rm \
--read-only \
--volume=borgbackup-caddy:/borg \
--volume=borgbackup-caddy-repo:/mnt/repo \
--workdir=/mnt/src \
--volume=caddy-data:/mnt/src/data:z,ro \
--volume=caddy-config:/mnt/src/config:z,ro \
--volume=caddy-etc:/mnt/src/etc/caddy:z,ro \
--env=BORG_REPO=/mnt/repo \
--env=BORG_HOST_ID="borgbackup-caddy@$(hostname --fqdn)" \
--secret=BORG_PASSPHRASE,type=env \
ghcr.io/bbx0/borgbackup:1.2-distroless \
create ::{now} data config etc/caddy

# Create the systemd service unit `container-borgbackup-caddy.service` from the "template container"
mkdir -p ~/.config/systemd/user
cd ~/.config/systemd/user
# Note: Prevent unwanted restarts with `--restart-policy=no` as needed.
podman generate systemd --name --new --files --restart-policy=no borgbackup-caddy

# Create the systemd timer unit `container-borgbackup-caddy.timer`
cat > container-borgbackup-caddy.timer << EOF
[Unit]
Description=Backup Caddy container

[Timer]
OnCalendar=daily
RandomizedDelaySec=900
Persistent=true

[Install]
WantedBy=timers.target
EOF

# Reload the systemd user units
systemctl --user daemon-reload

# Test the systemd unit to create a backup
systemctl --user start container-borgbackup-caddy.service
systemctl --user status container-borgbackup-caddy.service

# Enable the timer to create automatic backups
systemctl --user enable --now container-borgbackup-caddy.timer
```

To apply changes to the Backup configuration, just re-execute the `podman create` and `podman generate systemd` steps within the directory `~/.config/systemd/user`. Re-run `systemctl --user daemon-reload` after any change to the systemd units.

You can use `systemctl --user edit container-borgbackup-caddy.service` to maintain any additional service dependencies like additional start/stop dependencies or pre/post actions to the backup.

### Helper for interactive commands

A simple bash wrapper `~/.local/bin/borgbackup-caddy` for debugging / testing. (This helper is not needed, it is for demonstration purposes only.)

```bash
install -Dm 750 <(echo '#!/usr/bin/env bash'"
podman run \
--name borgbackup-caddy \
--rm \
--read-only \
--volume=borgbackup-caddy:/borg \
--volume=borgbackup-caddy-repo:/mnt/repo \
--workdir=/mnt/src \
--volume=caddy-data:/mnt/src/data:z,ro \
--volume=caddy-config:/mnt/src/config:z,ro \
--volume=caddy-etc:/mnt/src/etc/caddy:z,ro \
--env=BORG_REPO=/mnt/repo \
--env=BORG_HOST_ID="'"borgbackup-caddy@$(hostname --fqdn)"'" \
--secret=BORG_PASSPHRASE,type=env \
ghcr.io/bbx0/borgbackup:1.2-distroless "'"$@"') ~/.local/bin/borgbackup-caddy

borgbackup-caddy info
borgbackup-caddy list
```

## Restore

The example uses `2022-12-31T00:13:09` as the name of the archive to restore. Use the `list` command to identify the latest archive, if you don't use predictable names.

```bash
# Let's assume we have another Caddy container to restore to.
# Note: For demonstration purposes we use a different container with name `caddy2`.
podman create --name caddy2 --read-only \
--volume=caddy2-data:/data \
--volume=caddy2-config:/config \
--volume=caddy2-etc:/etc/caddy \
docker.io/library/caddy:latest

# Use `borg extract` to fully restore all files from the backup archive.
# Note: All files are restored into the `--workdir`, where the source volumes must be mounted read/write.
# Note: The archive name `2022-12-31T00:13:09` will be different for you.
# Note: The `--security-opt label=disable` flag is optional and only needed for selinux.
podman run \
--name borgbackup-caddy \
--rm \
--read-only \
--security-opt label=disable \
--volume=borgbackup-caddy:/borg \
--volume=borgbackup-caddy-repo:/mnt/repo \
--workdir=/mnt/src \
--volume=caddy2-data:/mnt/src/data \
--volume=caddy2-config:/mnt/src/config \
--volume=caddy2-etc:/mnt/src/etc/caddy \
--env=BORG_REPO=/mnt/repo \
--env=BORG_HOST_ID="borgbackup-caddy@$(hostname --fqdn)" \
--secret=BORG_PASSPHRASE,type=env \
ghcr.io/bbx0/borgbackup:1.2-distroless \
extract ::2022-12-31T00:13:09
```

When using selinux on the host, you may see some warnings during restore. Use `--security-opt label=disable` to avoid these.

```bash
extract ::2022-12-31T00:13:09
when setting extended attribute security.selinux: [Errno 13] Permission denied: '<FD 7>'
when setting extended attribute security.selinux: [Errno 13] Permission denied: b'/mnt/src/data/caddy'
when setting extended attribute security.selinux: [Errno 13] Permission denied: b'/mnt/src/config/caddy'
```
