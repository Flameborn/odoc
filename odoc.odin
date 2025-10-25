package odindoc

import "core:fmt"
import "core:os"
import "core:strings"
import "core:path/filepath"
import "core:slice"

Doc_Entry :: struct {
    name: string,
    kind: string, // "proc", "struct", "enum", "union", "const", etc.
    signature: string,
    doc_comment: string,
    file: string,
    line: int,
    is_private: bool,
}

main :: proc() {
    if len(os.args) < 2 {
        print_usage()
        return
    }

    target := os.args[1]
    
    // Handle special flags
    if target == "--root" || target == "-r" {
        show_odin_root()
        return
    }
    
    if target == "--version" || target == "-v" {
        fmt.println("odindoc version 0.9.0")
        return
    }
    
    // Check if it's a directory (package) or a specific symbol
    if os.is_dir(target) {
        doc_package(target)
    } else {
        parts := strings.split(target, ".")
        if len(parts) == 2 {
            doc_symbol(parts[0], parts[1])
        } else {
            doc_package(target)
        }
    }
}

print_usage :: proc() {
    fmt.println("Usage: odindoc <package|symbol|flag>")
    fmt.println()
    fmt.println("Flags:")
    fmt.println("  --root, -r               Show detected Odin root directory")
    fmt.println("  --version, -v            Show version information")
    fmt.println()
    fmt.println("Examples:")
    fmt.println("  odindoc core:fmt              # Document entire package")
    fmt.println("  odindoc ./mypackage          # Document local package")
    fmt.println("  odindoc core:fmt.println     # Document specific symbol")
    fmt.println("  odindoc MyType               # Document type in current directory")
}

show_odin_root :: proc() {
    root, found := find_odin_root()
    defer if found do delete(root)
    
    if found {
        fmt.printf("✓ Odin root found: %s\n", root)
        
        // Verify core library exists
        core_path := filepath.join({root, "core"})
        if os.is_dir(core_path) {
            fmt.printf("✓ Core library verified at: %s\n", core_path)
        } else {
            fmt.printf("⚠ Warning: Core library not found at: %s\n", core_path)
        }
    } else {
        fmt.println("✗ Could not find Odin installation")
        fmt.println()
        fmt.println("Searched locations:")
        fmt.println("  - ODIN_ROOT environment variable")
        when ODIN_OS == .Darwin {
            fmt.println("  - /opt/homebrew/opt/odin")
            fmt.println("  - /usr/local/opt/odin")
            fmt.println("  - /opt/homebrew/Cellar/odin")
        } else when ODIN_OS == .Linux {
            fmt.println("  - /usr/local/share/odin")
            fmt.println("  - /usr/share/odin")
        } else when ODIN_OS == .Windows {
            fmt.println("  - C:\\Odin")
        }
        fmt.println("  - Directory containing 'odin' binary in PATH")
        fmt.println()
        fmt.println("Solution: Set the ODIN_ROOT environment variable:")
        fmt.println("  export ODIN_ROOT=/path/to/odin")
    }
}

doc_package :: proc(path: string) {
    entries := make([dynamic]Doc_Entry)
    defer delete(entries)

    // Find all .odin files in the directory
    files, root_found := find_odin_files(path)
    defer delete(files)
    
    if !root_found && strings.has_prefix(path, "core:") {
        fmt.println("✗ Error: Could not locate Odin installation")
        fmt.println("  Run 'odindoc --root' to diagnose the issue")
        return
    }

    for file in files {
        parse_file(file, &entries)
    }

    // Deduplicate entries by name (keep first occurrence)
    seen_names := make(map[string]bool)
    defer delete(seen_names)
    
    unique_entries := make([dynamic]Doc_Entry)
    defer delete(unique_entries)
    
    for entry in entries {
        if entry.name not_in seen_names {
            seen_names[entry.name] = true
            append(&unique_entries, entry)
        }
    }

    // Sort and display
    slice.sort_by(unique_entries[:], proc(a, b: Doc_Entry) -> bool {
        return a.name < b.name
    })

    if len(unique_entries) == 0 {
        fmt.println("No documentation found in package")
        return
    }

    // Extract package name from path
    pkg_name := filepath.base(path)
    if strings.has_prefix(path, "core:") {
        pkg_name = strings.trim_prefix(path, "core:")
    }
    
    fmt.printf("package %s // import \"%s\"\n\n", pkg_name, path)
    
    // Group by kind
    consts := make([dynamic]Doc_Entry)
    types := make([dynamic]Doc_Entry)
    procs := make([dynamic]Doc_Entry)
    defer delete(consts)
    defer delete(types)
    defer delete(procs)

    for entry in unique_entries {
        // Skip private entries
        if entry.is_private do continue
        
        switch entry.kind {
        case "proc":
            append(&procs, entry)
        case "struct", "enum", "union", "bit_set":
            append(&types, entry)
        case "const":
            append(&consts, entry)
        }
    }

    // Print constants
    for c in consts {
        print_entry_godoc_style(c)
    }

    // Print types
    for t in types {
        print_entry_godoc_style(t)
    }

    // Print procedures
    for p in procs {
        print_entry_godoc_style(p)
    }
}

