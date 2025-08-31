#!/bin/bash
echo "=== CODE METRICS - SIMPLIFIED ==="
echo "Generated: $(date)"
echo ""

# BASIC STRUCTURE
echo "📁 FILE STRUCTURE"
echo "Total files: $(find . -type f ! -path './node_modules/*' ! -path './.git/*' | wc -l)"
echo "Total directories: $(find . -type d ! -path './node_modules/*' ! -path './.git/*' | wc -l)"
echo "Source files (.ts/.tsx): $(find src -name '*.ts' -o -name '*.tsx' | wc -l)"
echo ""

# CODE METRICS
echo "📊 CODE SIZE"
TOTAL_LINES=$(find src -name '*.ts' -o -name '*.tsx' | xargs wc -l | tail -1 | awk '{print $1}')
FILE_COUNT=$(find src -name '*.ts' -o -name '*.tsx' | wc -l)
echo "Total lines of code: $TOTAL_LINES"
echo "Average lines per file: $((TOTAL_LINES / FILE_COUNT))"
echo "Largest file: $(find src -name '*.ts' -o -name '*.tsx' | xargs wc -l | sort -n | tail -2 | head -1)"
echo "Smallest file: $(find src -name '*.ts' -o -name '*.tsx' | xargs wc -l | sort -n | head -1)"
echo "Source code size: $(du -sh src | cut -f1)"
echo ""

# DEPENDENCIES
echo "📦 DEPENDENCIES"
echo "Total dependencies: $(jq '.dependencies | length' package.json 2>/dev/null || echo 0)"
echo "Dev dependencies: $(jq '.devDependencies | length' package.json 2>/dev/null || echo 0)"
echo "node_modules size: $(du -sh node_modules 2>/dev/null | cut -f1 || echo 'N/A')"
echo "Package.json size: $(du -sh package.json | cut -f1)"
echo ""

# BUILD COMPLEXITY
echo "⚡ BUILD METRICS"
echo "Build scripts: $(jq '.scripts | length' package.json 2>/dev/null || echo 0)"
echo "Config files: $(find . -maxdepth 1 -name '*.json' -o -name '*.config.*' -o -name '*.rc.*' | wc -l)"
echo ""

# BUILD TIME MEASUREMENT
echo "🏗️  BUILD TIME"
echo "Measuring build time..."
START_TIME=$(date +%s.%N)
npm run build >/dev/null 2>&1
END_TIME=$(date +%s.%N)
BUILD_TIME=$(echo "$END_TIME - $START_TIME" | bc -l 2>/dev/null || echo "N/A")
if [ "$BUILD_TIME" != "N/A" ]; then
    printf "Build time: %.2f seconds\n" $BUILD_TIME
    echo "Build output size: $(du -sh build 2>/dev/null | cut -f1 || echo 'N/A')"
else
    echo "Build time: Could not measure (bc not available)"
fi
echo ""

# ASSETS
echo "🎨 ASSETS"
echo "Asset files: $(find public -type f 2>/dev/null | wc -l || echo 0)"
echo "Asset size: $(du -sh public 2>/dev/null | cut -f1 || echo '0B')"
echo "CSS files: $(find . -name '*.css' ! -path './node_modules/*' | wc -l)"
echo "Image files: $(find . -name '*.png' -o -name '*.jpg' -o -name '*.svg' -o -name '*.gif' ! -path './node_modules/*' | wc -l)"
echo ""

# REACT PATTERNS ANALYSIS
echo "🔍 REACT PATTERNS"
echo ""

# HOOKS ANALYSIS
echo "📎 HOOKS"
echo "Custom hook files: $(find . -path '*/hooks/*.ts' -o -path '*/hooks/*.tsx' | wc -l)"
echo "Hook calls:"
echo "  useState: $(grep -r 'useState' src --include='*.ts' --include='*.tsx' | wc -l)"
echo "  useEffect: $(grep -r 'useEffect' src --include='*.ts' --include='*.tsx' | wc -l)"
echo "  useMemo: $(grep -r 'useMemo' src --include='*.ts' --include='*.tsx' | wc -l)"
echo "  useCallback: $(grep -r 'useCallback' src --include='*.ts' --include='*.tsx' | wc -l)"
echo "  useRef: $(grep -r 'useRef' src --include='*.ts' --include='*.tsx' | wc -l)"
echo "  useContext: $(grep -r 'useContext' src --include='*.ts' --include='*.tsx' | wc -l)"
echo "  Custom hooks: $(grep -r 'use[A-Z][a-zA-Z]*' src --include='*.ts' --include='*.tsx' | grep -v 'useState\|useEffect\|useMemo\|useCallback\|useRef\|useContext' | wc -l)"
echo ""

# STATE MANAGEMENT
echo "🗄️  STATE MANAGEMENT"
echo "State setters: $(grep -r 'set[A-Z][a-zA-Z]*(' src --include='*.ts' --include='*.tsx' | wc -l)"
echo "useReducer: $(grep -r 'useReducer' src --include='*.ts' --include='*.tsx' | wc -l)"
echo "createContext: $(grep -r 'createContext' src --include='*.ts' --include='*.tsx' | wc -l)"
echo "Provider components: $(grep -r '\.Provider\|Provider>' src --include='*.tsx' | wc -l)"
echo ""

# PERFORMANCE OPTIMIZATIONS
echo "⚡ PERFORMANCE PATTERNS"
echo "React.memo: $(grep -r 'React\.memo\|memo(' src --include='*.ts' --include='*.tsx' | wc -l)"
echo "useMemo calls: $(grep -r 'useMemo(' src --include='*.ts' --include='*.tsx' | wc -l)"
echo "useCallback calls: $(grep -r 'useCallback(' src --include='*.ts' --include='*.tsx' | wc -l)"
echo ""

# COMPONENTS
echo "🧩 COMPONENTS"
echo "JSX elements: $(grep -r '<[A-Z][a-zA-Z]*' src --include='*.tsx' | wc -l)"
echo "HTML elements: $(grep -r '<[a-z][a-zA-Z]*' src --include='*.tsx' | wc -l)"
echo "Self-closing tags: $(grep -r '<[a-zA-Z][a-zA-Z]*/>' src --include='*.tsx' | wc -l)"
echo "Fragment usage: $(grep -r '<>\|Fragment>' src --include='*.tsx' | wc -l)"
echo ""

# EVENT HANDLING
echo "🎮 INTERACTIVITY"
echo "Event handlers: $(grep -r 'handle[A-Z][a-zA-Z]*' src --include='*.ts' --include='*.tsx' | wc -l)"
echo "onClick handlers: $(grep -r 'onClick' src --include='*.tsx' | wc -l)"
echo "onChange handlers: $(grep -r 'onChange' src --include='*.tsx' | wc -l)"
echo "Arrow functions: $(grep -r '=>' src --include='*.tsx' | wc -l)"