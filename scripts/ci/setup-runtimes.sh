
#!/usr/bin/env bash

set -Eeuo pipefail

readonly SOURCE_DIR="src"
readonly ROOT_DIR="$(git rev-parse --show-toplevel)"

if [[ ! -d "$ROOT_DIR/$SOURCE_DIR" ]]; then
    echo "::error::Source directory does not exist: $ROOT_DIR/$SOURCE_DIR"
    exit 1
fi

python3 - "$ROOT_DIR" "$SOURCE_DIR" <<'PY'
import json
import os
import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

root_dir = Path(sys.argv[1]).resolve()
source = (root_dir / sys.argv[2]).resolve()

versions = {
    "java": set(),
    "go": set(),
    "node": set(),
}

def fail(message):
    print(f"::error::{message}")
    sys.exit(1)


def local_name(tag):
    return tag.rsplit("}", 1)[-1]


def maven_java_version(path):
    try:
        root = ET.parse(path).getroot()
    except ET.ParseError as exc:
        fail(f"Invalid Maven XML: {path}: {exc}")

    properties = {}

    for element in root.iter():
        name = local_name(element.tag)

        if name in {
            "java.version",
            "maven.compiler.release",
            "maven.compiler.source",
            "jdk.version",
        }:
            properties[name] = (element.text or "").strip()

    for key in (
        "maven.compiler.release",
        "java.version",
        "maven.compiler.source",
        "jdk.version",
    ):
        value = properties.get(key, "")

        for _ in range(5):
            match = re.fullmatch(r"\$\{([^}]+)\}", value)

            if not match:
                break

            value = properties.get(match.group(1), "")

        if re.fullmatch(r"\d+(?:\.\d+)?", value):
            return value

    fail(f"No explicit Java version found in {path}")


def node_version(project_dir, package):
    current = project_dir

    # Search project directory and its parents for version files.
    while current == source or source in current.parents:

        for filename in (".nvmrc", ".node-version"):
            candidate = current / filename

            if candidate.is_file():
                value = candidate.read_text().strip().removeprefix("v")

                if re.fullmatch(r"\d+(?:\.\d+){0,2}", value):
                    return value

                fail(f"Invalid Node.js version in {candidate}: {value}")

        if current == source:
            break

        current = current.parent

    # Check package.json.
    engines = package.get("engines", {})
    value = engines.get("node", "").strip().removeprefix("v")

    if re.fullmatch(r"\d+(?:\.\d+){0,2}", value):
        return value

    # Check corresponding Dockerfile.
    service_name = project_dir.name
    dockerfile = root_dir / "docker" / service_name / "Dockerfile"

    if dockerfile.is_file():
        content = dockerfile.read_text()

        match = re.search(
            r"(?m)^\s*FROM\s+(?:--platform=\S+\s+)?node:(\d+(?:\.\d+){0,2})(?:[-@]|\s|$)",
            content
        )

        if match:
            return match.group(1)

    fail(
        f"No Node.js version found for {project_dir}. "
        "Add .nvmrc, .node-version, an exact engines.node version, "
        "or a Node.js base image in the corresponding Dockerfile."
    )


# Discover project manifests while pruning unnecessary directories.
excluded_dirs = {
    ".git",
    "node_modules",
    "target",
    "vendor",
    "dist",
    "build",
}

manifests = []

for current, directories, files in os.walk(source):
    directories[:] = sorted(
        directory
        for directory in directories
        if directory not in excluded_dirs
    )

    for filename in files:
        if filename in {"pom.xml", "go.mod", "package.json"}:
            manifests.append(Path(current) / filename)

manifests.sort()

if not manifests:
    fail("No supported project manifests discovered.")


# Detect required runtime versions.
for manifest in manifests:

    print(f"Inspecting project: {manifest.relative_to(root_dir)}")

    if manifest.name == "pom.xml":
        versions["java"].add(maven_java_version(manifest))

    elif manifest.name == "go.mod":
        content = manifest.read_text()

        match = re.search(
            r"(?m)^go\s+(\d+\.\d+(?:\.\d+)?)\s*$",
            content
        )

        if not match:
            fail(f"No valid Go version declaration in {manifest}")

        versions["go"].add(match.group(1))

    elif manifest.name == "package.json":
        try:
            package = json.loads(manifest.read_text())
        except json.JSONDecodeError as exc:
            fail(f"Invalid package.json: {manifest}: {exc}")

        versions["node"].add(
            node_version(manifest.parent, package)
        )


# This workflow currently supports one version per technology.
for technology, detected in versions.items():

    if len(detected) > 1:
        fail(
            f"Multiple {technology} versions discovered: "
            f"{', '.join(sorted(detected))}. "
            "This pipeline currently requires one version per technology."
        )


# Export versions to GitHub Actions.
output_file = os.environ.get("GITHUB_OUTPUT")

for technology, detected in versions.items():

    version = next(iter(detected), "")

    print(f"{technology}_version={version}")

    if output_file:
        with open(output_file, "a", encoding="utf-8") as output:
            output.write(f"{technology}_version={version}\n")


print("Runtime discovery completed successfully.")

PY
