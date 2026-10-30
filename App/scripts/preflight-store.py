#!/usr/bin/env python3
"""Report local publisher prerequisites without reading or printing private keys."""

import argparse
import json
import os
import re
import subprocess
import sys
import urllib.parse
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
CONFIG_PATH = ROOT / "AppStore/Submission.local.json"
SIGNING_SETTINGS = {
    "FOLIANCE_APP_SIGN_IDENTITY": "appSigningIdentity",
    "FOLIANCE_INSTALLER_SIGN_IDENTITY": "installerSigningIdentity",
    "FOLIANCE_PROVISION_PROFILE": "provisionProfile",
    "FOLIANCE_TEAM_ID": "teamID",
}
IDENTITY_LINE = re.compile(r'^\s*\d+\)\s+([0-9A-Fa-f]{40})\s+"([^"]+)"')


def parse_args():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--allow-missing-screenshots",
        action="store_true",
        help="check package-signing inputs while warning that screenshots are still required for submission",
    )
    return parser.parse_args()


def load_config(issues):
    if not CONFIG_PATH.exists():
        issues.append(
            "Create ignored AppStore/Submission.local.json with public supportURL and privacyURL (see example)."
        )
        return {}
    try:
        data = json.loads(CONFIG_PATH.read_text())
    except (OSError, json.JSONDecodeError):
        issues.append("Local App Store submission settings could not be read as valid JSON.")
        return {}
    if not isinstance(data, dict):
        issues.append("Local App Store submission settings must contain a JSON object.")
        return {}
    return data


def resolved_setting(environment_key, config):
    value = os.environ.get(environment_key)
    if value:
        return value.strip()
    local_value = config.get(SIGNING_SETTINGS[environment_key], "")
    return local_value.strip() if isinstance(local_value, str) else ""


def identity_kind(common_name):
    name = common_name.casefold()
    if any(token in name for token in (
        "mac app distribution",
        "3rd party mac developer application",
        "apple distribution",
    )):
        return "app"
    if any(token in name for token in (
        "mac installer distribution",
        "3rd party mac developer installer",
    )):
        return "installer"
    return None


def check_signing_identities(app_identity, installer_identity, issues):
    try:
        result = subprocess.run(
            ["security", "find-identity", "-v"],
            capture_output=True,
            text=True,
            check=False,
        )
    except OSError:
        issues.append("Could not inspect installed signing identities with the macOS security tool.")
        return
    if result.returncode != 0:
        issues.append("Could not inspect installed valid signing identities.")
        return

    identities = []
    for line in (result.stdout + "\n" + result.stderr).splitlines():
        match = IDENTITY_LINE.match(line)
        if match:
            fingerprint, common_name = match.groups()
            identities.append((fingerprint.casefold(), common_name, identity_kind(common_name)))
    if not identities:
        issues.append("No valid signing identities are installed.")
        return

    for label, configured, expected_kind in (
        ("App signing", app_identity, "app"),
        ("Installer signing", installer_identity, "installer"),
    ):
        if not configured:
            continue
        normalized = configured.casefold()
        matches = [
            item for item in identities
            if normalized in (item[0], item[1].casefold())
        ]
        if not matches:
            issues.append(f"Configured {label.lower()} identity is not installed as a valid identity.")
        elif not any(item[2] == expected_kind for item in matches):
            issues.append(f"Configured {label.lower()} identity is not the required certificate type.")


def main():
    args = parse_args()
    issues = []
    warnings = []
    config = load_config(issues)

    for key in ("supportURL", "privacyURL"):
        value = config.get(key, "")
        url = urllib.parse.urlparse(value if isinstance(value, str) else "")
        if (
            url.scheme != "https"
            or not url.netloc
            or url.netloc.endswith(".invalid")
            or url.netloc == "example.com"
        ):
            issues.append(f"Set a real public HTTPS {key}.")

    settings = {
        key: resolved_setting(key, config)
        for key in SIGNING_SETTINGS
    }
    for key, value in settings.items():
        if not value:
            issues.append(f"Set {key} in the environment or ignored local submission settings.")

    profile = settings["FOLIANCE_PROVISION_PROFILE"]
    if profile:
        profile_path = Path(profile).expanduser()
        if not profile_path.is_absolute():
            profile_path = ROOT / profile_path
        if not profile_path.is_file():
            issues.append("Provisioning profile path does not exist.")

    check_signing_identities(
        settings["FOLIANCE_APP_SIGN_IDENTITY"],
        settings["FOLIANCE_INSTALLER_SIGN_IDENTITY"],
        issues,
    )

    screenshots_dir = ROOT / "AppStore/Screenshots"
    screenshots = list(screenshots_dir.glob("*.png")) if screenshots_dir.exists() else []
    if not screenshots:
        message = "Capture final native screenshots for App Store Connect before submission."
        if args.allow_missing_screenshots:
            warnings.append(message)
        else:
            issues.append(message)

    if issues:
        print("App Store publisher prerequisites still required:")
        for issue in issues:
            print(f"- {issue}")
        for warning in warnings:
            print(f"Warning: {warning}")
        return 1

    if warnings:
        print("Local package-signing prerequisites are present; submission readiness has not been verified.")
        for warning in warnings:
            print(f"Warning: {warning}")
        print("This check does not upload a package or promise review approval.")
    else:
        print("Local publisher prerequisites are present. Validate the signed package with Transporter.")
        print("This check does not upload a package or promise review approval.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
