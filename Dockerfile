# syntax=docker.io/docker/dockerfile:1
# check=error=true

# Usage: 
#  buildctl build --frontend gateway.v0 --opt source=docker.io/docker/dockerfile:1 --local context=. --local dockerfile=. --opt build-arg:version=2.0.0b14 --progress=plain
#  buildctl build --frontend gateway.v0 --opt source=docker.io/docker/dockerfile:1 --local context=. --local dockerfile=. --output type=image,name=localhost:5000/borgbackup:2.0.0b14,push=true --opt build-arg:version=2.0.0b14 --opt platform="linux/amd64,linux/arm64,linux/arm/v7"

# Default to Debian 12, which is the latest platform for the BorgBackup standalone binary releases
# the 'offical' python image provides a standalone python build under /usr/local
# the 'slim' variant comes with pip, setuptools and wheel pre-installed
ARG base_image=docker.io/python:3-slim-bookworm
ARG version

### Download source (to cache as layer)
FROM scratch AS source
# Signing Key: Thomas Waldmann <tw@waldmann-edv.de>
ADD https://keys.openpgp.org/vks/v1/by-fingerprint/6D5BEF9ADD2075805747B70F9F88FB52FAF7B393 signing_key.asc
ARG version
ADD https://github.com/borgbackup/borg/releases/download/${version}/borgbackup-${version}.tar.gz borgbackup-${version}.tar.gz
ADD https://github.com/borgbackup/borg/releases/download/${version}/borgbackup-${version}.tar.gz.asc borgbackup-${version}.tar.gz.asc

### Base image ###
# - Set bash as shell with errexit, nounset, xtrace and pipefail
# - Set build environment and defaults
# - Setup APT caching <https://docs.docker.com/reference/dockerfile/#example-cache-apt-packages>
# - Install a ssh client to support remote repositories
FROM ${base_image} AS base
SHELL [ "/usr/bin/bash", "-c", "-eux", "-o", "pipefail" ]
ARG base_image version TARGETARCH TARGETVARIANT

ARG BORG_BASE_DIR=/borg
ARG BORG_FUSE_IMPL=none
ARG BORG_VERSION=${version}
ARG BORG_SRC_DIR=/usr/local/src/borgbackup-${BORG_VERSION}-${TARGETARCH}${TARGETVARIANT}
ARG BORG_WHEEL_DIR=${BORG_SRC_DIR}/wheels
ARG DEBIAN_FRONTEND=noninteractive
ARG PIP_CACHE_DIR=/var/local/cache/borg-${BORG_VERSION}/${TARGETARCH}${TARGETVARIANT}/pip
ARG PIP_CONSTRAINT=${BORG_SRC_DIR}/requirements.d/development.lock.txt
ARG PIP_DISABLE_PIP_VERSION_CHECK=1
ARG PIP_ROOT_USER_ACTION=ignore

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked,id=apt-cache-${TARGETARCH}${TARGETVARIANT} --mount=type=cache,target=/var/lib/apt,sharing=locked,id=apt-lib-${TARGETARCH}${TARGETVARIANT} <<-'EOT'
	rm -f /etc/apt/apt.conf.d/docker-clean
	echo 'Binary::apt::APT::Keep-Downloaded-Packages "true";' > /etc/apt/apt.conf.d/keep-cache
	apt-get -y -qq update
	apt-get -y -qq --no-install-recommends install openssh-client
	ssh -V
EOT

### Build stage ###
# - https://borgbackup.readthedocs.io/en/stable/installation.html#dependencies
FROM base AS build
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked,id=apt-cache-${TARGETARCH}${TARGETVARIANT} --mount=type=cache,target=/var/lib/apt,sharing=locked,id=apt-lib-${TARGETARCH}${TARGETVARIANT} <<-'EOT'
	apt-get -y -qq --no-install-recommends install \
		build-essential \
		libacl1-dev libffi-dev libssl-dev liblz4-dev libzstd-dev libxxhash-dev \
		pkg-config \
		sqv
EOT

