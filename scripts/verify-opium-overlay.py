#!/usr/bin/env python3
"""Verify the three patches against the checksum-verified Opium 0.18.0 archive."""

import argparse
import hashlib
from pathlib import Path
import shutil
import subprocess
import tarfile
import tempfile
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
PATCHES = (
    "opium.0.18.0-debug-verbose.patch",
    "opium.0.18.0-customizable-start.patch",
    "opium.0.18.0-yojson.patch",
)
SHA512 = (
    "345585719e58b8a08b45244123f03e094a9c67ad8c2ee903dac4d8b646703cfea74"
    "ab87a82f43cf6113ad394c296bddb4bb5fbd910ed8511693b5ec6867baece"
)


def run(*args, cwd, show=True):
    print("+", " ".join(map(str, args)), flush=True)
    result = subprocess.run(list(map(str, args)), cwd=cwd, text=True,
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    if show or result.returncode:
        print(result.stdout, end="", flush=True)
    result.check_returncode()
    return result.stdout


def archive():
    cache = ROOT / "_build/overlay-validation"
    cache.mkdir(parents=True, exist_ok=True)
    target = cache / "opium-0.18.0.tbz"
    if not target.exists():
        urls = (
            "https://github.com/rgrinberg/opium/releases/download/0.18.0/opium-0.18.0.tbz",
            f"https://opam.ocaml.org/cache/sha512/{SHA512[:2]}/{SHA512}",
        )
        for url in urls:
            try:
                print(f"Downloading {url}", flush=True)
                with urllib.request.urlopen(url, timeout=25) as response:
                    data = response.read()
                if hashlib.sha512(data).hexdigest() != SHA512:
                    raise SystemExit("Source archive SHA512 mismatch")
                target.write_bytes(data)
                break
            except OSError as error:
                print(f"Download failed: {error}", flush=True)
        else:
            raise SystemExit("Could not download the official source archive")
    if hashlib.sha512(target.read_bytes()).hexdigest() != SHA512:
        raise SystemExit("Cached source archive SHA512 mismatch")
    return target


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--switch", help="existing opam switch; packages are not installed")
    parser.add_argument("--typed-endpoint", type=Path,
                        help="also rebuild and exercise this checkout's Opium adapter")
    args = parser.parse_args()
    prefix = ["opam", "exec"]
    if args.switch:
        prefix += [f"--switch={args.switch}"]
    prefix += ["--"]
    with tempfile.TemporaryDirectory(prefix="opium-overlay-check-") as tmp:
        work = Path(tmp)
        with tarfile.open(archive()) as tar:
            tar.extractall(work, filter="data")
        roots = list(work.iterdir())
        if len(roots) != 1 or not roots[0].is_dir():
            raise SystemExit("Unexpected source archive layout")
        stage = roots[0]
        for name in PATCHES:
            patch = ROOT / "patches" / name
            output = run("patch", "--dry-run", "--batch", "--fuzz=0", "-p1", "-i", patch,
                         cwd=stage)
            if "offset" in output.lower() or "fuzz" in output.lower():
                raise SystemExit("Patch did not apply exactly")
            run("patch", "--batch", "--fuzz=0", "-p1", "-i", patch, cwd=stage)
        # Build only the production package before adding external tests.
        run(*prefix, "dune", "build", "-p", "opium", "@install", cwd=stage, show=False)
        run(*prefix, "dune", "build", "--profile", "release", "@examples",
            cwd=stage, show=False)
        shutil.copytree(ROOT / "test_overlay", stage / "test_overlay")
        shutil.copyfile(stage / "test_overlay/dune.inc", stage / "test_overlay/dune")
        run(*prefix, "dune", "exec", "--profile", "release",
            "./test_overlay/overlay_test.exe", cwd=stage)
        if args.typed_endpoint:
            adapter = stage / "adapter_under_test"
            adapter.mkdir()
            for suffix in ("ml", "mli"):
                name = f"typed_endpoint_opium.{suffix}"
                shutil.copyfile(args.typed_endpoint / "opium" / name, adapter / name)
            shutil.copyfile(ROOT / "test_overlay/adapter/adapter_check.ml",
                            adapter / "adapter_check.ml")
            (adapter / "dune").write_text("""(library
 (name adapter_under_test)
 (wrapped false)
 (modules typed_endpoint_opium)
 (libraries base cohttp lwt opium typed-endpoint uri yojson)
 (preprocess (pps ppx_let)))
(test
 (name adapter_check)
 (modules adapter_check)
 (libraries adapter_under_test opium cohttp-lwt-unix yojson))
""")
            run(*prefix, "dune", "exec", "--profile", "release",
                "./adapter_under_test/adapter_check.exe", cwd=stage)
    print("Verified archive, patch order, package build, examples and overlay tests.")


if __name__ == "__main__":
    main()
