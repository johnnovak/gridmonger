#!/usr/bin/env python3

# Indexer v.1.0.1
# Author: Josh Brunty (josh dot brunty at marshall dot edu)
# DESCRIPTION: This script generates an .html index  of files within a directory (recursive is OFF by default). Start from current dir or from folder passed as first positional argument. Optionally filter by file types with --filter "*.py".

# -handle symlinked files and folders: displayed with custom icons
# By default only the current folder is processed.
# Use -r or --recursive to process nested folders.

import argparse
import datetime
import os
import sys
from pathlib import Path
from urllib.parse import quote

DEFAULT_OUTPUT_FILE = 'index.html'


def process_dir(top_dir, opts):
    glob_patt = opts.filter or '*'

    path_top_dir: Path
    path_top_dir = Path(top_dir)
    index_file = None

    index_path = Path(path_top_dir, opts.output_file)

    if opts.verbose:
        print(f'Traversing dir {path_top_dir.absolute()}')

    try:
        index_file = open(index_path, 'w', encoding='utf-8')
    except Exception as e:
        print('cannot create file %s %s' % (index_path, e))
        return

    index_file.write("""<!DOCTYPE html>
<html>
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <link rel="preconnect" href="https://fonts.googleapis.com">
    <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
    <link href="https://fonts.googleapis.com/css2?family=Alegreya:ital,wght@0,400..500;1,400..500&display=swap" rel="stylesheet">
    <link href="https://fonts.googleapis.com/css2?family=Alegreya+SC&family=Alegreya:ital,wght@0,400..900;1,400..900&display=swap" rel="stylesheet">
    <style>
    * { padding: 0; margin: 0; }
    body {
        max-width: 900px;
        margin: 0 auto;
        background-color: #d8d0c5;
        color: #4e4336;
        font: 500 20px/1.0em "Alegreya", serif;
    }
    a {
        color: #b86622;
        text-decoration: none;
    }
    a:hover {
        color: #9d5111;
        text-decoration: underline;
    }
    header,
    #summary {
        margin-top: 3em;
        padding-left: 33px;
    }
    th:first-child,
    td:first-child {
        width: 5%;
    }
    th:last-child,
    td:last-child {
        width: 5%;
    }
    p.back {
        font: 600 23px/1.5em "Alegreya SC", serif;
        text-align: center;
        margin: 3em 0;
    }
    h1 {
        font: 600 34px/1.5em "Alegreya SC", serif;
        white-space: nowrap;
        text-overflow: ellipsis;
    }
    main {
        display: block;
    }
    table {
        width: 100%;
        border-collapse: collapse;
        margin-bottom: 5em;
    }
    tr {
        border-bottom: 1px dashed #4e433650;
    }
    th,
    td {
        text-align: left;
        padding: 10px 0;
    }
    th {
        padding-top: 15px;
        padding-bottom: 15px;
        white-space: nowrap;
    }
    td {
        white-space: nowrap;
    }
    td:nth-child(2) {
        width: 80%;
    }
    th:nth-child(3),
    td:nth-child(3) {
        padding: 0 30px 0 20px;
        text-align: right;
    }
    th:nth-child(4),
    td:nth-child(4) {
        text-align: right;
    }
    td .name {
        margin-left: 20px;
        word-break: break-all;
        overflow-wrap: break-word;
        white-space: pre-wrap;
    }
    tr.clickable {
        cursor: pointer;
    }
    .icon {
        display: inline-flex;
        height: 22px;
        vertical-align: middle;
    }
    span.file {
      color: #4e4336;
    }
    .icon svg {
        width: 22px;
        max-height: 100%;
        fill: currentcolor;
    }
    </style>
</head>
<body>

  <header>
    <p class="back"><a href="/">&larr; Back to website</a></p>

    <h1>"""
                     f'{path_top_dir}'
                     """</h1>
                 </header>
                 <main>
                 <div class="listing">
                     <table aria-describedby="summary">
                         <thead>
                         <tr>
                             <th></th>
                             <th>Name</th>
                             <th>Size</th>
                             <th class="hideable">
                                 Modified
                             </th>
                             <th class="hideable"></th>
                         </tr>
                         </thead>
                         <tbody>
                         <tr class="clickable">
                             <td></td>
                             <td>
                               <span class="icon {icon_type}"><svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><path d="M21 21h-4v-7.5c0-1.93-1.57-3.5-3.5-3.5H11v4L4 8l7-6v4h2.5c4.14 0 7.5 3.36 7.5 7.5V21Z"/></svg></span>
                               <a href=".."><span class="name">..</span></a>
                             </td>
                             <td>&mdash;</td>
                             <td class="hideable">&mdash;</td>
                             <td class="hideable"></td>
                         </tr>
                 """)

    # sort dirs first
    sorted_entries = sorted(path_top_dir.glob(glob_patt), key=lambda p: (p.is_file(), p.name))

    entry: Path
    for entry in sorted_entries:

        # don't include index.html in the file listing
        if entry.name.lower() == opts.output_file.lower():
            continue

        if entry.is_dir() and opts.recursive:
            process_dir(entry, opts)

        # From Python 3.6, os.access() accepts path-like objects
        if (not entry.is_symlink()) and not os.access(str(entry), os.W_OK):
            print(f"*** WARNING *** entry {entry.absolute()} is not writable! SKIPPING!")
            continue
        if opts.verbose:
            print(f'{entry.absolute()}')

        size_bytes = -1  ## is a folder
        size_pretty = '&mdash;'
        last_modified = '-'
        last_modified_human_readable = '-'
        last_modified_iso = ''
        try:
            if entry.is_file():
                size_bytes = entry.stat().st_size
                size_pretty = pretty_size(size_bytes)

            if entry.is_dir() or entry.is_file():
                last_modified = datetime.datetime.fromtimestamp(entry.stat().st_mtime).replace(microsecond=0)
                last_modified_iso = last_modified.isoformat()
                last_modified_human_readable = last_modified.strftime("%c")

        except Exception as e:
            print('ERROR accessing file name:', e, entry)
            continue

        entry_path = str(entry.name)

        if entry.is_dir():
            icon_type = 'folder'
            svg_path = '<path d="M19 20H4a2 2 0 0 1-2-2V6c0-1.11.89-2 2-2h6l2 2h7a2 2 0 0 1 2 2H4v10l2.14-8h17.07l-2.28 8.5c-.23.87-1.01 1.5-1.93 1.5Z"/>'
            if os.name not in ('nt',):
                # append trailing slash to dirs, unless it's windows
                entry_path = os.path.join(entry.name, '')
        else:
            icon_type = 'file'
            svg_path = '<path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8l-6-6m4 18H6V4h7v5h5v11Z"/>'

        index_file.write(f"""
        <tr class="file">
            <td></td>
            <td>
                <span class="icon {icon_type}"><svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">{svg_path}</svg></span>
                <a href="{quote(entry_path)}">
                    <span class="name">{entry.name}</span>
                </a>
            </td>
            <td data-order="{size_bytes}">{size_pretty}</td>
            <td class="hideable"><time datetime="{last_modified_iso}">{last_modified_human_readable}</time></td>
            <td class="hideable"></td>
        </tr>
""")

    index_file.write("""
            </tbody>
        </table>

        <p class="back"><a href="/">&larr; Back to website</a></p>
    </div>
</main>
</body>
</html>""")
    if index_file:
        index_file.close()


