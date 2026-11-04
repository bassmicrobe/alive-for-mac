#!/usr/bin/env python3
"""Import CI signing credentials without putting passwords in process arguments."""

import base64
import errno
import fcntl
import os
from pathlib import Path
import pty
import re
import secrets
import select
import subprocess
import termios
import time


def main():
    keychain = str(Path(os.environ["RUNNER_TEMP"]) / "alive-signing.keychain-db")
    p12 = Path(os.environ["RUNNER_TEMP"]) / "developer-id.p12"
    keychain_password = secrets.token_hex(32)
    sensitive = [keychain_password] + [os.environ[name] for name in (
        "P12_BASE64", "P12_PASSWORD", "NOTARY_PASSWORD", "NOTARY_APPLE_ID"
    )]

    def sanitized(data):
        text = data.decode(errors="replace") if isinstance(data, (bytes, bytearray)) else data
        for value in sensitive:
            if value:
                text = text.replace(value, "[REDACTED]")
        return text

    def run(args, data=None):
        result = subprocess.run(args, input=data, capture_output=True)
        if result.returncode:
            raise RuntimeError(sanitized(result.stdout + result.stderr))
        return result.stdout

    def security(*args):
        # security's interactive command parser takes one command on stdin.
        # No shell is involved, and command output (including prompts) stays private.
        if any("\n" in value or "\r" in value for value in args):
            raise RuntimeError("Newlines are not supported in keychain arguments")
        command = " ".join('"' + value.replace("\\", "\\\\").replace('"', '\\"') + '"'
                           for value in args)
        return run(["security", "-i"], (command + "\n").encode())

    try:
        with p12.open("xb") as handle:
            os.chmod(p12, 0o600)
            handle.write(base64.b64decode("".join(os.environ["P12_BASE64"].split()), validate=True))
        security("create-keychain", "-p", keychain_password, keychain)
        security("set-keychain-settings", "-lut", "21600", keychain)
        security("unlock-keychain", "-p", keychain_password, keychain)
        security("import", str(p12), "-P", os.environ["P12_PASSWORD"],
                 "-T", "/usr/bin/codesign", "-t", "cert", "-f", "pkcs12", "-k", keychain)
        security("set-key-partition-list", "-S", "apple-tool:,apple:,codesign:",
                 "-s", "-k", keychain_password, keychain)
        old = run(["security", "list-keychains", "-d", "user"]).decode()
        paths = re.findall(r'"([^"\n]+)"', old)
        run(["security", "list-keychains", "-d", "user", "-s", keychain,
             *[path for path in paths if path != keychain]])
        identities = run(["security", "find-identity", "-v", "-p", "codesigning", keychain]).decode()
        team = os.environ["TEAM_ID"]
        names = re.findall(r'"(Developer ID Application: [^"\n]+)"', identities)
        names = [name for name in names if name.endswith(f"({team})")]
        if len(names) != 1:
            raise RuntimeError("Expected one valid Developer ID Application identity for the team")
        identity = names[0]
        print(f"Signing identity: {identity}", flush=True)

        # notarytool documents a secure prompt when --password is omitted.
        # Give that prompt a terminal with echo disabled, and send the password
        # only after the prompt appears. Never forward terminal output verbatim.
        master, slave = pty.openpty()
        attributes = termios.tcgetattr(slave)
        attributes[3] &= ~(termios.ECHO | termios.ECHONL)
        termios.tcsetattr(slave, termios.TCSANOW, attributes)
        args = ["xcrun", "notarytool", "store-credentials", "alive-ci-notary",
                "--apple-id", os.environ["NOTARY_APPLE_ID"], "--team-id", team,
                "--keychain", keychain]
        process = subprocess.Popen(args, stdin=slave, stdout=slave, stderr=slave,
                                   start_new_session=True,
                                   preexec_fn=lambda: fcntl.ioctl(0, termios.TIOCSCTTY, 0))
        os.close(slave)
        output = bytearray()
        sent = False
        deadline = time.monotonic() + 180
        try:
            while time.monotonic() < deadline:
                if select.select([master], [], [], 0.5)[0]:
                    try:
                        chunk = os.read(master, 65536)
                    except OSError as error:
                        if error.errno == errno.EIO:
                            break
                        raise
                    if not chunk:
                        break
                    output.extend(chunk)
                    if not sent and re.search(rb"App-specific password(?: for [^\r\n:]+)?\s*:", output, re.I):
                        password = os.environ["NOTARY_PASSWORD"]
                        if "\n" in password or "\r" in password:
                            raise RuntimeError("Unexpected newline in app-specific password")
                        os.write(master, password.encode() + b"\n")
                        sent = True
                if process.poll() is not None:
                    break
            else:
                raise RuntimeError("Timed out validating notarization credentials")
            process.wait(timeout=10)
            if process.returncode or not sent:
                raise RuntimeError("Notarization credential validation failed: " + sanitized(output))
        finally:
            if process.poll() is None:
                process.kill()
                process.wait()
            os.close(master)

        print("Notarization credentials validated and saved in the temporary keychain.")
        with open(os.environ["GITHUB_OUTPUT"], "a") as handle:
            handle.write(f"identity={identity}\nkeychain={keychain}\n")
    finally:
        p12.unlink(missing_ok=True)


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        # Never include traceback locals containing credentials.
        print(f"::error::{error}")
        raise SystemExit(1)
