from __future__ import annotations

import argparse
import hashlib
import json
import re
import subprocess
import zipfile
from pathlib import Path, PurePosixPath
from typing import Iterable


FORBIDDEN_SUFFIXES = {
    ".exe", ".dll", ".mpq", ".pdb", ".ilk", ".lib", ".obj", ".db", ".sqlite",
}
FORBIDDEN_FILENAMES = {
    ".env", "authserver.conf", "worldserver.conf", "realmlist.wtf",
}
LOCAL_WINDOWS_PATH = re.compile(rb"(?i)(?:^|[\s'\"(])(?:[a-z]:[\\/])")
ASSIGNED_SECRET = re.compile(
    rb"(?i)(?:password|passwd|database[_-]?(?:user|password))\s*[=:]\s*['\"]?[^$<{\s][^\r\n]*"
)
SQL_MIGRATION_PATTERN = re.compile(
    r"^(?P<version>\d{4}_\d{2}_\d{2}_\d{2})_solo_collections_schema_v(?P<schema>\d+)\.sql$"
)


class ReleaseError(RuntimeError):
    pass


def run_git(repo: Path, *args: str, binary: bool = False) -> bytes | str:
    result = subprocess.run(
        ["git", "-C", str(repo), *args],
        check=False,
        capture_output=True,
        text=not binary,
    )
    if result.returncode:
        stderr = result.stderr.decode("utf-8", errors="replace") if binary else result.stderr
        raise ReleaseError(f"git {' '.join(args)} failed in {repo}: {stderr.strip()}")
    return result.stdout


def commit_id(repo: Path) -> str:
    return str(run_git(repo, "rev-parse", "HEAD")).strip()


def require_clean_tracked(repo: Path) -> None:
    status = str(run_git(repo, "status", "--porcelain", "--untracked-files=no")).strip()
    if status:
        raise ReleaseError(f"tracked working tree changes must be committed before release: {repo}")


def commit_paths(repo: Path, commit: str) -> list[str]:
    output = run_git(repo, "ls-tree", "-r", "--name-only", "-z", commit, binary=True)
    assert isinstance(output, bytes)
    return [value.decode("utf-8") for value in output.split(b"\0") if value]


def commit_file(repo: Path, commit: str, relative: str) -> bytes:
    output = run_git(repo, "show", f"{commit}:{relative}", binary=True)
    assert isinstance(output, bytes)
    return output


def assert_safe_entries(entries: Iterable[tuple[str, bytes]]) -> None:
    for name, payload in entries:
        path = PurePosixPath(name)
        lowered = path.name.lower()
        if path.is_absolute() or ".." in path.parts:
            raise ReleaseError(f"unsafe archive path: {name}")
        if path.suffix.lower() in FORBIDDEN_SUFFIXES or lowered in FORBIDDEN_FILENAMES:
            raise ReleaseError(f"forbidden release file: {name}")
        if LOCAL_WINDOWS_PATH.search(payload):
            raise ReleaseError(f"local Windows path leaked into release text: {name}")
        if ASSIGNED_SECRET.search(payload):
            raise ReleaseError(f"credential-like value leaked into release text: {name}")


