#!/usr/bin/env python3
"""Package the Interface mobile add-on as a reviewed, versioned, hash-bound archive.

The add-on's source is ``addons/WolkaraRoue`` - the Lua the release review reads. This
script turns that source into two committed artifacts:

* ``WolkaraRoue-<version>.zip`` - the add-on's folder, and nothing else, so installing
  it is copying one folder into the game's ``Interface/AddOns``;
* ``WolkaraRoue-<version>.json`` - its manifest: the release, the interface the TOC
  declares, the archive's own SHA-256 and every file's size and SHA-256.

Both are deterministic. The same source gives byte-identical files, so a fixture can
rebuild them and compare, and a difference is a difference in what was reviewed rather
than a difference in the clock or the ZIP writer.

``--fixtures DIR`` writes a set of deliberately wrong packages beside a good copy, each
in its own directory. The Swift fixture (``tests/test_addon_package.swift``) runs the
production verifier against every one of them and requires each to be refused for the
reason its name gives.

Run from anywhere; it works on the repository root.
"""
import argparse
import hashlib
import json
import pathlib
import shutil
import sys
import zipfile

ROOT = pathlib.Path(__file__).resolve().parent.parent.parent
SOURCE = ROOT / "addons" / "WolkaraRoue"
DESTINATION = ROOT / "wolkaraforever" / "Addons"
FOLDER = "WolkaraRoue"
FORMAT = "wolkaraforever.addon"
FORMAT_VERSION = 1
# The ZIP's own timestamp: fixed, so two runs are byte-identical. 1980-01-01 is the
# earliest a ZIP can name, and no file's mode or owner is carried either.
EPOCH = (1980, 1, 1, 0, 0, 0)
MODE = 0o644


def toc_heading(text, name):
    """A ``## Name:`` value from the TOC, or None."""
    for line in text.splitlines():
        if line.startswith(f"## {name}:"):
            return line.split(":", 1)[1].strip()
    return None


def read_release():
    toc = (SOURCE / "WolkaraRoue.toc").read_text(encoding="utf-8")
    release = toc_heading(toc, "Version")
    interface = toc_heading(toc, "Interface")
    if not release or not interface:
        raise SystemExit(f"{SOURCE}/WolkaraRoue.toc: no ## Version or ## Interface line")
    try:
        interface = int(interface.split(",")[0].strip())
    except ValueError:
        raise SystemExit(f"{SOURCE}/WolkaraRoue.toc: ## Interface is not a number")
    return release, interface


def source_files():
    """Every file the add-on ships, sorted, with its bytes read once."""
    files = sorted(p for p in SOURCE.rglob("*") if p.is_file())
    if not files:
        raise SystemExit(f"{SOURCE}: no files to package")
    return [(p.relative_to(SOURCE).as_posix(), p.read_bytes()) for p in files]


def toc_lists_every_script(files):
    """The TOC must name every Lua file: an add-on that ships a script it does not load,
    or loads one it does not ship, is not the add-on that was reviewed."""
    toc = (SOURCE / "WolkaraRoue.toc").read_text(encoding="utf-8")
    listed = {line.strip() for line in toc.splitlines()
              if line.strip() and not line.startswith("##")}
    present = {name for name, _ in files if name.endswith(".lua")}
    if listed != present:
        missing = sorted(present - listed)
        absent = sorted(listed - present)
        raise SystemExit(f"WolkaraRoue.toc does not match the sources: "
                         f"not loaded {missing}, not shipped {absent}")


def zip_information(name):
    information = zipfile.ZipInfo(f"{FOLDER}/{name}", date_time=EPOCH)
    information.compress_type = zipfile.ZIP_DEFLATED
    information.create_system = 3          # Unix, so the mode below is what is read back
    information.external_attr = (0o100000 | MODE) << 16
    return information


def build_zip(path, files):
    with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
        for name, data in files:
            archive.writestr(zip_information(name), data)


def sha256(data):
    return hashlib.sha256(data).hexdigest()


def build_manifest(release, interface, archive_path, files):
    return {
        "format": FORMAT,
        "version": FORMAT_VERSION,
        "name": FOLDER,
        "release": release,
        "interface": interface,
        "archive": archive_path.name,
        "sha256": sha256(archive_path.read_bytes()),
        "files": {f"{FOLDER}/{name}": {"size": len(data), "sha256": sha256(data)}
                  for name, data in files},
    }


