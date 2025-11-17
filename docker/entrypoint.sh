#!/usr/bin/env bash
set -euo pipefail

# Generate host keys if missing
ssh-keygen -A >/dev/null 2>&1 || true

# Start SSHD in background
/usr/sbin/sshd

# (opsional) update nuclei templates saat runtime bila folder kosong
if [ -d "${NUCLEI_TEMPLATES_PATH:-/opt/hexstrike-ai/cent-nuclei-templates}" ]; then
  if [ -z "$(ls -A "${NUCLEI_TEMPLATES_PATH}")" ]; then
    echo "[entrypoint] Nuclei templates kosong, menjalankan cent pull..."
    cent -p "${NUCLEI_TEMPLATES_PATH}" || true
  fi
fi

# Jalankan command utama (Python server)
exec "$@"
