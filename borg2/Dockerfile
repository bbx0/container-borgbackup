# syntax=docker.io/docker/dockerfile:1
# check=error=true

# Usage: 
#  podman build --file Dockerfile --build-arg version=2.0.0b14 --tag localhost:5000/borgbackup:2.0.0b14
#  buildctl build --frontend gateway.v0 --opt source=docker.io/docker/dockerfile:1 --local context=. --local dockerfile=. --opt build-arg:version=2.0.0b14 --progress=plain
#  buildctl build --frontend gateway.v0 --opt source=docker.io/docker/dockerfile:1 --local context=. --local dockerfile=. --output type=image,name=localhost:5000/borgbackup:2.0.0b14,push=true --opt build-arg:version=2.0.0b14 --opt platform="linux/amd64,linux/arm64,linux/arm/v7"

# Default to Debian 12, which is the latest platform for the BorgBackup standalone binary releases
# the 'offical' python image provides a standalone python build under /usr/local
# the 'slim' variant comes with pip, setuptools and wheel pre-installed
ARG base_image=docker.io/python:3-slim-bookworm
ARG rclone_image=docker.io/rclone/rclone:1
ARG version

ARG BORG_BASE_DIR=/borg
ARG BORG_FUSE_IMPL=none
ARG BORG_VERSION=${version}
ARG BORG_SRC_DIR=/usr/local/src/borgbackup-${BORG_VERSION}-${TARGETARCH}${TARGETVARIANT}
ARG BORG_WHEEL_DIR=${BORG_SRC_DIR}/wheels
ARG PIP_CACHE_DIR=/var/local/cache/borg-${BORG_VERSION}/${TARGETARCH}${TARGETVARIANT}/pip
ARG PIP_CONSTRAINT=${BORG_SRC_DIR}/requirements.d/development.lock.txt
ARG PIP_DISABLE_PIP_VERSION_CHECK=1
ARG PIP_ROOT_USER_ACTION=ignore
ARG RCLONE_CACHE_DIR=/rclone/cache
ARG RCLONE_CONFIG=/rclone/config/rclone.conf

### Download source (to cache as layer)
FROM scratch AS source
# Signing Key: Thomas Waldmann <tw@waldmann-edv.de>
ADD https://keys.openpgp.org/vks/v1/by-fingerprint/6D5BEF9ADD2075805747B70F9F88FB52FAF7B393 signing_key.asc
ARG version
ADD https://github.com/borgbackup/borg/releases/download/${version}/borgbackup-${version}.tar.gz borgbackup-${version}.tar.gz
ADD https://github.com/borgbackup/borg/releases/download/${version}/borgbackup-${version}.tar.gz.asc borgbackup-${version}.tar.gz.asc

### Get the rclone Debian package ###
# - Download the rclone Debian package based on the ${rclone_image} version
# - Verify the signed SHA256SUMS file with gpgv. (sqv cannot be used as it rejects the weak DSA1024 signature.)
# - Check the SHA256SUMS for the rclone package.
FROM --platform=${BUILDPLATFORM} ${rclone_image} AS rclone
# Signing Key: Nick Craig-Wood <nick@craig-wood.com>
ADD https://keys.openpgp.org/vks/v1/by-fingerprint/FBF737ECE9F8AB18604BD2AC93935E02FF3B54FA /rclone/signing_key.asc
ARG TARGETARCH TARGETVARIANT
WORKDIR /rclone
RUN <<-'EOT'
	set -eux -o pipefail
	apk add --no-cache coreutils gpg gpgv grep

	VERSION=$(rclone version |grep --perl-regexp --only-matching -e '(?<=rclone v)([[:digit:]]+\.[[:digit:]]+\.[[:digit:]]+)$')
	rclone copyurl --print-filename "https://downloads.rclone.org/v${VERSION}/SHA256SUMS" ./SHA256SUMS.pgp
	rclone copyurl --print-filename "https://downloads.rclone.org/v${VERSION}/rclone-v${VERSION}-linux-${TARGETARCH}${TARGETVARIANT:+-${TARGETVARIANT}}.deb" ./rclone-current-linux-${TARGETARCH}${TARGETVARIANT:+-${TARGETVARIANT}}.deb
	ln -s rclone-current-linux-${TARGETARCH}${TARGETVARIANT:+-${TARGETVARIANT}}.deb rclone-v${VERSION}-linux-${TARGETARCH}${TARGETVARIANT:+-${TARGETVARIANT}}.deb

	gpg --quiet --batch --with-colons --status-fd 2 --no-autostart --no-tty --output signing_key.gpg --dearmor signing_key.asc
	gpgv --keyring ./signing_key.gpg SHA256SUMS.pgp

	gpg --quiet --batch --with-colons --status-fd 2 --no-autostart --no-tty --no-default-keyring --keyring ./signing_key.gpg --output SHA256SUMS --decrypt SHA256SUMS.pgp
	sha256sum --check --strict --ignore-missing SHA256SUMS
