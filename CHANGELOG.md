# Changelog

All notable changes to NewTerminal-AI will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [2.2.0] - 2026-11-10

This release replaces the destructive-command safety gate, fixes the bugs found in a production-readiness
audit of the module, the sample profile, both installers and the release workflow, removes stale
duplicate files, and tightens CI. It also includes the changes made since 2.1.0 that had not been
released yet.

### Security
- The destructive-command safety gate is rewritten. It now parses the generated command with the PowerShell parser and walks the syntax tree instead of matching 11 regular expressions. It flags deletes and overwrites through any alias, abbreviated parameter, pipeline, statement chain, script block or subexpression; code it cannot inspect (`Invoke-Expression`, `[scriptblock]::Create`, `& $variable`, encoded commands, nested shells, `Start-Process`, COM objects, unvetted .NET calls); disk, power, registry and destructive git commands; and it fails closed on anything that does not parse
- A command edited at the `ai` prompt is checked by the gate again before it runs
- Commands containing terminal escape sequences or invisible formatting characters are flagged
- The system prompt no longer teaches the model to create files with `-Force`

### Changed
- **Stricter by design:** every delete and every file overwrite is flagged, including a plain `Remove-Item file.txt`. `aia` and `nl` refuse flagged commands; `ai` and the `AI>` prompt show the reasons and run the command only after you type `yes` (`ai` previously could not run a flagged command at all, the `AI>` prompt accepted `y`)
- The REPL starts on import only in an interactive console, so a profile that imports the module no longer breaks `pwsh -Command`, `pwsh -File` or editor hosts
- Command output is rendered with the normal PowerShell formatter in every mode
- `tools/Invoke-Lint.ps1` fails on warnings in every PowerShell file, not only in the module
- CI scans the git history with gitleaks; the release workflow runs lint and tests first, checks the tag against `$script:ModuleVersion`, and publishes with `gh`
- `install.sh` installs the launcher to `NEWTERMINAL_AI_BIN_DIR` (default `/usr/local/bin`, falling back to `~/.local/bin`) and picks the Microsoft package repository that matches the distribution

