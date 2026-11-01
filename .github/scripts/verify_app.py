#!/usr/bin/env python3
"""Static checks on a built iOS .app, run in CI before anything is released.

Catches problems that otherwise only show up as a crash on launch: the Xcode
preview "debug dylib" stub layout, libraries missing from the bundle, binaries
built for another platform or CPU, system libraries that don't exist on iOS,
a broken code signature and missing entitlements.
"""
import argparse
import os
import plistlib
import shutil
import struct
import subprocess
import sys

CPU_ARM64 = 0x0100000C
FILETYPES = {2: "MH_EXECUTE", 6: "MH_DYLIB", 8: "MH_BUNDLE"}
PLATFORMS = {1: "macOS", 2: "iOS", 6: "Mac Catalyst", 7: "iOS Simulator"}
LOAD_CMDS = {0xC: "load", 0x80000018: "weak", 0x8000001F: "reexport", 0x80000023: "upward"}
LC_RPATH = 0x8000001C
LC_BUILD_VERSION = 0x32
LC_VERSION_MIN_IPHONEOS = 0x25

errors = []
warnings = []


def error(msg):
    errors.append(msg)
    print(f"::error::{msg}")


def warn(msg):
    warnings.append(msg)
    print(f"::warning::{msg}")


class MachO:
    def __init__(self, path):
        self.path = path
        self.deps = []
        self.rpaths = []
        self.platform = None
        self.fat = False
        with open(path, "rb") as f:
            data = f.read()
        off = 0
        magic = struct.unpack_from("<I", data, 0)[0]
        if magic == 0xBEBAFECA:  # fat header is big-endian
            self.fat = True
            count = struct.unpack_from(">I", data, 4)[0]
            slices = [struct.unpack_from(">iiIII", data, 8 + i * 20) for i in range(count)]
            arm = [s for s in slices if s[0] == CPU_ARM64]
            if not arm:
                self.cpu, self.filetype = slices[0][0] if slices else None, None
                return
            off = arm[0][2]
        _, self.cpu, _, self.filetype, ncmds, _, _, _ = struct.unpack_from("<IiiIIIII", data, off)
        p = off + 32
        for _ in range(ncmds):
            cmd, size = struct.unpack_from("<II", data, p)
            if cmd in LOAD_CMDS or cmd == LC_RPATH:
                name_off = struct.unpack_from("<I", data, p + 8)[0]
                name = data[p + name_off:p + size].split(b"\0")[0].decode()
                if cmd == LC_RPATH:
                    self.rpaths.append(name)
                else:
                    self.deps.append((LOAD_CMDS[cmd], name))
            elif cmd == LC_BUILD_VERSION:
                self.platform = struct.unpack_from("<I", data, p + 8)[0]
            elif cmd == LC_VERSION_MIN_IPHONEOS:
                self.platform = 2
            p += size


def is_macho(path):
    try:
        with open(path, "rb") as f:
            head = f.read(4)
    except OSError:
        return False
    return head in (b"\xcf\xfa\xed\xfe", b"\xca\xfe\xba\xbe")


def in_sdk(sdk, path):
    """True if an iOS system library exists in the SDK, None if no SDK to check against."""
    if sdk is None:
        return None
    base = path[:-len(".dylib")] if path.endswith(".dylib") else path
    return any(os.path.exists(sdk + c) for c in (base + ".tbd", path + ".tbd", path))


