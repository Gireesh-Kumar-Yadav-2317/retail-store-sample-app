
#!/usr/bin/env bash

set -Eeuo pipefail

readonly SOURCE_DIR="src"
readonly ROOT_DIR="$(git rev-parse --show-toplevel)"

cd "$ROOT_DIR"

# --------------------------------------------------
# Validate repository
# --------------------------------------------------

if [[ ! -d "$SOURCE_DIR" ]]; then
    echo "::error::Source directory does not exist: $SOURCE_DIR"
    exit 1
fi

echo "Starting dynamic code quality analysis..."

# --------------------------------------------------
# Discover application projects
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
    echo "::error::No supported projects discovered."
    exit 1
fi

echo "Discovered ${#manifests[@]} project(s)."

quality_checks=0
skipped_checks=0

# --------------------------------------------------
# Analyze each discovered project
# --------------------------------------------------

for manifest in "${manifests[@]}"; do

    project_dir="$(dirname "$manifest")"
    absolute_project_dir="$ROOT_DIR/$project_dir"

    echo
    echo "======================================"
    echo "Quality analysis: $project_dir"
    echo "======================================"

    cd "$absolute_project_dir"

    case "$manifest" in

        # ------------------------------------------
        # Java / Maven
        # ------------------------------------------

        */pom.xml)

            echo "Technology: Java / Maven"

            if grep -q "maven-checkstyle-plugin" pom.xml; then

                echo "Running Maven Checkstyle..."

                if [[ -x ./mvnw ]]; then
                    ./mvnw \
                        --batch-mode \
                        --no-transfer-progress \
                        checkstyle:check

                elif command -v mvn >/dev/null 2>&1; then
                    mvn \
                        --batch-mode \
                        --no-transfer-progress \
                        checkstyle:check

                else
                    echo "::error::Maven and Maven Wrapper are unavailable."
                    exit 1
                fi

                ((quality_checks += 1))

            else

                echo "SKIPPED: Checkstyle is not configured."
                ((skipped_checks += 1))

            fi
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

            echo "Running go vet..."
            go vet ./...

            echo "Checking Go formatting..."

            unformatted_files="$(gofmt -l .)"

            if [[ -n "$unformatted_files" ]]; then
                echo "::error::Go files require formatting:"
                printf '%s\n' "$unformatted_files"
                exit 1
            fi

            ((quality_checks += 1))
            ;;

        # ------------------------------------------
        # Node.js
        # ------------------------------------------

        */package.json)

            echo "Technology: Node.js"

            # Verify Node.js availability.

            if ! command -v node >/dev/null 2>&1; then
                echo "::error::Node.js is not installed."
                exit 1
            fi

            # Verify Corepack availability.

            if ! command -v corepack >/dev/null 2>&1; then
                echo "::error::Corepack is unavailable."
                exit 1
            fi

            # --------------------------------------
            # Detect configured lint script
            # --------------------------------------

            if ! node -e '
                const pkg = require("./package.json");
                process.exit(pkg.scripts?.lint ? 0 : 1);
            '; then

                echo "SKIPPED: No lint script configured."
                ((skipped_checks += 1))
                continue

            fi

            # --------------------------------------
            # Detect package manager
            # --------------------------------------

            PACKAGE_MANAGER="$(node -p \
                "require('./package.json').packageManager || ''")"

            if [[ -z "$PACKAGE_MANAGER" ]]; then
                echo "::error::packageManager is not declared in package.json."
                exit 1
            fi

            case "$PACKAGE_MANAGER" in

                yarn@*)
                    PACKAGE_MANAGER_NAME="yarn"

                    if [[ ! -f yarn.lock ]]; then
                        echo "::error::Yarn lockfile is missing."
                        exit 1
                    fi
                    ;;

                pnpm@*)
                    PACKAGE_MANAGER_NAME="pnpm"

                    if [[ ! -f pnpm-lock.yaml ]]; then
                        echo "::error::pnpm lockfile is missing."
                        exit 1
                    fi
                    ;;

                npm@*)
                    PACKAGE_MANAGER_NAME="npm"

                    if [[ ! -f package-lock.json ]]; then
                        echo "::error::npm lockfile is missing."
                        exit 1
                    fi
                    ;;

                *)
                    echo "::error::Unsupported package manager: $PACKAGE_MANAGER"
                    exit 1
                    ;;

            esac

            echo "Package manager: $PACKAGE_MANAGER"

            # --------------------------------------
            # Install locked dependencies
            # --------------------------------------

            echo "Installing locked dependencies..."

            case "$PACKAGE_MANAGER_NAME" in

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
            # Run configured lint command
            # --------------------------------------

            echo "Running configured lint command..."

            case "$PACKAGE_MANAGER_NAME" in

                yarn)
                    corepack yarn run lint
                    ;;

                pnpm)
                    corepack pnpm run lint
                    ;;

                npm)
                    npm run lint
                    ;;

            esac

            ((quality_checks += 1))
            ;;

    esac

    echo "Completed: $project_dir"

done

# --------------------------------------------------
# Quality analysis summary
# --------------------------------------------------

cd "$ROOT_DIR"

echo
echo "======================================"
echo "QUALITY ANALYSIS SUMMARY"
echo "======================================"

echo "Successful quality checks: $quality_checks"
echo "Skipped quality checks: $skipped_checks"

if [[ "$quality_checks" -eq 0 ]]; then
    echo "::error::No quality checks were executed."
    exit 1
fi

echo "Code quality analysis completed."
