#!/usr/bin/env python3
"""Resolve one verified latest-release snapshot for all image variants."""

import argparse
import gzip
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
import time
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parent.parent
OPENAI = "https://persistent.oaistatic.com/codex-app-prod/linux/rpm/x86_64/"
VERSION = re.compile(r"[0-9]+(?:\.[0-9]+)+")


def run(*args):
    return subprocess.check_output(args, text=True).strip()


def metadata(url):
    if urllib.parse.urlsplit(url).scheme != "https":
        raise ValueError("Metadata URL must use HTTPS")
    headers = {"User-Agent": "LagExpress-Bazzite-updater"}
    if urllib.parse.urlsplit(url).hostname == "api.github.com":
        token = os.environ.get("GH_TOKEN") or os.environ.get("GITHUB_TOKEN")
        if token:
            headers["Authorization"] = f"Bearer {token}"
    for attempt in range(3):
        try:
            request = urllib.request.Request(url, headers=headers)
            with urllib.request.urlopen(request, timeout=30) as response:
                data = response.read(16 * 1024 * 1024 + 1)
            if len(data) > 16 * 1024 * 1024:
                raise ValueError("Release metadata exceeds size limit")
            return data
        except OSError:
            if attempt == 2:
                raise
            time.sleep(2 ** attempt)


def download(url, path):
    return run(
        "curl", "--fail", "--silent", "--show-error", "--location",
        "--proto", "=https", "--proto-redir", "=https",
        "--retry", "3", "--retry-all-errors", "--retry-max-time", "600",
        "--connect-timeout", "30", "--max-time", "600",
        "--max-filesize", "1073741824", "--output", str(path),
        "--write-out", "%{url_effective}", url,
    )


