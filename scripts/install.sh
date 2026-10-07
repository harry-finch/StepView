#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_APP="${PROJECT_DIR}/build/StepView.app"

if [ ! -d "${BUILD_APP}" ]; then
    echo "⚠️  L'application n'est pas encore compilée. Lancement de la compilation..."
    "${PROJECT_DIR}/scripts/build.sh"
fi

# Choix de la destination : /Applications en priorité, sinon ~/Applications
INSTALL_DIR="/Applications"
if [ ! -w "${INSTALL_DIR}" ]; then
    INSTALL_DIR="${HOME}/Applications"
    mkdir -p "${INSTALL_DIR}"
fi

TARGET_APP="${INSTALL_DIR}/StepView.app"
TARGET_APPEX="${TARGET_APP}/Contents/PlugIns/StepViewQL.appex"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

echo "=========================================================="
echo "  Installation de StepView & Quick Look Extension"
echo "=========================================================="
echo "Destination : ${TARGET_APP}"

# 1. Copie de l'application
rm -rf "${TARGET_APP}"
cp -R "${BUILD_APP}" "${TARGET_APP}"
echo "[1/4] Application copiée dans ${INSTALL_DIR}"

# 2. Enregistrement dans LaunchServices (UTI .step / .stp)
if [ -f "${LSREGISTER}" ]; then
    "${LSREGISTER}" -f "${TARGET_APP}"
    echo "[2/4] Types de fichiers STEP (.step, .stp) enregistrés dans LaunchServices"
fi

# 3. Enregistrement et activation du plugin Quick Look dans PlugInKit
if [ -d "${TARGET_APPEX}" ]; then
    pluginkit -a "${TARGET_APPEX}"
    pluginkit -e use -i com.stepview.app.QuickLook
    echo "[3/4] Extension Quick Look enregistrée et activée dans PlugInKit"
fi

# 4. Rafraîchissement des démons Quick Look et du Finder
qlmanage -r > /dev/null 2>&1 || true
qlmanage -r cache > /dev/null 2>&1 || true
killall Finder > /dev/null 2>&1 || true
echo "[4/4] Cache Quick Look réinitialisé et Finder actualisé"

echo ""
echo "=========================================================="
echo "  ✓ Installation terminée avec succès !"
echo "  Vous pouvez maintenant :"
echo "  1. Sélectionner un fichier .step dans le Finder et presser Espace"
echo "  2. Double-cliquer sur StepView dans vos Applications pour ouvrir l'app"
echo "=========================================================="