doc_symbol :: proc(pkg: string, symbol: string) {
    entries := make([dynamic]Doc_Entry)
    defer delete(entries)

    files, root_found := find_odin_files(pkg)
    defer delete(files)
    
    if !root_found && strings.has_prefix(pkg, "core:") {
        fmt.println("✗ Error: Could not locate Odin installation")
        fmt.println("  Run 'odindoc --root' to diagnose the issue")
        return
    }

    for file in files {
        parse_file(file, &entries)
    }

    found := false
    for entry in entries {
        if entry.name == symbol {
            // Don't show private symbols
            if entry.is_private {
                fmt.printf("Symbol '%s' is private in package '%s'\n", symbol, pkg)
                return
            }
            
            // Extract package name
            pkg_name := filepath.base(pkg)
            if strings.has_prefix(pkg, "core:") {
                pkg_name = strings.trim_prefix(pkg, "core:")
            }
            
            fmt.printf("package %s // import \"%s\"\n\n", pkg_name, pkg)
            print_entry_godoc_style(entry)
            found = true
            break
        }
    }

    if !found {
        fmt.printf("Symbol '%s' not found in package '%s'\n", symbol, pkg)
    }
}

print_entry_godoc_style :: proc(entry: Doc_Entry) {
    // Print the signature
    fmt.printf("%s :: %s", entry.name, entry.signature)
    fmt.println()
    
    // Print documentation comment with indentation
    if entry.doc_comment != "" {
        lines := strings.split(entry.doc_comment, "\n")
        defer delete(lines)
        
        for line in lines {
            trimmed := strings.trim_space(line)
            // Remove leading // from comment lines
            trimmed = strings.trim_space(strings.trim_prefix(trimmed, "//"))
            
            if trimmed != "" {
                fmt.printf("    %s\n", trimmed)
            }
        }
    }
    
    fmt.println()
}

print_entry :: proc(entry: Doc_Entry, verbose := false) {
    if entry.doc_comment != "" {
        fmt.println(entry.doc_comment)
    }
    
    fmt.printf("%s :: %s\n", entry.name, entry.signature)
    
    if verbose {
        fmt.printf("  // %s:%d\n", entry.file, entry.line)
    }
    fmt.println()
}

find_odin_files :: proc(path: string) -> ([dynamic]string, bool) {
    files := make([dynamic]string)
    root_found := true
    
    actual_path := path
    if !os.is_dir(path) {
        // Try as a core library reference
        if strings.has_prefix(path, "core:") {
            pkg := strings.trim_prefix(path, "core:")
            
            odin_root, found := find_odin_root()
            defer if found do delete(odin_root)
            
            if found {
                actual_path = filepath.join({odin_root, "core", pkg})
            } else {
                root_found = false
                return files, root_found
            }
        }
    }

    handle, err := os.open(actual_path)
    if err != os.ERROR_NONE {
        return files, root_found
    }
    defer os.close(handle)

    file_infos, read_err := os.read_dir(handle, -1)
    if read_err != os.ERROR_NONE {
        return files, root_found
    }
    defer os.file_info_slice_delete(file_infos)

    for info in file_infos {
        if !info.is_dir && strings.has_suffix(info.name, ".odin") {
            full_path := filepath.join({actual_path, info.name})
            append(&files, full_path)
        }
    }

    return files, root_found
}

find_odin_root :: proc() -> (string, bool) {
    // Try multiple locations for Odin installation
    odin_root := os.get_env("ODIN_ROOT")
    
    search_paths := make([dynamic]string)
    defer delete(search_paths)
    
    if odin_root != "" {
        append(&search_paths, odin_root)
    }
    
    // Common installation locations
    when ODIN_OS == .Darwin {
        append(&search_paths, "/opt/homebrew/opt/odin")
        append(&search_paths, "/opt/homebrew/opt/odin/libexec")
        append(&search_paths, "/usr/local/opt/odin")
        append(&search_paths, "/usr/local/opt/odin/libexec")
        
        // Check versioned Cellar paths
        if handle, err := os.open("/opt/homebrew/Cellar/odin"); err == os.ERROR_NONE {
            defer os.close(handle)
            if infos, read_err := os.read_dir(handle, -1); read_err == os.ERROR_NONE {
                defer os.file_info_slice_delete(infos)
                for info in infos {
                    if info.is_dir {
                        version_path := filepath.join({"/opt/homebrew/Cellar/odin", info.name})
                        append(&search_paths, version_path)
                        libexec_path := filepath.join({version_path, "libexec"})
                        append(&search_paths, libexec_path)
                    }
                }
            }
        }
    } else when ODIN_OS == .Linux {
        append(&search_paths, "/usr/local/share/odin")
        append(&search_paths, "/usr/share/odin")
    } else when ODIN_OS == .Windows {
        append(&search_paths, "C:\\Odin")
    }
    
    // Also check relative to odin binary location
    odin_bin, bin_ok := find_odin_binary()
    if bin_ok {
        bin_dir := filepath.dir(odin_bin)
        append(&search_paths, bin_dir)
        
        // Also check parent directory (for homebrew libexec structure)
        parent_dir := filepath.dir(bin_dir)
        append(&search_paths, parent_dir)
    }
    defer if bin_ok do delete(odin_bin)
    
    for search_path in search_paths {
        core_path := filepath.join({search_path, "core"})
        if os.is_dir(core_path) {
            return strings.clone(search_path), true
        }
    }
    
    return "", false
}

