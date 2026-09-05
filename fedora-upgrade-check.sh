#!/bin/bash

cat /etc/fedora-release
uname -r
sudo dnf check
sudo dnf upgrade --refresh
