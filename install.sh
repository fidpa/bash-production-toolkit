#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2024 Marc Allgeier
set -uo pipefail

# install.sh - Installation script for Bash Production Toolkit
# Usage: ./install.sh [--prefix DIR] [--skip-completion]

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

warn() {
    echo -e "${YELLOW}[WARNING]${NC} $*" >&2
}

error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*"
}

# Prerequisites check
check_prerequisites() {
    log "Checking prerequisites..."

    # Check Bash version (require 4.0+)
    if [[ "${BASH_VERSINFO[0]}" -lt 4 ]]; then
        error "Bash 4.0+ required (found: ${BASH_VERSION})"
        exit 1
    fi
    success "Bash version: ${BASH_VERSION}"

    # Check required commands
    local required_commands=("mkdir" "cp" "chmod" "cat")
    for cmd in "${required_commands[@]}"; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            error "Required command not found: $cmd"
            exit 1
        fi
    done
    success "All required commands available"
}

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
            error "Unknown option: $1"
            echo "Run './install.sh --help' for usage information." >&2
            exit 1
            ;;
    esac
done

# Check prerequisites before installation
check_prerequisites

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo
echo -e "${BLUE}=== Bash Production Toolkit Installation ===${NC}"
log "Installation directory: $PREFIX"
echo

# Create installation directory
if [[ ! -d "$PREFIX" ]]; then
    log "Creating installation directory..."
    mkdir -p "$PREFIX" || {
        error "Failed to create directory $PREFIX"
        exit 1
    }
fi

# Copy libraries
log "Installing libraries..."
cp -r "$SCRIPT_DIR/src" "$PREFIX/" || {
    error "Failed to copy libraries"
    exit 1
}

# Copy examples (optional)
if [[ -d "$SCRIPT_DIR/examples" ]]; then
    log "Installing examples..."
    cp -r "$SCRIPT_DIR/examples" "$PREFIX/" || {
        warn "Failed to copy examples"
    }
fi

# Copy documentation
if [[ -d "$SCRIPT_DIR/docs" ]]; then
    log "Installing documentation..."
    cp -r "$SCRIPT_DIR/docs" "$PREFIX/" || {
        warn "Failed to copy documentation"
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
success "Installation complete!"
echo
echo -e "${BLUE}Next steps:${NC}"
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
        log "Bash completion can be added manually if needed."
        log "Completion directory: $COMPLETION_DIR"
    fi
fi

exit 0
