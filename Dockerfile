# syntax=docker.io/docker/dockerfile:1

# Usage: 
#  buildctl build --frontend gateway.v0 --opt source=docker.io/docker/dockerfile:1 --local context=. --local dockerfile=. --output type=image,name=localhost:5000/borgbackup:1.1.18,push=true --opt build-arg:version=1.1.18 --opt platform="linux/amd64,linux/arm64,linux/arm/v7"
#  podman build --file Dockerfile --build-arg version=1.1.18 --tag localhost:5000/borgbackup:1.1.18

# Default to Debian 11, which is the current platform for the BorgBackup standalone binary releases
# the 'offical' python image provides a standalone python build under /usr/local
# the 'slim' variant comes with pip, setuptools and wheel pre-installed
ARG base_image=docker.io/python:3-slim-bullseye
ARG version

# Build environment and defaults
ARG BORG_BASE_DIR=/borg
ARG BORG_FUSE_IMPL=none
ARG BORG_VERSION=${version}
ARG BORG_SRC_DIR=/usr/local/src/borgbackup-${BORG_VERSION}-${TARGETARCH}${TARGETVARIANT}
ARG BORG_WHEEL_DIR=${BORG_SRC_DIR}/wheels
ARG PIP_CACHE_DIR=/var/local/cache/borg-${BORG_VERSION}/${TARGETARCH}${TARGETVARIANT}/pip
ARG PIP_CONSTRAINT=${BORG_SRC_DIR}/requirements.d/development.lock.txt
ARG PIP_DISABLE_PIP_VERSION_CHECK=1
ARG PIP_ROOT_USER_ACTION=ignore

### Download source (to cache as layer)
FROM scratch as source
# Signing Key: Thomas Waldmann <tw@waldmann-edv.de>
ADD https://keys.openpgp.org/vks/v1/by-fingerprint/6D5BEF9ADD2075805747B70F9F88FB52FAF7B393 signing_key.asc
ARG BORG_VERSION
ADD https://github.com/borgbackup/borg/releases/download/${BORG_VERSION}/borgbackup-${BORG_VERSION}.tar.gz borgbackup-${BORG_VERSION}.tar.gz
ADD https://github.com/borgbackup/borg/releases/download/${BORG_VERSION}/borgbackup-${BORG_VERSION}.tar.gz.asc borgbackup-${BORG_VERSION}.tar.gz.asc

### Build stage ###
FROM ${base_image} as build

# Install OS build dependencies (https://borgbackup.readthedocs.io/en/stable/installation.html#dependencies) 
ARG DEBIAN_FRONTEND=noninteractive
RUN --mount=type=tmpfs,target=/var/cache/apt --mount=type=tmpfs,target=/var/lib/apt \
  apt-get -y -qq update && \ 
  apt-get -y -qq --no-install-recommends install \
  build-essential \
  libacl1-dev libffi-dev libssl-dev liblz4-dev libzstd-dev libxxhash-dev \
  pkg-config \
  sqv

# Extract into build layer (verify gpg key)
ARG BORG_BASE_DIR BORG_FUSE_IMPL BORG_SRC_DIR BORG_VERSION BORG_WHEEL_DIR
WORKDIR ${BORG_SRC_DIR}
RUN --mount=type=bind,from=source,target=/mnt/source \
  sqv /mnt/source/borgbackup-${BORG_VERSION}.tar.gz.asc /mnt/source/borgbackup-${BORG_VERSION}.tar.gz --keyring /mnt/source/signing_key.asc && \
  tar --extract --auto-compress --file=/mnt/source/borgbackup-${BORG_VERSION}.tar.gz --strip-components=1

# Build and Install: Wheel for BorgBackup from source (and cache PIP and GIT repo across builds)
ARG PIP_CACHE_DIR PIP_CONSTRAINT PIP_DISABLE_PIP_VERSION_CHECK PIP_ROOT_USER_ACTION
ARG PIP_NO_BINARY=:all:
ARG PIP_USE_FEATURE=no-binary-enable-wheel-cache
ARG NO_CYTHON_COMPILE=true

