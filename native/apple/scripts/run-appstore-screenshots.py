#!/usr/bin/env python3
"""Run a previously built AppStore test plan with private demo configuration.

Build the matching AppStore scheme in Release with simulator ad-hoc signing first.
Pass --credentials-file for a local username/password file, or --credentials-ssh
for the same file on the demo host. The file contains username= and password=.
Only one run may execute at a time; boot only its destination simulator.
"""
import argparse
import json
import os
import pathlib
import plistlib
import subprocess
import tempfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--xctestrun", required=True, type=pathlib.Path)
    parser.add_argument("--destination", required=True)
    parser.add_argument("--server", required=True)
    parser.add_argument("--playlist", required=True)
    parser.add_argument("--credentials-file", required=True)
    parser.add_argument("--credentials-ssh")
    parser.add_argument("--result", required=True, type=pathlib.Path)
    parser.add_argument("--log", required=True, type=pathlib.Path)
    args = parser.parse_args()
    if args.credentials_ssh:
        # Keep the remote path literal; it is never evaluated by a shell locally.
        import shlex
        credentials = subprocess.check_output(
            ["ssh", args.credentials_ssh, "cat " + shlex.quote(args.credentials_file)], text=True)
    else:
        credentials = pathlib.Path(args.credentials_file).read_text()
    values = dict(line.split("=", 1) for line in credentials.splitlines() if "=" in line)
    config = {"OPENSTREAM_DEMO_SERVER": args.server, "OPENSTREAM_TEST_M3U": args.playlist,
              "OPENSTREAM_DEMO_USER": values["username"], "OPENSTREAM_DEMO_PASSWORD": values["password"]}
    # Xcode mangles literal URL values in runner environments. One hex JSON value
    # preserves URLs and passwords exactly; it remains private, never an attachment.
    encoded = json.dumps(config).encode().hex()
    root = str(args.xctestrun.resolve().parent)

    def resolve(value):
        if isinstance(value, str):
            return value.replace("__TESTROOT__", root)
        if isinstance(value, dict):
            return {key: resolve(item) for key, item in value.items()}
        if isinstance(value, list):
            return [resolve(item) for item in value]
        return value

    run = resolve(plistlib.loads(args.xctestrun.read_bytes()))
    for configuration in run["TestConfigurations"]:
        for target in configuration["TestTargets"]:
            for key in ["EnvironmentVariables", "TestingEnvironmentVariables"]:
                target.setdefault(key, {})["OPENSTREAM_DEMO_CONFIG_HEX"] = encoded
            target["OnlyTestIdentifiers"] = ["AppStoreScreenshotUITests/testAppStorePass"]
    args.result.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(prefix="openstream-private-", suffix=".xctestrun", dir="/tmp") as private:
        os.chmod(private.name, 0o600)
        plistlib.dump(run, private)
        private.flush()
        descriptor = os.open(args.log, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
        with os.fdopen(descriptor, "w") as log:
            result = subprocess.run(["xcodebuild", "test-without-building", "-xctestrun", private.name,
                                     "-destination", args.destination, "-parallel-testing-enabled", "NO",
                                     "-maximum-concurrent-test-simulator-destinations", "1",
                                     "-collect-test-diagnostics", "never", "-resultBundlePath", str(args.result)],
                                    stdout=log, stderr=subprocess.STDOUT)
    print("Test exit:", result.returncode)
    raise SystemExit(result.returncode)


if __name__ == "__main__":
    main()
