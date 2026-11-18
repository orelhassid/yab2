#!/usr/bin/env python3
"""Install Yab Daily and follow completed, signed Sidebar Preview builds on this Mac."""
import argparse
import ctypes
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import tempfile

LABEL = "local.yab.daily-updater"
BUNDLE = "dev.serafim.fast.daily.dev"
DAILY = Path("/Applications/Yab Daily.app")
SUPPORT = Path.home() / "Library/Application Support/Yab Daily Updater"
AGENT = Path.home() / "Library/LaunchAgents" / (LABEL + ".plist")


def signature(app):
    result = subprocess.run(["/usr/bin/codesign", "-dv", "--verbose=4", app],
                            capture_output=True, text=True, check=True)
    return next(line[7:] for line in result.stderr.splitlines() if line.startswith("CDHash="))


def info(app):
    return plistlib.loads((app / "Contents/Info.plist").read_bytes())


def refresh(source):
    if not source.exists():
        return
    if info(source)["CFBundleIdentifier"] != "dev.serafim.fast.sidebar.dev":
        raise ValueError("Unexpected preview bundle identifier")
    revision = signature(source)
    if DAILY.exists():
        installed = info(DAILY)
        if installed["CFBundleIdentifier"] != BUNDLE:
            raise ValueError("Another application already occupies the destination")
        if installed.get("YabDailySource") == revision:
            return

    # Stage on the destination volume. A partially copied or unsigned build
    # never replaces a working bundle, even if the builder is running again.
    with tempfile.TemporaryDirectory(prefix=".yab-daily-", dir=DAILY.parent) as stage:
        candidate = Path(stage) / DAILY.name
        subprocess.run(["/usr/bin/ditto", source, candidate], check=True)
        subprocess.run(["/usr/bin/codesign", "--verify", "--deep", "--strict", candidate], check=True)
        if signature(candidate) != revision:
            raise RuntimeError("Source changed during staging")
        metadata = info(candidate)
        metadata.update(CFBundleIdentifier=BUNDLE, CFBundleName="Yab Daily",
                        CFBundleDisplayName="Yab Daily", YabDataName="Yab Daily",
                        YabDailySource=revision)
        metadata.pop("YabFeed", None)
        (candidate / "Contents/Info.plist").write_bytes(plistlib.dumps(metadata))
        icon = candidate / "Contents/Resources/yab.icns"
        stock = Path("/Applications/yab.app/Contents/Resources/yab.icns")
        if not icon.exists() and stock.is_file():
            shutil.copyfile(stock, icon)
        subprocess.run(["/usr/bin/codesign", "--force", "--sign", "-", candidate], check=True)
        subprocess.run(["/usr/bin/codesign", "--verify", "--deep", "--strict", candidate], check=True)
        if DAILY.exists():
            # Darwin RENAME_SWAP changes both names atomically, including
            # nonempty directories. Existing processes keep their mapped executable.
            swap = ctypes.CDLL(None, use_errno=True).renamex_np
            if swap(os.fsencode(candidate), os.fsencode(DAILY), 2) != 0:
                error = ctypes.get_errno()
                raise OSError(error, os.strerror(error))
        else:
            candidate.rename(DAILY)
        print("Installed Yab Daily", metadata["CFBundleShortVersionString"], revision, flush=True)


def install(source):
    if not source.is_dir():
        raise FileNotFoundError(source)
    refresh(source)
    SUPPORT.mkdir(parents=True, exist_ok=True)
    script = SUPPORT / "update.py"
    shutil.copyfile(__file__, script)
    AGENT.parent.mkdir(parents=True, exist_ok=True)
    job = dict(Label=LABEL, ProgramArguments=["/usr/bin/python3", str(script), str(source)],
               RunAtLoad=True, StartInterval=60, ProcessType="Background",
               StandardOutPath=str(SUPPORT / "update.log"), StandardErrorPath=str(SUPPORT / "update.log"))
    AGENT.write_bytes(plistlib.dumps(job))
    domain = "gui/" + str(os.getuid())
    subprocess.run(["/bin/launchctl", "bootout", domain + "/" + LABEL], capture_output=True)
    subprocess.run(["/bin/launchctl", "bootstrap", domain, AGENT], check=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--install", action="store_true")
    parser.add_argument("source", type=Path)
    args = parser.parse_args()
    (install if args.install else refresh)(args.source.resolve())
