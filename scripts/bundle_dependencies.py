#!/usr/bin/env python3
import os
import sys
import shutil
import subprocess
import glob

def bundle_dependencies(target_dir):
    os.makedirs(target_dir, exist_ok=True)

    seeds = [
        "/opt/homebrew/opt/opencascade/lib/libTKDESTEP.dylib",
        "/opt/homebrew/opt/opencascade/lib/libTKXSBase.dylib",
        "/opt/homebrew/opt/opencascade/lib/libTKMesh.dylib",
        "/opt/homebrew/opt/opencascade/lib/libTKTopAlgo.dylib",
        "/opt/homebrew/opt/opencascade/lib/libTKGeomAlgo.dylib",
        "/opt/homebrew/opt/opencascade/lib/libTKBRep.dylib",
        "/opt/homebrew/opt/opencascade/lib/libTKGeomBase.dylib",
        "/opt/homebrew/opt/opencascade/lib/libTKG3d.dylib",
        "/opt/homebrew/opt/opencascade/lib/libTKG2d.dylib",
        "/opt/homebrew/opt/opencascade/lib/libTKMath.dylib",
        "/opt/homebrew/opt/opencascade/lib/libTKernel.dylib",
        "/opt/homebrew/opt/opencascade/lib/libTKPrim.dylib",
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
                candidate = os.path.realpath(f"/opt/homebrew/opt/opencascade/lib/{dep_name}")
                if os.path.exists(candidate) and candidate not in all_needed:
                    queue.append(candidate)
            elif dep.startswith("/opt/homebrew/"):
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
    files = glob.glob(os.path.join(target_dir, "*.7.9.3.dylib"))
    for f in files:
        base = os.path.basename(f)
        dirn = os.path.dirname(f)
        v79 = base.replace(".7.9.3.dylib", ".7.9.dylib")
        v = base.replace(".7.9.3.dylib", ".dylib")
        for sym in [v79, v]:
            target_sym = os.path.join(dirn, sym)
            if not os.path.exists(target_sym):
                os.symlink(base, target_sym)

    print("[3/4] Réécriture des chemins LC_ID_DYLIB et dépendances @rpath...")
    for p, base in copied.items():
        target = os.path.join(target_dir, base)
        subprocess.run(["install_name_tool", "-id", f"@rpath/{base}", target], check=True, stderr=subprocess.DEVNULL)

    for p, base in copied.items():
        target = os.path.join(target_dir, base)
        res = subprocess.run(["otool", "-L", target], capture_output=True, text=True)
        for line in res.stdout.splitlines()[1:]:
            dep = line.strip().split(" (compatibility")[0].strip()
            if dep.startswith("/opt/homebrew/"):
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
        print("Usage: bundle_dependencies.py <target_frameworks_dir>")
        sys.exit(1)
    bundle_dependencies(sys.argv[1])