### Fixed
- A failed generation (model not pulled, timeout) no longer ends the REPL or makes the module import fail
- A stale exit code from an earlier program is no longer reported for the current command
- Objects were printed as their `ToString()` value (`Get-PSDrive` showed only drive names); they are now formatted as tables and lists
- Prose around a fenced code block and inline backticks are removed from the model's reply instead of being executed
- "What is the model of this laptop" is no longer answered with the name of the AI model
- Requests are sent as UTF-8 under Windows PowerShell 5.1
- The REPL exits at end of input instead of looping on an error
- `Get-ContextInfo` reports the working-tree status on a detached HEAD
- `install.sh` no longer overwrites an existing PowerShell profile, and is executable
- `install.ps1` parses under Windows PowerShell 5.1 (it is now saved with a byte order mark), installs into the module folder of the PowerShell edition that runs it, exports every function the aliases need, and detects a failed `winget`
- The sample profile no longer calls functions that do not exist or starts a second prompt
- Release workflow has the permission it needs to create a release and no longer ships an empty `media/` folder
- Typing `exit` now actually leaves the interactive REPL (`break` previously only left the `switch`)
- `Get-ContextInfo` no longer throws in directories without `.git`/`package.json` (`Test-Path ... -or ...` parsing bug)
- Markdown code fences in model replies are now stripped from multi-line responses
- `Start-AITerminal` is now exported (it was referenced by the installer manifest but never exported)
- `history` now shows output when exactly one entry exists
- Safety check catches `Remove-Item ... C:\` with `-Recurse`/`-Force` in any order
- Installers pull `llama3.2:1b`, the model the module actually calls (they previously pulled `llama3.2:3b`)
- Release workflow no longer copies the missing `install-any.sh` and now ships the module file

### Removed
- `releases/v2.0.0/` (copies of files that live elsewhere in the repository, including an old module with the old safety check)
- `scripts/`: the alternate installers and the standalone Bash variant. They were broken, and the Bash variant executed model output behind a regex check that could not be made safe. Use `install.ps1` / `install.sh`
- `scripts/github-integration.ps1` and its output `docs/PROJECT_STATUS.md`
- `tests/test-installation.ps1`, which reported success whatever happened
- `assets/media/demo.svg` and `docs/pester-run.svg` (unreferenced or out of date)

### Added
- `tests/SafetyGate.Tests.ps1` (one test per command the gate must flag or allow) and `tests/Repo.Tests.ps1` (file encodings, sample profile, installers)
- The gate reports why a command is flagged (`Get-CommandRisk`), and the reasons are shown before any confirmation
- `.gitattributes` keeps `*.sh` files on LF line endings in a Windows checkout
- Pester unit test suite (`tests/NewTerminal-AI.Tests.ps1`) and PSScriptAnalyzer lint script (`tools/Invoke-Lint.ps1`)
- GitHub Actions CI on Ubuntu and Windows
- `NEWTERMINAL_AI_MODEL` / `NEWTERMINAL_AI_OLLAMA_URL` environment overrides and `NEWTERMINAL_AI_NO_AUTOSTART` to import the module without starting the REPL
- Cross-platform support for macOS and Linux
- Professional project structure with organized directories
- Comprehensive installation scripts for all platforms
- Educational command display feature
- Enhanced documentation and examples

## [2.0.0] - 2025-01-27

### Added
- **Warp AI-style clean interface** - Minimal, focused output
- **Educational command display** - Shows CLI commands before execution
- **Auto-execution mode (`aia`)** - Commands execute automatically with clean output
- **Interactive mode (`ai`)** - Review commands before execution
- **Natural language mode (`nl`)** - Conversation-style terminal interface
- **Cross-platform compatibility** - Support for Windows, macOS, and Linux
- **Professional installation scripts** - Automated setup for all platforms
- **Command history management** - Track and review AI-generated commands
- **Enhanced safety features** - Better dangerous command detection
- **Clean output mode** - Reduced verbosity for better user experience

### Changed
- **Complete UI overhaul** - Moved from verbose to clean, Warp AI-inspired interface
- **Improved command generation** - Better context awareness and accuracy
- **Enhanced error handling** - More user-friendly error messages
- **Optimized performance** - Faster response times and better resource usage
- **Restructured codebase** - Better organization and maintainability

### Fixed
- **PowerShell execution policy issues** - Better handling of restricted environments
- **Ollama connection stability** - Improved error recovery and reconnection
- **Command safety validation** - More accurate dangerous command detection
- **Memory usage optimization** - Reduced resource consumption
- **Cross-platform path handling** - Better file system compatibility

### Removed
- **Verbose status messages** - Cleaned up unnecessary output
- **Legacy command formats** - Simplified to three main commands (`aia`, `ai`, `nl`)
- **Redundant confirmation prompts** - Streamlined user interaction

## [1.5.0] - 2025-01-20

### Added
- **Enhanced AI model support** - Support for multiple Ollama models
- **Automatic model selection** - Chooses optimal model based on system resources
- **Improved command safety** - Better detection of potentially dangerous operations
- **Context awareness** - Better understanding of current directory and environment
- **Command history** - Track previously executed AI-generated commands

### Changed
- **Improved AI prompting** - Better command generation accuracy
- **Enhanced error messages** - More helpful and actionable error information
- **Optimized model loading** - Faster startup and response times

### Fixed
- **Model download issues** - Better handling of network interruptions
- **PowerShell profile integration** - Improved automatic setup
- **Command execution errors** - Better error handling and recovery

## [1.0.0] - 2025-01-15

### Added
- **Initial release** of NewTerminal-AI
- **Basic natural language processing** - Convert natural language to CLI commands
- **Ollama integration** - Local AI model support
- **PowerShell module** - Windows PowerShell integration
- **Command confirmation** - Safety prompts for dangerous operations
- **Basic installation script** - Automated setup process
- **AI model management** - Download and configure AI models
- **Context-aware commands** - Understanding of current working directory

### Features
- Support for common file operations
- Git integration for version control commands
- System information and process management
- Package manager integration (npm, pip, etc.)
- Basic safety checks for destructive commands
- Colorized output for better readability

## [0.9.0] - 2025-01-10 (Beta)

### Added
- **Beta release** for testing and feedback
- **Core AI functionality** - Basic natural language to command conversion
- **Ollama backend** - Local AI model integration
- **PowerShell integration** - Windows terminal support
- **Basic safety features** - Simple dangerous command detection

### Known Issues
- Limited cross-platform support
- Basic error handling
- Minimal documentation
- No automated installation

## [0.5.0] - 2025-01-05 (Alpha)

### Added
- **Alpha release** - Initial proof of concept
- **Basic AI integration** - Simple command generation
- **PowerShell prototype** - Windows-only support
- **Manual setup** - Basic installation instructions

### Limitations
- Windows PowerShell only
- Manual Ollama setup required
- Limited command support
- No safety features
- Minimal error handling

---

## Version Numbering

We follow [Semantic Versioning](https://semver.org/):

- **MAJOR** version for incompatible API changes
- **MINOR** version for backwards-compatible functionality additions
- **PATCH** version for backwards-compatible bug fixes

## Release Process

1. **Development** - Features developed in feature branches
2. **Testing** - Comprehensive testing across all supported platforms
3. **Documentation** - Update README, examples, and changelog
4. **Release** - Create release packages and GitHub release
5. **Distribution** - Update installation scripts and documentation

## Support Policy

- **Current major version** - Full support with new features and bug fixes
- **Previous major version** - Security updates and critical bug fixes for 6 months
- **Older versions** - Community support only

## Migration Guides

### Upgrading from 1.x to 2.x

Major changes in 2.0:
- New command structure (`aia`, `ai`, `nl`)
- Clean output mode by default
- Cross-platform support
- New installation process

**Migration steps:**
1. Uninstall previous version
2. Run new installation script
3. Update any custom scripts to use new command names
4. Test functionality in your environment

### Upgrading from 0.x to 1.x

Major changes in 1.0:
- Stable API and command structure
- Improved AI model support
- Enhanced safety features
- Better error handling

**Migration steps:**
1. Backup your current configuration
2. Run the new installer
3. Reconfigure any custom settings
4. Test all functionality

---

**For detailed upgrade instructions and breaking changes, see our [Migration Guide](docs/migration.md).**