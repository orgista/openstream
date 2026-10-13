#!/usr/bin/env python3
"""Run the checked-in E2E plans on existing Dev-Mini simulators, restoring data.

From native/apple: scripts/mini.sh 'python3 Tests/Fixtures/run-e2e.py'
Optional --platform iOS|tvOS and repeatable --only Class/test selectors.
No simulators are created. Scratch, snapshots and xcresults stay in /tmp.
Copy the resulting fixtures-*.json into verification-artifacts/e2e-2026-10-12.
"""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import tempfile
import threading
import time

sys.dont_write_bytecode = True

ROOT = Path(__file__).resolve().parents[2]
BUNDLE = "com.orgista.openstream"
GROUP = "group.com.orgista.openstream"
SIMS = {"iOS": "73E49263-D838-4C4E-9CED-803AA1497945", "tvOS": "F2107E8F-87F4-4685-9C91-84B56D78EC6F"}
SCHEMES = {"iOS": "OpenStreamiOSUITests", "tvOS": "OpenStreamTVUITests"}
TARGETS = {"iOS": "OpenStreamiOSUITests", "tvOS": "OpenStreamTVUITests"}
DD = Path.home() / "Developer/sim-dd-internal"


def command(args, **kw):
    return subprocess.run(args, check=True, **kw)


def read_json(args):
    return json.loads(subprocess.check_output(args, text=True))


def container(sim, kind):
    # simctl can retain a deleted app-group path after a UI-test install.
    area = "Data/Application" if kind == "data" else "Shared/AppGroup"
    identifier = BUNDLE if kind == "data" else kind
    base = Path.home() / "Library/Developer/CoreSimulator/Devices" / sim / "data/Containers" / area
    candidates = []
    for metadata in base.glob("*/.com.apple.mobile_container_manager.metadata.plist"):
        try:
            if plistlib.loads(metadata.read_bytes()).get("MCMMetadataIdentifier") == identifier:
                candidates.append(metadata.parent)
        except (OSError, plistlib.InvalidFileException):
            pass
    if not candidates:
        raise RuntimeError("No live container for " + kind)
    def activity(path):
        return max((p.stat().st_mtime for p in path.rglob("*") if p.is_file()
                    and p.name != ".com.apple.mobile_container_manager.metadata.plist"), default=path.stat().st_mtime)
    return max(candidates, key=activity)


def hashes(path):
    return {str(p.relative_to(path)): hashlib.sha256(p.read_bytes()).hexdigest()
            for p in path.rglob("*") if p.is_file() and p.name != ".com.apple.mobile_container_manager.metadata.plist"}


