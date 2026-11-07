#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${BUILD_DIR:-${PROJECT_DIR}/build}"

# Préfixe Open CASCADE (Homebrew par défaut) transmis au script de bundling
export OCCT_PREFIX="${OCCT_PREFIX:-$(brew --prefix opencascade)}"

# Cible : architecture de la machine + déploiement minimal macOS.
# 26.0 = minos des dylibs Homebrew (otool -l | grep -A3 LC_BUILD_VERSION) ; une cible
# plus basse produirait des avertissements d'éditeur de liens et un bundle non fonctionnel.
export MACOSX_DEPLOYMENT_TARGET="${MACOSX_DEPLOYMENT_TARGET:-26.0}"
TARGET="$(uname -m)-apple-macos${MACOSX_DEPLOYMENT_TARGET}"
APP_DIR="${BUILD_DIR}/StepView.app"
CONTENTS_DIR="${APP_DIR}/Contents"
FRAMEWORKS_DIR="${CONTENTS_DIR}/Frameworks"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
PLUGINS_DIR="${CONTENTS_DIR}/PlugIns"
QL_APPEX_DIR="${PLUGINS_DIR}/StepViewQL.appex"
QL_CONTENTS_DIR="${QL_APPEX_DIR}/Contents"
QL_MACOS_DIR="${QL_CONTENTS_DIR}/MacOS"

echo "=========================================================="
echo "  Compilation de StepView & Extension Quick Look (.appex) "
echo "=========================================================="

# 1. Préparation des répertoires du bundle macOS
echo "[1/6] Nettoyage et création des structures de bundles..."
rm -rf "${APP_DIR}"
mkdir -p "${MACOS_DIR}"
mkdir -p "${FRAMEWORKS_DIR}"
mkdir -p "${PLUGINS_DIR}"
mkdir -p "${QL_MACOS_DIR}"
mkdir -p "${QL_CONTENTS_DIR}/Resources"

# 2. Copie et relocalisation des dylibs OCCT
echo "[2/6] Intégration autonome des bibliothèques Open CASCADE..."
python3 "${PROJECT_DIR}/scripts/bundle_dependencies.py" "${FRAMEWORKS_DIR}" "${OCCT_PREFIX}"

# 3. Compilation de StepCADCore.framework
echo "[3/6] Compilation de StepCADCore.framework (Objective-C++ / OCCT Bridge)..."
FW_DIR="${FRAMEWORKS_DIR}/StepCADCore.framework"
FW_VERSIONS="${FW_DIR}/Versions/A"
mkdir -p "${FW_VERSIONS}/Headers"
mkdir -p "${FW_VERSIONS}/Modules"
mkdir -p "${FW_VERSIONS}/Resources"

cp "${PROJECT_DIR}/StepCADCore/include/CADMeshBridge.h" "${FW_VERSIONS}/Headers/"
cp "${PROJECT_DIR}/StepCADCore/include/StepCADCore.h" "${FW_VERSIONS}/Headers/"
cp "${PROJECT_DIR}/StepCADCore/include/module.modulemap" "${FW_VERSIONS}/Modules/"
cp "${PROJECT_DIR}/StepCADCore/Resources/Info.plist" "${FW_VERSIONS}/Resources/"

ln -sf A "${FW_DIR}/Versions/Current"
ln -sf Versions/Current/Headers "${FW_DIR}/Headers"
ln -sf Versions/Current/Modules "${FW_DIR}/Modules"
ln -sf Versions/Current/Resources "${FW_DIR}/Resources"
ln -sf Versions/Current/StepCADCore "${FW_DIR}/StepCADCore"

clang++ -dynamiclib -std=c++17 -fobjc-arc -O2 \
  -mmacosx-version-min="${MACOSX_DEPLOYMENT_TARGET}" \
  -I"${OCCT_PREFIX}/include/opencascade" \
  -I"${PROJECT_DIR}/StepCADCore/include" \
  -L"${FRAMEWORKS_DIR}" \
  -Wl,-rpath,@loader_path/. \
  -lTKDESTEP -lTKXSBase -lTKMesh -lTKTopAlgo -lTKGeomAlgo \
  -lTKBRep -lTKGeomBase -lTKG3d -lTKG2d -lTKMath \
  -lTKernel -lTKPrim \
  -install_name @rpath/StepCADCore.framework/Versions/A/StepCADCore \
  -framework Foundation -framework CoreGraphics \
  "${PROJECT_DIR}/StepCADCore/src/CADMeshBridge.mm" \
  -o "${FW_VERSIONS}/StepCADCore"

