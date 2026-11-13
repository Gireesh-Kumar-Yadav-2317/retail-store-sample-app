
#!/usr/bin/env bash

set -Eeuo pipefail

readonly SOURCE_DIR="src"

# --------------------------------------------------
# Validate source directory
# --------------------------------------------------

if [[ ! -d "$SOURCE_DIR" ]]; then
    echo "::error::Source directory '$SOURCE_DIR' does not exist."
    exit 1
fi

echo "======================================"
echo "Discovering application projects..."
echo "======================================"

# --------------------------------------------------
# Discover supported project manifests
# --------------------------------------------------

mapfile -t manifests < <(
    find "$SOURCE_DIR" \
        \( \
            -name .git \
            -o -name node_modules \
            -o -name target \
            -o -name vendor \
            -o -name dist \
            -o -name build \
        \) -prune -o \
        -type f \
        \( \
            -name pom.xml \
            -o -name go.mod \
            -o -name package.json \
        \) \
        -print | sort
)

if [[ ${#manifests[@]} -eq 0 ]]; then
    echo "::error::No supported project manifests were discovered."
    exit 1
fi

echo "Discovered ${#manifests[@]} project manifest(s)."

# --------------------------------------------------
# Process every discovered project
# --------------------------------------------------

for manifest in "${manifests[@]}"; do

    project_dir="$(dirname "$manifest")"

    echo
    echo "======================================"
    echo "Project: $project_dir"
    echo "Manifest: $manifest"
    echo "======================================"

    ROOT_DIR="$(git rev-parse --show-toplevel)"

    cd "$ROOT_DIR/$project_dir"

    # --------------------------------------------------
    # Java / Maven
    # --------------------------------------------------

    case "$manifest" in

        */pom.xml)

            echo "Technology detected: Java / Maven"

            if [[ -f ./mvnw ]]; then

                echo "Using Maven Wrapper"

                bash ./mvnw \
                    --batch-mode \
                    --no-transfer-progress \
                    clean verify

            elif command -v mvn >/dev/null 2>&1; then

                echo "Using system Maven"

                mvn \
                    --batch-mode \
                    --no-transfer-progress \
                    clean verify

            else

                echo "::error::Maven is not installed and Maven Wrapper is missing."
                exit 1

            fi

            echo "SUCCESS: $project_dir"
            ;;

        # --------------------------------------------------
        # Go
        # --------------------------------------------------

        */go.mod)

            echo "Technology detected: Go"

            if ! command -v go >/dev/null 2>&1; then
                echo "::error::Go is not installed."
                exit 1
            fi

            go test \
                -race \
                -count=1 \
                ./...

            echo "SUCCESS: $project_dir"
            ;;

        # --------------------------------------------------
        # Node.js
        # --------------------------------------------------

        */package.json)

            echo "Technology detected: Node.js"

            if ! command -v node >/dev/null 2>&1; then
                echo "::error::Node.js is not installed."
                exit 1
            fi

            if ! command -v corepack >/dev/null 2>&1; then
                echo "::error::Corepack is not available."
                exit 1
            fi

            # ----------------------------------------------
            # Detect package manager
            # ----------------------------------------------

            if [[ -f yarn.lock ]]; then

                PACKAGE_MANAGER="yarn"

            elif [[ -f pnpm-lock.yaml ]]; then

                PACKAGE_MANAGER="pnpm"

            elif [[ -f package-lock.json ]]; then

                PACKAGE_MANAGER="npm"

            else

                echo "::error::No supported lockfile found in $project_dir"
                exit 1

            fi

            echo "Package manager: $PACKAGE_MANAGER"

            # ----------------------------------------------
            # Install dependencies
            # ----------------------------------------------

            case "$PACKAGE_MANAGER" in

                yarn)

                    corepack yarn install --immutable
                    ;;

                pnpm)

                    corepack pnpm install --frozen-lockfile
                    ;;

                npm)

                    npm ci
                    ;;

            esac

            # ----------------------------------------------
            # Discover test script
            # ----------------------------------------------

            TEST_SCRIPT="$(
                node -e '
                    const pkg = require("./package.json");
                    const scripts = pkg.scripts || {};

                    if (scripts.test) {
                        console.log("test");
                    } else if (scripts.execute) {
                        console.log("execute");
                    }
                '
            )"

            if [[ -z "$TEST_SCRIPT" ]]; then

                echo "::error::No supported test script (test or execute) found in $project_dir"
                exit 1

            fi

            echo "Running Node.js script: $TEST_SCRIPT"

            # ----------------------------------------------
            # Execute tests
            # ----------------------------------------------

            case "$PACKAGE_MANAGER" in

                yarn)

                    corepack yarn run "$TEST_SCRIPT"
                    ;;

                pnpm)

                    corepack pnpm run "$TEST_SCRIPT"
                    ;;

                npm)

                    npm run "$TEST_SCRIPT"
                    ;;

            esac

            echo "SUCCESS: $project_dir"
            ;;

    esac

done

# --------------------------------------------------
# Completion
# --------------------------------------------------

echo
echo "======================================"
echo "All discovered project tests completed."
echo "======================================"
