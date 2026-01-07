#!/usr/bin/env python3
"""
md2guide.py - Convert Markdown to AmigaGuide format

Usage: md2guide.py input.md [output.guide]

Supports:
  - Headings (# ## ###) -> @node sections
  - Bold (**text**) -> @{b}text@{ub}
  - Italic (*text*) -> @{i}text@{ui}
  - Code (`code`) -> @{b}code@{ub}
  - Code blocks (```) -> verbatim with @{fg highlight}
  - Links [text](url) -> @{"text" link url} or plain URL
  - Lists (- item) -> bullet points
  - Horizontal rules (---) -> separator line

Author: Jaroslav Pulchart
License: LGPL v2.1
"""

import re
import sys
import os
from datetime import datetime


def escape_amigaguide(text):
    """Escape special AmigaGuide characters and replace non-ASCII"""
    # @ needs to be escaped as @@
    text = text.replace('@', '@@')
    # Replace common Unicode characters with ASCII equivalents
    replacements = {
        '→': '->',
        '←': '<-',
        '↔': '<->',
        '•': '*',
        '–': '-',
        '—': '--',
        '"': '"',
        '"': '"',
        ''': "'",
        ''': "'",
        '…': '...',
        '©': '(c)',
        '®': '(R)',
        '™': '(TM)',
        '×': 'x',
        '÷': '/',
        '≤': '<=',
        '≥': '>=',
        '≠': '!=',
        '±': '+/-',
        '✓': '[x]',
        '✗': '[ ]',
        '✔': '[x]',
        '✘': '[ ]',
        '☐': '[ ]',
        '☑': '[x]',
        '★': '*',
        '☆': '*',
        '●': '*',
        '○': 'o',
        '■': '#',
        '□': '[ ]',
        '▪': '-',
        '▫': '-',
    }
    for unicode_char, ascii_equiv in replacements.items():
        text = text.replace(unicode_char, ascii_equiv)
    # Remove any remaining non-ASCII characters
    text = text.encode('ascii', 'replace').decode('ascii')
    return text


def convert_inline(line, in_code_block=False):
    """Convert inline Markdown formatting to AmigaGuide"""
    if in_code_block:
        return escape_amigaguide(line)
    
    # Replace Unicode characters first
    line = escape_amigaguide(line)
    # Note: escape_amigaguide already handles @ -> @@
    
    # Bold: **text** or __text__
    line = re.sub(r'\*\*([^*]+)\*\*', r'@{b}\1@{ub}', line)
    line = re.sub(r'__([^_]+)__', r'@{b}\1@{ub}', line)
    
    # Italic: *text* or _text_ (but not inside words)
    line = re.sub(r'(?<!\w)\*([^*]+)\*(?!\w)', r'@{i}\1@{ui}', line)
    line = re.sub(r'(?<!\w)_([^_]+)_(?!\w)', r'@{i}\1@{ui}', line)
    
    # Inline code: `code`
    line = re.sub(r'`([^`]+)`', r'@{b}\1@{ub}', line)
    
    # Links: [text](url)
    # Internal links (to .md files or anchors) -> AmigaGuide links
    def convert_link(match):
        text = match.group(1)
        url = match.group(2)
        # Internal .md link -> link to .guide file
        if url.endswith('.md'):
            # Get just the filename, replace .md with .guide
            guide_file = os.path.basename(url)[:-3] + '.guide'
            # Also update link text if it contains .md
            display_text = text.replace('.md', '.guide')
            return f'@{{"  {display_text}  " link "{guide_file}/Main"}}'
        # Anchor link
        elif url.startswith('#'):
            node = url[1:].replace('-', '_')
            return f'@{{"{text}" link {node}}}'
        # External URL -> just show text and URL
        else:
            return f'{text} ({url})'
    
    line = re.sub(r'\[([^\]]+)\]\(([^)]+)\)', convert_link, line)
    
    return line


def extract_nodes(lines):
    """Extract heading structure to create node links"""
    nodes = []
    for line in lines:
        match = re.match(r'^(#{1,3})\s+(.+)$', line)
        if match:
            level = len(match.group(1))
            title = match.group(2)
            node_name = re.sub(r'[^a-zA-Z0-9_]', '_', title)
            nodes.append((level, title, node_name))
    return nodes


