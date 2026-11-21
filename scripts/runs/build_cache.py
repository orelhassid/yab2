#!/usr/bin/env python3
"""Keep unchanged build inputs warm across farm snapshot checkouts."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import stat
import subprocess
import tempfile
import time


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def save(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, name = tempfile.mkstemp(dir=path.parent, prefix=".cache-")
    try:
        with os.fdopen(fd, "w") as stream:
            json.dump(value, stream, sort_keys=True)
        os.replace(name, path)
    finally:
        Path(name).unlink(missing_ok=True)


def read(path):
    try:
        value = json.loads(path.read_text())
        return value if isinstance(value, dict) else {}
    except (OSError, ValueError):
        return {}


def source_inputs(root):
    paths = [root / "Package.swift", root / "Package.resolved"]
    paths.extend((root / "Sources").rglob("*"))
    result = {}
    for path in sorted(paths):
        info = path.lstat() if path.exists() else None
        if info is None or not stat.S_ISREG(info.st_mode):
            continue
        result[str(path.relative_to(root))] = {
            "sha": digest(path), "mode": stat.S_IMODE(info.st_mode),
            "size": info.st_size, "mtime": info.st_mtime_ns,
        }
    return result


def prepare_sources(root, manifest):
    previous = read(manifest).get("files", {})
    restored = 0
    for name, current in source_inputs(root).items():
        old = previous.get(name, {}) if isinstance(previous, dict) else {}
        if not isinstance(old, dict):
            continue
        # A checkout can rewrite an identical file. Only identical bytes and
        # permissions may keep the timestamp the compiler previously saw.
        if all(current[k] == old.get(k) for k in ("sha", "mode", "size")):
            stamp = old.get("mtime")
            if isinstance(stamp, int) and 0 < stamp < 2**63 and current["mtime"] != stamp:
                path = root / name
                os.utime(path, ns=(path.stat().st_atime_ns, stamp))
                restored += 1
        elif current["mtime"] == old.get("mtime"):
            # Content changed with a preserved timestamp (e.g. cp -p). Do not
            # let that accidental equality masquerade as a compiler cache hit.
            path = root / name
            os.utime(path, ns=(path.stat().st_atime_ns,
                              max(time.time_ns(), current["mtime"] + 1_000_000_000)))
    print("source cache: restored %d unchanged input timestamps" % restored)


def record_sources(root, manifest):
    save(manifest, {"files": source_inputs(root)})


def icon_key(root, step, minimum, toolchain):
    paths = [root / "build.sh"]
    paths.extend((root / "Icon/yab.icon").rglob("*"))
    if step == "app":
        paths.extend((root / "Icon/yab Dev.icon").rglob("*"))
        # build.sh's YAB_BUNDLE_ICON puts another document on the bundle.
        bundle_icon = os.environ.get("YAB_BUNDLE_ICON")
        if bundle_icon:
            paths.extend((root / bundle_icon).rglob("*"))
    paths.extend((root / "Icon/Alternates").glob("*.png"))
    paths.extend((root / "Icon/Alternates").glob("*.icon/**/*"))
    inputs = [("cache-helper", digest(Path(__file__).resolve()))]
    inputs.extend((str(p.relative_to(root)), digest(p)) for p in sorted(set(paths)) if p.is_file())
    value = [step, minimum, toolchain, inputs]
    if step == "app" and os.environ.get("YAB_BUNDLE_ICON"):
        value.append(["bundle-icon", os.environ["YAB_BUNDLE_ICON"]])
    return hashlib.sha256(json.dumps(value, sort_keys=True).encode()).hexdigest()


def icon_files(folder):
    return {str(p.relative_to(folder)): digest(p)
            for p in sorted(folder.rglob("*"))
            if p.is_file() and p != folder / ".manifest.json"}


def record_icons(folder, key):
    files = icon_files(folder)
    for name in ("Assets.car", "yab.icns", "AppIcons/yab-dark.icns"):
        if name not in files or not (folder / name).stat().st_size:
            raise RuntimeError("incomplete icon cache: " + name)
    save(folder / ".manifest.json", {"key": key, "files": files})


def valid_icons(folder, key):
    value = read(folder / ".manifest.json")
    if value.get("key") != key or not value.get("files"):
        return False
    return value["files"] == icon_files(folder)


# Built apps, kept by the content of everything that goes into them, so a job
# whose app inputs didn't change (a probe after an evals-only edit, the same
# tree built on another lane) copies the app instead of compiling it. On
# 2026-10-09/10 98 of 227 farm builds repeated an app key already built; each
# held the compiler 10-14 s even when Swift had nothing to do, and waited for
# it behind other lanes' compiles (up to 800 s on adhd).
APP_TREES = ("Sources", "Resources", "Icon", "Skills", "DockTile")
APP_FILES = (
    "Package.swift", "Package.resolved", "build.sh", "VERSION", "THIRD_PARTY_NOTICES.md",
    "scripts/package-development-space", "scripts/openui/package.json", "scripts/openui/package-lock.json",
    "scripts/openui/build.mjs", "scripts/openui/index.html", "scripts/openui/library.mjs",
    "scripts/openui/renderer.jsx", "scripts/openui/theme.css",
)
APP_CACHE = Path(os.environ.get("YAB_APP_CACHE_DIR") or Path.home() / ".local/state/yab-farm/apps")
# 40 apps of about 80 MB, 3.2 GB. With ten, m4 kept an app about an hour on
# 2026-10-20 (15 sessions, each with its own trees and its main "before"),
# and adhd, under 40 GB free, five: a main build was evicted before the next
# session's "before" asked for it.
APP_KEEP = 40


def developer_dir():
    """The selected Xcode, without running xcode-select or xcodebuild: under
    disk load `xcodebuild -version` took over 20 s on the farm's Macs."""
    if os.environ.get("DEVELOPER_DIR"):
        return os.path.realpath(os.environ["DEVELOPER_DIR"])
    for link in ("/private/var/select/developer_dir", "/var/db/xcode_select_link"):
        if os.path.islink(link):
            return os.path.realpath(link)
    if os.path.isdir("/Applications/Xcode.app/Contents/Developer"):
        return "/Applications/Xcode.app/Contents/Developer"
    return subprocess.check_output(["xcode-select", "-p"], text=True, timeout=20).strip()


