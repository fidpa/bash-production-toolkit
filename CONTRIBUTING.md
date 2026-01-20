# Contributing to Bash Production Toolkit

First off, thank you for considering contributing to Bash Production Toolkit! It's people like you that make this toolkit a great tool for the community.

## Code of Conduct

This project and everyone participating in it is governed by our [Code of Conduct](CODE_OF_CONDUCT.md). By participating, you are expected to uphold this code. Please report unacceptable behavior to the project maintainer.

## Getting Started

### Development Setup

1. **Fork the repository** on GitHub
2. **Clone your fork** locally:
   ```bash
   git clone https://github.com/YOUR_USERNAME/bash-production-toolkit.git
   cd bash-production-toolkit
   ```
3. **Install shellcheck** for linting:
   ```bash
   # Ubuntu/Debian
   sudo apt install shellcheck

   # macOS
   brew install shellcheck
   ```

### Project Structure

```
bash-production-toolkit/
├── src/              # Library source files
├── examples/         # Usage examples
├── docs/             # Documentation
└── config/           # Configuration files
```

## How to Contribute

### Reporting Bugs

Before creating bug reports, please check existing issues to avoid duplicates. When you create a bug report, include as many details as possible using the bug report template.

**Good bug reports include:**
- A clear and descriptive title
- Exact steps to reproduce the problem
- Expected vs. actual behavior
- Your environment (Bash version, OS, etc.)
- Relevant logs or error messages

### Suggesting Features

Feature requests are welcome! Please use the feature request template and provide:
- A clear description of the problem you're trying to solve
- Your proposed solution
- Any alternative solutions you've considered
- Why this feature would be useful to most users

### Pull Requests

1. **Create a feature branch** from `main`:
   ```bash
   git checkout -b feature/your-feature-name
   ```

2. **Make your changes** following our coding standards (see below)

3. **Test your changes**:
   ```bash
   # Run shellcheck on modified files
   shellcheck src/your-library.sh

   # Test examples
   bash examples/your-example.sh
   ```

4. **Commit your changes** with a clear commit message:
   ```bash
   git commit -m "Add feature: your feature description"
   ```

5. **Push to your fork**:
   ```bash
   git push origin feature/your-feature-name
   ```

6. **Open a Pull Request** on GitHub

## Coding Standards

### Bash Style Guidelines

- **ShellCheck**: All code must pass `shellcheck` with no warnings
- **Error Handling**: Use `set -uo pipefail` in all scripts
- **Quoting**: Always quote variables: `"$var"` not `$var`
- **Functions**: One responsibility per function (Single Responsibility Principle)
- **Comments**: Document complex logic and non-obvious decisions
- **Indentation**: 4 spaces (no tabs)

**Example:**
```bash
#!/usr/bin/env bash
set -uo pipefail

# Good: Properly quoted, error handling, clear function name
my_function() {
    local input="$1"
    if [[ -z "$input" ]]; then
        echo "Error: Input required" >&2
        return 1
    fi
    echo "Processing: $input"
}
```

### Documentation Standards

- **Function Documentation**: Document all public functions
- **Examples**: Include usage examples for new features
- **README**: Update README.md if adding new libraries or features
- **CHANGELOG**: Add entry to CHANGELOG.md (we follow [Keep a Changelog](https://keepachangelog.com/))

## Development Workflow

1. **Pick an issue** or create one for discussion
2. **Discuss approach** in the issue before major changes
3. **Implement changes** following coding standards
4. **Test thoroughly** - include edge cases
5. **Update documentation** as needed
6. **Submit PR** with clear description

## Release Process

Maintainers handle releases using semantic versioning (MAJOR.MINOR.PATCH):
- **MAJOR**: Breaking changes
- **MINOR**: New features (backward compatible)
- **PATCH**: Bug fixes

## Questions?

Don't hesitate to ask questions in:
- GitHub Issues (for project-related questions)
- Pull Request comments (for implementation details)

## Recognition

Contributors are listed in our README.md. Thank you for making this project better!
