#!/usr/bin/env python3
"""
Publie une MàJ BYM sur GitHub (bym-text).

Usage :
  python publish_bym.py --dry-run                  # affiche ce qui serait publié
  python publish_bym.py --notes "corr Ge 1:1"     # génère + pousse
  python publish_bym.py --version 1.0.3 --notes "x"
  python publish_bym.py --no-push                 # génère sans pousser
  python publish_bym.py --full                    # publie les 66 livres

Étapes automatisées (voir PUBLISH_Bym.md) :
  1) md_to_json.py  (bym_md/ -> bym_json/)
  2) generate_manifest.py --apply  (delta -> manifest.json)
  3) Copy bym_json/ + manifest.json vers clone bym-text
  4) git add / commit / push
  5) rappel vérif app (Réglages > MàJ)

Stdlib seule. Windows / PowerShell 5.1 compatible.
"""
import argparse
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")  # type: ignore[attr-defined]
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")  # type: ignore[attr-defined]
except Exception:
    pass

ROOT = Path(__file__).resolve().parents[1]  # bym3/
APPCODEBAR = Path(__file__).parent
BYM_MD = APPCODEBAR / "bym_md"
BYM_JSON_ROOT = ROOT / "bym_json"
BYM_JSON_APPCODEBAR = APPCODEBAR / "bym_json"
ASSETS = ROOT / "bible_app" / "assets" / "bible" / "bym"
DEFAULT_CLONE = Path(os.environ.get("BYM_TEXT_CLONE", str(Path.home() / "bym-text")))
if os.name == "nt" and not DEFAULT_CLONE.exists():
    # fallback temp
    DEFAULT_CLONE = Path(os.environ.get("TEMP", r"C:\Temp")) / "bym-text"


def run(cmd, cwd=None, check=True):
    print(f"  $ {' '.join(str(c) for c in cmd)}")
    r = subprocess.run(cmd, cwd=str(cwd) if cwd else None)
    if check and r.returncode != 0:
        sys.exit(r.returncode)
    return r


