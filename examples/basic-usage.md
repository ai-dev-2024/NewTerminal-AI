# Basic Usage Examples

This guide provides practical examples of using NewTerminal-AI for common tasks.

> **Which command to use.** `aia` runs the generated command straight away, so it refuses anything
> the safety gate flags: deleting, overwriting, killing or restarting something, and anything it
> cannot analyse. For those requests use `ai`, which shows the command and the reasons it was
> flagged, and runs it only after you type `yes`. See the *Safety gate* section of the README.

## 🚀 Getting Started

### First Steps

```bash
# Test the installation
aia "show current directory"

# Get system information
aia "show system info"

# List available commands
aia "help me understand what commands are available"
```

## 📁 File Operations

### Creating Files and Directories

```bash
# Create a single file
aia "create a file called hello.txt"

# Create multiple files
aia "create files named config.json, readme.md, and app.js"

# Create a directory structure
aia "create a project folder with src, docs, and tests subdirectories"

# Create a file with content
aia "create a Python file called main.py with a hello world function"
```

### File Management

```bash
# List files with details
aia "show all files with their sizes and dates"

# Find specific files
aia "find all Python files in this directory"
aia "find files larger than 10MB"
aia "find files modified in the last 24 hours"

# Copy and move files
aia "copy all images to a backup folder"
aia "move all log files to an archive directory"

# Delete files (flagged by the safety gate: use `ai` and confirm with "yes")
ai "delete all temporary files"
ai "remove empty directories"
```

### File Content Operations

```bash
# View file contents
aia "show the contents of package.json"
aia "display the first 10 lines of error.log"

# Search within files
aia "find all files containing the word 'TODO'"
aia "search for 'function' in all JavaScript files"

# File comparison
aia "compare config.json with config.backup.json"
```

## 🔧 Development Tasks

### Git Operations

```bash
# Repository setup
aia "initialize a new git repository"
aia "add a remote origin to my GitHub repo"

# Daily git workflow
aia "check git status"
aia "add all changes to staging"
aia "commit changes with message 'update documentation'"
aia "push changes to main branch"

# Branch management
aia "create a new branch called feature-login"
aia "switch to the main branch"
aia "merge feature-login into main"

# Git history and logs
aia "show the last 5 commits"
aia "show changes in the last commit"
```

### Package Management

```bash
# Node.js projects
aia "initialize a new npm project"
aia "install express as a dependency"
aia "install nodemon as a dev dependency"
aia "run the start script"

# Python projects
aia "create a virtual environment"
aia "install packages from requirements.txt"
aia "freeze current packages to requirements.txt"

# Other package managers
aia "install packages using yarn"
aia "update all pip packages"
```

### Build and Development

```bash
# Project setup
aia "create a new React project"
aia "initialize a TypeScript project"

# Build operations
aia "run the build command"
aia "start the development server"
aia "run all tests"

# Code quality
aia "run the linter"
aia "format all code files"
aia "check for security vulnerabilities"
```

## 🖥️ System Administration

### Process Management

```bash
# View processes
aia "show all running processes"
aia "find processes using port 3000"
aia "show processes using the most CPU"

# Process control (flagged by the safety gate: use `ai` and confirm with "yes")
ai "kill the process running on port 8080"
ai "restart the nginx service"
```

### System Information

```bash
# Hardware and system
aia "show system specifications"
aia "check available disk space"
aia "display memory usage"
aia "show network configuration"

# Performance monitoring
aia "show CPU usage"
aia "display disk I/O statistics"
aia "check network connectivity"
```

### File System Operations

```bash
# Disk usage
aia "show disk usage by directory"
aia "find the largest files in this directory"
aia "show directory sizes"

# Permissions and ownership
aia "change file permissions to 755"
aia "make this script executable"
aia "show file permissions for all files"
```

## 🌐 Network Operations

### Web and API Tasks

```bash
# Download files
aia "download the file from this URL"
aia "clone this git repository"

# Network testing
aia "ping google.com"
aia "test connection to localhost port 3000"
aia "check if a website is accessible"

# Web development
aia "start a simple HTTP server"
aia "make a GET request to this API endpoint"
```

## 📊 Data Processing

### Text Processing

```bash
# File manipulation
aia "count lines in all text files"
aia "find and replace 'old_name' with 'new_name' in all files"
aia "extract email addresses from this file"

# Data extraction
aia "show unique values from the first column of data.csv"
aia "count occurrences of each word in this text file"
```

### Archive Operations

```bash
# Compression
aia "compress this folder into a zip file"
aia "create a tar.gz archive of the project"

# Extraction
aia "extract this zip file"
aia "list contents of this archive without extracting"
```

## 🔍 Search and Find

### Advanced Search

```bash
# Content search
aia "find all files containing 'password' but exclude .git folders"
aia "search for functions named 'getUserData' in all code files"

# File search
aia "find all files modified today"
aia "locate all configuration files"
aia "find broken symbolic links"
```

## 🛠️ Troubleshooting

### Common Issues

```bash
# Permission problems
aia "fix permission denied errors for this script"
aia "make all files in this directory readable"

# Path and environment
aia "show my PATH environment variable"
aia "find where this command is installed"

# Process issues
aia "find what's using port 80"
ai "kill all processes with this name"   # flagged: confirm with "yes"
```

## 💡 Learning and Help

### Command Explanation

```bash
# Understanding commands
aia "explain what the 'grep' command does"
aia "show me examples of using 'find' command"
aia "what's the difference between 'cp' and 'mv'?"

# Best practices
aia "show me the best way to backup files"
aia "how do I safely delete files?"
aia "what's the recommended way to manage environment variables?"
```

## 🎯 Pro Tips

### Efficiency Shortcuts

```bash
# Combine operations
aia "create a backup of config files and compress them"
aia "find large files and move them to archive folder"

# Batch operations
aia "rename all .jpeg files to .jpg"
aia "convert all images to smaller sizes"

# Automation
aia "create a script that backs up my project daily"
aia "set up a cron job to clean temporary files"
```

### Context-Aware Commands

```bash
# Project-specific
aia "deploy this application"
aia "run the appropriate test command for this project"
aia "install dependencies for this project type"

# Environment-aware
aia "show me the development environment setup"
aia "switch to production configuration"
```

---

**Remember**: NewTerminal-AI learns from context, so the more specific you are about what you want to accomplish, the better the results will be!