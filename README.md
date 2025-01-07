<!-- markdownlint-configure-file { "no-inline-html": { "allowed_elements": [ "br" ] } } -->

# BorgBackup container

[![docker](https://img.shields.io/badge/Docker%20Hub-1D63ED?logo=docker&logoColor=white)](https://hub.docker.com/r/bbx0/borgbackup)
[![GitHub](https://img.shields.io/badge/GitHub-black?logo=github&logoColor=white)](https://github.com/bbx0/container-borgbackup)

A distribution of [BorgBackup](https://www.borgbackup.org/) based on the [Docker Official Images](https://github.com/docker-library/official-images#what-are-official-images) for [Python](https://hub.docker.com/_/python). An SSH client and [rclone](https://rclone.org) (borg2 only) are available for backing up to remote storage.

The container image is suitable as a backup client and as a base image for other projects.

This is a [Borg Community](https://github.com/borgbackup/community) user contribution.

## Shared Tags

The [supported](https://github.com/borgbackup/borg/blob/master/SECURITY.md) BorgBackup versions are continuously built and published as shared tag based on a [GitHub workflow](https://github.com/bbx0/container-borgbackup/actions/workflows/main.yaml).

| Tag                                                                                                                                                                                                                                        | Comment                                                                                                   |
| ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | --------------------------------------------------------------------------------------------------------- |
| [ghcr.io/bbx0/borgbackup:2.0](https://github.com/bbx0/container-borgbackup/blob/main/borg2/Dockerfile)<br>[ghcr.io/bbx0/borgbackup:2.0-distroless](https://github.com/bbx0/container-borgbackup/blob/main/borg2/Dockerfile.distroless)     | beta for *testing* the [2.0.x](https://github.com/borgbackup/borg/issues/6602) pre-releases               |
| **[ghcr.io/bbx0/borgbackup:1.4](https://github.com/bbx0/container-borgbackup/blob/main/borg1/Dockerfile)**<br>[ghcr.io/bbx0/borgbackup:1.4-distroless](https://github.com/bbx0/container-borgbackup/blob/main/borg1/Dockerfile.distroless) | **stable series**                                                                                         |
| [ghcr.io/bbx0/borgbackup:1.2](https://github.com/bbx0/container-borgbackup/blob/main/borg1/Dockerfile)<br>[ghcr.io/bbx0/borgbackup:1.2-distroless](https://github.com/bbx0/container-borgbackup/blob/main/borg1/Dockerfile.distroless)     | supported series                                                                                          |
| [ghcr.io/bbx0/borgbackup:1.1](https://github.com/bbx0/container-borgbackup/blob/main/borg1/Dockerfile)<br>[ghcr.io/bbx0/borgbackup:1.1-distroless](https://github.com/bbx0/container-borgbackup/blob/main/borg1/Dockerfile.distroless)     | [EOL, please upgrade](https://github.com/borgbackup/borg/commit/d07e28db7b63df38fbe1c9987898d0d26f3264ff) |

You have to manage any [`borg upgrade`](https://borgbackup.readthedocs.io/en/stable/usage/upgrade.html#when-you-do-not-need-borg-upgrade) yourself. Please always read the BorgBackup [Change Log](https://borgbackup.readthedocs.io/en/stable/changes.html#change-log) before switching to a new version tag. There is no `:latest` tag to help reduce the risk of breaking repository data.

The container images are built multi-platform for: `linux/amd64`, `linux/arm64`, `linux/arm/v7`.

The [`-distroless`](https://github.com/GoogleContainerTools/distroless) variant is based on Googles [distroless images](https://github.com/GoogleContainerTools/distroless#distroless-container-images) and contains binaries for `borg`, `cat`, `rclone` (borg2 only) and `ssh`.

## Usage

### Quick start

A simple example with an SSH repository URL.

```yaml
# docker-compose.yaml
name: backup
services:
  borg:
    image: bbx0/borgbackup:1.4
    read_only: true
    environment:
      BORG_PASSPHRASE: mysecret
      BORG_REPO: ssh://user@example.com:22/./repos/myrepo
      BORG_RSH: ssh -i /run/secrets/borg.sshkey -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR
      BORG_HOST_ID: mycontainer-quickstart-2f1c4b@example.net
    working_dir: /mnt/src
    volumes:
      - borg:/borg # BorgBackup requires a persistent internal volume `/borg` for data and cache
      - ./borg.sshkey:/run/secrets/borg.sshkey:ro # an existing ssh private key file
      - ./mydata:/mnt/src/mydata:ro,z # the source data to backup mounted under the `working_dir`
volumes:
  borg:
```

```bash
docker-compose run --rm borg init --encryption=repokey
docker-compose run --rm borg create ::{now} mydata # source data relative to the `working_dir`
docker-compose run --rm borg info
docker-compose run --rm borg list ::
```

### Configuration

BorgBackup allows configuration via [environment variables](https://borgbackup.readthedocs.io/en/stable/usage/general.html#environment-variables), which is the recommended approach for this container. Some environment variables are pre-configured with a default. Options for borg2 are experimental and may change without prior notice.

| Environment Variable          | Default                      | Comment                                                                                                                                                                                                                     |
| ----------------------------- | ---------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `BORG_BASE_DIR`               | `/borg`                      | The mount point `/borg` is defined as volume in the container.<br>You must keep it on permanent storage to allow BorgBackup to maintain its internal configuration and cache.                                               |
| `BORG_REPO`                   |                              | Set it to your [repository URL](https://borgbackup.readthedocs.io/en/stable/usage/general.html#repository-urls) or a mounted volume.                                                                                        |
| `BORG_PASSPHRASE`             |                              | Optional: The passphrase for an encrypted repository.                                                                                                                                                                       |
| `BORG_PASSCOMMAND`            |                              | Optional: You can provide the passphrase as a mounted file and use `cat` to consume it.<br>Example: `BORG_PASSCOMMAND: cat /run/secrets/passphrase`                                                                         |
| `BORG_RSH`                    |                              | Optional: Provide your ssh key and configuration options.                                                                                                                                                                   |
| `BORG_HOST_ID`                |                              | For ephemeral containers you need to provide a static identifier to allow automatic stale lock removal. Must be a persistent unique ID for the container.<br>Example: `BORG_HOST_ID: mycontainer-uniqueid@host.example.com` |
| `BORG_FUSE_IMPL`              | `none`                       | BorgBackup is compiled without FUSE support. Please create an issue explaining your use case if you need this.                                                                                                              |
| **borg2 only (experimental)** |                              |                                                                                                                                                                                                                             |
| `RCLONE_CONFIG`               | `/rclone/config/rclone.conf` | Optional: The mount point for a `rclone` configuration file.                                                                                                                                                                |
| `RCLONE_CONFIG_*`             |                              | Optional: You can provide `rclone` configuration options as environment variables instead of a configuration file.                                                                                                          |
| `RCLONE_CACHE_DIR`            | `/rclone/cache`              | Optional: The mount point for a persistent `rclone` cache directory. Usually this is not needed.                                                                                                                            |

Please check the BorgBackup documentation for all available [environment variables](https://borgbackup.readthedocs.io/en/stable/usage/general.html#environment-variables).

### Recommendations

- Use `--security-opt label=disable` to prevent file system relabeling when backing up or restoring to a local file system with `selinux` enabled.
- Use an ephemeral container (`--rm`). There is no need to keep the container after command execution when `/borg` is provided as a persistent volume and the `BORG_HOST_ID` is set.
- Use a read-only container (`--read-only`). The container will not require write access to its own rootfs.
- Do *not* provide any ssh configuration in `/root/.ssh`. Use a mounted secret to provide the key file via the `-i` flag and use the `-o` flag to provide any config options in `BORG_RSH`. You can mount config files to `/etc/ssh/ssh_config` or `/etc/ssh/ssh_known_hosts`.
- Make use of the *native* scheduler of your hosting environment to trigger backups. A systemd.timer or Kubernetes CronJobs should be at your disposal. This allows to control any start/stop dependencies via the container runtime directly.

See [`docs/`](https://github.com/bbx0/container-borgbackup/tree/main/docs) for more examples (e.g. with [`caddy`](https://github.com/bbx0/container-borgbackup/blob/main/docs/example-caddy.md)).
