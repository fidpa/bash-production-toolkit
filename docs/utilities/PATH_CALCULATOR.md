# Path Calculator Library (v1.1)

Utilities for relative path calculation, path validation, and markdown-aware path operations. Useful for documentation tools, link validators, and build systems.

## Quick Start

```bash
#!/bin/bash
set -euo pipefail

source /path/to/utilities/path-calculator.sh

# Calculate relative path between files
relative=$(calculate_relative_path \
    "/docs/how-to/setup.md" \
    "/docs/reference/api.md")
echo "$relative"  # ../reference/api.md

# Validate path exists
if validate_path_exists "/etc/myapp/config.yaml" "file"; then
    echo "Config found"
fi

# Normalize markdown path
normalized=$(normalize_markdown_path "README#installation")
echo "$normalized"  # README.md (anchor to stderr)
```

## Installation

```bash
source /path/to/bash-production-toolkit/src/utilities/path-calculator.sh
```

## API Reference

### calculate_relative_path

```bash
relative=$(calculate_relative_path "source_path" "target_path")
```

Calculate the relative path from source to target.

**Parameters:**
| Parameter | Description |
|-----------|-------------|
| source_path | Path to start from |
| target_path | Path to reach |

**Returns:** Relative path string

**Example:**
```bash
# Same directory
calculate_relative_path "/docs/a.md" "/docs/b.md"
# Output: b.md

# Parent directory
calculate_relative_path "/docs/how-to/guide.md" "/docs/README.md"
# Output: ../README.md

# Deep nesting
calculate_relative_path "/docs/tutorial/basic/intro.md" "/docs/reference/api/core.md"
# Output: ../../reference/api/core.md
```

### validate_path_exists

```bash
if validate_path_exists "path" [type]; then
    echo "Path exists"
fi
```

Validate that a path exists with optional type checking.

**Parameters:**
| Parameter | Default | Description |
|-----------|---------|-------------|
| path | (required) | Path to validate |
| type | `any` | Expected type: `file`, `dir`, or `any` |

**Returns:** 0 if valid, 1 if invalid

**Checks:**
- Path exists
- Type matches (if specified)
- Path is readable
- Directories are executable (traversable)

**Example:**
```bash
# Check file exists
if validate_path_exists "/etc/passwd" "file"; then
    echo "File found"
fi

# Check directory exists
if validate_path_exists "/var/log" "dir"; then
    echo "Directory found"
fi

# Check any path exists
if validate_path_exists "/some/path"; then
    echo "Path exists (file or directory)"
fi
```

### normalize_markdown_path

```bash
normalized=$(normalize_markdown_path "path")
# Anchor (if present) written to stderr
```

Normalize a markdown path: add `.md` extension and extract anchor.

**Parameters:**
| Parameter | Description |
|-----------|-------------|
| path | Markdown path (with or without extension/anchor) |

**Output:**
- stdout: Normalized path (with .md extension)
- stderr: Anchor (if present)

**Example:**
```bash
# Add .md extension
normalize_markdown_path "README"
# stdout: README.md

# Already has extension
normalize_markdown_path "guide.md"
# stdout: guide.md

# Extract anchor
normalize_markdown_path "guide#installation"
# stdout: guide.md
# stderr: installation

# Capture both
path=$(normalize_markdown_path "README#usage" 2>&1)
# path="README.md installation"
```

### calculate_path_depth

```bash
depth=$(calculate_path_depth "path")
```

Count directory nesting level.

**Example:**
```bash
calculate_path_depth "/"
# Output: 0

calculate_path_depth "docs/README.md"
# Output: 1

calculate_path_depth "docs/how-to/network/setup.md"
# Output: 3
```

### to_project_relative

```bash
relative=$(to_project_relative "/absolute/path" [project_root])
```

Convert absolute path to project-relative.

**Parameters:**
| Parameter | Default | Description |
|-----------|---------|-------------|
| path | (required) | Absolute path to convert |
| project_root | (auto-detected) | Project root directory |

**Auto-detection:** Searches upward for `.git` directory.

**Example:**
```bash
# Auto-detect project root
to_project_relative "/home/user/myproject/src/main.py"
# Output: src/main.py

# Explicit project root
to_project_relative "/opt/app/lib/utils.sh" "/opt/app"
# Output: lib/utils.sh
```

### is_docs_path

```bash
if is_docs_path "path" [docs_dir]; then
    echo "Path is in documentation"
fi
```

Check if path is within documentation directory.

**Parameters:**
| Parameter | Default | Description |
|-----------|---------|-------------|
| path | (required) | Path to check |
| docs_dir | `${PROJECT_ROOT}/docs` | Documentation directory |

**Example:**
```bash
# Check default docs directory
is_docs_path "docs/README.md"  # Returns 0 (true)
is_docs_path "src/main.py"     # Returns 1 (false)

# Custom docs directory
is_docs_path "manual/guide.md" "manual"  # Returns 0 (true)
```

## Configuration

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `VERBOSE` | `false` | Enable debug output |
| `PROJECT_ROOT` | (auto-detected) | Project root directory |
| `PC_DISABLE_LOGGING` | (unset) | Disable logging.sh integration |

### Logging Integration

If `logging.sh` is sourced, the library uses it for logging. Otherwise, fallback functions are provided:

```bash
# With logging.sh
source /path/to/logging.sh
source /path/to/path-calculator.sh
# Uses log_debug, log_error from logging.sh

# Without logging.sh
source /path/to/path-calculator.sh
# Uses internal pc_log_debug, pc_log_error
```

