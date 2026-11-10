# Contributing to NewTerminal-AI 🤝

Thank you for your interest in contributing to NewTerminal-AI! We welcome contributions from developers of all skill levels. This guide will help you get started.

## 🚀 Quick Start

1. **Fork the repository** on GitHub
2. **Clone your fork** locally:
   ```bash
   git clone https://github.com/<your-username>/NewTerminal-AI.git
   cd NewTerminal-AI
   ```
3. **Create a feature branch**:
   ```bash
   git checkout -b feature/your-feature-name
   ```
4. **Make your changes** and test them
5. **Submit a pull request**

## 🛠️ Development Setup

### Prerequisites
- PowerShell 7+ (`pwsh`) on Windows, macOS or Linux, and Git
- [Pester](https://pester.dev) 5.7.1 and PSScriptAnalyzer 1.25.0 (the versions CI uses)
- [Ollama](https://ollama.com) with a model such as `llama3.2:1b`, only for trying the tool by hand.
  The automated tests mock every Ollama call.

### Local Development

1. **Install the test tools**:
   ```powershell
   Install-Module Pester -RequiredVersion 5.7.1 -Scope CurrentUser -Force -SkipPublisherCheck
   Install-Module PSScriptAnalyzer -RequiredVersion 1.25.0 -Scope CurrentUser -Force
   ```

2. **Run lint and tests** (no Ollama needed):
   ```powershell
   ./tools/Invoke-Lint.ps1
   Invoke-Pester -Path ./tests
   ```

3. **Try the module by hand** (needs Ollama running and a pulled model):
   ```powershell
   $env:NEWTERMINAL_AI_NO_AUTOSTART = '1'   # load the commands without starting the AI> prompt
   Import-Module ./NewTerminal-AI.psm1 -Force
   aia "list files"
   ```

## 📋 Contribution Guidelines

### Code Style

#### PowerShell
- Use **PascalCase** for function names
- Use **camelCase** for variable names
- Include **comment-based help** for all functions
- Follow **PowerShell best practices**
- Use **Write-Host** with colors for user-facing output

#### Shell Scripts
- Use **snake_case** for function and variable names
- Include **function documentation**
- Follow **POSIX compliance** where possible
- Use **proper error handling** with `set -e`
- Include **color output** for better UX

#### General
- **Consistent indentation** (4 spaces for PowerShell, 2 spaces for shell)
- **Clear, descriptive variable names**
- **Comprehensive error handling**
- **User-friendly error messages**

### Commit Messages

Use the [Conventional Commits](https://www.conventionalcommits.org/) format:

```
type(scope): description

[optional body]

[optional footer]
```

**Types:**
- `feat`: New feature
- `fix`: Bug fix
- `docs`: Documentation changes
- `style`: Code style changes (formatting, etc.)
- `refactor`: Code refactoring
- `test`: Adding or updating tests
- `chore`: Maintenance tasks

**Examples:**
```
feat(ai): add support for custom AI models
fix(windows): resolve PowerShell execution policy issue
docs(readme): update installation instructions
```

## 🧪 Testing

### Manual Testing Checklist

Before submitting a PR, please test:

#### Core Functionality
- [ ] `aia "list files"` - Auto-execution works
- [ ] `ai "create test file"` - Interactive mode works
- [ ] `nl` - Natural language mode starts and responds
- [ ] Command history functionality
- [ ] Error handling for invalid commands
- [ ] Safety checks for dangerous commands

#### Cross-Platform (if applicable)
- [ ] Windows: PowerShell 7 and Windows PowerShell 5.1
- [ ] macOS and Linux: PowerShell 7 (`pwsh`)
- [ ] Installation scripts work correctly (`install.ps1`, `install.sh`)

#### Edge Cases
- [ ] Ollama not running
- [ ] Invalid AI model
- [ ] Network connectivity issues
- [ ] Large command outputs
- [ ] Special characters in commands

### Automated Testing

CI runs PSScriptAnalyzer and the Pester suite on Ubuntu and Windows, plus a gitleaks secret scan.
A pull request has to keep all three green.

- `tests/NewTerminal-AI.Tests.ps1`: module behaviour (Ollama calls are mocked).
- `tests/SafetyGate.Tests.ps1`: one row per command the safety gate must flag or allow.
- `tests/Repo.Tests.ps1`: file encodings, the sample profile, and the installers
  (`install.sh` runs in a throwaway `HOME` with stub tools; nothing is installed).

Rules for changes:

1. **A bug fix comes with a test that fails without the fix.** Tag it `Regression`.
2. **A change to the safety gate comes with rows in `tests/SafetyGate.Tests.ps1`**: the command that
   got through (or was wrongly blocked), and nearby everyday commands that must keep working.
3. The gate must stay static and fail closed: no lookups on the machine it runs on, and anything it
   cannot parse or analyse is flagged.
4. PowerShell files that contain non-ASCII characters must be saved as UTF-8 **with** a byte order
   mark, otherwise Windows PowerShell 5.1 cannot parse them. `tests/Repo.Tests.ps1` checks this.

## 🐛 Bug Reports

When reporting bugs, please include:

1. **Environment details**:
   - OS and version
   - PowerShell/Shell version
   - Ollama version
   - AI model being used

2. **Steps to reproduce**:
   - Exact commands used
   - Expected behavior
   - Actual behavior

3. **Error messages**:
   - Full error output
   - Screenshots if helpful

4. **Additional context**:
   - Recent changes to system
   - Other relevant software

## 💡 Feature Requests

We love new ideas! When suggesting features:

1. **Check existing issues** to avoid duplicates
2. **Describe the problem** you're trying to solve
3. **Propose a solution** with examples
4. **Consider the impact** on existing users
5. **Think about implementation** complexity

## 🏗️ Architecture Overview

### Project Structure
```
NewTerminal-AI/
├── NewTerminal-AI.psm1               # The module (all runtime logic, including the safety gate)
├── Microsoft.PowerShell_profile.ps1  # Sample profile with tab completion
├── install.ps1 / install.sh          # Installers (Windows / Linux + macOS)
├── tests/                            # Pester tests
├── tools/Invoke-Lint.ps1             # PSScriptAnalyzer wrapper
├── docs/                             # Banner image
├── examples/                         # Usage examples
├── .github/workflows/                # CI and release workflows
├── README.md                         # Main documentation
├── CONTRIBUTING.md                   # This file
└── LICENSE                           # MIT license
```

### Key Components (`NewTerminal-AI.psm1`)

- **Invoke-AICommand** (`ai`): generates a command and asks before running it
- **Invoke-AICommandAuto** (`aia`): generates a command and runs it if the safety gate allows it
- **Start-NLMode** (`nl`) and **Start-AITerminal**: the two interactive prompts
- **Get-CommandRisk / Test-CommandSafety**: the safety gate. It parses the generated command with the
  PowerShell parser and returns the reasons it must not run without confirmation
- **Invoke-GeneratedCommand**: the single place where a command is executed and recorded

## 🎯 Priority Areas

We're especially looking for contributions in:

1. **Cross-platform compatibility**
   - Testing on different OS versions
   - Shell compatibility improvements
   - Installation script enhancements

2. **AI model optimization**
   - Support for new models
   - Performance improvements
   - Memory usage optimization

3. **User experience**
   - Better error messages
   - Improved command suggestions
   - Enhanced safety features

4. **Documentation**
   - Usage examples
   - Troubleshooting guides
   - Video tutorials

5. **Testing**
   - Automated test suite
   - Integration tests
   - Performance benchmarks

## 📚 Resources

- [PowerShell Documentation](https://docs.microsoft.com/powershell)
- [Bash Scripting Guide](https://tldp.org/LDP/Bash-Beginners-Guide/html/)
- [Ollama API Documentation](https://github.com/ollama/ollama/blob/main/docs/api.md)
- [Conventional Commits](https://www.conventionalcommits.org/)

## 🤔 Questions?

If you have questions about contributing:

1. **Check the [Issues](https://github.com/muhib-karim/NewTerminal-AI/issues)** for existing discussions
2. **Open an [Issue](https://github.com/muhib-karim/NewTerminal-AI/issues/new)** for general questions
3. **Join our community** (links coming soon)

## 🙏 Recognition

All contributors will be:
- **Listed in our README** contributors section
- **Mentioned in release notes** for their contributions
- **Invited to our contributors' channel** (coming soon)

Thank you for helping make NewTerminal-AI better for everyone! 🚀