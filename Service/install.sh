#!/bin/bash

set -euo pipefail

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

TARGET_USER="${SUDO_USER:-${USER:-$(id -un)}}"
TARGET_GROUP="$(id -gn "$TARGET_USER" 2>/dev/null || echo "$TARGET_USER")"

install -D -m 0755 "$BASE_DIR/dank-fan-stats-daemon.sh" /usr/local/bin/dank-fan-stats-daemon

sed -e "s/@CLIENT_USER@/${TARGET_USER}/g" \
	-e "s/@CLIENT_GROUP@/${TARGET_GROUP}/g" \
	"$BASE_DIR/dank-fan-stats.service" >/etc/systemd/system/dank-fan-stats.service
chmod 0644 /etc/systemd/system/dank-fan-stats.service

install -D -m 0644 "$BASE_DIR/ec_sys.conf" /etc/modules-load.d/ec_sys.conf

install -D -m 0644 "$BASE_DIR/ec_sys-write.conf" /etc/modprobe.d/ec_sys.conf

install -d -m 0755 /var/lib/dank-fan-stats

modprobe -r ec_sys 2>/dev/null || true
modprobe ec_sys 2>/dev/null || true

systemctl daemon-reload
systemctl enable dank-fan-stats.service >/dev/null 2>&1 || true
systemctl restart dank-fan-stats.service

echo "Installed dank-fan-stats (client user: ${TARGET_USER})."