def toolchain_identity():
    """Xcode's version and build, the Swift compiler's file and the macOS SDK."""
    import plistlib
    dev = Path(developer_dir())
    parts = [str(dev)]
    try:
        version = plistlib.loads((dev.parent / "version.plist").read_bytes())
        parts += [version.get("CFBundleShortVersionString", ""), version.get("ProductBuildVersion", "")]
    except (OSError, ValueError):
        pass  # Command Line Tools: no version.plist; the compiler's file says which.
    for frontend in (dev / "Toolchains/XcodeDefault.xctoolchain/usr/bin/swift-frontend", dev / "usr/bin/swift-frontend"):
        if frontend.exists():
            info = frontend.stat()
            parts += [str(frontend), str(info.st_size), str(info.st_mtime_ns)]
            break
    sdk = dev / "Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk"
    parts.append(os.path.realpath(sdk) if sdk.exists() else "")
    return parts


def app_key(root, config, arch=""):
    """sha256 over every input of build.sh's app before its name, debug
    flag and signature, which it applies to a reused app as to a built one."""
    paths = [root / name for name in APP_FILES]
    for tree in APP_TREES:
        paths.extend((root / tree).rglob("*"))
    inputs = [("cache-helper", digest(Path(__file__).resolve()))]
    for path in sorted(set(paths)):
        if path.is_file() and not path.is_symlink():
            inputs.append((str(path.relative_to(root)), digest(path), stat.S_IMODE(path.stat().st_mode)))
        elif path.is_symlink():
            inputs.append((str(path.relative_to(root)), "->" + os.readlink(path)))
    bundle_icon = os.environ.get("YAB_BUNDLE_ICON")
    icon = []
    if bundle_icon:
        folder = (root / bundle_icon) if not os.path.isabs(bundle_icon) else Path(bundle_icon)
        icon = [bundle_icon] + [(str(p.relative_to(folder)), digest(p)) for p in sorted(folder.rglob("*")) if p.is_file()]
    google = [os.environ.get("YAB_GOOGLE_CLIENT_ID", ""), os.environ.get("YAB_GOOGLE_CLIENT_SECRET", "")]
    if not google[0]:
        env_file = Path.home() / ".config/yab/google-client.env"
        google = [digest(env_file)] if env_file.is_file() else []
    value = {"config": config, "arch": arch, "step": "app", "wmo": os.environ.get("YAB_WMO", ""), "icon": icon,
             "google": google, "toolchain": toolchain_identity(), "inputs": inputs}
    return hashlib.sha256(json.dumps(value, sort_keys=True).encode()).hexdigest()


def app_files(app):
    return {str(p.relative_to(app)): (p.lstat().st_size if not p.is_symlink() else "->" + os.readlink(p))
            for p in sorted(app.rglob("*")) if p.is_file() or p.is_symlink()}


def app_entry(cache, key):
    """The cached app for this key, whole and unchanged, or None."""
    entry = cache / key
    manifest = read(entry / "manifest.json")
    app = entry / "app"
    if manifest.get("key") != key or not (app / "Contents/MacOS/yab").is_file():
        return None
    try:
        if manifest.get("files") != app_files(app) or manifest.get("binary") != digest(app / "Contents/MacOS/yab"):
            return None
    except OSError:
        return None
    return entry


def touch(entry):
    (entry / "used").write_text("%d\n" % time.time())


def app_valid(cache, key):
    entry = app_entry(cache, key)
    if entry:
        touch(entry)  # newest, so a concurrent store doesn't evict it
    return entry is not None


