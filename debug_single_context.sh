#!/bin/bash
cd /home/andre/code/ClaudeRunnerWorkflow

echo "Before testing file existence:"
ls -la "runner-contexts/ascii-art-purist/CLAUDE.md"

echo ""
echo "Testing file existence check:"
if [ -f "runner-contexts/ascii-art-purist/CLAUDE.md" ]; then
    echo "File exists: YES"
else
    echo "File exists: NO"
fi

echo ""
echo "Testing with absolute path:"
if [ -f "/home/andre/code/ClaudeRunnerWorkflow/runner-contexts/ascii-art-purist/CLAUDE.md" ]; then
    echo "File exists (absolute): YES"
else
    echo "File exists (absolute): NO"
fi

echo ""
echo "Current working directory: $(pwd)"