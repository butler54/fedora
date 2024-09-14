#!/usr/bin/env bash
# This was procedural

sudo dnf update
sudo dnf config-manager --add-repo https://developer.download.nvidia.com/compute/cuda/repos/fedora39/x86_64/cuda-fedora39.repo
sudo dnf clean all
sudo dnf clean expire-cache
sudo dnf module disable nvidia-driver
sudo dnf install cuda cuda-toolkit xorg-x11-drv-nvidia-cuda