# Extract into build layer (verify gpg key)
WORKDIR ${BORG_SRC_DIR}
RUN --mount=type=bind,from=source,target=/mnt/source <<-'EOT'
	sqv "/mnt/source/borgbackup-${BORG_VERSION}.tar.gz.asc" "/mnt/source/borgbackup-${BORG_VERSION}.tar.gz" --keyring /mnt/source/signing_key.asc
	tar --extract --auto-compress --file="/mnt/source/borgbackup-${BORG_VERSION}.tar.gz" --strip-components=1
EOT

# Build and Install: Wheel for BorgBackup from source (and cache PIP and GIT repo across builds)
ARG PIP_NO_BINARY=:all:
ARG NO_CYTHON_COMPILE=true
WORKDIR ${BORG_WHEEL_DIR}
RUN --mount=type=cache,target=${PIP_CACHE_DIR} --mount=type=tmpfs,target=/tmp <<-'EOT'
	pip install pkgconfig
	pip wheel Cython --use-pep517 --config-setting="--build-option=--no-cython-compile"
	pip wheel "${BORG_SRC_DIR}"
	pip install --no-index --no-cache-dir --find-links="${BORG_WHEEL_DIR}" --only-binary=:all: borgbackup=="${BORG_VERSION}"
EOT

# Test: Run self-tests
RUN --mount=type=tmpfs,target=/tmp --mount=type=tmpfs,target=${BORG_BASE_DIR} <<-'EOT'
	borg --version | grep --silent --fixed-strings "borg ${BORG_VERSION}"
	borg debug info --debug
EOT

### Test stage (pytest) ###
FROM base AS test
RUN --mount=type=bind,from=build,source=${BORG_SRC_DIR},target=${BORG_SRC_DIR} --mount=type=cache,target=${PIP_CACHE_DIR} <<-'EOT'
	pip install pytest pytest-benchmark pytest-xdist python-dateutil
	pip install --no-index --no-cache-dir --find-links="${BORG_WHEEL_DIR}" --only-binary=:all: borgbackup=="${BORG_VERSION}"
EOT

ARG XDISTN=auto
ARG PYTHONFAULTHANDLER=1
WORKDIR ${BORG_SRC_DIR}
# Skip readonly tests as CAP_LINUX_IMMUTABLE is disabled by default in Docker
RUN --mount=type=bind,from=build,source=${BORG_SRC_DIR},target=${BORG_SRC_DIR} --mount=type=tmpfs,target=/tmp --mount=type=tmpfs,target=${BORG_BASE_DIR} <<-'EOT'
	pytest --quiet -n "${XDISTN}" --disable-warnings --exitfirst --benchmark-skip -k 'not test_readonly' --pyargs borg.testsuite
EOT

### Final stage (publish target image) ###
FROM base AS final
# Persist ENV into image
ENV BORG_VERSION=${BORG_VERSION} BORG_BASE_DIR=${BORG_BASE_DIR} BORG_FUSE_IMPL=${BORG_FUSE_IMPL}
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1
VOLUME /borg

# Install the wheel and execute once
RUN --mount=type=bind,from=build,source=${BORG_SRC_DIR},target=${BORG_SRC_DIR} <<-'EOT'
	pip install --no-index --no-cache-dir --find-links="${BORG_WHEEL_DIR}" --only-binary=:all: --no-compile borgbackup=="${BORG_VERSION}"
	borg debug info --debug
EOT

ENTRYPOINT ["/usr/local/bin/borg"]

# Labeling https://github.com/opencontainers/image-spec/blob/main/annotations.md
LABEL\
	org.opencontainers.image.title="BorgBackup" \
	org.opencontainers.image.description="BorgBackup is a deduplicating backup program with support for compression and authenticated encryption." \
	org.opencontainers.image.licenses="BSD-3-Clause" \
	org.opencontainers.image.vendor="BorgBackup Community (unofficial)" \
	org.opencontainers.image.version=${BORG_VERSION} \
	org.opencontainers.image.source="https://github.com/bbx0/container-borgbackup" \
	org.opencontainers.image.authors="Philipp Micheel <bbx0+borgbackup at bitdevs dot de>" \
	org.opencontainers.image.base.name=${base_image}