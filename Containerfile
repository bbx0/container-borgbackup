# Default to ${base_image}, which is the platform for the latest BorgBackup standalone binary release
ARG base_image=docker.io/debian:bullseye-slim

# Create container image with
# - official BorgBackup binary release
# - openssh client

FROM ${base_image}
ARG version
ARG base_image
ARG archive=borg-linuxnew64.tgz
ARG archive_url=https://github.com/borgbackup/borg/releases/download/${version}/${archive}
# Signing Key: Thomas Waldmann <tw@waldmann-edv.de
ARG public_key=6D5BEF9ADD2075805747B70F9F88FB52FAF7B393
ARG public_key_url=https://keys.openpgp.org/vks/v1/by-fingerprint/${public_key}

# Set image defaults
# - Set base dir to /borg to allow indepentent data persistance and rootfs being mounted read-only
# - Set entrypoint to borg to allow usage "as binary" (unset any additional CMD from the base image)
ENV BORG_BASE_DIR=/borg
VOLUME /borg
ENTRYPOINT ["/usr/local/bin/borg"]
CMD []

# Labeling https://github.com/opencontainers/image-spec/blob/main/annotations.md
LABEL \
  org.opencontainers.image.title="BorgBackup" \
  org.opencontainers.image.description="BorgBackup is a deduplicating backup program, which supports compression and authenticated encryption." \
  org.opencontainers.image.licenses="BSD-3-Clause" \
  org.opencontainers.image.vendor="BorgBackup Community (unofficial)" \
  org.opencontainers.image.version=${version} \
  org.opencontainers.image.source="https://github.com/bbx0/container-borgbackup" \
  org.opencontainers.image.authors="39773919+bbx0@users.noreply.github.com" \
  org.opencontainers.image.base.name=${base_image}

# Setup the image
# - Install packages
#   - openssh-client: for usage with BORG_RSH
# - Install temporary packages (removed from final image)
#   - sqv: signature verification of downloaded archives 
#   - curl: download the archives
#   - ca-certificates: trusted CAs for curl (HTTPS)
# - Download the archive, signature and public key to /tmp
# - Verify the archive with the GPG Key (sqv only exits with 0 if everything is okay)
# - Extract to /usr/local/lib/borg/
# - Link the binary into PATH
# - Remove downloaded archives and temporary packages
# - Test that the binary executes
WORKDIR /tmp
RUN \
  export DEBIAN_FRONTEND=noninteractive; \
  apt-get -y -qq update && \ 
  apt-get -y -qq --no-install-recommends install openssh-client sqv curl ca-certificates && \
  curl --fail --silent --show-error --location --remote-name-all \
  --url ${archive_url} \
  --url ${archive_url}.asc \
  --url ${public_key_url} && \
  sqv ${archive}.asc ${archive} --keyring ${public_key} && \
  tar --extract --auto-compress --file="${archive}" --strip-components=1 --one-top-level=/usr/local/lib/borg && \
  ln -s /usr/local/lib/borg/borg.exe /usr/local/bin/borg && \
  rm /tmp/* && \
  apt-get -y -qq --purge --auto-remove remove sqv curl ca-certificates && \
  apt-get -y -qq clean && \
  rm -rf /var/lib/apt/lists/*; \
  borg --version