WORKDIR ${BORG_WHEEL_DIR}
RUN --mount=type=cache,target=${PIP_CACHE_DIR} --mount=type=tmpfs,target=/tmp \
  pip install pkgconfig && \
  pip wheel Cython --use-pep517 --config-setting="--build-option=--no-cython-compile" && \
  pip wheel ${BORG_SRC_DIR} && \
  pip install --no-index --no-cache-dir --find-links=${BORG_WHEEL_DIR} --only-binary=:all: borgbackup==${BORG_VERSION}

# Test: Run self-tests
RUN --mount=type=tmpfs,target=/tmp --mount=type=tmpfs,target=${BORG_BASE_DIR} \
  borg --version | grep --silent --fixed-strings "borg ${BORG_VERSION}" && \
  borg debug info --debug

### Test stage (pytest) ###
FROM ${base_image} as test
ARG BORG_BASE_DIR BORG_FUSE_IMPL BORG_SRC_DIR BORG_VERSION BORG_WHEEL_DIR
ARG PIP_CACHE_DIR PIP_CONSTRAINT PIP_DISABLE_PIP_VERSION_CHECK PIP_ROOT_USER_ACTION

RUN --mount=type=bind,from=build,source=${BORG_SRC_DIR},target=${BORG_SRC_DIR} --mount=type=cache,target=${PIP_CACHE_DIR} \
  pip install pytest pytest-benchmark pytest-xdist python-dateutil && \
  pip install --no-index --no-cache-dir --find-links=${BORG_WHEEL_DIR} --only-binary=:all: borgbackup==${BORG_VERSION}

ARG XDISTN=auto
ARG PYTHONFAULTHANDLER=1
WORKDIR ${BORG_SRC_DIR}
# Skip readonly tests as CAP_LINUX_IMMUTABLE is disabled by default in Docker
RUN --mount=type=bind,from=build,source=${BORG_SRC_DIR},target=${BORG_SRC_DIR} --mount=type=tmpfs,target=/tmp --mount=type=tmpfs,target=${BORG_BASE_DIR} \
  pytest --quiet -n ${XDISTN} --disable-warnings --exitfirst --benchmark-skip -k 'not test_readonly' --pyargs borg.testsuite

### Final stage (publish target image) ###
FROM ${base_image} as final
ARG base_image

# Install a ssh client to support remote repositories
ARG DEBIAN_FRONTEND=noninteractive
RUN --mount=type=tmpfs,target=/var/cache/apt --mount=type=tmpfs,target=/var/lib/apt \
  apt-get -y -qq update && \ 
  apt-get -y -qq --no-install-recommends install openssh-client && \
  ssh -V

# Persist ENV into image
ARG BORG_BASE_DIR BORG_FUSE_IMPL BORG_SRC_DIR BORG_VERSION BORG_WHEEL_DIR
ENV BORG_VERSION=${BORG_VERSION} BORG_BASE_DIR=${BORG_BASE_DIR} BORG_FUSE_IMPL=${BORG_FUSE_IMPL}
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1
VOLUME /borg

# Install the wheel and execute once
ARG PIP_CACHE_DIR PIP_CONSTRAINT PIP_DISABLE_PIP_VERSION_CHECK PIP_ROOT_USER_ACTION
RUN --mount=type=bind,from=build,source=${BORG_SRC_DIR},target=${BORG_SRC_DIR} \
  pip install --no-index --no-cache-dir --find-links=${BORG_WHEEL_DIR} --only-binary=:all: --no-compile borgbackup==${BORG_VERSION} && \
  borg debug info --debug

ENTRYPOINT ["borg"]

# Labeling https://github.com/opencontainers/image-spec/blob/main/annotations.md
LABEL\
  org.opencontainers.image.title="BorgBackup" \
  org.opencontainers.image.description="BorgBackup is a deduplicating backup program with support for compression and authenticated encryption." \
  org.opencontainers.image.licenses="BSD-3-Clause" \
  org.opencontainers.image.vendor="BorgBackup Community (unofficial)" \
  org.opencontainers.image.version=${BORG_VERSION} \
  org.opencontainers.image.source="https://github.com/bbx0/container-borgbackup" \
  org.opencontainers.image.authors="39773919+bbx0@users.noreply.github.com" \
  org.opencontainers.image.base.name=${base_image}