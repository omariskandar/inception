#!/bin/bash
set -euo pipefail

CERT_PATH="${SSL_CERT_PATH:?/etc/nginx/ssl/self.crt}"
KEY_PATH="${SSL_KEY_PATH:?/etc/nginx/ssl/self.key}"
DOMAIN="${DOMAIN_NAME:?localhost}"

if [ ! -f "${CERT_PATH}" ] || [ ! -f "${KEY_PATH}" ]; then
  echo "[nginx] Generating self-signed certificate for ${DOMAIN}..."
  openssl req -x509 -nodes -newkey rsa:2048 -days 365 \
    -keyout "${KEY_PATH}" -out "${CERT_PATH}" \
    -subj "/CN=${DOMAIN}" >/dev/null 2>&1 || true
  chmod 600 "${KEY_PATH}"
fi

echo "[nginx] TLS ready at ${CERT_PATH}"