## Examples

### Link Validator

```bash
#!/bin/bash
set -euo pipefail

source /path/to/path-calculator.sh

validate_markdown_links() {
    local file="$1"
    local dir
    dir=$(dirname "$file")

    # Extract markdown links: [text](path)
    grep -oP '\[.*?\]\(\K[^)]+' "$file" | while read -r link; do
        # Skip external links
        [[ "$link" =~ ^https?:// ]] && continue

        # Normalize path
        normalized=$(normalize_markdown_path "$link" 2>/dev/null)

        # Build absolute path
        target="${dir}/${normalized}"

        # Validate
        if ! validate_path_exists "$target" "file"; then
            echo "Broken link in ${file}: ${link}"
        fi
    done
}

# Validate all markdown files
find docs -name "*.md" | while read -r file; do
    validate_markdown_links "$file"
done
```

### Relative Link Fixer

```bash
#!/bin/bash
set -euo pipefail

source /path/to/path-calculator.sh

fix_absolute_links() {
    local file="$1"
    local project_root
    project_root=$(git rev-parse --show-toplevel)

    while IFS= read -r line; do
        # Find absolute paths in links
        if [[ "$line" =~ \]\((/[^)]+)\) ]]; then
            abs_path="${BASH_REMATCH[1]}"

            # Calculate relative path
            rel_path=$(calculate_relative_path "$file" "${project_root}${abs_path}")

            # Replace in line
            line="${line//](${abs_path})/](${rel_path})}"
        fi
        echo "$line"
    done < "$file"
}

# Fix all markdown files
find docs -name "*.md" -exec bash -c 'fix_absolute_links "$0" > "$0.tmp" && mv "$0.tmp" "$0"' {} \;
```

### Documentation TOC Generator

```bash
#!/bin/bash
set -euo pipefail

source /path/to/path-calculator.sh

generate_toc() {
    local docs_dir="${1:-docs}"
    local output="${2:-docs/TOC.md}"

    echo "# Table of Contents" > "$output"
    echo "" >> "$output"

    find "$docs_dir" -name "*.md" ! -name "TOC.md" | sort | while read -r file; do
        # Get depth for indentation
        depth=$(calculate_path_depth "$file")
        indent=$(printf '%*s' $((depth * 2)) '')

        # Get title from first heading
        title=$(grep -m1 '^#' "$file" | sed 's/^#* //')

        # Calculate relative link from TOC
        rel_link=$(calculate_relative_path "$output" "$file")

        echo "${indent}- [${title}](${rel_link})" >> "$output"
    done
}

generate_toc docs docs/TOC.md
```

### Breadcrumb Generator

```bash
#!/bin/bash
set -euo pipefail

source /path/to/path-calculator.sh

generate_breadcrumbs() {
    local file="$1"
    local project_root
    project_root=$(git rev-parse --show-toplevel)

    # Get relative path
    rel_path=$(to_project_relative "$file" "$project_root")

    # Build breadcrumb
    breadcrumb=""
    current=""

    IFS='/' read -ra parts <<< "$rel_path"
    for part in "${parts[@]}"; do
        if [[ -z "$current" ]]; then
            current="$part"
        else
            current="${current}/${part}"
        fi

        # Add separator
        [[ -n "$breadcrumb" ]] && breadcrumb+=" > "

        # Add link
        if [[ "$part" == *.md ]]; then
            name="${part%.md}"
            breadcrumb+="**${name}**"
        else
            breadcrumb+="[${part}]($(calculate_relative_path "$file" "${project_root}/${current}/README.md"))"
        fi
    done

    echo "$breadcrumb"
}

# Usage
generate_breadcrumbs "/project/docs/how-to/network/setup.md"
# Output: [docs](../../README.md) > [how-to](../README.md) > [network](README.md) > **setup**
```

### Cross-Reference Checker

```bash
#!/bin/bash
set -euo pipefail

source /path/to/path-calculator.sh

check_cross_references() {
    local file="$1"

    # Find all internal links
    grep -oP '\[.*?\]\(\K[^)#]+' "$file" 2>/dev/null | while read -r link; do
        # Skip external links
        [[ "$link" =~ ^https?:// ]] && continue

        # Skip anchors
        [[ "$link" =~ ^# ]] && continue

        # Normalize and validate
        normalized=$(normalize_markdown_path "$link" 2>/dev/null)
        target_dir=$(dirname "$file")
        target="${target_dir}/${normalized}"

        if ! validate_path_exists "$target"; then
            echo "Missing: ${file} -> ${link}"
        fi
    done
}

# Check all files
find docs -name "*.md" | while read -r file; do
    check_cross_references "$file"
done
```

## Self-Test

Run the library directly to execute built-in tests:

```bash
# Run tests
bash /path/to/path-calculator.sh

# With verbose output
VERBOSE=true bash /path/to/path-calculator.sh
```

## Technical Notes

### Path Resolution

Uses `realpath -m` for path resolution:
- `-m`: No-require mode (handles non-existent paths)
- Resolves symlinks
- Normalizes `.` and `..`

### Depth Calculation

Uses IFS-based splitting for efficiency:

```bash
# Internal implementation
IFS='/' read -ra parts <<< "$path"
depth=${#parts[@]}
```

This is simpler and faster than `tr` or `awk` approaches.

## See Also

- [ARCHITECTURE.md](../ARCHITECTURE.md) - Dependency information
- [LOGGING.md](../foundation/LOGGING.md) - Optional logging integration
