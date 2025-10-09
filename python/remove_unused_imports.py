#!/usr/bin/env python3
"""
Script to remove unused imports from Solidity files.

This script scans .sol files in src/, test/, and script/ directories,
identifies unused imports, and removes them from the files.

An import is considered unused if the imported symbol appears ONLY in the
import statement itself (not elsewhere in the file, including comments).
"""

import os
import re
from pathlib import Path
from typing import List, Tuple, Set, Dict


def find_sol_files(base_dirs: List[str]) -> List[Path]:
    """Find all .sol files in the given directories recursively."""
    sol_files = []
    for base_dir in base_dirs:
        if os.path.exists(base_dir):
            for root, _, files in os.walk(base_dir):
                for file in files:
                    if file.endswith('.sol'):
                        sol_files.append(Path(root) / file)
    return sol_files


def parse_imports(content: str) -> List[Tuple[int, str, List[str], str]]:
    """
    Parse import statements from Solidity file content.
    
    Returns list of tuples: (line_number, full_line, [symbols], from_path)
    Handles patterns:
    - import {X} from "Y";
    - import {X, Y, Z} from "W";
    """
    imports = []
    lines = content.split('\n')
    
    # Regex to match: import {symbols} from "path";
    import_pattern = re.compile(r'^\s*import\s+\{([^}]+)\}\s+from\s+"([^"]+)"\s*;')
    
    for i, line in enumerate(lines):
        match = import_pattern.match(line)
        if match:
            symbols_str = match.group(1)
            from_path = match.group(2)
            
            # Split symbols by comma and clean whitespace
            symbols = [s.strip() for s in symbols_str.split(',')]
            
            imports.append((i, line, symbols, from_path))
    
    return imports


def count_symbol_occurrences(content: str, symbol: str, import_line_num: int) -> int:
    """
    Count occurrences of a symbol in the file content, excluding the import line and comments.
    Uses word boundaries to avoid substring matches.
    """
    lines = content.split('\n')
    count = 0
    in_multiline_comment = False

    # Create regex pattern with word boundaries
    # \b matches word boundaries (between \w and \W)
    pattern = re.compile(r'\b' + re.escape(symbol) + r'\b')

    for i, line in enumerate(lines):
        # Skip the import line itself
        if i == import_line_num:
            continue

        # Track multi-line comment state
        stripped = line.strip()

        # Check for multi-line comment start
        if '/*' in line:
            in_multiline_comment = True

        # Skip if we're in a multi-line comment
        if in_multiline_comment:
            # Check if multi-line comment ends on this line
            if '*/' in line:
                in_multiline_comment = False
            continue

        # Skip single-line comments
        if stripped.startswith('//'):
            continue

        # For lines with inline comments, only search the code part
        comment_pos = line.find('//')
        if comment_pos != -1:
            # Only search the part before the comment
            search_line = line[:comment_pos]
        else:
            search_line = line

        # Count matches in this line
        matches = pattern.findall(search_line)
        count += len(matches)

    return count


def process_file(file_path: Path) -> Tuple[bool, List[str]]:
    """
    Process a single Solidity file to remove unused imports.
    
    Returns: (was_modified, list_of_removed_imports)
    """
    with open(file_path, 'r', encoding='utf-8') as f:
        content = f.read()
    
    imports = parse_imports(content)
    
    if not imports:
        return False, []
    
    removed_imports = []
    lines = content.split('\n')
    lines_to_remove = set()
    lines_to_modify = {}
    
    for line_num, full_line, symbols, from_path in imports:
        used_symbols = []
        unused_symbols = []
        
        for symbol in symbols:
            occurrences = count_symbol_occurrences(content, symbol, line_num)
            if occurrences > 0:
                used_symbols.append(symbol)
            else:
                unused_symbols.append(symbol)
        
        if unused_symbols:
            if not used_symbols:
                # All symbols are unused - remove the entire line
                lines_to_remove.add(line_num)
                removed_imports.append(f"{full_line.strip()} (all symbols unused)")
            else:
                # Some symbols are used - keep only the used ones
                new_import = f'import {{{", ".join(used_symbols)}}} from "{from_path}";'
                # Preserve original indentation
                indent = len(full_line) - len(full_line.lstrip())
                new_import = ' ' * indent + new_import
                lines_to_modify[line_num] = new_import
                removed_imports.append(f"{full_line.strip()} -> removed: {', '.join(unused_symbols)}")
    
    if not removed_imports:
        return False, []
    
    # Apply modifications
    new_lines = []
    for i, line in enumerate(lines):
        if i in lines_to_remove:
            continue  # Skip this line entirely
        elif i in lines_to_modify:
            new_lines.append(lines_to_modify[i])
        else:
            new_lines.append(line)
    
    new_content = '\n'.join(new_lines)
    
    # Write back to file
    with open(file_path, 'w', encoding='utf-8') as f:
        f.write(new_content)
    
    return True, removed_imports


def main():
    """Main function to process all Solidity files."""
    base_dirs = ['test/', 'src/', 'script/']
    
    print("=" * 80)
    print(f"Scanning directories: {', '.join(base_dirs)}")
    print()
    
    sol_files = find_sol_files(base_dirs)
    print(f"Found {len(sol_files)} .sol files")
    print()
    
    total_modified = 0
    total_imports_removed = 0
    
    for file_path in sorted(sol_files):
        was_modified, removed_imports = process_file(file_path)
        
        if was_modified:
            total_modified += 1
            total_imports_removed += len(removed_imports)
            
            print(f"✓ {file_path}")
            for removed in removed_imports:
                print(f"  - {removed}")
            print()
    
    print("=" * 80)
    print(f"Summary:")
    print(f"  Files processed: {len(sol_files)}")
    print(f"  Files modified: {total_modified}")
    print(f"  Imports removed/modified: {total_imports_removed}")
    print("=" * 80)


if __name__ == "__main__":
    main()

