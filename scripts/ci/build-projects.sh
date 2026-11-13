
#!/usr/bin/env bash

set -Eeuo pipefail

readonly SOURCE_DIR="src"
readonly EXCLUDED_DIRS=(
    node_modules
    target
    vendor
    dist
    build
    .git
)

readonly ROOT_DIR="$(git rev-parse --show-toplevel)"
readonly ROOT_SOURCE_DIR="$ROOT_DIR/$SOURCE_DIR"

success_count=0
failure_count=0

# --------------------------------------------------
# 1. Validate environment
# --------------------------------------------------

echo "Starting dynamic application builds..."

if [[ ! -d "$ROOT_SOURCE_DIR" ]]; then
    echo "::error::Source directory does not exist: $ROOT_SOURCE_DIR"
    exit 1
fi

for tool in git find sort; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "::error::Required command is unavailable: $tool"
        exit 1
    fi
done

# --------------------------------------------------
# 2. Discover projects
# --------------------------------------------------

find_args=("$ROOT_SOURCE_DIR")

for excluded_dir in "${EXCLUDED_DIRS[@]}"; do
    find_args+=(-name "$excluded_dir" -prune -o)
done

mapfile -t manifests < <(
    find "${find_args[@]}" \
        -type f \
        \( -name pom.xml -o -name go.mod -o -name package.json \) \
        -print | sort
)

if [[ ${#manifests[@]} -eq 0 ]]; then
    echo "::error::No supported projects discovered."
    exit 1
fi

echo "Discovered ${#manifests[@]} project(s)."

# --------------------------------------------------
# 3. Build projects
# --------------------------------------------------

for manifest in "${manifests[@]}"; do

    project_dir="$(dirname "$manifest")"
    project_path="$ROOT_DIR/$project_dir"

    echo
    echo "======================================"
    echo "Building: $project_dir"
    echo "======================================"

    cd "$project_path"

    case "$manifest" in

        */pom.xml)

            echo "Technology: Java / Maven"

            if [[ -x ./mvnw ]]; then
                ./mvnw \
                    --batch-mode \
                    --no-transfer-progress \
                    package

            elif command -v mvn >/dev/null 2>&1; then
                mvn \
                    --batch-mode \
                    --no-transfer-progress \
                    package

            else
                echo "::error::Maven is unavailable for $project_dir"
                exit 1
            fi

            shopt -s nullglob
            artifacts=(target/*.jar target/*.war)
            shopt -u nullglob

            if [[ ${#artifacts[@]} -eq 0 ]]; then
                echo "::error::No JAR or WAR artifact found in $project_dir"
                exit 1
            fi

            for artifact in "${artifacts[@]}"; do
                if [[ ! -s "$artifact" ]]; then
                    echo "::error::Empty build artifact: $artifact"
                    exit 1
                fi

                echo "Artifact: $artifact"
            done
            ;;

        */go.mod)

            echo "Technology: Go"

            if ! command -v go >/dev/null 2>&1; then
                echo "::error::Go is unavailable for $project_dir"
                exit 1
            fi

            go build -o build/application .

            if [[ ! -s build/application ]]; then
                echo "::error::Go build artifact is missing or empty."
                exit 1
            fi

            echo "Artifact: build/application"
            ;;

        */package.json)

            echo "Technology: Node.js"

            if ! command -v node >/dev/null 2>&1; then
                echo "::error::Node.js is unavailable for $project_dir"
                exit 1
            fi

            if ! node -e '
                const p = require("./package.json");
                process.exit(p.scripts?.build ? 0 : 1);
            '; then
                echo "::error::No build script configured in $project_dir/package.json"
                exit 1
            fi

            if [[ -f pnpm-lock.yaml ]]; then
                corepack pnpm run build

            elif [[ -f yarn.lock ]]; then
                corepack yarn build

            elif [[ -f package-lock.json ]]; then
                npm run build

            else
                echo "::error::No supported lockfile found in $project_dir"
                exit 1
            fi
            ;;

    esac

    ((success_count += 1))

    echo "SUCCESS: $project_dir"

done

# --------------------------------------------------
# 4. Build summary
# --------------------------------------------------

cd "$ROOT_DIR"

echo
echo "======================================"
echo "APPLICATION BUILD SUMMARY"
echo "======================================"

echo "Successful projects: $success_count"
echo "Failed projects: $failure_count"

echo "All discovered projects built successfully."
