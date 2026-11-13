
#!/usr/bin/env bash

set -Eeuo pipefail

readonly SOURCE_DIR="src"

if [[ ! -d "$SOURCE_DIR" ]]; then
    echo "::error::Source directory does not exist: $SOURCE_DIR"
    exit 1
fi

echo "Starting dynamic code quality analysis..."

mapfile -t manifests < <(
    find "$SOURCE_DIR" \
        \( -name node_modules -o -name target -o -name vendor -o -name dist \) -prune -o \
        -type f \
        \( -name pom.xml -o -name go.mod -o -name package.json \) \
        -print | sort
)

if [[ ${#manifests[@]} -eq 0 ]]; then
    echo "::error::No supported projects discovered."
    exit 1
fi

echo "Discovered ${#manifests[@]} project(s)."

readonly ROOT_DIR
ROOT_DIR="$(git rev-parse --show-toplevel)"

quality_checks=0
skipped_checks=0

for manifest in "${manifests[@]}"; do

    project_dir="$(dirname "$manifest")"
    absolute_project_dir="$ROOT_DIR/$project_dir"

    echo
    echo "======================================"
    echo "Quality analysis: $project_dir"
    echo "======================================"

    cd "$absolute_project_dir"

    case "$manifest" in

        */pom.xml)
            echo "Technology: Java / Maven"

            if grep -q "maven-checkstyle-plugin" pom.xml; then
                echo "Running Maven Checkstyle..."

                if [[ -x ./mvnw ]]; then
                    ./mvnw --batch-mode --no-transfer-progress checkstyle:check
                else
                    mvn --batch-mode --no-transfer-progress checkstyle:check
                fi

                ((quality_checks += 1))
            else
                echo "SKIPPED: Checkstyle is not configured in this POM."
                ((skipped_checks += 1))
            fi
            ;;

        */go.mod)
            echo "Technology: Go"

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

        */package.json)
            echo "Technology: Node.js"

            if ! command -v node >/dev/null 2>&1; then
                echo "::error::Node.js is not installed."
                exit 1
            fi

            if ! command -v npm >/dev/null 2>&1; then
                echo "::error::npm is not installed."
                exit 1
            fi

            if node -e '
                const p = require("./package.json");
                process.exit(p.scripts?.lint ? 0 : 1);
            '; then

                echo "Running configured ESLint/lint command..."
                npm run lint

                ((quality_checks += 1))
            else
                echo "SKIPPED: No lint script configured in package.json."
                ((skipped_checks += 1))
            fi
            ;;

    esac

    echo "Completed: $project_dir"

done

cd "$ROOT_DIR"

echo
echo "======================================"
echo "QUALITY ANALYSIS SUMMARY"
echo "======================================"

echo "Successful quality checks: $quality_checks"
echo "Skipped quality checks: $skipped_checks"

echo "Code quality analysis completed."
