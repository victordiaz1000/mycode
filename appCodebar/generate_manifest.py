#!/usr/bin/env python3
"""
Génère le manifest.json pour les MàJ BYM GitHub.

Usage:
  python generate_manifest.py              # dry-run : affiche le diff
  python generate_manifest.py --apply      # écrit manifest.json
  python generate_manifest.py --full       # liste les 66 fichiers (au lieu du diff)
  python generate_manifest.py --version 1.0.2 --notes "Corrections"

- Compare bym_json/ local (sortie de md_to_json.py) avec le manifest distant
  (https://raw.githubusercontent.com/victordiaz1000/bym-text/main/manifest.json).
- Si aucun manifest distant (404) -> considère 0 fichier.
- Calcule le SHA256 de chaque JSON et liste les fichiers modifiés.
- Propose un bump semver : patch++ si ≤3 fichiers, minor++ sinon.
- Écrit manifest.json avec {version, updatedAt, notes, files}.

Stdlib seule, comme md_to_json.py.
"""
import argparse
import datetime
import hashlib
import json
import os
import sys
import urllib.request
import urllib.error

# Windows cp1252 -> force utf-8 pour les accents
try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")
except Exception:
    pass

DEFAULT_MANIFEST_URL = "https://cdn.jsdelivr.net/gh/victordiaz1000/bym-text@main/manifest.json"
REPO_FILES_URL = "https://cdn.jsdelivr.net/gh/victordiaz1000/bym-text@main/bym_json/{file}"

def sha256_file(path):
    # Normalise CRLF -> LF pour eviter les faux diffs Windows (core.autocrlf)
    h = hashlib.sha256()
    with open(path, "rb") as f:
        data = f.read()
        data = data.replace(b"\r\n", b"\n")
        h.update(data)
    return h.hexdigest()

def fetch_json(url):
    try:
        with urllib.request.urlopen(url, timeout=12) as r:
            if r.status != 200:
                return None
            return json.loads(r.read().decode("utf-8"))
    except Exception:
        return None

def fetch_hashes_from_manifest(manifest, base_url):
    """Tente de récupérer les hashes distants en téléchargeant chaque fichier listé.
    Si manifest.files est vide ou absent, on considère qu'on ne peut pas comparer
    par hash et on télécharge tout (retourne dict vide -> diff = tous les fichiers locaux).
    """
    files = manifest.get("files") if manifest else None
    # Si le manifest distant n'a pas de liste, on ne peut pas comparer finement.
    # On retourne None pour signaler "full".
    if not files:
        return None
    # Dérive la base depuis l'URL du manifest : .../manifest.json -> .../
    base = base_url.rsplit('/', 1)[0] + '/' if '/' in base_url else REPO_FILES_URL.rsplit('/', 2)[0] + '/'
    hashes = {}
    for fname in files:
        # Le manifest peut contenir "bym_json/01-..." ou juste "01-..."
        # On normalise
        short = os.path.basename(fname)
        if '/' in fname:
            url = base + fname
        else:
            url = base + 'bym_json/' + urllib.request.pathname2url(short)
        try:
            with urllib.request.urlopen(url, timeout=12) as r:
                if r.status == 200:
                    h = hashlib.sha256()
                    data = r.read().replace(b"\r\n", b"\n")
                    h.update(data)
                    hashes[short] = h.hexdigest()
        except Exception:
            continue
    return hashes

def bump_version(prev, changed_count):
    try:
        parts = [int(x) for x in prev.split(".")]
        while len(parts) < 3:
            parts.append(0)
        if changed_count > 3:
            parts[1] += 1
            parts[2] = 0
        else:
            parts[2] += 1
        return ".".join(str(x) for x in parts[:3])
    except Exception:
        return "1.0.1"