def write_zip(target: Path, entries: dict[str, bytes]) -> None:
    assert_safe_entries(entries.items())
    with zipfile.ZipFile(target, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
        for name in sorted(entries):
            info = zipfile.ZipInfo(name, date_time=(1980, 1, 1, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o100644 << 16
            archive.writestr(info, entries[name])


def addon_entries(repo: Path, commit: str) -> dict[str, bytes]:
    prefix = "addon/SoloCollections/"
    entries = {
        f"SoloCollections/{path.removeprefix(prefix)}": commit_file(repo, commit, path)
        for path in commit_paths(repo, commit)
        if path.startswith(prefix) and not path.startswith(prefix + "Media/Retail/")
    }
    entries["SoloCollections/LICENSE"] = commit_file(repo, commit, "LICENSE")
    entries["SoloCollections/THIRD_PARTY_NOTICES.md"] = commit_file(
        repo, commit, "THIRD_PARTY_NOTICES.md"
    )
    return entries


def module_entries(repo: Path, commit: str) -> dict[str, bytes]:
    allowed_prefixes = ("conf/", "data/", "src/", "tests/")
    allowed_files = {
        ".editorconfig", ".gitattributes", "include.sh", "LICENSE", "README.md",
        "THIRD_PARTY_NOTICES.md",
    }
    entries: dict[str, bytes] = {}
    for path in commit_paths(repo, commit):
        if path in allowed_files or path.startswith(allowed_prefixes):
            entries[f"mod-solo-collections/{path}"] = commit_file(repo, commit, path)
    return entries


def compose_manifest(
    version: str,
    addon_commit: str,
    module_commit: str,
    core_commit: str,
    catalog: dict,
    protocol: dict,
    sql_schema_version: int,
    sql_migration_version: str,
) -> dict:
    by_key = {entry["typeKey"]: entry for entry in catalog["collectionTypes"]}
    mappings = [
        {
            "typeId": int(by_key[key]["typeId"]),
            "typeKey": key,
            "sha256": digest,
        }
        for key, digest in catalog["typeMappingHashes"].items()
    ]
    mappings.sort(key=lambda entry: entry["typeId"])
    return {
        "releaseSchemaVersion": 1,
        "version": version,
        "commits": {
            "addon": addon_commit,
            "module": module_commit,
            "azerothcore": core_commit,
        },
        "protocol": {"name": "SC2", "version": int(protocol["protocolVersion"])},
        "catalog": {
            "schemaVersion": int(catalog["schemaVersion"]),
            "metadataVersion": catalog["metadataVersion"],
            "mappingHash": catalog["mappingHash"],
            "perCategoryMappingHashes": mappings,
        },
        "assetPackVersion": catalog["assetPackVersion"],
        "sql": {
            "schemaVersion": sql_schema_version,
            "migrationVersion": sql_migration_version,
            "newInstall": "mod-solo-collections/data/sql/db-characters/solo_collections_schema_v1.sql",
            "appendOnlyMigration": (
                "mod-solo-collections/data/sql/updates/char/"
                f"{sql_migration_version}_solo_collections_schema_v{sql_schema_version}.sql"
            ),
        },
        "distribution": {
            "clientResourcesBundled": False,
            "excluded": ["game assets", "client EXE/DLL", "database credentials", "local paths"],
        },
    }


def parse_sql_versions(module_repo: Path, commit: str) -> tuple[int, str]:
    header = commit_file(module_repo, commit, "src/SoloCollectionsAccountStore.h").decode("utf-8")
    match = re.search(r"AccountStoreSchemaVersion\s*=\s*(\d+)", header)
    if not match:
        raise ReleaseError("AccountStoreSchemaVersion was not found")
    schema_version = int(match.group(1))
    migrations: list[tuple[str, int]] = []
    prefix = "data/sql/updates/char/"
    for path in commit_paths(module_repo, commit):
        if not path.startswith(prefix):
            continue
        migration = SQL_MIGRATION_PATTERN.match(PurePosixPath(path).name)
        if migration:
            migrations.append((migration.group("version"), int(migration.group("schema"))))
    candidates = sorted(version for version, schema in migrations if schema == schema_version)
    if not candidates:
        raise ReleaseError(f"no append-only SQL migration found for schema v{schema_version}")
    return schema_version, candidates[-1]


def write_text(target: Path, value: str) -> None:
    target.write_text(value, encoding="utf-8", newline="\n")


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def build(args: argparse.Namespace) -> Path:
    addon_repo = args.addon_repo.resolve()
    module_repo = args.module_repo.resolve()
    core_repo = args.core_repo.resolve()
    output = args.output_dir.resolve()
    if output.exists():
        raise ReleaseError(f"refusing to overwrite existing output: {output}")
    for repo in (addon_repo, module_repo, core_repo):
        if not (repo / ".git").exists():
            raise ReleaseError(f"not a Git checkout: {repo}")
        require_clean_tracked(repo)

    addon_commit = commit_id(addon_repo)
    module_commit = commit_id(module_repo)
    core_commit = commit_id(core_repo)
    catalog = json.loads(commit_file(
        addon_repo, addon_commit, "catalog/generated/catalog-manifest.json"
    ).decode("utf-8"))
    protocol = json.loads(commit_file(
        addon_repo, addon_commit, "protocol/sc2/schema.json"
    ).decode("utf-8"))
    sql_schema, sql_migration = parse_sql_versions(module_repo, module_commit)
    manifest = compose_manifest(
        args.version, addon_commit, module_commit, core_commit, catalog, protocol,
        sql_schema, sql_migration,
    )

    output.mkdir(parents=True)
    addon_zip = output / f"SoloCollections-{args.version}-addon.zip"
    module_zip = output / f"mod-solo-collections-{args.version}-source.zip"
    write_zip(addon_zip, addon_entries(addon_repo, addon_commit))
    write_zip(module_zip, module_entries(module_repo, module_commit))

    manifest_path = output / "release-manifest.json"
    write_text(manifest_path, json.dumps(manifest, ensure_ascii=False, indent=2) + "\n")
    release_files = {
        "INSTALLATION.zh-CN.md": commit_file(
            addon_repo, addon_commit, "docs/UNIFIED_BACKEND_INSTALLATION.zh-CN.md"
        ),
        "LICENSES/SoloCollections-GPL-3.0-or-later.txt": commit_file(
            addon_repo, addon_commit, "LICENSE"
        ),
        "LICENSES/SoloCollections-THIRD_PARTY_NOTICES.md": commit_file(
            addon_repo, addon_commit, "THIRD_PARTY_NOTICES.md"
        ),
        "LICENSES/mod-solo-collections-AGPL-3.0.txt": commit_file(module_repo, module_commit, "LICENSE"),
        "LICENSES/mod-solo-collections-THIRD_PARTY_NOTICES.md": commit_file(
            module_repo, module_commit, "THIRD_PARTY_NOTICES.md"
        ),
    }
    assert_safe_entries(release_files.items())
    for relative, payload in release_files.items():
        target = output / Path(relative)
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(payload)

    checksummed = sorted(path for path in output.rglob("*") if path.is_file())
    checksum_lines = [f"{sha256(path)}  {path.relative_to(output).as_posix()}" for path in checksummed]
    write_text(output / "SHA256SUMS.txt", "\n".join(checksum_lines) + "\n")
    return output


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Build an audited SoloCollections unified-backend release.")
    parser.add_argument("--version", required=True, type=str)
    parser.add_argument("--addon-repo", type=Path, default=Path.cwd())
    parser.add_argument("--module-repo", required=True, type=Path)
    parser.add_argument("--core-repo", required=True, type=Path)
    parser.add_argument("--output-dir", required=True, type=Path)
    args = parser.parse_args()
    if not re.fullmatch(r"[0-9A-Za-z][0-9A-Za-z._-]*", args.version):
        parser.error("--version must contain only letters, digits, dot, underscore, or hyphen")
    return args


if __name__ == "__main__":
    try:
        result = build(parse_args())
        print(f"Unified release created: {result}")
    except ReleaseError as error:
        raise SystemExit(f"release failed: {error}")
