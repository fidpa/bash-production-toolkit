#!/usr/bin/env bash
set -uo pipefail

# install.sh - Installation script for Bash Production Toolkit
# Usage: ./install.sh [--prefix DIR] [--skip-completion]

# Default installation directory
PREFIX="${HOME}/.local/share/bash-production-toolkit"
SKIP_COMPLETION=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --prefix)
            PREFIX="$2"
            shift 2
            ;;
        --skip-completion)
            SKIP_COMPLETION=true
            shift
            ;;
        --help|-h)
            cat <<EOF
Usage: ./install.sh [OPTIONS]

Install Bash Production Toolkit to your system.

OPTIONS:
    --prefix DIR         Installation directory (default: ~/.local/share/bash-production-toolkit)
    --skip-completion    Skip bash completion installation
    --help, -h           Show this help message

EXAMPLE:
    ./install.sh
    ./install.sh --prefix /opt/bash-toolkit
    ./install.sh --skip-completion

After installation, add to your .bashrc or .bash_profile:
    export BASH_PRODUCTION_TOOLKIT="${PREFIX}"
    source "\${BASH_PRODUCTION_TOOLKIT}/init.sh"
EOF
            exit 0
            ;;
        *)
            echo "Error: Unknown option: $1" >&2
            echo "Run './install.sh --help' for usage information." >&2
            exit 1
            ;;
    esac
done

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=== Bash Production Toolkit Installation ==="
echo "Installation directory: $PREFIX"
echo

# Create installation directory
if [[ ! -d "$PREFIX" ]]; then
    echo "Creating installation directory..."
    mkdir -p "$PREFIX" || {
        echo "Error: Failed to create directory $PREFIX" >&2
        exit 1
    }
fi

# Copy libraries
echo "Installing libraries..."
cp -r "$SCRIPT_DIR/src" "$PREFIX/" || {
    echo "Error: Failed to copy libraries" >&2
    exit 1
}

# Copy examples (optional)
if [[ -d "$SCRIPT_DIR/examples" ]]; then
    echo "Installing examples..."
    cp -r "$SCRIPT_DIR/examples" "$PREFIX/" || {
        echo "Warning: Failed to copy examples" >&2
    }
fi

# Copy documentation
if [[ -d "$SCRIPT_DIR/docs" ]]; then
    echo "Installing documentation..."
    cp -r "$SCRIPT_DIR/docs" "$PREFIX/" || {
        echo "Warning: Failed to copy documentation" >&2
    }
fi

# Create init script for easy sourcing
cat > "$PREFIX/init.sh" <<'INIT_SCRIPT'
#!/usr/bin/env bash
# init.sh - Initialize Bash Production Toolkit

# Get toolkit directory
TOOLKIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Export toolkit path
export BASH_PRODUCTION_TOOLKIT="$TOOLKIT_DIR"

# Add library path for easy sourcing
export BASH_TOOLKIT_LIB="${TOOLKIT_DIR}/src"
INIT_SCRIPT

chmod 644 "$PREFIX/init.sh"

echo
echo "✓ Installation complete!"
echo
echo "Next steps:"
echo "1. Add to your .bashrc or .bash_profile:"
echo "   export BASH_PRODUCTION_TOOLKIT=\"${PREFIX}\""
echo "   source \"\${BASH_PRODUCTION_TOOLKIT}/init.sh\""
echo
echo "2. Source libraries in your scripts:"
echo "   source \"\${BASH_TOOLKIT_LIB}/logging.sh\""
echo "   source \"\${BASH_TOOLKIT_LIB}/secure-file-utils.sh\""
echo
echo "3. Reload your shell:"
echo "   source ~/.bashrc"
echo

# Bash completion (optional)
if [[ "$SKIP_COMPLETION" == "false" ]]; then
    COMPLETION_DIR="${HOME}/.local/share/bash-completion/completions"
    if [[ -d "$COMPLETION_DIR" ]] || mkdir -p "$COMPLETION_DIR" 2>/dev/null; then
        echo "Note: Bash completion can be added manually if needed."
        echo "Completion directory: $COMPLETION_DIR"
    fi
fi

exit 0
