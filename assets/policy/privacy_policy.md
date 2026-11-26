# Privacy policy

## The short version

Pesa Clarity works out your budget on your phone. Your transactions,
messages, statements and the questions you ask about them stay on it. Our server does five narrow jobs
and never sees a transaction. If you turn on Firefly III sync, your
transactions are sent from your phone to the Firefly III server you
choose, and never to ours.

## What stays on your phone

- Messages from the banks and wallets you choose. Messages from every other sender are ignored and never stored.
- On iPhone, messages come from a Shortcuts automation you set up. Each one waits in a file only Pesa Clarity can open until the app reads it, for at most 35 days.
- The fields read from those messages: amount, date, payee, balance and fee. Once a message is read, its text is deleted.
- Messages the app is still learning. They wait in Messages to check until you check them, then their text is deleted. The suggestions come from a reader that runs on your phone.
- Layouts you save with "Read messages like this the same way". A layout keeps the message's wording with the amount, payee, date and other details taken out, and numbers reduced to their shape, such as 9,999.99.
- Statement PDFs. Their passwords are used once, in memory, then discarded. PDFs are never uploaded.
- Budgets, debts, goals, payees, categories and every insight.
- In a business space: customers' and suppliers' names and what they owe, the phone numbers you add or pick from your contacts (the app gets only the contact you pick), and the pictures and documents kept for receipts and invoices, such as your logo, your M-PESA QR code and receipts you attach.
- Receipts, invoices and reports are made on your phone. They leave it only when you share or print them, in the app or on the printer you choose. A Bluetooth receipt printer you pair gets only what you print.

All of this sits in an encrypted database. The key is held by your
phone's secure hardware. With app lock on, it is released only after you
unlock the app with your PIN, fingerprint or Face ID. Without app lock,
it is released when the app opens.

## Ask

Ask answers questions about your money in your own words, such as "how
much did I spend on food last month?". Small models that ship inside the
app read your question and word the answer, on your phone. Every number
comes from your own records in the space you have open.

- Nothing is sent anywhere. Your questions, the answers and the records they come from never leave your phone, and Ask works without internet.
- Ask has no federated learning. "Improve the app" never includes anything from Ask.
- Conversations are kept in the space's encrypted database for as long as you choose in Ask settings: until you delete them, or for a year, 90, 30 or 7 days. You can also switch saving off.
- Words you teach Ask, such as "chakula" for Food, stay in that space too.
- You can delete one conversation, or every conversation in a space. Backups leave conversations out.

## What our server holds

**Sign-in**

Your account id, the email or Google account you sign in with, and when
you signed up, in and out. Our server stores your email or Google
account only as a keyed hash, never the address itself. One-time sign-in codes are deleted within a
day of expiring, and sign-in records after 90 days. You can also use
the app without an account; it then contacts our server only for the
update check and any crash report you choose to send.

**Encrypted backups**

If you choose our vault, backups are encrypted on your phone with your
passphrase before upload. We hold only the encrypted file and cannot
read it. We keep your latest 10 backups and delete older ones. The
server checks with Google (Android) or Apple (iPhone) that each backup
comes from the genuine app; neither sees the backup. You can back up to
your own Google Drive, your phone, an SD card or Files on iPhone instead.

**Model updates**

The app does not send any training updates today. With "Help improve
the app" on, it only learns from the categories you confirm, on your
phone, to make its own suggestions better; nothing about it leaves the
phone. If we ever add sending updates to improve the shared model, it
will be opt-in, and we will update this policy before it starts.

**Update check**

Once a day, with or without an account, the app asks our server whether
a newer version or a notice is waiting, such as a fix for a bank that
changed its messages. The request carries the app's version, which build
it is (Play, F-Droid, iPhone or website) and the platform, and, unless
you switch it off, the counting number described below. It carries no
account, device or phone id. The answer is signed, so the app shows only
notices that really come from us. The app asks you to update before you
carry on only when a version is known to get amounts wrong.

**Monthly count**

So we know how many phones use Pesa Clarity, the update check carries a
random number that your phone makes each month and replaces on the 1st
of the next. It is not made from anything about you or your phone, and
it is never sent with anything else. Our server uses it only to count
each phone once a day and once a month, adding one to totals by app
version, build and, for the month, country. It keeps those totals, which
name no one. It keeps a scrambled copy of the number only until the day
or month is over, then deletes it. We work out the country from your
internet address while answering, with a database kept on our server
(IP Geolocation by DB-IP, db-ip.com), and never store or log the
address. We never look at a total under 10. To stop, switch off "Count
this phone in monthly totals" in Privacy; the update check carries on
without the number. In the F-Droid build it is off until you switch it
on, and the update check itself runs only after you say yes to it.

**Crash reports**

If the app closes because of a fault, it asks on the next start whether
to send us a crash report, and shows you exactly what it would send. A
report holds the app's version and build, the phone's system version
(such as Android 13) and chip type (such as arm64), the kind of error,
and where in the app's own code it happened, as numbers. It never holds
amounts, messages, names, phone numbers, contacts or anything you typed,
and it carries no account, device or install id. It is not linked to
the monthly count. We keep reports for 90 days, then only how many there
were and when. In Privacy you can choose Ask each time, Always send or
Never send.

## Who runs our server

