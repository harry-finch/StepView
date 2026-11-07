#!/usr/bin/env python3
import os
import sys
import shutil
import subprocess
import re

def brew_prefix(formula=None):
    cmd = ["brew", "--prefix"] + ([formula] if formula else [])
    return subprocess.run(cmd, capture_output=True, text=True, check=True).stdout.strip()

def bundle_dependencies(target_dir, occt_prefix):
    os.makedirs(target_dir, exist_ok=True)
    # Préfixe Homebrew (/opt/homebrew sur Apple Silicon, /usr/local sur Intel)
    hb_prefix = brew_prefix().rstrip("/") + "/"
    occt_lib = os.path.join(occt_prefix, "lib")

    seeds = [
        occt_lib + "/libTKDESTEP.dylib",
        occt_lib + "/libTKXSBase.dylib",
        occt_lib + "/libTKMesh.dylib",
        occt_lib + "/libTKTopAlgo.dylib",
        occt_lib + "/libTKGeomAlgo.dylib",
        occt_lib + "/libTKBRep.dylib",
        occt_lib + "/libTKGeomBase.dylib",
        occt_lib + "/libTKG3d.dylib",
        occt_lib + "/libTKG2d.dylib",
        occt_lib + "/libTKMath.dylib",
        occt_lib + "/libTKernel.dylib",
        occt_lib + "/libTKPrim.dylib",
    ]

    queue = [os.path.realpath(p) for p in seeds]
    all_needed = set()

    while queue:
        curr = queue.pop(0)
        if curr in all_needed:
            continue
        all_needed.add(curr)
        res = subprocess.run(["otool", "-L", curr], capture_output=True, text=True)
        for line in res.stdout.splitlines()[1:]:
            line = line.strip()
            dep = line.split(" (compatibility")[0].strip()
            if dep.startswith("@rpath/"):
                dep_name = dep.replace("@rpath/", "")
                candidate = os.path.realpath(os.path.join(occt_lib, dep_name))
                if os.path.exists(candidate) and candidate not in all_needed:
                    queue.append(candidate)
            elif dep.startswith(hb_prefix):
                candidate = os.path.realpath(dep)
                if os.path.exists(candidate) and candidate not in all_needed:
                    queue.append(candidate)

    print(f"[1/4] Copie de {len(all_needed)} dylibs OCCT et dépendances vers {target_dir}...")
    copied = {}
    for p in all_needed:
        base = os.path.basename(p)
        target = os.path.join(target_dir, base)
        shutil.copy2(p, target)
        os.chmod(target, 0o755)
        copied[p] = base

    print("[2/4] Création des liens symboliques de compatibilité...")
    # Pour tout libX.A.B.C.dylib : créer libX.A.B.dylib et libX.dylib
    for f in os.listdir(target_dir):
        m = re.fullmatch(r"(lib.+?)\.(\d+)\.(\d+)\.(\d+)\.dylib", f)
        if not m or os.path.islink(os.path.join(target_dir, f)):
            continue
        name, a, b, _ = m.groups()
        for sym in [f"{name}.{a}.{b}.dylib", f"{name}.dylib"]:
            target_sym = os.path.join(target_dir, sym)
            if not os.path.lexists(target_sym):
                os.symlink(f, target_sym)

    print("[3/4] Réécriture des chemins LC_ID_DYLIB et dépendances @rpath...")
    for p, base in copied.items():
        target = os.path.join(target_dir, base)
        subprocess.run(["install_name_tool", "-id", f"@rpath/{base}", target], check=True, stderr=subprocess.DEVNULL)

    for p, base in copied.items():
        target = os.path.join(target_dir, base)
        res = subprocess.run(["otool", "-L", target], capture_output=True, text=True)
        for line in res.stdout.splitlines()[1:]:
            dep = line.strip().split(" (compatibility")[0].strip()
            if dep.startswith(hb_prefix):
                dep_real = os.path.realpath(dep)
                if dep_real in copied:
                    new_dep = f"@rpath/{copied[dep_real]}"
                    subprocess.run(["install_name_tool", "-change", dep, new_dep, target], check=True, stderr=subprocess.DEVNULL)
            elif dep.startswith("@rpath/"):
                dep_name = dep.replace("@rpath/", "")
                for orig, c_base in copied.items():
                    if c_base == dep_name or os.path.basename(orig) == dep_name:
                        subprocess.run(["install_name_tool", "-change", dep, f"@rpath/{c_base}", target], check=True, stderr=subprocess.DEVNULL)

    print("[4/4] Signature ad-hoc de toutes les dylibs...")
    for root, _, fnames in os.walk(target_dir):
        for fname in fnames:
            if fname.endswith(".dylib"):
                target = os.path.join(root, fname)
                if not os.path.islink(target):
                    subprocess.run(["codesign", "--force", "--sign", "-", target], check=True, stderr=subprocess.DEVNULL)

    print(f"✓ {len(copied)} bibliothèques prêtes et autonomes dans {target_dir}")

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: bundle_dependencies.py <target_frameworks_dir> [occt_prefix]")
        sys.exit(1)
    # Préfixe OCCT : 2e argument, sinon variable OCCT_PREFIX, sinon brew --prefix opencascade
    prefix = (sys.argv[2] if len(sys.argv) > 2 else os.environ.get("OCCT_PREFIX")) or brew_prefix("opencascade")
    bundle_dependencies(sys.argv[1], prefix)
