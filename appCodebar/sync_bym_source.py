"""Synchronise le corpus BYM avec le dépôt GitLab officiel.

Usage :
    python sync_bym_source.py --dry-run     # ce qui serait fait, sans rien écrire
    python sync_bym_source.py               # applique
    python sync_bym_source.py --all         # retélécharge les 66 livres

C'est la **seule** commande du flux de mise à jour du texte. Elle :

1. demande à GitLab le dernier commit de `master`, puis l'arbre de ce commit ;
2. compare l'`id` de chaque blob à l'empreinte git des `.md` locaux ;
3. télécharge les `.md` qui diffèrent, épinglés au sha du commit, et **vérifie
   l'empreinte** de chaque fichier reçu avant de l'écrire ;
4. reconvertit ces livres avec `md_to_json.py` et remplace les JSON embarqués
   dans `bible_app/assets/bible/bym/` ;
5. écrit `bible_app/assets/bible/bym/_source.json` — commit, date, et les 66
   empreintes.

`_source.json` est la référence que l'application compare à l'arbre distant pour
savoir s'il y a du neuf (`lib/data/bym_update_service.dart`). Il doit donc être
committé avec les JSON qu'il décrit : les séparer ferait proposer aux lecteurs
une mise à jour qu'ils ont déjà, ou masquerait une correction réelle.

Le contrôle d'empreinte est le même que celui du client Dart (`gitBlobId`) : les
deux implémentations se vérifient l'une l'autre. Aucune dépendance externe.
"""

import argparse
import hashlib
import json
import sys
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

import md_to_json

PROJECT_API = "https://gitlab.com/api/v4/projects/anjc%2Fbjc-source"
BRANCH = "master"
RAW_TEMPLATE = "https://gitlab.com/anjc/bjc-source/-/raw/{commit}/{file}"

TIMEOUT = 30
USER_AGENT = "bym-sync/1.0 (+bibledeyehoshouahamashiah.org)"

ROOT = Path(__file__).resolve().parent
MD_DIR = ROOT / "bym_md"
ASSETS_DIR = ROOT.parent / "bible_app" / "assets" / "bible" / "bym"
SOURCE_FILE = ASSETS_DIR / "_source.json"


def git_blob_id(data: bytes) -> str:
    """Empreinte git d'un contenu : sha1("blob <taille>\\0" + octets).

    C'est exactement l'`id` que GitLab publie dans l'arbre du dépôt, donc aucune
    normalisation de fin de ligne : les octets comptent tels quels.
    """
    return hashlib.sha1(b"blob %d\x00" % len(data) + data).hexdigest()


def fetch(url: str) -> bytes:
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(request, timeout=TIMEOUT) as response:
        return response.read()


def fetch_json(url: str):
    return json.loads(fetch(url).decode("utf-8"))


def head_commit() -> tuple[str, str, str]:
    """(sha, date ISO, titre) du dernier commit de la branche suivie."""
    commits = fetch_json(
        f"{PROJECT_API}/repository/commits?ref_name={BRANCH}&per_page=1"
    )
    if not commits:
        sys.exit(f"Aucun commit sur {BRANCH} — dépôt vide ou inaccessible.")
    commit = commits[0]
    sha = commit["id"]
    if len(sha) != 40 or not all(c in "0123456789abcdef" for c in sha):
        sys.exit(f"Sha de commit inattendu : {sha!r}")
    date = commit.get("committed_date") or commit.get("created_at")
    if not date:
        sys.exit("Commit sans date — impossible de dater le texte.")
    return sha, date, (commit.get("title") or "").strip()


