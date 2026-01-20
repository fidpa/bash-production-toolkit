# Security Policy

## Reporting a Vulnerability

If you discover a security vulnerability in Bash Production Toolkit, please report it responsibly:

1. **Do NOT** open a public issue
2. **Use GitHub Security Advisories**: Navigate to the [Security tab](https://github.com/fidpa/bash-production-toolkit/security/advisories) and click "Report a vulnerability"
3. **Provide details**:
   - Description of the vulnerability
   - Steps to reproduce
   - Potential impact
   - Suggested fix (if available)

## Response Timeline

- **Initial Response**: Within 72 hours
- **Status Update**: Within 7 days
- **Fix Timeline**: Depends on severity (critical issues prioritized)

## Supported Versions

| Version | Supported          |
| ------- | ------------------ |
| 1.x.x   | :white_check_mark: |
| < 1.0   | :x:                |

## Security Best Practices

When using Bash Production Toolkit in production:

- **Always source libraries**: Never execute them directly
- **Validate inputs**: Check all user-provided data
- **Use secure permissions**: `chmod 644` for libraries, `600` for sensitive configs
- **Review logs**: Monitor for unexpected behavior
- **Keep updated**: Use the latest stable version

## Disclosure Policy

We follow responsible disclosure:
- Security issues are fixed before public disclosure
- Credit is given to reporters (unless they prefer anonymity)
- CVE IDs are assigned for critical vulnerabilities