def stop(sim):
    subprocess.run(["xcrun", "simctl", "terminate", sim, BUNDLE], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def snapshot(sim, work):
    stop(sim)
    rows = []
    for kind in ["data", GROUP]:
        original = container(sim, kind)
        backup = work / kind
        command(["ditto", str(original), str(backup)])
        rows.append({"kind": kind, "original": str(original), "snapshot": str(backup)})
    # Widget placement, TV icon placement, and staged Messages drafts are host state.
    device = Path.home() / "Library/Developer/CoreSimulator/Devices" / sim / "data"
    host_paths = [device / "Library/SpringBoard", device / "Library/HeadBoard", device / "Library/SMS"]
    hosts = []
    for index, path in enumerate(host_paths):
        if path.exists():
            backup = work / f"host-{index}"
            command(["ditto", str(path), str(backup)])
            hosts.append({"original": str(path), "snapshot": str(backup)})
    return rows, hosts


def restore(sim, rows, hosts):
    stop(sim)
    for row in rows:
        row["restored"] = str(container(sim, row["kind"]))
    command(["xcrun", "simctl", "shutdown", sim])
    for row in rows + hosts:
        destinations = {row["original"], row.get("restored", row["original"])}
        for destination in destinations:
            command(["rsync", "-a", "--delete", "--exclude=.com.apple.mobile_container_manager.metadata.plist",
                     row["snapshot"] + "/", destination + "/"])
        row["verified"] = hashes(Path(row["snapshot"])) == hashes(Path(row.get("restored", row["original"])))
        if not row["verified"]:
            raise RuntimeError("Simulator restore verification failed: " + row.get("kind", "host"))


def extract_results(bundle):
    tree = read_json(["xcrun", "xcresulttool", "get", "test-results", "tests", "--path", str(bundle)])
    tests = []
    def walk(node):
        if node.get("nodeType") == "Test Case":
            tests.append({"identifier": node.get("nodeIdentifier"), "name": node.get("name"),
                          "status": node.get("result"), "duration": node.get("duration"),
                          "details": node.get("details", [])})
        for child in node.get("children", []):
            walk(child)
    for node in tree.get("testNodes", []):
        walk(node)
    summary = read_json(["xcrun", "xcresulttool", "get", "test-results", "summary", "--path", str(bundle)])
    return {"summary": summary, "tests": tests}


def run_platform(platform, work, only):
    sim = SIMS[platform]
    devices = read_json(["xcrun", "simctl", "list", "devices", "--json"])
    booted = [d["udid"] for group in devices["devices"].values() for d in group if d["state"] == "Booted"]
    if booted:
        raise RuntimeError("Another simulator is booted; stop before running E2E")
    command(["xcrun", "simctl", "boot", sim])
    command(["xcrun", "simctl", "bootstatus", sim, "-b"], stdout=subprocess.DEVNULL)
    try:
        rows, hosts = snapshot(sim, work)
    except Exception:
        command(["xcrun", "simctl", "shutdown", sim])
        raise
    result = {"platform": platform, "simulator": sim, "scratch": str(work), "muteAudio": True}
    try:
        buildlog = work / "build.log"
        with buildlog.open("w") as log:
            # The UI-test schemes have no app dependency: build the app explicitly.
            command(["xcodebuild", "-project", "OpenStreamApps.xcodeproj", "-scheme", "OpenStream " + platform,
                     "-destination", "id=" + sim, "-derivedDataPath", str(DD), "build"],
                    cwd=ROOT / "Apps", stdout=log, stderr=subprocess.STDOUT)
            command(["xcodebuild", "-project", "OpenStreamApps.xcodeproj", "-scheme", SCHEMES[platform],
                     "-testPlan", "E2E-" + platform, "-destination", "id=" + sim,
                     "-derivedDataPath", str(DD), "-parallel-testing-enabled", "NO", "build-for-testing"],
                    cwd=ROOT / "Apps", stdout=log, stderr=subprocess.STDOUT)
        result["buildLog"] = str(buildlog)
        products = DD / "Build/Products"
        app_path = products / ("Debug-iphonesimulator" if platform == "iOS" else "Debug-appletvsimulator") / "OpenStream.app"
        if not app_path.exists():
            apps = list((products / ("Debug-iphonesimulator" if platform == "iOS" else "Debug-appletvsimulator")).glob("*.app"))
            app_path = next(p for p in apps if "Runner" not in p.name)
        command(["xcrun", "simctl", "install", sim, str(app_path)])
        stub_path = work / "stubs"
        shutil.copytree(ROOT / "Apps/TestPlans/Stubs", stub_path)
        stub = str(stub_path)
        command(["xcrun", "simctl", "launch", sim, BUNDLE, "-OpenStreamResetOnLaunch", "YES",
                 "-OpenStreamStubNetwork", stub, "-OpenStreamStubMediaBase", "http://127.0.0.1:8767",
                 "-OpenStreamMuteAudio", "YES"])
        time.sleep(12)
        stop(sim)
        # Expand generated build placeholders only; the checked-in plan remains the source of settings.
        generated = max(products.glob("*E2E-" + platform + "*.xctestrun"), key=lambda p: p.stat().st_mtime)
        config = plistlib.loads(generated.read_bytes())
        def expand(value):
            if isinstance(value, str):
                return value.replace("__TESTROOT__", str(products))
            if isinstance(value, list):
                return [expand(x) for x in value]
            if isinstance(value, dict):
                return {k: expand(v) for k, v in value.items()}
            return value
        config = expand(config)
        for configuration in config["TestConfigurations"]:
            for target in configuration["TestTargets"]:
                target.setdefault("EnvironmentVariables", {})["OPENSTREAM_STUB_DIR"] = stub
        test_run = work / "plan.xctestrun"
        test_run.write_bytes(plistlib.dumps(config))
        bundle = work / "tests.xcresult"
        args = ["xcodebuild", "-xctestrun", str(test_run), "-destination", "id=" + sim,
                "-derivedDataPath", str(DD), "-parallel-testing-enabled", "NO", "-resultBundlePath", str(bundle)]
        args += ["-only-testing:" + TARGETS[platform] + "/" + t for t in only]
        with (work / "tests.log").open("w") as log:
            proc = subprocess.run(args + ["test-without-building"], stdout=log, stderr=subprocess.STDOUT)
        result["exitCode"] = proc.returncode
        result["resultBundle"] = str(bundle)
        result.update(extract_results(bundle))
        trace = container(sim, "data") / "Library/Caches/openstream-trace.log"
        if trace.exists():
            lines = trace.read_text(errors="replace").splitlines()
            result["libraryFixtureTrace"] = [line for line in lines
                                             if "library scanned" in line or "library scans done" in line
                                             or "library grouped" in line]
            result["fixturePlaybackHealth"] = [line for line in lines
                                               if "first frame, route=" in line or "failure timed out after" in line]
    except Exception as error:
        result["error"] = str(error)
        result["exitCode"] = 1
    finally:
        restore(sim, rows, hosts)
        result["cleanup"] = {"appAndGroup": rows, "hostData": hosts, "simulatorShutdown": True}
        (work / ("fixtures-" + platform.lower() + ".json")).write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps({"platform": platform, "exitCode": result["exitCode"], "results": str(work)}), flush=True)
    return result["exitCode"]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--platform", choices=SIMS, action="append")
    parser.add_argument("--only", action="append", default=[])
    args = parser.parse_args()
    os.environ["DEVELOPER_DIR"] = "/Applications/Xcode.app/Contents/Developer"
    work = Path(tempfile.mkdtemp(prefix="openstream-fixtures-", dir="/tmp"))
    print("E2E scratch: " + str(work), flush=True)
    clip = work / "e2e-long.mp4"
    command(["ffmpeg", "-v", "error", "-f", "lavfi", "-i", "testsrc2=size=256x144:rate=1",
             "-t", "1800", "-c:v", "libx264", "-pix_fmt", "yuv420p", "-movflags", "+faststart", str(clip)])
    live_clip = work / "e2e-live.ts"
    command(["ffmpeg", "-v", "error", "-f", "lavfi", "-i", "testsrc2=size=256x144:rate=25",
             "-f", "lavfi", "-i", "anullsrc=channel_layout=stereo:sample_rate=48000",
             "-t", "1800", "-c:v", "libx264", "-preset", "ultrafast", "-g", "50",
             "-b:v", "1500k", "-minrate", "1500k", "-maxrate", "1500k", "-bufsize", "3000k",
             "-x264-params", "nal-hrd=cbr:force-cfr=1", "-c:a", "aac",
             "-f", "mpegts", str(live_clip)])
    spec = importlib.util.spec_from_file_location("fixture_server", ROOT / "Tests/Fixtures/serve.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    server = module.FixtureServer("127.0.0.1", 8767, str(ROOT / "Tests/Fixtures/out"))
    server.e2e_media = str(clip)
    server.e2e_live = str(live_clip)
    # Keep a continuous timeline at real-time pacing: the short engine fixture
    # loops its timestamps and its default stress throughput outruns live playback.
    server.live_target_bps = live_clip.stat().st_size / 1800
    server.live_chunk_size = 64 * 1024
    # A short initial burst supplies the decoder probe before the app's
    # startup deadline; afterwards the continuous TS keeps real-time pacing.
    server.live_bootstrap_bytes = 3 * 1024 * 1024
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    codes = []
    try:
        for platform in args.platform or SIMS:
            platform_work = work / platform
            platform_work.mkdir()
            codes.append(run_platform(platform, platform_work, args.only))
    finally:
        server.shutdown()
        server.server_close()
        thread.join()
    raise SystemExit(1 if any(codes) else 0)


if __name__ == "__main__":
    main()
