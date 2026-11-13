#!/usr/bin/env bash

set -Eeuo pipefail

readonly SOURCE_DIR="src"

if [[ ! -d "$SOURCE_DIR" ]]; then
    echo "::error::Source directory '$SOURCE_DIR' does not exist."
    exit 1
fi

echo "Discovering application projects..."

mapfile -t manifests < <(
    find "$SOURCE_DIR" \
        \( -name node_modules -o -name target -o -name vendor -o -name dist \) -prune -o \
        -type f \
        \( -name pom.xml -o -name go.mod -o -name package.json \) \
        -print | sort
)

if [[ ${#manifests[@]} -eq 0 ]]; then
    echo "::error::No supported project manifests were discovered."
    exit 1
fi

echo "Discovered ${#manifests[@]} project manifest(s)."

for manifest in "${manifests[@]}"; do
    project_dir="$(dirname "$manifest")"

    echo
    echo "======================================"
    echo "Project: $project_dir"
    echo "Manifest: $manifest"
    echo "======================================"

    cd "$(git rev-parse --show-toplevel)/$project_dir"

    case "$manifest" in

        */pom.xml)
            echo "Technology detected: Java / Maven"

            if [[ -x ./mvnw ]]; then
                ./mvnw --batch-mode --no-transfer-progress clean verify
            elif command -v mvn >/dev/null 2>&1; then
                mvn --batch-mode --no-transfer-progress clean verify
            else
                echo "::error::Maven or Maven Wrapper is unavailable."
                exit 1
            fi
            ;;

        */go.mod)
            echo "Technology detected: Go"

            go test -race -count=1 ./...
            ;;

        */package.json)
            echo "Technology detected: Node.js"

            if ! python3 -c \
                'import json; import sys; p=json.load(open("package.json")); sys.exit(0 if p.get("scripts", {}).get("test") else 1)'
            then
                echo "::error::Missing test script in $project_dir/package.json"
                exit 1
            fi

            if [[ -f pnpm-lock.yaml ]]; then
                corepack pnpm install --frozen-lockfile
                corepack pnpm test

            elif [[ -f yarn.lock ]]; then
                corepack yarn install --immutable
                corepack yarn test

            elif [[ -f package-lock.json ]]; then
                npm ci
                npm test

            else
                echo "::error::No supported dependency lockfile found in $project_dir"
                exit 1
            fi
            ;;

    esac

    echo "SUCCESS: $project_dir"
done

cd "$(git rev-parse --show-toplevel)"

echo
echo "All discovered projects passed their test commands."
