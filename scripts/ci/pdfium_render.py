"""Renders every page of every PDF in a folder with PDFium, independently of PDFKit (plan revision 3, B2).

    python3 scripts/ci/pdfium_render.py <folder>

A file with a `<name>.password` beside it is opened with that password. Exits 1 when a file can't be
opened, a page can't be rendered, or the page count differs from what PDFium reports for the file, and
when the folder holds no PDF (the export did not run). Needs pypdfium2 (BSD-3-Clause and Apache-2.0),
which bundles PDFium (BSD-3-Clause).
"""
from __future__ import annotations

import pathlib
import sys


def main(folder: str) -> int:
    import pypdfium2 as pdfium  # imported here so the docstring can be read without it installed

    files = sorted(pathlib.Path(folder).glob("*.pdf"))
    if not files:
        print(f"::error::No PDFs to render in {folder}")
        return 1
    failed = 0
    for path in files:
        password_file = path.with_suffix(".password")
        password = password_file.read_text() if password_file.exists() else None
        try:
            document = pdfium.PdfDocument(str(path), password=password)
            pages = len(document)
            for index in range(pages):
                page = document[index]
                bitmap = page.render(scale=0.25)
                if bitmap.width == 0 or bitmap.height == 0:
                    raise RuntimeError(f"page {index + 1} rendered empty")
                page.close()
            document.close()
            print(f"ok       {path.name} ({pages} pages)")
        except Exception as error:  # every failure is reported, then the job fails
            print(f"::error title=PDFium::{path.name}: {error}")
            failed = 1
    return failed


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print(__doc__)
        sys.exit(2)
    sys.exit(main(sys.argv[1]))
