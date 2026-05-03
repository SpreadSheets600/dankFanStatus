#!/bin/bash

set -euo pipefail

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

install -D -m 0755 "$BASE_DIR/dank-fan-stats-daemon.sh" /usr/local/bin/dank-fan-stats-daemon
install -D -m 0644 "$BASE_DIR/dank-fan-stats.service" /etc/systemd/system/dank-fan-stats.service

systemctl daemon-reload
systemctl enable --now dank-fan-stats.service