These services run it for us and process data only on our instructions:

- Google Cloud runs the server. Like any web host, it keeps standard request logs, such as IP address and time, for security. It keeps no request logs for the update check or crash reports, and its other logs never include the counting number or crash reports' contents.
- Neon stores sign-in data in its database.
- Cloudflare R2 stores encrypted backups.
- Brevo sends sign-in codes by email.

If you ask us to email you a copy of this policy, Brevo sends it to the
address you give. We use that address once and do not keep it.

Some of them store data outside Kenya. We use them under their data
processing terms, as the Kenya Data Protection Act 2019 requires for
transfers abroad.

## Shared spaces

A Household or a chama/savings group space can be shared with other
people. Members share that space's budget, transactions, goals and
member list. Your personal space is never included.

- You share by sending an encrypted file (.pcshare) through any app you choose, such as WhatsApp, email or Bluetooth. Our server is not involved.
- Each file is end-to-end encrypted with AES-256-GCM, using a key for that space and each member's X25519 key. The app that carries the file, and Pesa Clarity, cannot read it.
- When you join, your phone makes its own key. The private key never leaves your phone. A join request holds your name and public key, and safety words let you both check it.
- Approvals and declines are signed on the approver's phone. A record of who changed or approved what is kept in the space's history on members' phones.
- The camera is used only to scan join and invite QR codes. The images are not stored or sent.
- Members you share with can see the shared space's data and keep copies. Leaving or removing someone stops future updates, but cannot erase copies already on their phones.
- Shared data stays on members' phones, encrypted. Deleting a space deletes it from your phone.

## Firefly III

Firefly III is a free personal finance manager that people run on their
own server. Pesa Clarity can send your transactions to it, so you do not
have to type them in again.

- It is off until you turn it on in Profile. You choose the server, which spaces to send and from which date.
- For each transaction the app sends the amount, date, payee, category, account names and notes, such as the M-Pesa code. It also sends each account's balance on the start date and the space's name as a tag. It never sends message text.
- It sends them from your phone straight to the server address you type. Nothing goes through our server, and we never see what is sent.
- Changes and deletes in the app are sent too. Nothing is read back from your server.
- Your Firefly III token stays in your phone's secure storage. It is sent only to your server, and never put in a backup, a log or a crash report.
- Turning it off stops sending and removes the token from your phone. What was already sent stays on your server. Deleting a space stops sending it; what was sent stays too.
- We cannot see or delete anything on your server. You look after it and who can reach it.

## Exchange rates

To count money in other currencies, the app downloads today's exchange
rates from a public rates service. The request carries only your base
currency's code, such as KES; the service sees your IP address, as any
website does. You can set your own rates instead.

## Giving (F-Droid build)

The F-Droid build has a Support screen for anyone who wants to give a
small gift by M-Pesa. Giving is your choice and never unlocks anything.

- The Support screen opens CitaPay's page in your browser. Its address carries only the amount you chose.
- CitaPay, run by Citatech, and Safaricom's M-Pesa process the payment. They see what any M-Pesa payment shows, such as your phone number and name, plus the amount and any note you type.
- CitaPay's terms cover the payment: pay.citatech.cloud/legal/terms.
- Pesa Clarity receives only the money and the M-Pesa notice of it.
- The app sends nothing to CitaPay. To say thank you, it recognises your gift from your own M-Pesa message, on your phone.

## Your choices

The app asks on first run, and you can change these any time:

- Help improve the app: on by default. Today it only lets the app learn from your confirmed categories on your phone; nothing is sent.
- Contribute to licensed models: off unless you opt in.
- Count this phone in monthly totals: on by default; off by default in the F-Droid build.
- Crash reports: the app asks each time, unless you choose Always send or Never send.
- Firefly III sync: off unless you turn it on.

Pesa Clarity has no ads and no third-party trackers, and no analytics beyond the monthly count above.

## Keeping it safe

Data on your phone is encrypted, and everything sent to our server
travels over an encrypted connection. Firefly III sync uses an encrypted
connection too, unless you choose a plain one to a server on your home
network. Deleting your account removes
your account, sign-in records and vault backups from our server.

## Your rights

Under the Kenya Data Protection Act 2019 you can ask to see, correct or
delete the data we hold about you, take a copy with you, and object to
how it is used or to automated decisions. To ask, write to our Data
Protection Officer, Dan Njuguna, at njugunahdann@gmail.com. We will
answer within 30 days. You can delete your account from inside the app.
If you are unhappy with our answer, you can complain to the Office of
the Data Protection Commissioner (odpc.go.ke).

Pesa Clarity is for people aged 18 and over.

## This website

This site sets no cookies, runs no analytics and loads nothing from
other servers. Fonts are served from this site. If you choose a light or
dark theme, your browser keeps that choice on your device; it is never
sent to us. The site runs two small scripts: one switches the theme, and
one searches the site in your browser. Nothing you type is sent anywhere. The web host may
keep standard request logs, such as IP address and time, for security.

## Changes

When this policy changes, the app shows what changed and asks you to
read it before you carry on.

## Questions

Write to our Data Protection Officer, Dan Njuguna, at
njugunahdann@gmail.com. You can also ask in public on GitHub
(github.com/pesaclarity), or report a security issue privately using the
security policy there.