def remote_tree(sha: str) -> dict[str, str]:
    """`01-Genese.md` → empreinte de blob, pour le commit [sha]."""
    entries = fetch_json(f"{PROJECT_API}/repository/tree?ref={sha}&per_page=100")
    tree = {}
    for entry in entries:
        if entry.get("type") != "blob":
            continue
        name = entry.get("name", "")
        if not name.endswith(".md"):
            continue
        tree[name] = entry["id"]
    if not tree:
        sys.exit("Arbre sans fichier .md — le dépôt a été réorganisé.")
    return tree


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Synchronise bym_md/ et les JSON embarqués avec GitLab."
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="affiche ce qui serait téléchargé, sans rien écrire",
    )
    parser.add_argument(
        "--all",
        action="store_true",
        help="retélécharge et reconvertit les 66 livres",
    )
    args = parser.parse_args()

    local_files = sorted(MD_DIR.glob("*.md"))
    if not local_files:
        sys.exit(f"Aucun .md dans {MD_DIR}")
    local = {path.name: git_blob_id(path.read_bytes()) for path in local_files}

    try:
        sha, date, title = head_commit()
        tree = remote_tree(sha)
    except urllib.error.URLError as error:
        sys.exit(f"GitLab injoignable : {error}")

    print(f"Commit amont : {sha[:10]} du {date}")
    if title:
        print(f"              « {title} »")

    missing = sorted(set(local) - set(tree))
    added = sorted(set(tree) - set(local))
    for name in missing:
        print(f"  ! {name} absent de l'arbre amont — conservé tel quel")
    for name in added:
        print(f"  ! {name} nouveau en amont — non embarqué (catalogue à revoir)")

    shared = sorted(set(local) & set(tree))
    changed = [name for name in shared if args.all or local[name] != tree[name]]

    if not changed:
        print(f"\n{len(shared)} livres déjà à jour.")
        if not args.dry_run:
            write_source(sha, date, {name: tree[name] for name in shared}, local)
        return

    print(f"\n{len(changed)} livre(s) à mettre à jour :")
    for name in changed:
        print(f"  - {name}  {local[name][:8]} -> {tree[name][:8]}")

    if args.dry_run:
        print("\n--dry-run : rien n'a été écrit.")
        return

    ASSETS_DIR.mkdir(parents=True, exist_ok=True)
    total_verses = 0
    for name in changed:
        url = RAW_TEMPLATE.format(commit=sha, file=urllib.parse.quote(name))
        data = fetch(url)
        received = git_blob_id(data)
        if received != tree[name]:
            # Un seul refus annule tout : mieux vaut un corpus cohérent en
            # retard qu'un corpus panaché dont `_source.json` mentirait.
            sys.exit(
                f"{name} : empreinte reçue {received[:8]} au lieu de "
                f"{tree[name][:8]} — rien de plus n'est écrit."
            )
        (MD_DIR / name).write_bytes(data)

        book = md_to_json.parse_book(MD_DIR / name)
        verses = sum(len(c["verses"]) for c in book["chapters"])
        total_verses += verses
        # newline="\n" comme md_to_json.py : le convertisseur Dart écrit en LF et
        # le test doré compare octet pour octet.
        (ASSETS_DIR / f"{Path(name).stem}.json").write_text(
            json.dumps(book, ensure_ascii=False, indent=2),
            encoding="utf-8",
            newline="\n",
        )
        print(f"  + {name:30} {len(book['chapters']):3} chapitres, {verses:5} versets")

    write_source(sha, date, {name: tree[name] for name in shared}, local)
    print(f"\n{len(changed)} livre(s) réécrit(s), {total_verses} versets convertis.")
    print("Régénérer entièrement les JSON : python md_to_json.py "
          f"bym_md {ASSETS_DIR}")


def write_source(
    sha: str, date: str, blobs: dict[str, str], local: dict[str, str]
) -> None:
    """Écrit `_source.json` : commit, date, et l'empreinte des 66 `.md`.

    Les livres restés locaux (absents de l'arbre amont) gardent leur empreinte
    locale : sans cela, l'application les reproposerait à chaque vérification.
    """
    merged = dict(local)
    merged.update(blobs)
    SOURCE_FILE.write_text(
        json.dumps(
            {
                "commit": sha,
                "committedAt": date,
                "blobs": dict(sorted(merged.items())),
            },
            ensure_ascii=False,
            indent=2,
        ),
        encoding="utf-8",
        newline="\n",
    )
    print(f"{SOURCE_FILE.name} écrit : {len(merged)} empreintes, commit {sha[:10]}")


if __name__ == "__main__":
    main()