codesign --force --sign - "${FW_DIR}"

# 4. Compilation de l'extension Quick Look (StepViewQL.appex)
echo "[4/6] Compilation de l'extension Quick Look StepViewQL.appex..."
cp "${PROJECT_DIR}/StepViewQL/Resources/Info.plist" "${QL_CONTENTS_DIR}/Info.plist"
/usr/libexec/PlistBuddy -c "Set :LSMinimumSystemVersion ${MACOSX_DEPLOYMENT_TARGET}" "${QL_CONTENTS_DIR}/Info.plist"

swiftc -O -target "${TARGET}" \
  -F "${FRAMEWORKS_DIR}" \
  -I "${FW_DIR}/Headers" \
  -Xlinker -rpath -Xlinker @executable_path/../../../../Frameworks \
  -Xlinker -rpath -Xlinker @loader_path/../../../../Frameworks \
  -framework Foundation -framework AppKit -framework SceneKit -framework QuickLookUI -framework StepCADCore \
  "${PROJECT_DIR}/StepViewQL/src/PreviewViewController.swift" \
  "${PROJECT_DIR}/StepView/src/CADSceneView.swift" \
  "${PROJECT_DIR}/StepView/src/CADGeometryBuilder.swift" \
  "${PROJECT_DIR}/StepViewQL/src/main.swift" \
  -o "${QL_MACOS_DIR}/StepViewQL"

codesign --force --sign - --entitlements "${PROJECT_DIR}/StepViewQL/Resources/StepViewQL.entitlements" "${QL_APPEX_DIR}"

# 5. Compilation de l'application hôte StepView.app
echo "[5/6] Compilation de l'application conteneur StepView.app..."
cp "${PROJECT_DIR}/StepView/Resources/Info.plist" "${CONTENTS_DIR}/Info.plist"
/usr/libexec/PlistBuddy -c "Set :LSMinimumSystemVersion ${MACOSX_DEPLOYMENT_TARGET}" "${CONTENTS_DIR}/Info.plist"
echo -n "APPL????" > "${CONTENTS_DIR}/PkgInfo"
mkdir -p "${CONTENTS_DIR}/Resources"
if [ -f "${PROJECT_DIR}/StepView/Resources/AppIcon.icns" ]; then
    cp "${PROJECT_DIR}/StepView/Resources/AppIcon.icns" "${CONTENTS_DIR}/Resources/AppIcon.icns"
fi

swiftc -O -target "${TARGET}" \
  -F "${FRAMEWORKS_DIR}" \
  -I "${FW_DIR}/Headers" \
  -Xlinker -rpath -Xlinker @executable_path/../Frameworks \
  -Xlinker -rpath -Xlinker @loader_path/../Frameworks \
  -framework Foundation -framework AppKit -framework SceneKit -framework StepCADCore \
  "${PROJECT_DIR}/StepView/src/AppDelegate.swift" \
  "${PROJECT_DIR}/StepView/src/MainWindowController.swift" \
  "${PROJECT_DIR}/StepView/src/CADSceneView.swift" \
  "${PROJECT_DIR}/StepView/src/CADGeometryBuilder.swift" \
  "${PROJECT_DIR}/StepView/src/main.swift" \
  -o "${MACOS_DIR}/StepView"

# 6. Signature de l'ensemble du bundle de l'application
echo "[6/6] Signature finale du bundle d'application..."
codesign --force --sign - --entitlements "${PROJECT_DIR}/StepView/Resources/StepView.entitlements" "${APP_DIR}"

echo ""
echo "=========================================================="
echo "  ✓ Compilation terminée avec succès !"
echo "  Bundle généré : ${APP_DIR}"
echo "=========================================================="
