# syntax=docker.io/docker/dockerfile:1

# Usage: buildctl build --frontend gateway.v0 --opt source=docker.io/docker/dockerfile:1 --local context=. --local dockerfile=. --output type=image,name=localhost:5000/borgbackup:latest,push=true --opt build-arg:version=1.1.18 --opt platform="linux/amd64,linux/arm64,linux/arm/v7"

# Default to Debian 11, which is the current platform for the BorgBackup standalone binary releases
# the 'offical' python image provides a standalone python build under /usr/local
# the 'slim' variant comes with pip, setuptools and wheel preinstalled
ARG base_image=docker.io/python:3.11-slim-bullseye
ARG version

# Build environment
ARG TARGET_DIR=/opt/borg
ARG PIP_ROOT_USER_ACTION=ignore PIP_CACHE_DIR=/var/local/cache/pip PIP_WHEEL_DIR=${TARGET_DIR}/wheels PIP_SRC_DIR=${TARGET_DIR}/src PIP_DISABLE_PIP_VERSION_CHECK=1
ARG GIT_CACHE_DIR=/var/local/cache/git
ARG BORG_FUSE_IMPL=none BORG_BASE_DIR=/borg

### Build stage ###
# - Compile wheels and run testsuite

FROM ${base_image} as build

# Build: Install OS build dependencies (and cache APT across builds) 
# - Check runtime dependencies (The APT cache is empty in the base image, so dpkg-query will fail for any package not installed prior to first apt update.)
# - https://borgbackup.readthedocs.io/en/stable/installation.html#dependencies
ARG DEBIAN_FRONTEND=noninteractive
RUN --mount=type=cache,id=build-apt-cache,target=/var/cache/apt,sharing=locked --mount=type=cache,id=build-apt-lib,target=/var/lib/apt,sharing=locked \
  dpkg-query --show --showformat='${Package}:${db:Status-Status}\n' libacl1 libssl1.1 liblz4-1 libzstd1 libxxhash0 libcrypt1 libffi7 && \
  rm -f /etc/apt/apt.conf.d/docker-clean && \
  echo 'Binary::apt::APT::Keep-Downloaded-Packages "true";' > /etc/apt/apt.conf.d/keep-cache && \
  apt-get -y -qq update && \ 
  apt-get -y -qq --no-install-recommends install \
  libacl1-dev libssl-dev liblz4-dev libzstd-dev libxxhash-dev libffi-dev \
  build-essential \
  pkg-config \
  git

# Prepare: Import env vars
ARG version TARGET_DIR PIP_ROOT_USER_ACTION PIP_CACHE_DIR PIP_WHEEL_DIR PIP_SRC_DIR PIP_DISABLE_PIP_VERSION_CHECK GIT_CACHE_DIR BORG_FUSE_IMPL BORG_BASE_DIR
WORKDIR ${TARGET_DIR}

# Build: Download BorgBackup source (and cache the GIT repository across builds)
# - Same as using pip wheel with `--src=${PIP_SRC_DIR} --editable git+https://github.com/borgbackup/borg.git@${version}#egg=borgbackup`
#   but with proper caching (and separation of build artifacts into the build layer)
# - Cython needs write access to ${PIP_SRC_DIR}/borgbackup during build, so we cannot cache it directly
RUN --mount=type=cache,target=${GIT_CACHE_DIR},sharing=locked \
  test -d ${GIT_CACHE_DIR}/borg.git && git -C ${GIT_CACHE_DIR}/borg.git remote update --prune || \
  git -C ${GIT_CACHE_DIR} clone --mirror https://github.com/borgbackup/borg.git borg.git && \
  mkdir -p ${PIP_SRC_DIR} && \
  git -C ${PIP_SRC_DIR} -c advice.detachedHead=false clone --depth 1 --branch ${version} file://${GIT_CACHE_DIR}/borg.git borgbackup

