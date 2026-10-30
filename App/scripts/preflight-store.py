#!/usr/bin/env python3
"""Report local publisher prerequisites without reading or printing private keys."""

import argparse
import json
import os
import re
import struct
import subprocess
import sys
import urllib.parse
import zlib
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
PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"
MAX_SCREENSHOTS = 10
SCREENSHOT_DIMENSIONS = {
    (1280, 800),
    (1440, 900),
    (2560, 1600),
    (2880, 1800),
}


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


def inspect_screenshot_png(path):
    """Validate a PNG's chunks, decoded scanlines and App Store dimensions."""
    try:
        data = path.read_bytes()
    except OSError as error:
        raise ValueError(f"could not be read ({error})") from error
    if len(data) < len(PNG_SIGNATURE) or data[:8] != PNG_SIGNATURE:
        raise ValueError("is empty or does not have a PNG signature")

    offset = 8
    dimensions = None
    bit_depth = color_type = interlace = None
    seen_ihdr = seen_plte = seen_idat = seen_iend = False
    idat_finished = False
    palette = False
    idat_data = bytearray()
    while offset < len(data):
        if len(data) - offset < 12:
            raise ValueError("has a truncated PNG chunk")
        length = struct.unpack_from(">I", data, offset)[0]
        chunk_type = data[offset + 4:offset + 8]
        payload_start = offset + 8
        payload_end = payload_start + length
        chunk_end = payload_end + 4
        if chunk_end > len(data):
            raise ValueError("has a truncated PNG chunk payload")
        payload = data[payload_start:payload_end]
        expected_crc = struct.unpack_from(">I", data, payload_end)[0]
        actual_crc = zlib.crc32(chunk_type + payload) & 0xFFFFFFFF
        if actual_crc != expected_crc:
            raise ValueError("contains a PNG chunk with an invalid checksum")
        if not seen_ihdr and chunk_type != b"IHDR":
            raise ValueError("does not begin with an IHDR chunk")
        if seen_idat and chunk_type != b"IDAT":
            idat_finished = True

        if chunk_type == b"IHDR":
            if seen_ihdr or offset != 8 or length != 13:
                raise ValueError("has an invalid IHDR chunk")
            width, height, bit_depth, color_type, compression, filtering, interlace = struct.unpack(
                ">IIBBBBB", payload
            )
            if (width, height) not in SCREENSHOT_DIMENSIONS:
                allowed = ", ".join(f"{w}x{h}" for w, h in sorted(SCREENSHOT_DIMENSIONS))
                raise ValueError(f"has unsupported dimensions {width}x{height}; accepted sizes are {allowed}")
            legal_depths = {
                0: {1, 2, 4, 8, 16},
                2: {8, 16},
                3: {1, 2, 4, 8},
                4: {8, 16},
                6: {8, 16},
            }
            if color_type not in legal_depths or bit_depth not in legal_depths[color_type]:
                raise ValueError("has an invalid PNG color type or bit depth")
            if compression != 0 or filtering != 0 or interlace not in (0, 1):
                raise ValueError("uses unsupported PNG compression, filtering or interlace settings")
            dimensions = (width, height)
            seen_ihdr = True
        elif chunk_type == b"PLTE":
            if seen_plte or seen_idat or color_type in (0, 4) or not 3 <= length <= 768 or length % 3:
                raise ValueError("has an invalid PLTE chunk")
            seen_plte = palette = True
        elif chunk_type == b"IDAT":
            if idat_finished:
                raise ValueError("has nonconsecutive IDAT chunks")
            seen_idat = True
            idat_data.extend(payload)
        elif chunk_type == b"IEND":
            if length != 0 or not seen_idat:
                raise ValueError("has an invalid IEND chunk")
            seen_iend = True
            offset = chunk_end
            if offset != len(data):
                raise ValueError("contains data after IEND")
            break
        elif not (chunk_type[0] & 0x20):
            raise ValueError(f"contains an unsupported critical PNG chunk {chunk_type!r}")

        offset = chunk_end

    if not seen_iend or not dimensions or not idat_data:
        raise ValueError("is missing required PNG image data or IEND")
    if color_type == 3 and not palette:
        raise ValueError("uses indexed color without a PLTE palette")

    try:
        decoder = zlib.decompressobj()
        decoded = decoder.decompress(bytes(idat_data)) + decoder.flush()
    except zlib.error as error:
        raise ValueError("contains corrupt compressed image data") from error
    if not decoder.eof or decoder.unused_data or decoder.unconsumed_tail:
        raise ValueError("contains incomplete or trailing compressed image data")

    width, height = dimensions
    channels = {0: 1, 2: 3, 3: 1, 4: 2, 6: 4}[color_type]
    bits_per_pixel = channels * bit_depth
    pass_rows = []
    if interlace == 0:
        pass_rows = [((width * bits_per_pixel + 7) // 8)] * height
    else:
        starts_x, starts_y = (0, 4, 0, 2, 0, 1, 0), (0, 0, 4, 0, 2, 0, 1)
        steps_x, steps_y = (8, 8, 4, 4, 2, 2, 1), (8, 8, 8, 4, 4, 2, 2)
        for sx, sy, dx, dy in zip(starts_x, starts_y, steps_x, steps_y):
            pass_width = max(0, (width - sx + dx - 1) // dx)
            pass_height = max(0, (height - sy + dy - 1) // dy)
            if pass_width and pass_height:
                row_bytes = (pass_width * bits_per_pixel + 7) // 8
                pass_rows.extend([row_bytes] * pass_height)
    if len(decoded) != sum(row_bytes + 1 for row_bytes in pass_rows):
        raise ValueError("has an invalid decoded image-data length")
    cursor = 0
    for row_bytes in pass_rows:
        if decoded[cursor] > 4:
            raise ValueError("contains an invalid PNG row filter")
        cursor += row_bytes + 1
    return dimensions


def check_screenshots(screenshots_dir, allow_missing, issues, warnings):
    screenshots = sorted(
        path for path in screenshots_dir.iterdir()
        if path.is_file() and path.suffix.casefold() == ".png"
    ) if screenshots_dir.is_dir() else []
    if not screenshots:
        message = "Capture final native PNG screenshots for App Store Connect before submission."
        if allow_missing:
            warnings.append(message)
        else:
            issues.append(message)
        return
    if len(screenshots) > MAX_SCREENSHOTS:
        issues.append(f"Found {len(screenshots)} screenshot PNG files; App Store Connect allows at most {MAX_SCREENSHOTS}.")
    for screenshot in screenshots:
        try:
            inspect_screenshot_png(screenshot)
        except ValueError as error:
            issues.append(f"Invalid screenshot {screenshot.name}: {error}.")


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
    check_screenshots(screenshots_dir, args.allow_missing_screenshots, issues, warnings)

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