EOT

### Build stage ###
# - https://borgbackup.readthedocs.io/en/stable/installation.html#dependencies
FROM ${base_image} AS build
ARG DEBIAN_FRONTEND=noninteractive
RUN \
	--mount=type=tmpfs,target=/var/cache/apt \
	--mount=type=tmpfs,target=/var/lib/apt \
	bash -eux -o pipefail <<-'EOT'
		apt-get -y -qq update	
		apt-get -y -qq --no-install-recommends install \
			build-essential \
			libacl1-dev libffi-dev libssl-dev liblz4-dev libzstd-dev libxxhash-dev \
			pkg-config \
			sqv
EOT

# Extract into build layer (verify gpg key)
ARG BORG_BASE_DIR BORG_FUSE_IMPL BORG_VERSION BORG_SRC_DIR BORG_WHEEL_DIR
WORKDIR ${BORG_SRC_DIR}
RUN --mount=type=bind,from=source,target=/mnt/source \
	bash -eux -o pipefail <<-'EOT'
		sqv "/mnt/source/borgbackup-${BORG_VERSION}.tar.gz.asc" "/mnt/source/borgbackup-${BORG_VERSION}.tar.gz" --keyring /mnt/source/signing_key.asc
		tar --extract --auto-compress --file="/mnt/source/borgbackup-${BORG_VERSION}.tar.gz" --strip-components=1
EOT

# Build and Install: Wheel for BorgBackup from source (and cache PIP and GIT repo across builds)
ARG PIP_CACHE_DIR PIP_CONSTRAINT PIP_DISABLE_PIP_VERSION_CHECK PIP_ROOT_USER_ACTION
ARG PIP_NO_BINARY=:all:
ARG NO_CYTHON_COMPILE=true
ARG	PYTHONDONTWRITEBYTECODE=1
WORKDIR ${BORG_WHEEL_DIR}
RUN \
	--mount=type=cache,target=${PIP_CACHE_DIR} \
	--mount=type=tmpfs,target=/tmp \
	bash -eux -o pipefail <<-'EOT'

		# We pin the development.lock.txt as a constraints file but it is requirements file.
		# Constraints cannot have extras.
		sed -i 's/\[[^][]*\]//' ${PIP_CONSTRAINT}

		# Borg 2.0.0b14 requires setuptools==75.1.0. Constrain packages requiring setuptools>=77.0.1 to the last compatible version.
		[ "${BORG_VERSION}" != "2.0.0b14" ] || {
			echo "calver<=2025.03.31" 
			echo "types-psutil<=6.1.0.20241221"
		} >> ${PIP_CONSTRAINT}
	
		# Build and install
		pip install pkgconfig
		pip wheel Cython --use-pep517 --config-setting="--build-option=--no-cython-compile"
		pip wheel "${BORG_SRC_DIR}"
		pip install --no-index --no-cache-dir --find-links="${BORG_WHEEL_DIR}" --only-binary=:all: borgbackup=="${BORG_VERSION}"
		
		# Test: Run self-tests
		borg --version | grep --silent --fixed-strings "borg ${BORG_VERSION}"
		borg debug info --debug
EOT

