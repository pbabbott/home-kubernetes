#!/usr/bin/env python3
"""
Sync Dashy config from the live deployment into the Helm chart configmap template.

Reads temp/dashboard-config.yaml, strips YAML anchors and the filteredItems
block, replaces live URLs with Helm template variables ({{ .Values.urls.KEY }}),
and writes the result into applications/base/dashy/templates/configmap.yaml.

Usage:
  ./scripts/sync-dashy-config.py
"""

import os
import re
import sys
import termios
import tty

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TEMP_CONFIG = os.path.join(REPO_ROOT, "temp", "dashboard-config.yaml")
HELMRELEASE = os.path.join(REPO_ROOT, "applications", "non-prod-gen2", "dashy", "helmrelease.yaml")
CONFIGMAP = os.path.join(REPO_ROOT, "applications", "base", "dashy", "templates", "configmap.yaml")

CONFIGMAP_HEADER = """\
apiVersion: v1
kind: ConfigMap
metadata:
  name: dashboard-config
  namespace: dashy
data:
  conf.yml: |
"""

# ANSI colours
CYAN   = "\033[96m"
YELLOW = "\033[93m"
GREEN  = "\033[92m"
BOLD   = "\033[1m"
RESET  = "\033[0m"

DASHY_URL = "https://dashy.local.non-prod.abbottland.io"


def press_any_key(prompt: str = "Press any key to continue...") -> None:
    print(f"\n  {YELLOW}{prompt}{RESET}\n")
    fd = sys.stdin.fileno()
    try:
        old = termios.tcgetattr(fd)
        try:
            tty.setraw(fd)
            sys.stdin.read(1)
        finally:
            termios.tcsetattr(fd, termios.TCSADRAIN, old)
    except termios.error:
        # Not a real TTY (e.g. piped input) – fall back to a plain Enter prompt.
        input()


def prompt_manual_export() -> None:
    temp_rel = os.path.relpath(TEMP_CONFIG, REPO_ROOT)
    print()
    print(f"  {BOLD}{CYAN}{'─' * 60}{RESET}")
    print(f"  {BOLD}{CYAN}  Manual step required: export Dashy config{RESET}")
    print(f"  {BOLD}{CYAN}{'─' * 60}{RESET}")
    print()
    print(f"    1.  Open  {BOLD}{DASHY_URL}{RESET}")
    print(f"    2.  Click  {BOLD}Edit  →  Export Config  →  Download as File{RESET}")
    print(f"    3.  Save / overwrite the downloaded file to:")
    print()
    print(f"          {BOLD}{GREEN}{temp_rel}{RESET}")
    print()
    print(f"  {BOLD}{CYAN}{'─' * 60}{RESET}")
    press_any_key("Done? Press any key to continue ...")


def parse_url_map(helmrelease_path: str) -> dict[str, str]:
    """Return a mapping of live URL → Helm values key from the helmrelease."""
    url_map: dict[str, str] = {}
    in_urls = False
    with open(helmrelease_path) as f:
        for line in f:
            stripped = line.rstrip()
            if re.match(r"\s+urls:\s*$", stripped):
                in_urls = True
                continue
            if in_urls:
                m = re.match(r"\s+(\w+):\s+(https?://\S+)", stripped)
                if m:
                    url_map[m.group(2)] = m.group(1)
                elif stripped and not stripped.startswith(" "):
                    in_urls = False
    return url_map


def transform(raw: str, url_map: dict[str, str]) -> str:
    """Strip anchors/aliases/filteredItems and substitute URLs."""
    lines = raw.splitlines()
    out: list[str] = []
    skip_filtered = False

    for line in lines:
        # Detect and skip the filteredItems block (it's just YAML aliases that
        # duplicate the items list and serve no purpose in the template).
        if re.match(r"^\s+filteredItems:\s*$", line):
            skip_filtered = True
            continue
        if skip_filtered:
            if re.match(r"^\s+-\s+\*", line) or line.strip() == "":
                continue
            skip_filtered = False

        # Strip YAML anchors – e.g. "      - &ref_0" → "      - <next key>"
        # We mark lines that reduced to a bare "- " so they can be merged below.
        line = re.sub(r"\s*&ref_\d+\b", "", line)

        # Replace live URLs with Helm template variables
        for url, key in url_map.items():
            line = line.replace(url, "{{ .Values.urls." + key + " }}")

        # Warn about any remaining bare URLs that have no mapping
        remaining = re.findall(r"https?://\S+", line)
        for u in remaining:
            print(f"  {YELLOW}WARNING: unmapped URL left as-is: {u}{RESET}", file=sys.stderr)

        out.append(line)

    # Merge bare list markers left by anchor stripping with the following line.
    # "      -\n            title: X"  →  "      - title: X"
    merged: list[str] = []
    i = 0
    while i < len(out):
        if re.match(r"^(\s+)-\s*$", out[i]) and i + 1 < len(out):
            indent = re.match(r"^(\s+)", out[i]).group(1)
            next_line = out[i + 1]
            # Strip extra indentation from the next line (it was indented under
            # the anchor) and merge onto the same line as the list marker.
            next_stripped = next_line.lstrip()
            merged.append(f"{indent}- {next_stripped}")
            i += 2
        else:
            merged.append(out[i])
            i += 1

    return "\n".join(merged).rstrip() + "\n"


def build_configmap(config_content: str) -> str:
    indented = "\n".join(
        "    " + l if l.strip() else ""
        for l in config_content.splitlines()
    )
    return CONFIGMAP_HEADER + indented + "\n"


def main() -> None:
    prompt_manual_export()

    print(f"  Reading {os.path.relpath(TEMP_CONFIG, REPO_ROOT)} ...")
    with open(TEMP_CONFIG) as f:
        raw = f.read()

    print(f"  Parsing URL map from {os.path.relpath(HELMRELEASE, REPO_ROOT)} ...")
    url_map = parse_url_map(HELMRELEASE)
    if not url_map:
        print(f"\n  {YELLOW}ERROR: No URLs found in helmrelease – aborting.{RESET}\n", file=sys.stderr)
        sys.exit(1)
    for url, key in url_map.items():
        print(f"    {CYAN}{url}{RESET}  →  {GREEN}{{{{ .Values.urls.{key} }}}}{RESET}")

    print(f"\n  Transforming config...")
    transformed = transform(raw, url_map)
    configmap = build_configmap(transformed)

    with open(CONFIGMAP, "w") as f:
        f.write(configmap)
    print(f"\n  {GREEN}{BOLD}✓ Written to {os.path.relpath(CONFIGMAP, REPO_ROOT)}{RESET}\n")


if __name__ == "__main__":
    main()
