# BorgBackup container

## Building

For local builds take a look at the [`Makefile`](https://github.com/bbx0/container-borgbackup/blob/main/Makefile) or the workflow ([main.yaml](https://github.com/bbx0/container-borgbackup/blob/main/.github/workflows/main.yaml), [build-push.yaml](https://github.com/bbx0/container-borgbackup/blob/main/.github/workflows/build-push.yaml)).

### Build Examples

```sh
# Build via podman / docker
podman build \
    --file Dockerfile \
    --tag localhost:5000/borgbackup:1.4.0
    --build-arg version=1.4.0 \
    --build-arg base_image=docker.io/python:3.11-slim-bookworm

podman build \
    --file Dockerfile.distroless \
    --tag localhost:5000/borgbackup:1.4.0-distroless
    --build-arg version=1.4.0 \
    --build-arg borg_image=localhost:5000/borgbackup:1.4.0 \
    --build-arg distroless_image=gcr.io/distroless/base-debian12
```

### Test builds

Running the BorgBackup `pytest` suite is supported. The Dockerfile contains a `test` target, which executes `pytest` on the given borg version. The build-arg `XDISTN` controls parallelization (see [`Makefile`](https://github.com/bbx0/container-borgbackup/blob/main/Makefile)). All readonly tests are skipped as `CAP_LINUX_IMMUTABLE` is disabled by default in Docker.

```bash
# Example: Run pytest on borg 1.4 x86_64
make "test(1.4)" PLATFORM=linux/amd64
# Example: Run pytest on borg 2.0 aarch64 with point release 2.0.0b4 and 8 threads
make "test(2.0)" PLATFORM=linux/arm64/v8 VERSION=2.0.0b4 XDISTN=8
```
