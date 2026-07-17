#!/usr/bin/env bash
# Apt autoremove and autoclean.
set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/../lib/maintain-common.sh"

export DEBIAN_FRONTEND=noninteractive
sudo_run apt-get autoremove -y
sudo_run apt-get autoclean -y
log_ok "Apt cleanup complete"
