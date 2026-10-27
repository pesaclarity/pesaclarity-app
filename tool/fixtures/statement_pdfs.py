"""Writes the synthetic M-Pesa statement PDFs in test/fixtures.

Every name, number and receipt is made up; never put real data here. The
layout follows the public M-Pesa statement table: fixed columns, details
wrapped inside their column, amounts right-aligned, withdrawals printed
negative, newest row first, and the header repeated on every page.

    pip install reportlab==5.0.1 pypdf==6.17.0
    python3 tool/fixtures/statement_pdfs.py

Writes synthetic_statement.pdf and synthetic_statement_locked.pdf (AES-128,
password 0000).
"""

from pathlib import Path

from pypdf import PdfReader, PdfWriter
from reportlab.lib.pagesizes import A4
from reportlab.pdfgen import canvas

OUT = Path(__file__).resolve().parents[2] / "test" / "fixtures"
FONT, SIZE, LEADING = "Helvetica", 8, 11
PAGE_W, PAGE_H = A4

# (receipt, completion time, details, paid in, withdrawn, balance), newest first.
ROWS = [
    ("TJA0000004", "2026-10-26 13:45:00",
     "Merchant Payment Online to 5000001 - EXAMPLE GROCERS", "", "-350.00", "5,135.00"),
    ("TJA0000001", "2026-10-26 09:15:42",
     "Customer Transfer of Funds Charge", "", "-15.00", "5,485.00"),
    ("TJA0000001", "2026-10-26 09:15:42",
     "Customer Transfer to - 0700***001 JANE DOE", "", "-1,500.00", "5,500.00"),
    ("TJA0000003", "2026-10-26 08:02:10",
     "Funds received from - 0700***002 JOHN KAMAU", "2,000.00", "", "7,000.00"),
]

# Left edges of text columns, right edges of amount columns.
COLS = {
    "receipt": 30, "time": 82, "details": 165, "status": 330,
    "paid_in": 440, "withdrawn": 500, "balance": 565,
}
HEADERS = [
    ("Receipt No.", "receipt", False), ("Completion Time", "time", False),
    ("Details", "details", False), ("Transaction Status", "status", False),
    ("Paid In", "paid_in", True), ("Withdrawn", "withdrawn", True),
    ("Balance", "balance", True),
]
DETAILS_WIDTH = 155


def wrap(c, text):
    lines, line = [], ""
    for word in text.split():
        trial = f"{line} {word}".strip()
        if line and c.stringWidth(trial, FONT, SIZE) > DETAILS_WIDTH:
            lines.append(line)
            line = word
        else:
            line = trial
    return lines + [line]


def draw(c, x, y, text, right=False):
    if right:
        c.drawRightString(x, y, text)
    else:
        c.drawString(x, y, text)


def header(c, y):
    for title, key, right in HEADERS:
        draw(c, COLS[key], y, title, right)
    c.line(28, y - 3, 567, y - 3)
    return y - LEADING - 2


def build(path, lines_on_first_page):
    c = canvas.Canvas(str(path), pagesize=A4, invariant=1)
    c.setFont(FONT, SIZE)
    y = PAGE_H - 40
    for text in ("M-PESA STATEMENT", "Customer Name: JOHN DOE",
                 "Statement Period: 01 Oct 2026 - 31 Oct 2026"):
        draw(c, 30, y, text)
        y -= LEADING
    y = header(c, y - 6)

    table = []
    for receipt, time, details, paid_in, withdrawn, balance in ROWS:
        chunks = wrap(c, details)
        table.append({"receipt": receipt, "time": time, "details": chunks[0],
                      "status": "Completed", "paid_in": paid_in,
                      "withdrawn": withdrawn, "balance": balance})
        table += [{"details": more} for more in chunks[1:]]

    page = 1
    for index, line in enumerate(table):
        if index == lines_on_first_page:
            draw(c, 30, 40, "Page 1 of 2")
            c.showPage()
            c.setFont(FONT, SIZE)
            page = 2
            y = header(c, PAGE_H - 40)
        for _, key, right in HEADERS:
            if line.get(key):
                draw(c, COLS[key], y, line[key], right)
        y -= LEADING
    draw(c, 30, 54, "Disclaimer: synthetic test statement, not a real record.")
    draw(c, 30, 40, f"Page {page} of 2")
    c.save()


def main():
    plain = OUT / "synthetic_statement.pdf"
    # Break after the first row's first line, so its wrapped details
    # continue under the repeated header on page 2.
    build(plain, lines_on_first_page=1)
    writer = PdfWriter(clone_from=PdfReader(plain))
    writer.encrypt(user_password="0000", owner_password=None, algorithm="AES-128")
    with open(OUT / "synthetic_statement_locked.pdf", "wb") as f:
        writer.write(f)


if __name__ == "__main__":
    main()
