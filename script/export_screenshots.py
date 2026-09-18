#!/usr/bin/env python3
"""Render documentation from current SwiftUI components and synthetic data only."""
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def run(*args):
    return subprocess.check_output(args, cwd=ROOT, text=True).strip()


def main():
    os.environ.setdefault("DEVELOPER_DIR", "/Applications/Xcode.app/Contents/Developer")
    with tempfile.TemporaryDirectory(prefix="CodexVista-docs-") as temporary:
        stage = Path(temporary)
        app = stage / "CodexVistaDocs.app"
        executable = app / "Contents/MacOS/CodexVistaDocs"
        executable.parent.mkdir(parents=True)
        source_paths = sorted((ROOT / "Sources/CodexVista").rglob("*.swift"))
        copied = []
        for path in source_paths:
            if path.name in ("CodexVistaApp.swift", "AppDelegate.swift"):
                continue
            # Only disposable copies expose private components and state for capture.
            # Production sources and the shipping target are never modified.
            source = path.read_text()
            source = re.sub(r"\b(?:fileprivate|private)(?:\(set\))?\s+", "", source)
            source = re.sub(r"\bDate\(\)", "DocumentationFixture.now", source)
            destination = stage / path.name
            destination.write_text(source)
            copied.append(str(destination))
        version = re.search(r"MARKETING_VERSION\s*=\s*(\S+)",
                            (ROOT / "Config/Version.xcconfig").read_text())[1]
        info = {"CFBundleExecutable": "CodexVistaDocs", "CFBundleIdentifier": "com.ychp.CodexVista.Documentation",
                "CFBundleName": "CodexVistaDocs", "CFBundlePackageType": "APPL",
                "CFBundleShortVersionString": version, "LSUIElement": True,
                "NSPrincipalClass": "NSApplication"}
        (app / "Contents/Info.plist").write_bytes(plistlib.dumps(info))
        sdk = run("xcrun", "--sdk", "macosx", "--show-sdk-path")
        harnesses = sorted((ROOT / "script/screenshots").glob("*.swift"))
        print("Compiling current SwiftUI components for documentation…", flush=True)
        subprocess.run(["xcrun", "swiftc", "-swift-version", "6", "-sdk", sdk,
                        "-module-cache-path", str(stage / "ModuleCache"), "-parse-as-library",
                        *copied, *map(str, harnesses), "-lsqlite3", "-o", str(executable)], check=True)
        resources = app / "Contents/Resources"
        resources.mkdir()
        # Compile the same catalog as the product, including its vector menu icon.
        assets = ROOT / "Sources/CodexVista/Resources/Assets.xcassets"
        partial_info = stage / "asset-info.plist"
        subprocess.run(["xcrun", "actool", str(assets), "--compile", str(resources),
                        "--platform", "macosx", "--minimum-deployment-target", "14.0",
                        "--app-icon", "AppIcon", "--output-partial-info-plist", str(partial_info)], check=True)
        info.update(plistlib.loads(partial_info.read_bytes()))
        (app / "Contents/Info.plist").write_bytes(plistlib.dumps(info))
        output = stage / "output"
        output.mkdir()
        try:
            subprocess.run(["open", "-n", "-W", str(app), "--args", str(output)], check=True, timeout=300)
        except subprocess.TimeoutExpired as error:
            progress = output / "progress.txt"
            last_capture = progress.read_text() if progress.exists() else "尚未开始渲染"
            raise RuntimeError(f"Screenshot app timed out; last capture: {last_capture}") from error
        if not (output / "complete.json").exists():
            raise RuntimeError("Screenshot app did not finish; existing documentation images were preserved")
        captures = json.loads((output / "complete.json").read_text())
        for capture in captures:
            path = capture["path"]
            destination = ROOT / "docs/images" / path
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_bytes((output / path).read_bytes())
            capture["sha256"] = hashlib.sha256(destination.read_bytes()).hexdigest()
        source_hash = hashlib.sha256()
        asset_paths = sorted(path for path in assets.rglob("*") if path.is_file())
        for path in [*source_paths, *asset_paths, *harnesses, ROOT / "Config/Version.xcconfig", Path(__file__)]:
            source_hash.update(str(path.relative_to(ROOT)).encode())
            source_hash.update(path.read_bytes())
        manifest = {"source_commit": run("git", "rev-parse", "HEAD"),
                    "source_sha256": source_hash.hexdigest(), "fixture_date": "2026-09-04T08:00:00Z",
                    "method": "Current SwiftUI/AppKit components, isolated documentation app, synthetic data; no live Codex reads",
                    "scale": 2, "captures": captures}
        (ROOT / "docs/images/manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n")
        print(f"Exported {len(captures)} captures to docs/images/", flush=True)


if __name__ == "__main__":
    main()