def main():
    ap = argparse.ArgumentParser(description="Génère manifest.json BYM")
    ap.add_argument("--apply", action="store_true", help="Écrit manifest.json")
    ap.add_argument("--full", action="store_true", help="Liste les 66 fichiers au lieu du diff")
    ap.add_argument("--version", help="Force la version (ex. 1.0.2)")
    ap.add_argument("--notes", help="Notes de version")
    ap.add_argument("--manifest-url", default=DEFAULT_MANIFEST_URL, help="URL du manifest distant")
    ap.add_argument("--bym-json", default="bym_json", help="Dossier bym_json local")
    ap.add_argument("--out", default="manifest.json", help="Fichier de sortie")
    args = ap.parse_args()

    bym_dir = args.bym_json
    if not os.path.isdir(bym_dir):
        # Essaie ../bym_json et ./appCodebar/bym_json
        for alt in ["../bym_json", "bym_json", "appCodebar/bym_json"]:
            if os.path.isdir(alt):
                bym_dir = alt
                break
    if not os.path.isdir(bym_dir):
        print(f"ERREUR: dossier {bym_dir} introuvable. Lance d'abord md_to_json.py", file=sys.stderr)
        sys.exit(1)

    local_files = sorted([f for f in os.listdir(bym_dir) if f.endswith(".json")])
    if len(local_files) != 66:
        print(f"ATTENTION: {len(local_files)} fichiers dans {bym_dir} (attendu 66)")

    # Hashes locaux
    local_hashes = {}
    for fname in local_files:
        local_hashes[fname] = sha256_file(os.path.join(bym_dir, fname))

    # Manifest distant
    print(f"-> Recuperation du manifest distant : {args.manifest_url}")
    prev_manifest = fetch_json(args.manifest_url)
    if prev_manifest:
        print(f"  trouvé version {prev_manifest.get('version')} ({len(prev_manifest.get('files', []))} fichiers listés)")
        prev_version = prev_manifest.get("version", "1.0.0")
        # Si le manifest distant a une liste, on fetch ses hashes pour comparer finement.
        # Sinon, on considère que tout est à mettre à jour (diff = tous).
        remote_hashes = None
        if not args.full and prev_manifest.get("files"):
            print("  -> calcul des hashes distants (peut prendre 10s)...")
            remote_hashes = fetch_hashes_from_manifest(prev_manifest, args.manifest_url)
        else:
            remote_hashes = None
    else:
        print("  aucun manifest distant (404) -> première publication")
        prev_manifest = {"version": "1.0.0", "files": []}
        prev_version = "1.0.0"
        remote_hashes = None

    # Calcul du diff
    if args.full:
        changed = local_files
        print(f"Mode --full : {len(changed)} fichiers")
    elif remote_hashes is None:
        # Pas de comparaison fine possible -> on considère tout comme changé
        # Mais on évite de lister 66 fichiers si l'utilisateur veut juste bump : on liste quand même tout
        # pour que le client ne retélécharge que le nécessaire s'il a déjà une version.
        # Alternative : laisser files=[] et le client retéléchargera tout (BymUpdateService le gère).
        # Ici on liste tout pour être explicite.
        changed = local_files
        print(f"Comparaison fine impossible (manifest distant sans liste) -> {len(changed)} fichiers considérés comme modifiés")
        print("Astuce : laisse files=[] dans le manifest et le client retéléchargera tout (9 Mo) - c'est ok pour une BYM.")
    else:
        changed = [f for f in local_files if local_hashes.get(f) != remote_hashes.get(f)]
        print(f"Diff : {len(changed)} fichier(s) modifié(s)")
        for f in changed:
            print(f"  - {f}")

    if not changed:
        print("\nAucun changement détecté -> rien à publier.")
        sys.exit(0)

    next_version = args.version or bump_version(prev_version, len(changed))
    notes = args.notes
    if not notes:
        # Notes auto : liste des 3 premiers + git log
        preview = ", ".join(changed[:3])
        if len(changed) > 3:
            preview += f" +{len(changed)-3} autres"
        notes = f"{len(changed)} livre(s) : {preview}"
        # Essaie d'ajouter le dernier message de commit sur bym_md
        try:
            import subprocess
            msg = subprocess.check_output(["git", "log", "--oneline", "-1", "--", "bym_md"], text=True, stderr=subprocess.DEVNULL).strip()
            if msg:
                notes += f" - {msg}"
        except Exception:
            pass

    manifest = {
        "version": next_version,
        "updatedAt": datetime.datetime.now(datetime.timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z"),
        "notes": notes,
        "files": changed if not args.full else local_files,
    }

    print("\nManifest proposé :")
    print(json.dumps(manifest, indent=2, ensure_ascii=False))

    if not args.apply:
        print("\n-> Dry-run. Relance avec --apply pour écrire manifest.json")
        return

    with open(args.out, "w", encoding="utf-8") as f:
        json.dump(manifest, f, indent=2, ensure_ascii=False)
        f.write("\n")
    print(f"\nOK Écrit {args.out}")

    # Conseil pour la publication
    print("\nPour publier :")
    print(f"  cp {args.out} /chemin/vers/bym-text/manifest.json")
    print(f"  cp {bym_dir}/*.json /chemin/vers/bym-text/bym_json/")
    print("  cd /chemin/vers/bym-text && git add . && git commit -m \"BYM {}\" && git push".format(next_version))

if __name__ == "__main__":
    main()
