# 0004 — Read messages no parser rule matched

**Status:** Implemented
**Date:** 2026-10-30

## Problem

A message from a selected bank or wallet that no ujumbe rule matches goes to the review inbox,
but the app had no screen for it: the text sat encrypted on the phone, unseen, and the money in
it never reached the ledger. New institutions, Saccos and reworded alerts all land there.

## What it does

- **Home** shows "3 messages to check" while the inbox holds any.
- **Messages to check** lists them, each with what the reader suggests ("Money out · 1,250 to
  Example Grocers").
- **Check this message** shows the text with each found field tinted, the suggested amount,
  payee, date and time, balance and receipt, and money out or in. Every value can be changed;
  a field the reader is unsure of says "Check this". **Add transaction** adds it to the
  institution's account; **Not a transaction** sets it aside. Either way the message text is
  deleted and only its hash stays.
- **Read messages like this the same way** (on by default) keeps the message's layout: the
  words around the fields in lower case, numbers only as their layout (`#9,999.99`), codes as
  `#mixed`, and each field as an empty slot. It stays in the encrypted database on the phone. A later message
  from the same institution that fits is added during capture without asking. Fields the
  person changed are left out of the layout; a changed amount saves none.

## How it reads

- `lib/src/domain/reader/`: the tokeniser and model input from pesaclarity-ml `docs/READER.md`
  (schema 1, checked against the copied vectors), decoding of the model's per-token labels,
  value parsing (amounts, day-first dates, 12 and 24 hour times, payee clean-up), the rules
  reader and templates.
- **Model or rules.** A trained reader (`reader.tflite` with `reader-manifest.json`) is used when
  installed in the app's `reader` folder and its manifest, size and SHA-256 check out; otherwise
  `RuleMessageReader` (currency next to a number, date and time shapes, the payee after "to",
  "from" or "at"). No model ships with the app yet: weights wait for the model licence.
- On synthetic messages, with each sentence layout held out of training in turn, the model's
  mean F1 is about 0.86 for the amount, 0.85 for the payee and 0.99 for the date; real messages
  will score lower, so nothing is added without the person, except through a layout they saved.

## Data

`ReaderTemplates` (schema 14): institution id, the template as JSON (the words around the
fields, numbers as layouts, fields as slots; no amounts, names or dates), created at. Transactions from the reader use source `sms`, the message hash, and ujumbe's
dedupe key from receipt, amount and minute, so a later statement import does not double them.

## Not done

- Shipping trained weights (needs the model licence decision).
- Editing or deleting saved layouts.
