#!/usr/bin/env bash
set -euo pipefail

missing=0

for cmd in kubectl curl sed openssl; do
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    echo "Falta comando: ${cmd}"
    missing=1
  fi
done

if [[ "${missing}" -ne 0 ]]; then
  echo "Instale os pre-requisitos acima e tente novamente."
  exit 1
fi

echo "Pre-requisitos basicos OK."

