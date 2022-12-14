# BorgBackup container

Unofficial distribution of [BorgBackup](https://www.borgbackup.org/) in a docker container. A SSH client is provided within in the image to allow backup to a remote storage.

## Tags and Variants

The latest patch release of a [supported](https://github.com/borgbackup/borg/blob/master/SECURITY.md) BorgBackup version is continuously build and published here as container. The shared tags below always link to the latest built.

You have to manage any [`borg upgrade`](https://borgbackup.readthedocs.io/en/stable/usage/upgrade.html#when-you-do-not-need-borg-upgrade) yourself. Please always read the BorgBackup [Change Log](https://borgbackup.readthedocs.io/en/stable/changes.html#change-log) before switching to a new version tag.

| Tag                             | Base image                          | Comment                                                   |
| ------------------------------- | ----------------------------------- | --------------------------------------------------------- |
| ghcr.io/bbx0/borgbackup:1.1     | docker.io/python:3.7-slim-bullseye  | oldstable series                                          |
| **ghcr.io/bbx0/borgbackup:1.2** | docker.io/python:3.9-slim-bullseye  | stable series                                             |
| ghcr.io/bbx0/borgbackup:2.0     | docker.io/python:3.11-slim-bullseye | beta series only for ***testing*** the 2.0.x pre-releases |

All images are continuously published based on the [GitHub workflow](https://github.com/bbx0/container-borgbackup/actions/workflows/main.yaml) without human intervention. Make sure to validate the images in your test environment before usage, as you always do. 😉

There is no :latest tag to reduce risk of breaking repository data.

### Variant `-distroless`

A "[Distroless](https://github.com/GoogleContainerTools/distroless)" variant is created from the containers above and published with suffix `-distroless`. This variant is based on [pyinstaller](https://pyinstaller.org) and Googles distroless [base image](https://github.com/GoogleContainerTools/distroless#docker) to package BorgBackup as a binary and to provide glibc.

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

The container images are built multi-platform for: `linux/amd64`, `linux/arm64`, `linux/arm/v7`, `linux/ppc64le`, `linux/s390x`. (There are no specific tests in place to confirm a produced image works well a target platform.)

## Usage

BorgBackup allows configuration via [environment variables][1], which is the recommended approach for this container.

Some environment variables are pre-configured.

| Environment Variable | Value   | Comment                                                                                                                                                                                                                 |
| -------------------- | ------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| BORG_BASE_DIR        | `/borg` | The mount point `/borg` is configured as volume in the container. You should keep it on permanent storage to allow BorgBackup to maintain its configuration and cache.                                                  |
| BORG_FUSE_IMPL       | `none`  | BorgBackup is compiled without FUSE support. Please create an issue explaining your use case if you need this.                                                                                                          |
| BORG_HOST_ID         |         | No value is set in the image. Please read the [documentation][1], you may want to configure this with ephemeral containers to allow automatic stale lock removal. Should be a (globally) unique name for the container. |

### Example

```bash
podman run --name borg --rm --read-only --volume borg:/borg ghcr.io/bbx0/borgbackup:1.2 <command>
```

TODO: Explain usage with examples.

## Building

For local builds take a look at the [`Makefile`](Makefile) or the workflow ([main.yaml](.github/workflows/main.yaml), [build-push.yaml](.github/workflows/build-push.yaml)).

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

[1]: https://borgbackup.readthedocs.io/en/stable/usage/general.html#environment-variables
