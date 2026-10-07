# StepView & StepViewQL

Utilitaire macOS moderne et haute performance pour la prévisualisation et la visualisation de modèles CAD au format STEP (`.step`, `.stp`) directement depuis le **Finder** via **Quick Look** (touche Espace) et via une application native dédiée.

---

## Fonctionnalités

* **Prévisualisation Quick Look native (`.appex`)** : Appuyez sur **Espace** sur n'importe quel fichier `.step` ou `.stp` dans le Finder pour afficher instantanément la pièce en 3D interactive.
* **Moteur de Rendu Studio 3D (SceneKit)** :
  * Contrôle orbital à 360°, panoramique (pan) et zoom fluide à la molette / trackpad.
  * Éclairage physique PBR (Physically Based Rendering) type studio de conception (Key, Fill, Rim lights avec ombres douces et plan de sol).
  * Centrage et cadrage automatique sur la boîte englobante (Bounding Box) du modèle.
  * Affichage en temps réel des statistiques (dimensions $L \times l \times H$ en mm, nombre de triangles, nombre de sommets).
* **Application autonome `StepView.app`** :
  * Glisser-déposer de fichiers CAO.
  * Bouton de recadrage de caméra ("Zoom to Fit").
  * Mode filaire (Wireframe) / Mode ombré PBR commutable en un clic.
* **Architecture C++ / Objective-C++ / Swift étanche** :
  * Noyau géométrique propulsé par **Open CASCADE Technology (OCCT)**.
  * Tessellation B-Rep adaptative pour préserver les quotas de mémoire RAM de `quicklookd`.
  * Isolation complète des macros C++ OCCT vis-à-vis du code Swift via un pont `StepCADCore.framework`.
  * Bundle autonome contenant toutes ses dépendances relocalisées en `@rpath`.

---

## Structure du Projet

```
StepView/
├── StepCADCore/               # Framework Objective-C++ / OCCT
│   ├── include/               # En-têtes publics et modulemap
│   │   ├── CADMeshBridge.h
│   │   ├── StepCADCore.h
│   │   └── module.modulemap
│   ├── src/                   # Moteur C++ de tessellation B-Rep
│   │   └── CADMeshBridge.mm
│   └── Resources/
│       └── Info.plist
├── StepView/                  # Application hôte macOS
│   ├── src/                   # Code Swift (AppKit + SceneKit)
│   │   ├── AppDelegate.swift
│   │   ├── MainWindowController.swift
│   │   ├── CADSceneView.swift
│   │   ├── CADGeometryBuilder.swift
│   │   └── main.swift
│   └── Resources/
│       ├── Info.plist
│       └── StepView.entitlements
├── StepViewQL/                # Extension Quick Look Preview (.appex)
│   ├── src/
│   │   ├── PreviewViewController.swift # QLPreviewingController
│   │   └── main.swift
│   └── Resources/
│       ├── Info.plist
│       └── StepViewQL.entitlements
├── sample_models/             # Modèles CAD de test
│   ├── cube.step
│   ├── cylinder.step
│   └── bracket.step
├── scripts/
│   ├── build.sh               # Script de compilation automatisé
│   ├── bundle_dependencies.py # Extraction et relocalisation des dylibs OCCT
│   ├── install.sh             # Déploiement dans /Applications et enregistrement LaunchServices
│   ├── uninstall.sh           # Désinstallation propre
│   └── test_runner.swift      # Suite de tests d'intégration automatisés
└── Makefile                   # Commandes rapides (build, test, install)
```

---

## Commandes Rapides

### 1. Compiler le projet
```bash
make
# ou ./scripts/build.sh
```

### 2. Exécuter la suite de tests automatisés
```bash
make test
```
Vérifie le parsing, la tessellation, la validité des maillages et le cycle de vie du contrôleur Quick Look sur l'ensemble des modèles de test.

### 3. Installer dans macOS
```bash
make install
# ou ./scripts/install.sh
```
Cette commande :
1. Copie `StepView.app` (contenant l'extension `StepViewQL.appex`) dans `/Applications`.
2. Associe les extensions `.step` et `.stp` au système via `lsregister`.
3. Enregistre et active l'extension avec `pluginkit`.
4. Réinitialise le cache du daemon `quicklookd`.

### 4. Désinstaller
```bash
make uninstall
# ou ./scripts/uninstall.sh
```

---

## Utilisation

1. **Dans le Finder** :
   * Naviguez vers un fichier `.step` ou `.stp` (par exemple dans le dossier `sample_models/`).
   * Appuyez sur la touche **Espace**.
   * Utilisez la souris ou le trackpad pour faire tourner la pièce en 3D, zoomer et observer les détails.

2. **Depuis l'application StepView** :
   * Lancez `StepView` depuis le dossier `/Applications` ou Spotlight.
   * Glissez-déposez n'importe quel fichier STEP sur la fenêtre.
   * Utilisez la barre d'outils pour recadrer la vue ou activer le mode filaire.