def format_table(table_lines):
    """Convert markdown table to formatted AmigaGuide table"""
    if not table_lines:
        return []
    
    # Parse table
    rows = []
    for line in table_lines:
        # Remove leading/trailing pipes and split
        cells = [escape_amigaguide(c.strip()) for c in line.strip('|').split('|')]
        rows.append(cells)
    
    if len(rows) < 2:
        return table_lines  # Not a valid table
    
    # Skip separator row (second row with ---)
    header = rows[0]
    data_rows = [r for r in rows[1:] if not all(c.replace('-', '').replace(':', '') == '' for c in r)]
    
    # Calculate column widths
    num_cols = len(header)
    col_widths = [len(h) for h in header]
    for row in data_rows:
        for i, cell in enumerate(row[:num_cols]):
            col_widths[i] = max(col_widths[i], len(cell))
    
    # Build formatted table
    result = []
    result.append('')
    
    # Header with bold
    header_line = '  '
    for i, h in enumerate(header):
        header_line += f'@{{b}}{h.ljust(col_widths[i])}@{{ub}}  '
    result.append(header_line)
    
    # Separator
    sep_line = '  ' + '  '.join('-' * w for w in col_widths)
    result.append(sep_line)
    
    # Data rows
    for row in data_rows:
        data_line = '  '
        for i in range(num_cols):
            cell = row[i] if i < len(row) else ''
            data_line += cell.ljust(col_widths[i]) + '  '
        result.append(data_line)
    
    result.append('')
    return result


def wrap_text(text, width=72):
    """Wrap text to specified width, preserving words"""
    if len(text) <= width:
        return [text]
    
    words = text.split()
    lines = []
    current_line = []
    current_len = 0
    
    for word in words:
        word_len = len(word)
        if current_len + word_len + (1 if current_line else 0) <= width:
            current_line.append(word)
            current_len += word_len + (1 if len(current_line) > 1 else 0)
        else:
            if current_line:
                lines.append(' '.join(current_line))
            current_line = [word]
            current_len = word_len
    
    if current_line:
        lines.append(' '.join(current_line))
    
    return lines


