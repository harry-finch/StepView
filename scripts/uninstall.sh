#!/usr/bin/env bash
set -euo pipefail

INSTALL_DIR="/Applications"
if [ ! -d "${INSTALL_DIR}/StepView.app" ] && [ -d "${HOME}/Applications/StepView.app" ]; then
    INSTALL_DIR="${HOME}/Applications"
fi

TARGET_APP="${INSTALL_DIR}/StepView.app"
TARGET_APPEX="${TARGET_APP}/Contents/PlugIns/StepViewQL.appex"

echo "Désinstallation de StepView..."

if [ -d "${TARGET_APPEX}" ]; then
    pluginkit -r "${TARGET_APPEX}" > /dev/null 2>&1 || true
    echo "Extension Quick Look désenregistrée."
fi

if [ -d "${TARGET_APP}" ]; then
    rm -rf "${TARGET_APP}"
    echo "Application supprimée de ${TARGET_APP}."
fi

qlmanage -r > /dev/null 2>&1 || true
qlmanage -r cache > /dev/null 2>&1 || true
echo "Cache Quick Look réinitialisé."
echo "✓ Désinstallation terminée."
