# BorgBackup container

Distribution of [BorgBackup](https://www.borgbackup.org/) in a docker container. A SSH client is provided within in the image to allow backup to a remote storage.

- GitHub: [bbx0/container-borgbackup](https://github.com/bbx0/container-borgbackup): [Dockerfile](https://github.com/bbx0/container-borgbackup/blob/main/Dockerfile), [Dockerfile.distroless](https://github.com/bbx0/container-borgbackup/blob/main/Dockerfile.distroless)
- Docker Hub: [bbx0/borgbackup](https://hub.docker.com/repository/docker/bbx0/borgbackup)

This is an unofficial community contribution.

## Tags and Variants

The latest patch release of all [supported](https://github.com/borgbackup/borg/blob/master/SECURITY.md) BorgBackup versions are continuously build and published here as container. The shared tags below always link to the latest point release.

You have to manage any [`borg upgrade`](https://borgbackup.readthedocs.io/en/stable/usage/upgrade.html#when-you-do-not-need-borg-upgrade) yourself. Please always read the BorgBackup [Change Log](https://borgbackup.readthedocs.io/en/stable/changes.html#change-log) before switching to a new version tag.

| Tag                             | Base image                          | Comment                                                   |
| ------------------------------- | ----------------------------------- | --------------------------------------------------------- |
| ghcr.io/bbx0/borgbackup:1.1     | docker.io/python:3.7-slim-bullseye  | oldstable series                                          |
| **ghcr.io/bbx0/borgbackup:1.2** | docker.io/python:3.9-slim-bullseye  | stable series                                             |
| ghcr.io/bbx0/borgbackup:2.0     | docker.io/python:3.11-slim-bullseye | beta series only for ***testing*** the 2.0.x pre-releases |

All images are continuously published based on a [GitHub workflow](https://github.com/bbx0/container-borgbackup/actions/workflows/main.yaml) without human intervention. Make sure to validate the images in your test environment before usage, as you always do. 😉

There is *no* `:latest` tag to reduce any risk of breaking repository data.

### Variant `-distroless`

A "[distroless](https://github.com/GoogleContainerTools/distroless)" variant is published with suffix `-distroless`. This variant is based on [pyinstaller](https://pyinstaller.org) and Googles distroless [base image](https://github.com/GoogleContainerTools/distroless#docker) to package BorgBackup as a binary and to provide glibc.

| Tag                                    | Base image                      | Comment                                       |
| -------------------------------------- | ------------------------------- | --------------------------------------------- |
| ghcr.io/bbx0/borgbackup:1.1-distroless | gcr.io/distroless/base-debian11 |                                               |
| ghcr.io/bbx0/borgbackup:1.2-distroless | gcr.io/distroless/base-debian11 |                                               |
| ghcr.io/bbx0/borgbackup:2.0-distroless | gcr.io/distroless/cc-debian11   | only for ***testing*** the 2.0.x pre-releases |

These binaries are added to the distroless base image:

- `borg`: BorgBackup (packed with pyinstaller)
- `ssh`: complete `openssh-client` package from Debian repository
- `cat`: for use with `BORG_PASSCOMMAND` (part of coreutils package from Debian repository)

### Platforms

The container images are built multi-platform for: `linux/amd64`, `linux/arm64`, `linux/arm/v7`, `linux/ppc64le`, `linux/s390x`.

(There are no specific tests in place to confirm a produced image works well a target platform.)

## Usage

BorgBackup allows configuration via [environment variables][1], which is the recommended approach for this container.

Some environment variables are pre-configured with a default.

<!-- markdownlint-capture -->
<!-- markdownlint-disable MD033 -->
| Environment Variable | Default | Comment                                                                                                                                                                                                                                                                                                                          |
| -------------------- | ------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `BORG_BASE_DIR`      | `/borg` | The mount point `/borg` is defined as volume in the container. <br /> You must keep it on permanent storage to allow BorgBackup to maintain its internal configuration and cache.                                                                                                                                                |
| `BORG_FUSE_IMPL`     | `none`  | BorgBackup is compiled without FUSE support. Please create an issue explaining your use case if you need this.                                                                                                                                                                                                                   |
| `BORG_REPO`          |         | Set to your remote location via `ssh://..` or a mounted remote storage.                                                                                                                                                                                                                                                          |
| `BORG_RSH`           |         | Optional: Provide your ssh configuration and make use of a mounted secret to provide the private key. <br /> Example: `--secret=id_private.key,type=mount,mode=0400` <br /> `--env=BORG_RSH="ssh -i /run/secrets/id_private.key -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR"` |
| `BORG_PASSPHRASE`    |         | Optional: Use a container secret to provide the passphrase. <br /> Example: `--secret=BORG_PASSPHRASE,type=env`                                                                                                                                                                                                                  |
| `BORG_PASSCOMMAND`   |         | Optional: You can provide a container secret as mount and use `cat` to consume it. <br /> Example: `--secret=BORG_PASSPHRASE,type=mount --env=BORG_PASSCOMMAND="cat /run/secrets/BORG_PASSPHRASE"`                                                                                                                               |
| `BORG_KEY_FILE`      |         | Optional: Use a container secret to usa a pre-generated key file. <br /> Example: `--secret=BORG_KEY_FILE,type=mount --env=BORG_KEY_FILE="/run/secrets/BORG_KEY_FILE"`                                                                                                                                                           |
| `BORG_HOST_ID`       |         | Optional: For ephemeral containers you need to provide a static identifier to allow automatic stale lock removal. Must be a globally unique id for the container. <br /> Please check the [documentation][1]. Example `--env=BORG_HOST_ID="borgbackup-XYZ@$(hostname --fqdn)"`                                                   |
<!-- markdownlint-restore -->

Please check the BorgBackup documentation for all available [environment variables](https://borgbackup.readthedocs.io/en/stable/usage/general.html#environment-variables).

### Recommendations

- Use `--security-opt label=disable` to prevent filesystem relabeling when backing up or restoring to a local filesystem with `selinux` enabled.
- Use a ephemeral container (`--rm`). There is no need to keep the container after command execution when `/borg` is provided as a persistent volume (and the `BORG_HOST_ID` is set).
- Use a read-only container (`--read-only`). The container will never require write access to its own rootfs.
- Do *not* provide any ssh configuration in `/root/.ssh`. Use a mounted secret to provide the key file via the `-i` flag and use the `-o` flag to provide any config options in `BORG_RSH`.
  - Mount config files to `/etc/ssh/ssh_config` or `/etc/ssh/ssh_known_hosts` as needed.
- Make use of the *native* scheduler of your hosting environment to trigger backups. A systemd.timer or Kubernetes CronJobs should be at your disposal. This allows to control any start/stop dependencies via the container runtime directly.

### Example

See [`docs/`](https://github.com/bbx0/container-borgbackup/docs/) for examples (e.g. with [`caddy`](https://github.com/bbx0/container-borgbackup/docs/example-caddy.md)).

```bash
podman run --name borg --rm --read-only --volume borg:/borg ghcr.io/bbx0/borgbackup:1.2 <command>
```

## Building

For local builds take a look at the [`Makefile`](https://github.com/bbx0/container-borgbackup/blob/main/Makefile) or the workflow ([main.yaml](https://github.com/bbx0/container-borgbackup/blob/main/.github/workflows/main.yaml), [build-push.yaml](https://github.com/bbx0/container-borgbackup/blob/main/.github/workflows/build-push.yaml)).

### Build Examples

```sh
# Build via podman / docker
podman build \
    --file Dockerfile \
    --tag localhost:5000/borgbackup:1.2.2
    --build-arg version=1.2.2 \
    --build-arg base_image=docker.io/python:3.9-slim-bullseye

podman build \
    --file Dockerfile.distroless \
    --tag localhost:5000/borgbackup:1.2.2-distroless
    --build-arg version=1.2.2 \
    --build-arg borg_image=localhost:5000/borgbackup:1.2.2 \
    --build-arg distroless_image=gcr.io/distroless/base-debian11
```

### Test builds

Running the BorgBackup `pytest` suite is supported. The Dockerfile contains a `test` target, which executes `pytest` on the given borg version. The build-arg `XDISTN` controls parallelization (see [`Makefile`](https://github.com/bbx0/container-borgbackup/blob/main/Makefile)). All readonly tests are skipped as `CAP_LINUX_IMMUTABLE` is disabled by default in Docker.

```bash
# Example: Run pytest on borg 1.2 x86_64
make "test(1.2)" PLATFORM=linux/amd64
# Example: Run pytest on borg 2.0 aarch64 with point release 2.0.0b4 and 8 threads
make "test(2.0)" PLATFORM=linux/arm64/v8 VERSION=2.0.0b4 XDISTN=8
```

## Alternatives

Some other valuable projects to check-out as an alternative in case you find anything missing here.

- [borg binary builder](https://gitlab.com/borg-binary-builder/borg-binaries) / [Borg ARM builds](https://borg.bauerj.eu): standalone builds for ARM using Docker (but not published as container image)
- [borgmatic-collective/docker-borgmatic](https://github.com/borgmatic-collective/docker-borgmatic):  Docker container for [Borgmatic](https://github.com/borgmatic-collective/borgmatic) based on Alpine
  - [modem7/docker-borgmatic](https://github.com/modem7/docker-borgmatic): Multiarch builds of the borgmatic container
- [pschiffe/docker-borg](https://github.com/pschiffe/docker-borg): Docker image with builtin sshfs support based on Fedora.
- [azlux/borgbackup-docker](https://github.com/azlux/borgbackup-docker): Docker image with a builtin mysql backup feature based on Debian.

[1]: https://borgbackup.readthedocs.io/en/stable/usage/general.html#environment-variables