### Test stage (pytest) ###
FROM ${base_image} AS test
ARG BORG_BASE_DIR BORG_SRC_DIR BORG_VERSION BORG_WHEEL_DIR
ARG PIP_CACHE_DIR PIP_CONSTRAINT PIP_DISABLE_PIP_VERSION_CHECK PIP_ROOT_USER_ACTION
ARG PYTHONFAULTHANDLER=1
ARG XDISTN=auto

WORKDIR ${BORG_SRC_DIR}
RUN \
	--mount=type=bind,from=build,source=${BORG_SRC_DIR},target=${BORG_SRC_DIR} \
	--mount=type=cache,target=${PIP_CACHE_DIR} \
	--mount=type=tmpfs,target=${BORG_BASE_DIR} \
	--mount=type=tmpfs,target=/tmp \
	bash -eux -o pipefail <<-'EOT'
		pip install pytest pytest-benchmark pytest-xdist python-dateutil
		pip install --no-index --no-cache-dir --find-links="${BORG_WHEEL_DIR}" --only-binary=:all: borgbackup=="${BORG_VERSION}"

		# Skip readonly tests as CAP_LINUX_IMMUTABLE is disabled by default in Docker
		pytest --quiet -n "${XDISTN}" --disable-warnings --exitfirst --benchmark-skip -k 'not test_readonly' --pyargs borg.testsuite
EOT

### Final stage (publish target image) ###
FROM ${base_image} AS final
ARG \
	base_image \
	BORG_BASE_DIR BORG_FUSE_IMPL BORG_SRC_DIR BORG_WHEEL_DIR BORG_VERSION \
	DEBIAN_FRONTEND=noninteractive \
	PIP_CONSTRAINT PIP_DISABLE_PIP_VERSION_CHECK PIP_ROOT_USER_ACTION \
	RCLONE_CACHE_DIR RCLONE_CONFIG \
	TARGETARCH TARGETVARIANT
ENV \
	BORG_VERSION=${BORG_VERSION} \
	BORG_BASE_DIR=${BORG_BASE_DIR} \
	BORG_FUSE_IMPL=${BORG_FUSE_IMPL} \
	PYTHONDONTWRITEBYTECODE=1 \
	PYTHONUNBUFFERED=1 \
	RCLONE_CONFIG=${RCLONE_CONFIG} \
	RCLONE_CACHE_DIR=${RCLONE_CACHE_DIR}

# Install the borg wheel and execute once
# Install openssh-client and rclone
RUN \
	--mount=type=bind,from=rclone,source=/rclone,target=/mnt/rclone \
	--mount=type=tmpfs,target=/var/cache/apt \
	--mount=type=tmpfs,target=/var/lib/apt \
	bash -eux -o pipefail <<-'EOT'
		apt-get -y -qq update
		apt-get -y -qq --no-install-recommends install openssh-client
		ssh -V

		dpkg -i "/mnt/rclone/rclone-current-linux-${TARGETARCH}${TARGETVARIANT:+-${TARGETVARIANT}}.deb"
		rclone config touch
		rclone version
EOT
RUN \
	--mount=type=bind,from=build,source=${BORG_SRC_DIR},target=${BORG_SRC_DIR} \
	bash -eux -o pipefail <<-'EOT'
		pip install --no-index --no-cache-dir --find-links="${BORG_WHEEL_DIR}" --only-binary=:all: --no-compile borgbackup=="${BORG_VERSION}"
		borg debug info --debug
EOT

VOLUME ["${BORG_BASE_DIR}"]
ENTRYPOINT ["/usr/local/bin/borg"]

# Labeling https://github.com/opencontainers/image-spec/blob/main/annotations.md
LABEL \
	org.opencontainers.image.title='BorgBackup' \
	org.opencontainers.image.description='BorgBackup is a deduplicating backup program with support for compression and authenticated encryption.' \
	org.opencontainers.image.licenses='BSD-3-Clause' \
	org.opencontainers.image.vendor='BorgBackup Community (unofficial)' \
	org.opencontainers.image.version="${BORG_VERSION}" \
	org.opencontainers.image.source='https://github.com/bbx0/container-borgbackup' \
	org.opencontainers.image.authors='Philipp Micheel <bbx0+borgbackup at bitdevs dot de>' \
	org.opencontainers.image.base.name="${base_image}"