def write_package(output, release, interface, files):
    output.mkdir(parents=True, exist_ok=True)
    archive = output / f"{FOLDER}-{release}.zip"
    build_zip(archive, files)
    manifest = output / f"{FOLDER}-{release}.json"
    manifest.write_text(json.dumps(build_manifest(release, interface, archive, files),
                                   indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return archive, manifest


# --- Fixtures -------------------------------------------------------------------------

def good_pair(fixtures, archive_name, manifest_name):
    good = fixtures / "good"
    good.mkdir(parents=True, exist_ok=True)
    shutil.copy2(DESTINATION / archive_name, good / archive_name)
    shutil.copy2(DESTINATION / manifest_name, good / manifest_name)
    return good


def fresh(fixtures, name):
    directory = fixtures / name
    if directory.exists():
        shutil.rmtree(directory)
    directory.mkdir(parents=True)
    return directory


def write_fixtures(fixtures, release, interface, files, archive_name, manifest_name):
    good = good_pair(fixtures, archive_name, manifest_name)
    good_archive = good / archive_name
    good_manifest = json.loads((good / manifest_name).read_text(encoding="utf-8"))

    # One byte of a stored file changed: the archive's own hash no longer matches.
    tampered = fresh(fixtures, "tampered")
    data = bytearray(good_archive.read_bytes())
    data[len(data) // 2] ^= 0xFF
    (tampered / archive_name).write_bytes(bytes(data))
    shutil.copy2(good / manifest_name, tampered / manifest_name)

    # Cut short: not a readable ZIP at all.
    truncated = fresh(fixtures, "truncated")
    (truncated / archive_name).write_bytes(good_archive.read_bytes()[:400])
    shutil.copy2(good / manifest_name, truncated / manifest_name)

    # An entry the manifest does not know: the package is not the one reviewed, even
    # though it is a valid ZIP of the right add-on.
    extra = fresh(fixtures, "extra-file")
    build_zip(extra / archive_name, files + [("Extra.lua", b"-- not reviewed\n")])
    extra_manifest = dict(good_manifest)
    extra_manifest["sha256"] = sha256((extra / archive_name).read_bytes())
    (extra / manifest_name).write_text(json.dumps(extra_manifest, indent=2, sort_keys=True) + "\n")

    # One reviewed file missing.
    missing = fresh(fixtures, "missing-file")
    build_zip(missing / archive_name, files[:-1])
    missing_manifest = dict(good_manifest)
    missing_manifest["sha256"] = sha256((missing / archive_name).read_bytes())
    (missing / manifest_name).write_text(json.dumps(missing_manifest, indent=2, sort_keys=True) + "\n")

    # A path that tries to leave the folder it is installed into.
    traversal = fresh(fixtures, "traversal")
    with zipfile.ZipFile(traversal / archive_name, "w", zipfile.ZIP_DEFLATED) as archive:
        for name, payload in files:
            archive.writestr(f"{FOLDER}/{name}", payload)
        archive.writestr(f"{FOLDER}/../evil.lua", b"-- outside the add-on\n")
    traversal_manifest = dict(good_manifest)
    traversal_manifest["sha256"] = sha256((traversal / archive_name).read_bytes())
    (traversal / manifest_name).write_text(json.dumps(traversal_manifest, indent=2, sort_keys=True) + "\n")

    # The archive of another release.
    other = fresh(fixtures, "wrong-version")
    shutil.copy2(good_archive, other / archive_name)
    wrong = json.loads((good / manifest_name).read_text(encoding="utf-8"))
    wrong["release"] = "9.9.9"
    (other / manifest_name).write_text(json.dumps(wrong, indent=2, sort_keys=True) + "\n")

    # No manifest beside the archive.
    bare = fresh(fixtures, "no-manifest")
    shutil.copy2(good_archive, bare / archive_name)

    # No archive beside the manifest.
    lonely = fresh(fixtures, "absent-archive")
    shutil.copy2(good / manifest_name, lonely / manifest_name)

    # A file's bytes changed and the manifest's archive hash was recomputed to match, but
    # the file's own recorded hash was left alone: the archive is the "right" ZIP of the
    # wrong add-on, and only the per-file hashes catch it.
    stale = fresh(fixtures, "stale-file-hash")
    changed = [(name, data + b"\n-- changed after review\n" if name == files[0][0] else data)
               for name, data in files]
    build_zip(stale / archive_name, changed)
    stale_manifest = json.loads((good / manifest_name).read_text(encoding="utf-8"))
    stale_manifest["sha256"] = sha256((stale / archive_name).read_bytes())
    (stale / manifest_name).write_text(json.dumps(stale_manifest, indent=2, sort_keys=True) + "\n")

    # A manifest for a different add-on entirely.
    foreign = fresh(fixtures, "foreign-manifest")
    shutil.copy2(good_archive, foreign / archive_name)
    other_addon = json.loads((good / manifest_name).read_text(encoding="utf-8"))
    other_addon["name"] = "SomeOtherAddon"
    (foreign / manifest_name).write_text(json.dumps(other_addon, indent=2, sort_keys=True) + "\n")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=pathlib.Path, default=DESTINATION,
                        help="where to write the archive and manifest (default: the layer)")
    parser.add_argument("--fixtures", type=pathlib.Path, default=None,
                        help="write the deliberately wrong packages into this directory")
    parser.add_argument("--check", action="store_true",
                        help="build into a temporary directory and compare with the "
                             "committed artifacts instead of writing them")
    arguments = parser.parse_args()

    release, interface = read_release()
    files = source_files()
    toc_lists_every_script(files)

    if arguments.check:
        import tempfile
        with tempfile.TemporaryDirectory() as temporary:
            archive, manifest = write_package(pathlib.Path(temporary), release, interface, files)
            for built, committed in ((archive, DESTINATION / archive.name),
                                     (manifest, DESTINATION / manifest.name)):
                if not committed.exists():
                    raise SystemExit(f"{committed} is missing; run this script without --check")
                if built.read_bytes() != committed.read_bytes():
                    raise SystemExit(f"{committed} is not what the sources produce; "
                                     f"run this script without --check")
            print(f"addon package: {archive.name} is what addons/WolkaraRoue produces")
    else:
        archive, manifest = write_package(arguments.output, release, interface, files)
        print(f"addon package: {archive}")
        print(f"addon package: {manifest}")
        print(f"addon package: release {release}, interface {interface}, "
              f"sha256 {json.loads(manifest.read_text())['sha256']}")

    if arguments.fixtures:
        archive_name = f"{FOLDER}-{release}.zip"
        manifest_name = f"{FOLDER}-{release}.json"
        write_fixtures(arguments.fixtures, release, interface, files, archive_name, manifest_name)
        print(f"addon package: fixtures in {arguments.fixtures}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
