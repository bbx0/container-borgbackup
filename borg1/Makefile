#!/usr/bin/env -S make -f

# Build the BorgBackup container and its distroless variant into a local registry

#: Usage {{{
#	Prerequisites:
#		- registry: local registry to push the image to listening at `localhost:5000`
#   	- buildkit: buildctl is used to compile the image
#	Build and push:
#		make "borg(1.4)"
#		make "distroless(1.4)"
#   Run pytest: 
#		make "test(1.4)" PLATFORM=linux/amd64
#   Run self test: 
#	 	make "distroless-test(1.4)" PLATFORM=linux/amd64
#: }}}

#: General settings {{{
SHELL           := /bin/bash
REGISTRY        ?= localhost:5000
IMAGE    		?= borgbackup
NAME			= $(REGISTRY)/$(IMAGE):$(VERSION)
PLATFORM		?= linux/amd64,linux/arm64/v8,linux/arm/v7
PUSH			:= true
#: }}}

#: Borg settings {{{
borg(1.1):	BASE_IMAGE			:= docker.io/library/python:3.10-slim-bookworm
borg(1.1):	DISTROLESS_IMAGE	:= gcr.io/distroless/base-debian12
borg(1.2):	BASE_IMAGE			:= docker.io/library/python:3.11-slim-bookworm
borg(1.2):	DISTROLESS_IMAGE	:= gcr.io/distroless/base-debian12
borg(1.4):	BASE_IMAGE			:= docker.io/library/python:3.11-slim-bookworm
borg(1.4):	DISTROLESS_IMAGE	:= gcr.io/distroless/base-debian12

# Determine latest patch release, when version is not set explicitly
borg(%):	VERSION				?= $(shell gh api repos/borgbackup/borg/releases --paginate --jq 'map(select(.draft==false and .prerelease==false and (.tag_name | startswith("$(%)"))))|max_by(.published_at).tag_name')
#: }}}

#: Targets  {{{
.DEFAULT_GOAL := borg(1.4)
# Create multiarch image (Buildkit with Dockerfile frontend)
borg(%):
	buildctl build --frontend gateway.v0 --opt source=docker.io/docker/dockerfile:1 --local context=. --local dockerfile=. \
	--output type=image,name=$(NAME)$(SUFFIX),push=$(PUSH) \
	--opt build-arg:version=$(VERSION) \
	--opt build-arg:base_image=$(BASE_IMAGE) \
	--opt build-arg:borg_image=$(NAME) \
	--opt build-arg:distroless_image=$(DISTROLESS_IMAGE) \
	--opt platform=$(PLATFORM) \
	--opt attest:sbom= \
	--opt attest:provenance=mode=max \
	$(OPTS)

# Distroless variant (needs an already pushed version of borg or fails)
distroless(%):		SUFFIX	+= -distroless
distroless(%):		OPTS	+= --opt filename=Dockerfile.distroless
distroless(%):		borg(%)	;

# Test stages
test(1.1):			XDISTN	?= 4
test(1.2):			XDISTN	?= 16
test(1.4):			XDISTN	?= 16
test(%):			OPTS	+= --opt target=test
test(%):			OPTS	+= --opt build-arg:XDISTN=$(XDISTN)
test(%):			PUSH	:= false
test(%):			borg(%)	;

distroless-test(%):	OPTS	+= --opt target=test
distroless-test(%):	PUSH	:= false
distroless-test(%): distroless(%)	;

# Clean build cache
buildkit-prune:
	buildctl prune --all

# additional and phony targets
.SUFFIXES:
.PHONY := buildkit-prune borg(%) test(%) distroless(%) distroless-test(%)
#: }}}

# vim:fileencoding=utf-8:foldmethod=marker