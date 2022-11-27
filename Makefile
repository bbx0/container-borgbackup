# vim:fileencoding=utf-8:foldmethod=marker

# Build the borgbackup container and its distroless variant into a local registry
# 
# All TARGETARCH are split into individual make targets to emulate parallel execution in CI automation (e.g. github actions jobs)
# 
# Prerequisites:
#	- registry: local registry to push the image to, ideally running at `localhost:5000`
#   - buildkit: buildctl is used to compile the image
#	- podman: optional to pull the image
# 
# Usage:
#	Build and push
#	   make -j$(nproc) VERSION=1.1.18
#   Run pytest: 
#     make -j$(nproc) test VERSION=2.0.0b4
#	  make test VERSION=2.0.0b4 PLATFORM=linux/amd64
#	  make distroless-test VERSION=2.0.0b4 PLATFORM=linux/amd64
#  	Build, push via buildkit and pull locally via podman
#	  make podman-pull VERSION=2.0.0b4 PLATFORM=linux/amd64
#

#: General settings {{{
.SUFFIXES:
SHELL            = /bin/bash
REGISTRY        ?= localhost:5000
IMAGE    		:= borgbackup
VERSION 		?= 1.1.18
PLATFORM		?= linux/amd64 linux/arm64 linux/arm/v7 linux/ppc64le linux/s390x
NAME			:= $(REGISTRY)/$(IMAGE):$(VERSION)
#: }}}

#: Image tag platform suffixes {{{
SUFFIX_linux/amd64   := -amd64
SUFFIX_linux/arm64   := -arm64
SUFFIX_linux/arm/v7  := -armv7
SUFFIX_linux/ppc64le := -ppc64le
SUFFIX_linux/s390x   := -s390x
#: }}}

#: Concatenate the PLATFORM list into a comma separated string PLATFORMS {{{
space     := $(true) $(true)
comma     := ,
PLATFORMS := "$(subst $(space),$(comma),$(PLATFORM))"
#: }}}

# all make targets are phony
.DEFAULT_GOAL := distroless-manifest
.PHONY := image manifest test distroless-image distroless-manifest distroless-test buildkit-prune podman-pull podman-clean podman-prune podman-registry-gc

#: Commands {{{
# Buildkit with Dockerfile frontend
BUILD := buildctl build --frontend gateway.v0 --opt source=docker.io/docker/dockerfile:1 --local context=. --local dockerfile=.
#: }}}

#: Create platform images and a multiarch manifest {{{
image(%):
	$(BUILD) --output type=image,name=$(NAME)$(SUFFIX_$(%)),push=true --opt build-arg:version=$(VERSION) --opt platform=$(%)
image: image($(PLATFORM))

image($(PLATFORMS)): image($(PLATFORM))
manifest: image($(PLATFORMS))

test(%):
	$(BUILD) --output type=image,name=$(NAME)$(SUFFIX_$(%)),push=false,store=false --opt build-arg:version=$(VERSION) --opt platform=$(%) --opt target=test
test: test($(PLATFORM))
#: }}}

#: Create distroless variant (needs pushed borgimage as base) {{{
distroless-image(%): image(%)
	$(BUILD) --opt filename=Dockerfile.distroless --output type=image,name=$(NAME)$(SUFFIX_$(%))-distroless,push=true --opt build-arg:version=$(VERSION) --opt build-arg:borg_image=$(NAME)$(SUFFIX_$(%)) --opt platform=$(%)
distroless-image: distroless-image($(PLATFORM))

distroless-image($(PLATFORMS)): distroless-image($(PLATFORM))
distroless-manifest: distroless-image($(PLATFORMS)) manifest

distroless-test(%): image(%)
	$(BUILD) --opt filename=Dockerfile.distroless --output type=image,name=$(NAME)$(SUFFIX_$(%))-distroless,push=false,store=false --opt build-arg:version=$(VERSION) --opt build-arg:borg_image=$(NAME)$(SUFFIX_$(%)) --opt platform=$(%) --opt target=test
distroless-test: distroless-test($(PLATFORM))
#: }}}


#: Housekeeping {{{
buildkit-prune:
	buildctl prune --all

podman-pull: manifest distroless-manifest
	podman pull --quiet $(NAME) $(NAME)-distroless

podman-clean:
	podman image rm --ignore $(NAME) $(foreach platform,$(PLATFORM),$(NAME)$(SUFFIX_$(platform))) $(NAME)-distroless $(foreach platform,$(PLATFORM),$(NAME)$(SUFFIX_$(platform))-distroless)
	podman manifest exists $(NAME) && podman manifest rm $(NAME) || true
	podman manifest exists $(NAME)-distroless && podman manifest rm $(NAME)-distroless || true
	podman image prune --force

podman-registry-gc:
	podman exec registry registry garbage-collect /etc/docker/registry/config.yml --delete-untagged=true --dry-run=false
#: }}}