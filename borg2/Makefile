#!/usr/bin/env -S make -f

# Build the BorgBackup container and its distroless variant into a local registry

#: Usage {{{
#	Prerequisites:
#		- registry: local registry to push the image to listening at `localhost:5000`
#   	- buildkit: buildctl is used to compile the image
#	Build and push:
#		make "borg(2.0)"
#		make "distroless(2.0)"
#		make "borg(2.0)" VERSION=2.0.0b11 PLATFORM=linux/amd64
#   Run pytest: 
#		make "test(2.0)" PLATFORM=linux/amd64
#		make "test(2.0)" VERSION=2.0.0b11 PLATFORM=linux/amd64 OPTS="--no-cache"
#   Run self test: 
#	 	make "distroless-test(2.0)" PLATFORM=linux/amd64
#: }}}

#: General settings {{{
SHELL           := /bin/bash
REGISTRY        ?= localhost:5000
IMAGE    		?= borgbackup
NAME			= $(REGISTRY)/$(IMAGE):$(VERSION)
PLATFORM		?= linux/amd64,linux/arm64,linux/arm/v7
PUSH			:= true
#: }}}

#: Borg settings {{{
borg(2.0):	BASE_IMAGE			:= docker.io/library/python:3.12-slim-bookworm
borg(2.0):	DISTROLESS_IMAGE	:= gcr.io/distroless/cc-debian12

# Determine latest patch release, when version is not set explicitly
borg(%):	VERSION				?= $(shell curl --fail --silent --location https://api.github.com/repos/borgbackup/borg/releases | jq -r 'map(select(.tag_name | startswith("$(%)")))|map(select(.prerelease==false and .draft==false))|max_by(.published_at).tag_name')
#: }}}

#: Targets  {{{
.DEFAULT_GOAL := borg(2.0)
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
test(2.0):			XDISTN	?= 8
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