def resolve(dep, image, main, app, sdk):
    """Where a dependency is found: 'bundle', 'system', 'unchecked', or None if nowhere."""
    if dep.startswith("@rpath/"):
        rel = dep[len("@rpath/"):]
        system_unchecked = False
        for owner in (image, main):
            for rp in owner.rpaths:
                base = rp.replace("@executable_path", app).replace("@loader_path", os.path.dirname(owner.path))
                if base.startswith("@"):
                    continue
                candidate = os.path.normpath(os.path.join(base, rel))
                if candidate.startswith(app):
                    if os.path.exists(candidate):
                        return "bundle"
                else:
                    found = in_sdk(sdk, candidate)
                    if found:
                        return "system"
                    if found is None:
                        system_unchecked = True
        return "unchecked" if system_unchecked else None
    if dep.startswith(("@executable_path/", "@loader_path/")):
        candidate = dep.replace("@executable_path", app).replace("@loader_path", os.path.dirname(image.path))
        return "bundle" if os.path.exists(candidate) else None
    if dep.startswith("/"):
        found = in_sdk(sdk, dep)
        return "system" if found else ("unchecked" if found is None else None)
    return None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("app")
    ap.add_argument("--sdk", help="iPhoneOS SDK path for checking system libraries")
    ap.add_argument("--expect-dylib", action="store_true", help="main executable must be patched to MH_DYLIB")
    ap.add_argument("--require-entitlement", action="append", default=[])
    args = ap.parse_args()
    app = os.path.abspath(args.app)

    info = plistlib.load(open(os.path.join(app, "Info.plist"), "rb"))
    for key in ("CFBundleExecutable", "CFBundleIdentifier"):
        if not info.get(key):
            error(f"Info.plist has no {key}")
    exe_path = os.path.join(app, info.get("CFBundleExecutable", ""))
    if not os.path.isfile(exe_path) or not is_macho(exe_path):
        error(f"main executable {info.get('CFBundleExecutable')} is missing or not a Mach-O")
        return finish()

    for name in os.listdir(app):
        if name.endswith(".debug.dylib") or name == "__preview.dylib":
            error(f"Xcode preview debug-dylib layout ({name}): the executable is only a stub")

    main_bin = MachO(exe_path)
    if main_bin.cpu != CPU_ARM64:
        error("main executable has no arm64 code")
    if args.expect_dylib and (main_bin.fat or main_bin.filetype != 6):
        error(f"main executable is {FILETYPES.get(main_bin.filetype, main_bin.filetype)}"
              f"{' (fat)' if main_bin.fat else ''}, expected thin MH_DYLIB")

    binaries = []
    for root, _, files in os.walk(app):
        for name in files:
            path = os.path.join(root, name)
            if os.path.islink(path):
                continue
            if name.endswith(".a"):
                warn(f"static library shipped in the bundle (not loadable): {os.path.relpath(path, app)}")
            elif is_macho(path):
                binaries.append(MachO(path))

    unchecked = 0
    for b in binaries:
        rel = os.path.relpath(b.path, app)
        if b.cpu != CPU_ARM64:
            error(f"{rel}: no arm64 code")
            continue
        if b.platform is None:
            warn(f"{rel}: no platform information")
        elif b.platform != 2:
            error(f"{rel}: built for {PLATFORMS.get(b.platform, b.platform)}, not iOS")
        for kind, dep in b.deps:
            where = resolve(dep, b, main_bin, app, args.sdk)
            if where == "unchecked":
                unchecked += 1
            elif where is None:
                (warn if kind == "weak" else error)(f"{rel}: depends on {dep}, which is neither in the app nor on iOS")
        print(f"  {rel}: {FILETYPES.get(b.filetype, b.filetype)}, {PLATFORMS.get(b.platform, '?')}, {len(b.deps)} deps")
    if unchecked:
        print(f"  ({unchecked} system dependencies not checked: no --sdk given)")

    if shutil.which("codesign"):
        r = subprocess.run(["codesign", "--verify", "--deep", "--strict", app], capture_output=True, text=True)
        if r.returncode != 0:
            error(f"code signature invalid: {r.stderr.strip()}")
        if args.require_entitlement:
            r = subprocess.run(["codesign", "-d", "--entitlements", "-", "--xml", app], capture_output=True)
            ents = plistlib.loads(r.stdout) if r.stdout.strip() else {}
            for key in args.require_entitlement:
                if not ents.get(key):
                    error(f"entitlement {key} missing")
    elif args.require_entitlement:
        print("  (codesign not available: signature and entitlements not checked)")

    return finish(len(binaries))


def finish(count=0):
    print(f"verify_app: {count} Mach-O files, {len(errors)} errors, {len(warnings)} warnings")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
