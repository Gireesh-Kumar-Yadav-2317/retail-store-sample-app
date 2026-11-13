
#!/usr/bin/env bash

set -Eeuo pipefail

# --------------------------------------------------
# 1. Configuration
# --------------------------------------------------

readonly SOURCE_DIR="src"

readonly EXCLUDED_DIRS=(
    .git
    node_modules
    target
    vendor
    dist
    build
)

# --------------------------------------------------
# 2. Repository initialization
# --------------------------------------------------

if ! ROOT_DIR="$(git rev-parse --show-toplevel 2>/dev/null)"; then
    echo "::error::Unable to determine Git repository root."
    exit 1
fi

readonly ROOT_DIR
readonly ROOT_SOURCE_DIR="$ROOT_DIR/$SOURCE_DIR"

cd "$ROOT_DIR"

# Always return to the repository root when the script exits.
trap 'cd "$ROOT_DIR"' EXIT

success_count=0
failure_count=0

declare -a failed_projects=()

# --------------------------------------------------
# 3. Logging
# --------------------------------------------------

log_info() {
    echo "[INFO] $*"
}

log_error() {
    echo "::error::$*"
}

# --------------------------------------------------
# 4. Validate environment
# --------------------------------------------------

log_info "Starting dynamic application builds..."

if [[ ! -d "$ROOT_SOURCE_DIR" ]]; then
    log_error "Source directory does not exist: $ROOT_SOURCE_DIR"
    exit 1
fi

for tool in find sort dirname; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        log_error "Required command is unavailable: $tool"
        exit 1
    fi
done

# --------------------------------------------------
# 5. Discover projects
# --------------------------------------------------

find_args=("$ROOT_SOURCE_DIR")

for excluded_dir in "${EXCLUDED_DIRS[@]}"; do
    find_args+=(-name "$excluded_dir" -prune -o)
done

mapfile -t manifests < <(
    find "${find_args[@]}" \
        -type f \
        \( -name pom.xml -o -name go.mod -o -name package.json \) \
        -print |
        sort
)

if [[ ${#manifests[@]} -eq 0 ]]; then
    log_error "No supported projects discovered."
    exit 1
fi

log_info "Discovered ${#manifests[@]} project(s)."

# --------------------------------------------------
# 6. Build projects
# --------------------------------------------------

for manifest in "${manifests[@]}"; do

    project_dir="$(dirname "$manifest")"

    # find starts from ROOT_SOURCE_DIR, so manifest and
    # project_dir are already absolute paths.
    project_path="$project_dir"

    project_name="${project_dir#"$ROOT_DIR"/}"

    echo
    echo "======================================"
    echo "Building: $project_name"
    echo "======================================"

    if [[ ! -d "$project_path" ]]; then
        log_error "Project directory does not exist: $project_path"
        ((failure_count += 1))
        failed_projects+=("$project_name")
        continue
    fi

    cd "$project_path"

    build_succeeded=false

    case "$manifest" in

        */pom.xml)

            log_info "Technology: Java / Maven"

            if [[ -x ./mvnw ]]; then

                ./mvnw \
                    --batch-mode \
                    --no-transfer-progress \
                    package || continue

            elif command -v mvn >/dev/null 2>&1; then

                mvn \
                    --batch-mode \
                    --no-transfer-progress \
                    package || continue

            else
                log_error "Maven is unavailable for $project_name"
                ((failure_count += 1))
                failed_projects+=("$project_name")
                continue
            fi

            shopt -s nullglob
            artifacts=(target/*.jar target/*.war)
            shopt -u nullglob

            if [[ ${#artifacts[@]} -eq 0 ]]; then
                log_error "No JAR or WAR artifact found in $project_name"
                ((failure_count += 1))
                failed_projects+=("$project_name")
                continue
            fi

            build_succeeded=true

            for artifact in "${artifacts[@]}"; do
                if [[ ! -s "$artifact" ]]; then
                    log_error "Empty build artifact: $artifact"
                    build_succeeded=false
                    break
                fi

                log_info "Artifact: $artifact"
            done
            ;;

        */go.mod)

            log_info "Technology: Go"

            if ! command -v go >/dev/null 2>&1; then
                log_error "Go is unavailable for $project_name"
                ((failure_count += 1))
                failed_projects+=("$project_name")
                continue
            fi

            if ! go build -o build/application .; then
                log_error "Go build failed for $project_name"
                ((failure_count += 1))
                failed_projects+=("$project_name")
                continue
            fi

            if [[ ! -s build/application ]]; then
                log_error "Go build artifact is missing or empty."
                ((failure_count += 1))
                failed_projects+=("$project_name")
                continue
            fi

            log_info "Artifact: build/application"
            build_succeeded=true
            ;;

        */package.json)

            log_info "Technology: Node.js"

            if ! command -v node >/dev/null 2>&1; then
                log_error "Node.js is unavailable for $project_name"
                ((failure_count += 1))
                failed_projects+=("$project_name")
                continue
            fi

            if ! node -e '
                const p = require("./package.json");
                process.exit(p.scripts?.build ? 0 : 1);
            '; then
                log_error "No build script configured in $project_name/package.json"
                ((failure_count += 1))
                failed_projects+=("$project_name")
                continue
            fi

            if ! command -v corepack >/dev/null 2>&1; then
                log_error "Corepack is unavailable for $project_name"
                ((failure_count += 1))
                failed_projects+=("$project_name")
                continue
            fi

            if [[ -f yarn.lock ]]; then
                if ! corepack yarn build; then
                    log_error "Yarn build failed for $project_name"
                    ((failure_count += 1))
                    failed_projects+=("$project_name")
                    continue
                fi

            elif [[ -f pnpm-lock.yaml ]]; then
                if ! corepack pnpm run build; then
                    log_error "pnpm build failed for $project_name"
                    ((failure_count += 1))
                    failed_projects+=("$project_name")
                    continue
                fi

            elif [[ -f package-lock.json ]]; then
                if ! npm run build; then
                    log_error "npm build failed for $project_name"
                    ((failure_count += 1))
                    failed_projects+=("$project_name")
                    continue
                fi

            else
                log_error "No supported lockfile found in $project_name"
                ((failure_count += 1))
                failed_projects+=("$project_name")
                continue
            fi

            build_succeeded=true
            ;;

    esac

    if [[ "$build_succeeded" == true ]]; then
        ((success_count += 1))
        log_info "SUCCESS: $project_name"
    else
        log_error "Build artifact validation failed: $project_name"
        ((failure_count += 1))
        failed_projects+=("$project_name")
    fi

done

# --------------------------------------------------
# 7. Build summary
# --------------------------------------------------

echo
echo "======================================"
echo "APPLICATION BUILD SUMMARY"
echo "======================================"

echo "Discovered projects: ${#manifests[@]}"
echo "Successful projects: $success_count"
echo "Failed projects: $failure_count"

if [[ ${#failed_projects[@]} -gt 0 ]]; then
    echo
    echo "Failed projects:"

    printf ' - %s\n' "${failed_projects[@]}"

    log_error "One or more application builds failed."
    exit 1
fi

log_info "All discovered projects built successfully."