def digest(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def checked_hash(value):
    if not re.fullmatch(r"[0-9a-f]{64}", value or ""):
        raise ValueError("Missing or invalid vendor SHA-256")
    return value


def entry(version, release, url, checksum):
    if not VERSION.fullmatch(version):
        raise ValueError(f"Unexpected release version: {version}")
    if urllib.parse.urlsplit(url).scheme != "https":
        raise ValueError("Artifact URL must use HTTPS")
    return dict(version=version, release=release, url=url,
                sha256=checked_hash(checksum), kind="rpm")


def rpm_identity(path, database, expected_name, expected_version):
    name, version, release, arch = run(
        "rpm", "--dbpath", str(database), "-qp", "--qf",
        "%{NAME}\t%{VERSION}\t%{RELEASE}\t%{ARCH}", str(path),
    ).split("\t")
    if (name, version, arch) != (expected_name, expected_version, "x86_64"):
        raise ValueError(f"Unexpected RPM identity: {name} {version} {arch}")
    if not release.isdigit():
        raise ValueError("Unexpected RPM release field")
    return release


def github_asset(repository, pattern):
    release = json.loads(metadata(f"https://api.github.com/repos/{repository}/releases/latest"))
    if release.get("draft") or release.get("prerelease"):
        raise ValueError(f"Expected stable release for {repository}")
    candidates = [a for a in release["assets"] if re.fullmatch(pattern, a["name"])]
    if len(candidates) != 1:
        raise ValueError(f"Expected exactly one matching Linux asset for {repository}")
    asset = candidates[0]
    checksum = checked_hash(asset.get("digest", "").removeprefix("sha256:"))
    if not asset["browser_download_url"].startswith(f"https://github.com/{repository}/releases/download/"):
        raise ValueError("Unexpected GitHub asset URL")
    return release["tag_name"].removeprefix("v"), asset["browser_download_url"], checksum


def resolve(output):
    with tempfile.TemporaryDirectory(prefix="bazzite-app-releases-") as temporary:
        work = Path(temporary)
        database = work / "rpmdb"
        gnupg_home = work / "gnupg"
        gnupg_home.mkdir(mode=0o700)
        subprocess.run(["rpm", "--dbpath", str(database), "--initdb"], check=True)
        apps = {}

        # OpenCode's official latest endpoint redirects to an immutable version URL.
        path = work / "opencode.rpm"
        url = download("https://opencode.ai/update/api/latest/desktop/opencode/opencode-desktop-linux-x86_64.rpm", path)
        match = re.fullmatch(r"https://opencode\.ai/files/bin/([0-9.]+)/opencode-desktop-linux-x86_64\.rpm", url)
        if not match:
            raise ValueError("Unexpected OpenCode versioned download URL")
        version = match[1]
        apps["opencode"] = entry(version, rpm_identity(path, database, "opencode", version), url, digest(path))
        path.unlink()

        # Hex publishes a stable release manifest with content-addressed artifacts.
        manifest = json.loads(metadata("https://anoma.ly/release/hex/desktop/stable.json"))
        if (manifest["schema"], manifest["app"], manifest["artifact"], manifest["channel"]) != (1, "hex", "desktop", "stable"):
            raise ValueError("Unexpected Hex release manifest")
        version = manifest["release"]["version"]
        target = manifest["release"]["targets"]["linux-x64-rpm"]
        checksum = checked_hash(target["sha256"])
        if target["url"] != f"/release/hex/files/{checksum}/hex.rpm":
            raise ValueError("Unexpected Hex content-addressed URL")
        url = "https://anoma.ly" + target["url"]
        path = work / "hex.rpm"
        download(url, path)
        if digest(path) != checksum or path.stat().st_size != target["size"]:
            raise ValueError("Hex release checksum/size mismatch")
        apps["hex"] = entry(version, rpm_identity(path, database, "hex", version), url, checksum)
        path.unlink()

        # OpenAI's signed RPM repository provides immutable package URLs and hashes.
        repomd = metadata(OPENAI + "repodata/repomd.xml")
        repomd_path = work / "repomd.xml"
        repomd_path.write_bytes(repomd)
        signature = work / "repomd.xml.asc"
        signature.write_bytes(metadata(OPENAI + "repodata/repomd.xml.asc"))
        keyring = work / "openai.gpg"
        subprocess.run(["gpg", "--homedir", str(gnupg_home), "--batch", "--no-options", "--dearmor", "--output", str(keyring),
                        str(ROOT / "build_files/keys/chatgpt.asc")], check=True)
        subprocess.run(["gpgv", "--homedir", str(gnupg_home), "--keyring", str(keyring), str(signature), str(repomd_path)], check=True)
        repo_ns = {"r": "http://linux.duke.edu/metadata/repo"}
        primary = ET.fromstring(repomd).find("r:data[@type='primary']", repo_ns)
        location = primary.find("r:location", repo_ns).attrib["href"]
        if not re.fullmatch(r"repodata/[0-9a-f]+-primary\.xml\.gz", location):
            raise ValueError("Unexpected OpenAI primary metadata URL")
        compressed = metadata(OPENAI + location)
        checksum_node = primary.find("r:checksum", repo_ns)
        if checksum_node.attrib["type"] != "sha256" or hashlib.sha256(compressed).hexdigest() != checksum_node.text:
            raise ValueError("OpenAI repository metadata checksum mismatch")
        ns = {"m": "http://linux.duke.edu/metadata/common"}
        packages = [p for p in ET.fromstring(gzip.decompress(compressed)).findall("m:package", ns)
                    if p.findtext("m:name", namespaces=ns) == "chatgpt"
                    and p.findtext("m:arch", namespaces=ns) == "x86_64"]
        def rpm_order(package):
            v = package.find("m:version", ns).attrib
            return tuple(map(int, v["ver"].split("."))), int(v["rel"])
        package = max(packages, key=rpm_order)
        version = package.find("m:version", ns).attrib
        location = package.find("m:location", ns).attrib["href"]
        expected_file = f"chatgpt-{version['ver']}-{version['rel']}.x86_64.rpm"
        if location != expected_file:
            raise ValueError("Unexpected OpenAI immutable package filename")
        checksum_node = package.find("m:checksum", ns)
        if checksum_node.attrib["type"] != "sha256":
            raise ValueError("OpenAI package is missing SHA-256")
        apps["chatgpt"] = entry(version["ver"], version["rel"], OPENAI + location, checksum_node.text)

        version, url, checksum = github_asset("stablyai/orca", r"orca-ide-[0-9.]+\.x86_64\.rpm")
        path = work / "orca.rpm"
        download(url, path)
        if digest(path) != checksum:
            raise ValueError("Orca release checksum mismatch")
        apps["orca-ide"] = entry(version, rpm_identity(path, database, "orca-ide", version), url, checksum)

        output.parent.mkdir(parents=True, exist_ok=True)
        staged = output.with_suffix(output.suffix + ".tmp")
        staged.write_text(json.dumps(apps, indent=2, sort_keys=True) + "\n")
        staged.replace(output)
        for name, app in sorted(apps.items()):
            print(f"{name}: {app['version']} ({app['kind']})")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", nargs="?", type=Path, default=ROOT / "build_files/desktop-apps.json")
    resolve(parser.parse_args().output)
