# Play Console answers (draft)

Draft answers for the Play Console forms the first release needs. Nothing here has been submitted. Every answer must match the privacy policy (`assets/policy/privacy_policy.md`) and what the app and server actually do; change all three together.

Package: `com.pesaclarity.app` (the `play` flavour).

## SMS and Call Log permissions declaration

**App content → Sensitive app permissions → SMS and Call Log.**

- **Permissions:** `READ_SMS`, `RECEIVE_SMS`. No Call Log permissions.
- **Core functionality:** SMS-based money management.
- **Is the app the default SMS handler?** No.

**How the app uses these permissions** (draft text for the form):

> Pesa Clarity is a budgeting app for Kenya. It builds the user's budget from the transaction messages their bank and M-Pesa send them. During setup the user ticks the banks and wallets they use; the app reads past messages and receives new ones from those senders only. Messages from every other sender are ignored and never stored. Each message is parsed on the phone into amount, date, payee, balance and fee, and the message text is then discarded. Nothing from the messages is sent to any server. Without SMS access the app cannot see transactions, which is its core feature; the user can import an M-Pesa statement PDF instead.

**Demo video** (link required). Record on a test phone with synthetic messages only, never real ones:

1. Welcome screen, then "Which accounts do you use?" with the explanation of which senders are read.
2. Ticking M-Pesa and a bank, then the Android permission prompt.
3. The scan, then Home and Activity showing the transactions found.

## Data safety

**App content → Data safety.**

| Question | Answer |
| --- | --- |
| Does the app collect or share user data? | Yes (collect) |
| Is all collected data encrypted in transit? | Yes (https only; cleartext is off) |
| Can users ask for their data to be deleted? | Yes, in the app (delete account) and by request |
| Shared with third parties? | No |

Collected data types, all **optional** (the app works without an account):

| Data type | What exactly | Purpose |
| --- | --- | --- |
| Personal info → Email address | Sign-in email. The server keeps only a keyed hash of it; the email passes through the email provider (Brevo) to send the code. | Account management |
| Device or other IDs | A server-issued device id and the device name shown in the devices list | Account management, security |

Not collected, and why:

- **SMS, financial info, transactions, statements:** processed only on the phone.
- **Vault backups:** encrypted on the phone with the user's passphrase before upload; the server cannot read them. Check Play's current guidance on end-to-end encrypted data before submitting.
- **Federated model updates:** not sent yet (the server side is pesaclarity-backend#8). Declare them when they ship.
- **Crash reports and analytics:** the app has none.

## Before submitting

- [ ] The privacy policy is published at a public URL (pesaclarity-web#3) and added to the store listing.
- [ ] The privacy policy names the device name the server keeps; it currently does not.
- [ ] A web page or link where people can ask to delete their account without the app; Play asks for this URL in the Data safety form.
- [ ] You have approved this wording.
