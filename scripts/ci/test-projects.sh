
#!/usr/bin/env bash

set -Eeuo pipefail

readonly SOURCE_DIR="src"
readonly ROOT_DIR="$(git rev-parse --show-toplevel)"

cd "$ROOT_DIR"

# --------------------------------------------------
# Validate repository
# --------------------------------------------------

if [[ ! -d "$SOURCE_DIR" ]]; then
    echo "::error::Source directory '$SOURCE_DIR' does not exist."
    exit 1
fi

echo "======================================"
echo "Discovering application test projects"
echo "======================================"

# E2E tests are deliberately excluded.
# They run in a separate job where the application is started.

mapfile -t manifests < <(
    find "$SOURCE_DIR" \
        \( \
            -name .git \
            -o -name node_modules \
            -o -name target \
            -o -name vendor \
            -o -name dist \
            -o -name build \
            -o -path "$SOURCE_DIR/e2e" \
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
    echo "::error::No supported application projects discovered."
    exit 1
fi

echo "Discovered ${#manifests[@]} application project(s)."

# --------------------------------------------------
# Test each discovered project
# --------------------------------------------------

tested_projects=0
skipped_projects=0

for manifest in "${manifests[@]}"; do

    project_dir="$(dirname "$manifest")"

    cd "$ROOT_DIR/$project_dir"

    echo
    echo "======================================"
    echo "Project: $project_dir"
    echo "======================================"

    case "$manifest" in

        # ------------------------------------------
        # Java / Maven
        # ------------------------------------------

        */pom.xml)

            echo "Technology: Java / Maven"

            if [[ -f ./mvnw ]]; then

                bash ./mvnw \
                    --batch-mode \
                    --no-transfer-progress \
                    clean verify

            elif command -v mvn >/dev/null 2>&1; then

                mvn \
                    --batch-mode \
                    --no-transfer-progress \
                    clean verify

            else

                echo "::error::Maven and Maven Wrapper are unavailable."
                exit 1

            fi

            ((tested_projects += 1))
            ;;

        # ------------------------------------------
        # Go
        # ------------------------------------------

        */go.mod)

            echo "Technology: Go"

            if ! command -v go >/dev/null 2>&1; then
                echo "::error::Go is not installed."
                exit 1
            fi

            go test -race -count=1 ./...

            ((tested_projects += 1))
            ;;

        # ------------------------------------------
        # Node.js
        # ------------------------------------------

        */package.json)

            echo "Technology: Node.js"

            if ! command -v node >/dev/null 2>&1; then
                echo "::error::Node.js is not installed."
                exit 1
            fi

            # Only run actual test scripts.
            # Do not run "execute" because that may launch Cypress.

            if ! node -e '
                const pkg = require("./package.json");
                process.exit(pkg.scripts?.test ? 0 : 1);
            '; then

                echo "No test script configured. Skipping: $project_dir"
                ((skipped_projects += 1))
                continue

            fi

            # --------------------------------------
            # Detect package manager from lockfile
            # --------------------------------------

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

            # --------------------------------------
            # Install locked dependencies
            # --------------------------------------

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

            # --------------------------------------
            # Run application tests
            # --------------------------------------

            case "$PACKAGE_MANAGER" in

                yarn)
                    corepack yarn run test
                    ;;

                pnpm)
                    corepack pnpm run test
                    ;;

                npm)
                    npm run test
                    ;;

            esac

            ((tested_projects += 1))
            ;;

    esac

done

# --------------------------------------------------
# Test summary
# --------------------------------------------------

echo
echo "======================================"
echo "Application test execution completed"
echo "======================================"

echo "Projects tested : $tested_projects"
echo "Projects skipped: $skipped_projects"

if [[ "$tested_projects" -eq 0 ]]; then
    echo "::error::No application test projects were executed."
    exit 1
fi