def main():
    ap = argparse.ArgumentParser(description="Publie MàJ BYM sur GitHub")
    ap.add_argument("--notes", help="Notes de version pour le manifest")
    ap.add_argument("--version", help="Force la version semver (ex 1.0.2)")
    ap.add_argument("--full", action="store_true", help="Publie les 66 livres")
    ap.add_argument("--dry-run", action="store_true", help="N'écrit ni ne pousse, affiche seulement")
    ap.add_argument("--no-push", action="store_true", help="Génère mais ne pousse pas")
    ap.add_argument("--clone", default=str(DEFAULT_CLONE), help="Chemin du clone bym-text")
    ap.add_argument("--manifest-url", default=None, help="URL manifest distant (pour generate_manifest.py)")
    args = ap.parse_args()

    clone = Path(args.clone)

    print("=== 1/5 md_to_json.py ===")
    cmd = [sys.executable, str(APPCODEBAR / "md_to_json.py"), str(BYM_MD), str(BYM_JSON_ROOT)]
    if args.dry_run:
        print(f"  [dry-run] {' '.join(cmd)}")
    else:
        run(cmd, cwd=ROOT)
        # sync appCodebar/bym_json si exclu du git (copie miroir)
        if BYM_JSON_APPCODEBAR != BYM_JSON_ROOT:
            # on ne copie que si le dossier existe ou pour debug
            pass
        # sync assets embarqués
        if ASSETS.exists():
            print(f"  -> sync {ASSETS}")
            for f in BYM_JSON_ROOT.glob("*.json"):
                shutil.copy2(f, ASSETS / f.name)
        else:
            print(f"  ! assets introuvable : {ASSETS} (skip)")

    print("\n=== 2/5 generate_manifest.py ===")
    gen = [sys.executable, str(APPCODEBAR / "generate_manifest.py")]
    if args.full:
        gen.append("--full")
    if args.version:
        gen += ["--version", args.version]
    if args.notes:
        gen += ["--notes", args.notes]
    if args.manifest_url:
        gen += ["--manifest-url", args.manifest_url]
    if not args.dry_run:
        gen.append("--apply")
    # generate_manifest écrit manifest.json à la racine bym3/ par défaut
    run(gen, cwd=ROOT)

    manifest_src = ROOT / "manifest.json"
    if not manifest_src.exists():
        print(f"\n! manifest.json non trouvé à {manifest_src} (dry-run ou aucun changement)")
        if not args.dry_run:
            print("  -> rien à publier (0 fichier modifié)")
        return

    manifest = json.loads(manifest_src.read_text(encoding="utf-8"))
    print(f"\nManifest : version {manifest.get('version')} | {len(manifest.get('files', []))} fichiers")
    for f in manifest.get("files", [])[:10]:
        print(f"  - {f}")
    if len(manifest.get("files", [])) > 10:
        print(f"  ... +{len(manifest['files'])-10} autres")

    if args.dry_run:
        print("\n[dry-run] arrêt avant copie/push")
        return

    print(f"\n=== 3/5 copie vers clone {clone} ===")
    if not clone.exists():
        print(f"  ! clone introuvable : {clone}")
        print(f"  -> git clone https://github.com/victordiaz1000/bym-text.git {clone}")
        run(["git", "clone", "https://github.com/victordiaz1000/bym-text.git", str(clone)])
    dest_json = clone / "bym_json"
    dest_json.mkdir(parents=True, exist_ok=True)
    shutil.copy2(manifest_src, clone / "manifest.json")
    print(f"  manifest.json -> {clone / 'manifest.json'}")
    for fname in manifest.get("files", []):
        # fname peut être "01-Genese.json" ou "bym_json/01-..."
        short = Path(fname).name
        src = BYM_JSON_ROOT / short
        if not src.exists():
            src = ROOT / fname
        if src.exists():
            shutil.copy2(src, dest_json / short)
            print(f"  {short} -> bym_json/")
        else:
            print(f"  ! source manquante : {src}")

    # Si --full ou manifest liste tout, s'assurer que les 66 sont présents
    if args.full or len(manifest.get("files", [])) == 66:
        for f in BYM_JSON_ROOT.glob("*.json"):
            if not (dest_json / f.name).exists():
                shutil.copy2(f, dest_json / f.name)

    print("\n=== 4/5 git push ===")
    if args.no_push:
        print("  --no-push : skip git push")
        print(f"  Vérifie puis pousse manuellement : cd {clone} && git add . && git commit -m \"BYM {manifest.get('version')}\" && git push")
    else:
        run(["git", "add", "manifest.json", "bym_json/"], cwd=clone)
        # check s'il y a quelque chose à committer
        r = subprocess.run(["git", "diff", "--cached", "--quiet"], cwd=str(clone))
        if r.returncode == 0:
            print("  (rien à committer)")
        else:
            run(["git", "commit", "-m", f"BYM {manifest.get('version')} - {manifest.get('notes','')}".strip()], cwd=clone)
            run(["git", "push"], cwd=clone)
            print("  -> poussé sur origin main")

    print("\n=== 5/5 vérif app ===")
    print(f"  1) Attends ~5 min (cache jsDelivr) puis ouvre :")
    print(f"     https://cdn.jsdelivr.net/gh/victordiaz1000/bym-text@main/manifest.json")
    print(f"  2) App > Réglages > MISE À JOUR DU TEXTE > Vérifier")
    print(f"  3) Mettre à jour -> doit afficher {manifest.get('version')}")
    print(f"  4) Rollback : Revenir au texte embarqué (BymUpdateStore.clear)")

    # optionnel : flutter checks
    if (ROOT / "bible_app" / "pubspec.yaml").exists() and not args.no_push:
        print("\n  (optionnel) flutter analyze / test dans bible_app/")

if __name__ == "__main__":
    main()
