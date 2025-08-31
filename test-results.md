# Claude CLI Permissions Test Results

## 📋 **Key Findings:**

### 🚨 **Claude CLI Interactive Mode Limitations:**

1. **Git can only do READ operations** - write operations like `git add`, `git commit` are blocked
2. **Path-based permissions are bugged** - patterns like `Bash(git:*)` fail (see [GitHub Issue #1520](https://github.com/anthropics/claude-code/issues/1520))

### ✅ **What Works:**
```bash
claude --allowedTools "Bash" -p "git status"           # Git read operations only
claude --allowedTools "Bash" -p "ls -la"               # Basic bash commands  
claude --allowedTools "Edit(*)" -p "hello"             # Edit with parentheses works
```

### ❌ **What Fails:**
```bash
claude --allowedTools "Bash(git:*)" -p "git status"    # Path-based permissions bug
claude --allowedTools "Bash(git add:*)" -p "git add"   # Git write operations blocked
claude --allowedTools "Bash" -p "git add file.txt"     # Git write operations blocked
claude --allowedTools "Bash" -p "git commit -m 'msg'"  # Git write operations blocked
```