find_odin_binary :: proc() -> (string, bool) {
    // Try to find odin in PATH
    path_env := os.get_env("PATH")
    paths := strings.split(path_env, ":" when ODIN_OS != .Windows else ";")
    defer delete(paths)
    
    odin_name := "odin" when ODIN_OS != .Windows else "odin.exe"
    
    for path in paths {
        test_path := filepath.join({path, odin_name})
        if os.exists(test_path) {
            return strings.clone(test_path), true
        }
    }
    
    return "", false
}

parse_file :: proc(filepath: string, entries: ^[dynamic]Doc_Entry) {
    data, ok := os.read_entire_file(filepath)
    if !ok {
        return
    }
    defer delete(data)

    content := string(data)
    lines := strings.split(content, "\n")
    defer delete(lines)

    doc_comment := strings.builder_make()
    defer strings.builder_destroy(&doc_comment)
    
    is_private_marker := false
    last_line_was_code := false

    for line, i in lines {
        trimmed := strings.trim_space(line)
        
        // Check for @(private) attribute
        if strings.contains(trimmed, "@(private)") || strings.contains(trimmed, "@private") {
            is_private_marker = true
            last_line_was_code = false
            continue
        }
        
        // Collect documentation comments
        if strings.has_prefix(trimmed, "//") {
            // If the last line was code (not a comment or empty), this is an inline/trailing comment
            // Don't include it in doc comments
            if last_line_was_code {
                last_line_was_code = false
                continue
            }
            
            comment := strings.trim_space(strings.trim_prefix(trimmed, "//"))
            if strings.builder_len(doc_comment) > 0 {
                strings.write_string(&doc_comment, "\n")
            }
            strings.write_string(&doc_comment, "// ")
            strings.write_string(&doc_comment, comment)
            last_line_was_code = false
            continue
        }

        // Empty lines - preserve doc comments but reset code tracking
        if trimmed == "" {
            if strings.builder_len(doc_comment) > 0 {
                strings.write_string(&doc_comment, "\n")
            }
            last_line_was_code = false
            continue
        }

        // Parse declarations
        if strings.contains(trimmed, "::") {
            parts := strings.split(trimmed, "::")
            if len(parts) >= 2 {
                name := strings.trim_space(parts[0])
                rest := strings.trim_space(strings.join(parts[1:], "::"))
                
                // Check if name starts with underscore or lowercase (private by convention)
                is_private := is_private_marker || 
                              strings.has_prefix(name, "_") ||
                              (len(name) > 0 && name[0] >= 'a' && name[0] <= 'z')
                
                // Strip proc body if it exists (everything from { onwards)
                if brace_idx := strings.index_byte(rest, '{'); brace_idx >= 0 {
                    rest = strings.trim_space(rest[:brace_idx])
                }
                
                entry := Doc_Entry{
                    name = strings.clone(name),
                    signature = strings.clone(rest),
                    doc_comment = strings.clone(strings.to_string(doc_comment)),
                    file = filepath,
                    line = i + 1,
                    is_private = is_private,
                }

                // Determine kind
                if strings.has_prefix(rest, "proc") {
                    entry.kind = "proc"
                } else if strings.has_prefix(rest, "struct") {
                    entry.kind = "struct"
                } else if strings.has_prefix(rest, "enum") {
                    entry.kind = "enum"
                } else if strings.has_prefix(rest, "union") {
                    entry.kind = "union"
                } else if strings.has_prefix(rest, "bit_set") {
                    entry.kind = "bit_set"
                } else {
                    entry.kind = "const"
                }

                append(entries, entry)
            }

            // Reset doc comment and private marker after declaration
            strings.builder_reset(&doc_comment)
            is_private_marker = false
            last_line_was_code = false
        } else {
            // Non-declaration line that's not a comment - reset doc comment and private marker
            strings.builder_reset(&doc_comment)
            is_private_marker = false
            last_line_was_code = true
        }
    }
}