#!/bin/bash

podman run -it \
  --name cloud-connected \
  --platform linux/arm64 \
  --privileged \
  --security-opt seccomp=unconfined \
  --security-opt label=disable \
  -v /dev/fuse:/dev/fuse \
  -v ~/Podman\ Volumes/cloud-connected/aws-credentials:/home/cloud-user/.aws:Z \
  -v ~/Podman\ Volumes/cloud-connected/gcp-credentials:/home/cloud-user/.config/gcloud:Z \
  -v ~/Podman\ Volumes/cloud-connected/terraform-projects:/home/cloud-user/terraform:Z \
  -v ~/Podman\ Volumes/cloud-connected/workspace:/home/cloud-user:Z \
  -p 8080:8080 \
  cloud-connected:latest