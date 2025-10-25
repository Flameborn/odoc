# odoc

A documentation tool for Odin, inspired by Go's `godoc`. Quickly view function signatures, types, and documentation comments on the command line without reading through source files.

## Installation

In the cloned directory, with Odin installed:

```bash
odin build .
```

## Usage

```bash
# View entire package documentation
odoc core:fmt
odoc ./mypackage

# View specific symbol
odoc core:fmt.println
odoc core:strings.Builder

# Check Odin installation path
odoc --root
```

## Output Format

```
package fmt // import "core:fmt"

println :: proc(args: ..any) -> int
    Formats using the default formats for its operands and writes to
    standard output. Spaces are always added between operands and a newline
    is appended.
```

## Features

- Extracts documentation from `//` comments above declarations
- Shows only public symbols (no `@(private)` attribute)
- Strips procedure bodies for clean signatures
- Automatically finds Odin installation (supports Homebrew on macOS)
- Godoc-style formatting with indented documentation

## Notes

Set `ODIN_ROOT` environment variable if your Odin installation isn't detected automatically.

This is a quick solution, written and tested in the span of 2 hours under MacOS, but other operating systems should work as well.