def app_restore(cache, key, destination, build=None):
    """Copy the cached app to build.sh's APP and give it this build's number."""
    import plistlib
    import shutil
    entry = app_entry(cache, key)
    if entry is None:
        return False
    touch(entry)
    destination = Path(destination)
    if destination.is_symlink():
        destination.unlink()
    elif destination.exists():
        shutil.rmtree(destination)
    shutil.copytree(entry / "app", destination, symlinks=True)
    if build:
        for info in (destination / "Contents/Info.plist",
                     destination / "Contents/PlugIns/YabDockTile.docktileplugin/Contents/Info.plist"):
            if info.exists():
                value = plistlib.loads(info.read_bytes())
                value["CFBundleVersion"] = build
                info.write_bytes(plistlib.dumps(value, sort_keys=False))
    return True


def app_store(cache, key, app, keep=None):
    """Keep a just-built app under its key: copied whole into a temporary
    folder, then renamed into place only if no other build got there first."""
    import shutil
    cache.mkdir(parents=True, exist_ok=True)
    if app_entry(cache, key):
        touch(cache / key)
        return False
    if (cache / key).exists():
        shutil.rmtree(cache / key, ignore_errors=True)  # damaged; replaced below
    temporary = Path(tempfile.mkdtemp(dir=cache, prefix=".new-"))
    try:
        shutil.copytree(app, temporary / "app", symlinks=True)
        save(temporary / "manifest.json", {"key": key, "files": app_files(temporary / "app"),
                                           "binary": digest(temporary / "app/Contents/MacOS/yab"), "stored": time.time()})
        touch(temporary)
        try:
            os.rename(temporary, cache / key)
        except OSError:
            return False  # another build stored the same key a moment ago
    finally:
        if temporary.exists():
            shutil.rmtree(temporary, ignore_errors=True)
    evict(cache, keep)
    return True


def evict(cache, keep=None):
    """At most keep apps (about 80 MB each), least recently used out first;
    fewer on a Mac short of disk. Half-written copies an hour old go too."""
    import shutil
    if keep is None:
        free = shutil.disk_usage(cache).free
        keep = APP_KEEP if free > 40 << 30 else APP_KEEP // 2 if free > 15 << 30 else 5
    entries = []
    for entry in cache.iterdir():
        if entry.name.startswith(".new-"):
            if time.time() - entry.stat().st_mtime > 3600:
                shutil.rmtree(entry, ignore_errors=True)
            continue
        try:
            entries.append((float((entry / "used").read_text()), entry))
        except (OSError, ValueError):
            entries.append((0.0, entry))
    for _, entry in sorted(entries, reverse=True)[keep:]:
        shutil.rmtree(entry, ignore_errors=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    for name in ("prepare-sources", "record-sources"):
        commands.add_parser(name).add_argument("manifest", type=Path)
    key_command = commands.add_parser("app-key")
    key_command.add_argument("config")
    key_command.add_argument("arch", nargs="?", default="")
    commands.add_parser("app-valid").add_argument("key")
    restore = commands.add_parser("app-restore")
    restore.add_argument("key")
    restore.add_argument("app", type=Path)
    restore.add_argument("--build")
    store = commands.add_parser("app-store")
    store.add_argument("key")
    store.add_argument("app", type=Path)
    key = commands.add_parser("icon-key")
    key.add_argument("step")
    key.add_argument("minimum")
    for name in ("valid-icons", "record-icons"):
        cmd = commands.add_parser(name)
        cmd.add_argument("folder", type=Path)
        cmd.add_argument("key")
    args = parser.parse_args()
    root = Path.cwd()
    if args.command == "prepare-sources":
        prepare_sources(root, args.manifest)
    elif args.command == "record-sources":
        record_sources(root, args.manifest)
    elif args.command == "icon-key":
        actool = Path(subprocess.check_output(["xcrun", "--find", "actool"], text=True).strip())
        version = subprocess.check_output(["xcodebuild", "-version"], text=True)
        sdk = subprocess.check_output(["xcrun", "--sdk", "macosx", "--show-sdk-version"], text=True)
        print(icon_key(root, args.step, args.minimum, [str(actool), digest(actool), version, sdk]))
    elif args.command == "valid-icons":
        raise SystemExit(0 if valid_icons(args.folder, args.key) else 1)
    elif args.command == "record-icons":
        record_icons(args.folder, args.key)
    elif args.command == "app-key":
        print(app_key(root, args.config, args.arch))
    elif args.command == "app-valid":
        raise SystemExit(0 if app_valid(APP_CACHE, args.key) else 1)
    elif args.command == "app-restore":
        raise SystemExit(0 if app_restore(APP_CACHE, args.key, args.app, args.build) else 1)
    elif args.command == "app-store":
        print("app cache: " + ("saved " if app_store(APP_CACHE, args.key, args.app) else "already had ") + args.key[:12])


if __name__ == "__main__":
    main()