# bytes pretty-printing
UNITS_MAPPING = [
    (1024 ** 5, ' PB'),
    (1024 ** 4, ' TB'),
    (1024 ** 3, ' GB'),
    (1024 ** 2, ' MB'),
    (1024 ** 1, ' KB'),
    (1024 ** 0, (' byte', ' bytes')),
]


def pretty_size(bytes, units=UNITS_MAPPING):
    """Human-readable file sizes.
    ripped from https://pypi.python.org/pypi/hurry.filesize/
    """
    for factor, suffix in units:
        if bytes >= factor:
            break
    amount = int(bytes / factor)

    if isinstance(suffix, tuple):
        singular, multiple = suffix
        if amount == 1:
            suffix = singular
        else:
            suffix = multiple
    return str(amount) + suffix


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description='''DESCRIPTION: This script generates an .html index  of files within a directory (recursive is OFF by default). Start from current dir or from folder passed as first positional argument. Optionally filter by file types with --filter "*.py"
Email josh dot brunty at marshall dot edu for additional help. ''')

    parser.add_argument('top_dir',
                        nargs='?',
                        action='store',
                        help='top folder from which to start generating indexes, '
                             'use current folder if not specified',
                        default=os.getcwd())

    parser.add_argument('--filter', '-f',
                        help='only include files matching glob',
                        required=False)

    parser.add_argument('--output-file', '-o',
                        metavar='filename',
                        default=DEFAULT_OUTPUT_FILE,
                        help=f'Custom output file, by default "{DEFAULT_OUTPUT_FILE}"')

    parser.add_argument('--recursive', '-r',
                        action='store_true',
                        help="recursively process nested dirs (FALSE by default)",
                        required=False)

    parser.add_argument('--verbose', '-v',
                        action='store_true',
                        help='***WARNING: can take longer time with complex file tree structures on slow terminals***'
                             ' verbosely list every processed file',
                        required=False)

    config = parser.parse_args(sys.argv[1:])
    process_dir(config.top_dir, config)