def md2guide(md_content, title=None, version="1.0", date=None):
    """Convert Markdown content to AmigaGuide format"""
    
    if date is None:
        date = datetime.now().strftime("%d.%m.%Y")
    
    lines = md_content.split('\n')
    nodes = extract_nodes(lines)
    
    # Extract title from first H1 if not provided
    if title is None:
        for level, heading, _ in nodes:
            if level == 1:
                title = heading
                break
        if title is None:
            title = "Documentation"
    
    # Build output
    output = []
    
    # Database header
    output.append(f'@database "{title}"')
    output.append(f'@$VER: {title.replace(" ", "_")}.guide {version} ({date})')
    output.append(f'@author "Generated by md2guide.py"')
    output.append(f'@(c) "See LICENSE"')
    output.append('')
    
    # Main node with table of contents
    output.append('@node Main "Table of Contents"')
    output.append('')
    output.append(f'@{{b}}{title}@{{ub}}')
    output.append('')
    
    # Generate hierarchical TOC from H2 and H3 headings
    current_h2 = None
    for level, heading, node_name in nodes:
        if level == 2:
            output.append(f'    @{{"  {heading}  " link {node_name}}}')
            current_h2 = node_name
        elif level == 3 and current_h2:
            output.append(f'        @{{"  {heading}  " link {node_name}}}')
    
    output.append('')
    output.append('@endnode')
    output.append('')
    
    # Build node index for navigation
    node_list = ['Main']  # Main is first
    for level, heading, node_name in nodes:
        if level <= 3:  # Only H1-H3 create nodes
            node_list.append(node_name)
    
    def get_nav_links(current_idx):
        """Generate navigation links for a node"""
        nav = []
        nav.append('')
        nav.append('-' * 40)
        links = []
        if current_idx > 0:
            prev_node = node_list[current_idx - 1]
            links.append(f'@{{"<< Prev" link {prev_node}}}')
        links.append('@{"Contents" link Main}')
        if current_idx < len(node_list) - 1:
            next_node = node_list[current_idx + 1]
            links.append(f'@{{"Next >>" link {next_node}}}')
        nav.append('  '.join(links))
        return nav
    
    # Process content into nodes
    current_node = None
    current_node_idx = 0
    current_content = []
    in_code_block = False
    in_table = False
    table_lines = []
    code_lang = None
    
    for line in lines:
        # Code block handling
        if line.startswith('```'):
            if not in_code_block:
                in_code_block = True
                code_lang = line[3:].strip()
                current_content.append('')
                current_content.append('@{fg highlight}')
            else:
                in_code_block = False
                current_content.append('@{fg text}')
                current_content.append('')
            continue
        
        if in_code_block:
            current_content.append('  ' + escape_amigaguide(line))
            continue
        
        # Table handling
        is_table_line = line.strip().startswith('|') and line.strip().endswith('|')
        if is_table_line:
            if not in_table:
                in_table = True
                table_lines = []
            table_lines.append(line)
            continue
        elif in_table:
            # End of table, format and add
            in_table = False
            formatted = format_table(table_lines)
            current_content.extend(formatted)
            table_lines = []
            # Continue processing current line
        
        # Heading - start new node (H1-H3) or inline heading (H4+)
        match = re.match(r'^(#{1,6})\s+(.+)$', line)
        if match:
            level = len(match.group(1))
            heading = match.group(2)
            
            # H4+ headings are inline, not new nodes
            if level >= 4:
                current_content.append('')
                current_content.append(f'@{{b}}{convert_inline(heading)}@{{ub}}')
                continue
            
            # Save previous node
            if current_node:
                # Remove trailing empty lines
                while current_content and current_content[-1] == '':
                    current_content.pop()
                # Add navigation links
                current_content.extend(get_nav_links(current_node_idx))
                output.extend(current_content)
                output.append('')
                output.append('@endnode')
                output.append('')
            
            node_name = re.sub(r'[^a-zA-Z0-9_]', '_', heading)
            
            # Find index of this node
            if node_name in node_list:
                current_node_idx = node_list.index(node_name)
            
            current_node = node_name
            current_content = []
            output.append(f'@node {node_name} "{heading}"')
            
            if level == 1:
                current_content.append(f'@{{b}}@{{u}}{heading}@{{uu}}@{{ub}}')
            elif level == 2:
                current_content.append(f'@{{b}}{heading}@{{ub}}')
            else:
                current_content.append(f'@{{i}}{heading}@{{ui}}')
            current_content.append('')
            continue
        
        # Horizontal rule
        if re.match(r'^-{3,}$|^\*{3,}$|^_{3,}$', line):
            current_content.append('')
            current_content.append('=' * 60)
            current_content.append('')
            continue
        
        # List item
        if re.match(r'^\s*[-*+]\s+', line):
            item = re.sub(r'^\s*[-*+]\s+', '', line)
            current_content.append(f'  * {convert_inline(item)}')
            continue
        
        # Numbered list
        match = re.match(r'^\s*(\d+)\.\s+(.+)$', line)
        if match:
            num = match.group(1)
            item = match.group(2)
            current_content.append(f'  {num}. {convert_inline(item)}')
            continue
        
        # Regular line - wrap long lines
        converted = convert_inline(line)
        if len(converted) > 75 and not line.startswith('|'):  # Don't wrap tables
            wrapped = wrap_text(converted, 72)
            current_content.extend(wrapped)
        else:
            current_content.append(converted)
    
    # Close last node
    if current_node:
        # Remove trailing empty lines
        while current_content and current_content[-1] == '':
            current_content.pop()
        # Add navigation links
        current_content.extend(get_nav_links(current_node_idx))
        output.extend(current_content)
        output.append('')
        output.append('@endnode')
    
    # Post-process: remove multiple consecutive empty lines
    result = []
    prev_empty = False
    for line in output:
        is_empty = line.strip() == ''
        if is_empty and prev_empty:
            continue  # Skip consecutive empty lines
        result.append(line)
        prev_empty = is_empty
    
    return '\n'.join(result)


def main():
    if len(sys.argv) < 2:
        print("Usage: md2guide.py input.md [output.guide] [--version X.Y] [--date DD.MM.YYYY]")
        print("")
        print("Converts Markdown to AmigaGuide format.")
        print("")
        print("Options:")
        print("  --version X.Y       Set version string (default: 1.0)")
        print("  --date DD.MM.YYYY   Set date (default: today)")
        print("  --title TITLE       Set document title (default: from H1)")
        sys.exit(1)
    
    input_file = sys.argv[1]
    
    # Parse optional arguments
    output_file = None
    version = "1.0"
    date = None
    title = None
    
    i = 2
    while i < len(sys.argv):
        arg = sys.argv[i]
        if arg == '--version' and i + 1 < len(sys.argv):
            version = sys.argv[i + 1]
            i += 2
        elif arg == '--date' and i + 1 < len(sys.argv):
            date = sys.argv[i + 1]
            i += 2
        elif arg == '--title' and i + 1 < len(sys.argv):
            title = sys.argv[i + 1]
            i += 2
        elif not arg.startswith('--'):
            output_file = arg
            i += 1
        else:
            i += 1
    
    if output_file is None:
        output_file = os.path.splitext(input_file)[0] + '.guide'
    
    # Read input
    with open(input_file, 'r', encoding='utf-8') as f:
        md_content = f.read()
    
    # Convert
    guide_content = md2guide(md_content, title=title, version=version, date=date)
    
    # Write output
    with open(output_file, 'w', encoding='iso-8859-1') as f:
        f.write(guide_content)
    
    print(f"Converted: {input_file} -> {output_file}")


if __name__ == '__main__':
    main()

