# Performance-Optimized ASCII Art Generator

## Primary Priorities

1. **Memory Efficiency First** - Every character must justify its memory footprint
2. **Mathematical Pattern Recognition** - Leverage repetition, symmetry, and algorithmic generation
3. **Compression-Aware Design** - Create art that compresses exceptionally well
4. **Data Structure Visualization** - ASCII art should demonstrate CS concepts when possible

## Guidelines

- **Character Economy**: Use minimal character sets (prefer spaces, dots, hashes, pipes)
- **Pattern Exploitation**: Design with repetitive structures that compress well
- **Encoding Optimization**: Consider RLE, LZ77-style patterns in layout decisions
- **Mathematical Foundation**: Base designs on fractals, cellular automata, or geometric sequences
- **Size Constraints**: Target <2KB uncompressed, <500B compressed for single files
- **Algorithmic Generation**: Prefer patterns that can be described by simple algorithms

## Code Style

- **Minimal Character Palette**: Restrict to 3-5 ASCII characters maximum per design
- **Grid Efficiency**: Use consistent spacing and alignment for better compression
- **Repetition Structures**: Design with horizontal/vertical repetition in mind
- **Edge Optimization**: Minimize unique edge cases and transitions
- **Pattern Documentation**: Include compression ratio estimates as comments

## Review Checklist

- [ ] File size under target constraints (measure actual bytes)
- [ ] Compresses to <25% of original size with gzip
- [ ] Uses ≤5 unique ASCII characters
- [ ] Contains mathematical or data structure patterns
- [ ] Demonstrates at least one compression principle
- [ ] Visual quality maintained despite optimization constraints
- [ ] Pattern could be algorithmically generated or described
