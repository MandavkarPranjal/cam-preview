#!/usr/bin/env bash
# Install the cam-preview plugin into Omarchy's user plugin dir.
set -euo pipefail

SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="${HOME}/.config/omarchy/plugins/himmel.cam-preview"
MODE="copy"

case "${1:-}" in
  --link)  MODE="link" ;;
  --remove)
    if [[ -e "${PLUGIN_DIR}" ]]; then
      rm -rf "${PLUGIN_DIR}"
      echo "Removed ${PLUGIN_DIR}"
    else
      echo "Not installed (${PLUGIN_DIR} does not exist)"
    fi
    exit 0
    ;;
  --help|-h)
    echo "Usage: $0 [--link|--remove]"
    echo "  (default)  copy the plugin into ~/.config/omarchy/plugins/himmel.cam-preview"
    echo "  --link     symlink the repo dir instead (for development)"
    echo "  --remove   delete the installed copy"
    exit 0
    ;;
esac

if [[ ! -f "${SOURCE_DIR}/manifest.json" || ! -f "${SOURCE_DIR}/Panel.qml" ]]; then
  echo "error: manifest.json and Panel.qml must exist next to this script" >&2
  exit 1
fi

mkdir -p "$(dirname "${PLUGIN_DIR}")"

if [[ "${MODE}" == "link" ]]; then
  if [[ -e "${PLUGIN_DIR}" && ! -L "${PLUGIN_DIR}" ]]; then
    echo "error: ${PLUGIN_DIR} exists and is not a symlink" >&2
    exit 1
  fi
  ln -sfn "${SOURCE_DIR}" "${PLUGIN_DIR}"
  echo "Linked ${SOURCE_DIR} -> ${PLUGIN_DIR}"
else
  rm -rf "${PLUGIN_DIR}"
  cp -r "${SOURCE_DIR}/manifest.json" "${SOURCE_DIR}/Panel.qml" "${PLUGIN_DIR}/"
  echo "Installed to ${PLUGIN_DIR}"
fi

echo "Restart the shell to load it: omarchy restart shell"