# Build and Install: Wheel for BorgBackup from source (and cache PIP and GIT repo across builds)
# Skip cython self-compilation
ARG NO_CYTHON_COMPILE=true
RUN --mount=type=cache,target=${PIP_CACHE_DIR} --mount=type=tmpfs,target=/tmp \
  mkdir -p ${PIP_WHEEL_DIR} && \
  pip install pkgconfig no-manylinux && \
  pip install Cython && \
  pip wheel --wheel-dir=${PIP_WHEEL_DIR} --no-binary=:all: --use-feature=no-binary-enable-wheel-cache ${PIP_SRC_DIR}/borgbackup && \
  pip install --no-index --no-cache-dir --find-links=${PIP_WHEEL_DIR} --only-binary=:all: borgbackup==${version}

# Test: Run self-tests
# - Confirm borg version to fail on any caching issues
RUN \
  borg --version | grep --silent --fixed-strings "borg ${version}" && \
  borg debug info --debug

### Test stage ###
FROM build as test
# - Run the testsuite and abort on error
# - Confirm borg version to fail on any caching issues
# - The readonly tests fail as CAP_LINUX_IMMUTABLE is disabled by default in Docker

ARG version PYTHONFAULTHANDLER=1 PIP_SRC_DIR BORG_FUSE_IMPL BORG_BASE_DIR
WORKDIR ${PIP_SRC_DIR}/borgbackup
RUN --mount=type=cache,target=${PIP_CACHE_DIR} --mount=type=tmpfs,target=/tmp --mount=type=tmpfs,target=/borg \
  borg --version | grep --silent --fixed-strings "borg ${version}" && \
  pip install pytest pytest-benchmark pytest-xdist python-dateutil && \
  pytest --quiet -n auto --disable-warnings --exitfirst --benchmark-skip -k 'not test_readonly' --pyargs borg.testsuite


### Python stage (publish target image) ###

FROM ${base_image} as python

# Install a ssh client to support remote repositories
ARG DEBIAN_FRONTEND=noninteractive
RUN --mount=type=cache,id=final-apt-cache,target=/var/cache/apt,sharing=locked --mount=type=cache,id=final-apt-lib,target=/var/lib/apt,sharing=locked \
  rm -f /etc/apt/apt.conf.d/docker-clean && \
  echo 'Binary::apt::APT::Keep-Downloaded-Packages "true";' > /etc/apt/apt.conf.d/keep-cache && \
  apt-get -y -qq update && \ 
  apt-get -y -qq --no-install-recommends install openssh-client && \
  ssh -V

# Import and configure env vars
ARG version base_image PIP_ROOT_USER_ACTION PIP_WHEEL_DIR PIP_DISABLE_PIP_VERSION_CHECK BORG_BASE_DIR BORG_FUSE_IMPL
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1 
ENV BORG_VERSION=${version} BORG_BASE_DIR=${BORG_BASE_DIR} BORG_FUSE_IMPL=${BORG_FUSE_IMPL}
VOLUME /borg

# Install the wheel and execute once
RUN --mount=type=bind,from=build,source=${PIP_WHEEL_DIR},target=${PIP_WHEEL_DIR} \
  pip install --no-index --no-cache-dir --find-links=${PIP_WHEEL_DIR} --only-binary=:all: --no-compile borgbackup==${version} && \
  borg debug info --debug

ENTRYPOINT ["borg"]

# Labeling https://github.com/opencontainers/image-spec/blob/main/annotations.md
LABEL\
  org.opencontainers.image.title="BorgBackup" \
  org.opencontainers.image.description="BorgBackup is a deduplicating backup program with support for compression and authenticated encryption." \
  org.opencontainers.image.licenses="BSD-3-Clause" \
  org.opencontainers.image.vendor="BorgBackup Community (unofficial)" \
  org.opencontainers.image.version=${version} \
  org.opencontainers.image.source="https://github.com/bbx0/container-borgbackup" \
  org.opencontainers.image.authors="39773919+bbx0@users.noreply.github.com" \
  org.opencontainers.image.base.name=${base_image}