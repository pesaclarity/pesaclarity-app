# Changelog

All notable changes to the app. Versions follow [semantic versioning](https://semver.org): until 1.0, a `feat` bumps the minor version and a `fix` the patch. Entries from 0.2.0 on are written by release-please from commit titles (pull request titles until pull requests into `dev` were rebase-merged).

## [0.5.9](https://github.com/pesaclarity/pesaclarity-app/compare/v0.5.8...v0.5.9) (2026-11-25)


### Features

* add group sync client for shared spaces, off by default ([6a0ef07](https://github.com/pesaclarity/pesaclarity-app/commit/6a0ef071c59e89ff178a489148aaa080a20a38d6))
* add group sync client for shared spaces, off by default ([fda7187](https://github.com/pesaclarity/pesaclarity-app/commit/fda7187dc1b41822131e065a5ed97dec96ae5ef5))
* **home:** money since payday ([6bea02c](https://github.com/pesaclarity/pesaclarity-app/commit/6bea02c7e1e17ebf082693195ad3d162d97cfaae))
* **home:** show money since payday instead of the calendar month ([393932c](https://github.com/pesaclarity/pesaclarity-app/commit/393932c657d9a7e881c5eae98bb3500c3c946009))
* rayo-only test builds and Model engine in Profile › About ([bccce39](https://github.com/pesaclarity/pesaclarity-app/commit/bccce3941b96c68d42deacbc246836c806b7a1a6))
* rayo-only test builds, model engine in Profile › About, on-device model test ([349d078](https://github.com/pesaclarity/pesaclarity-app/commit/349d078dbe7fb05e1d774d7b4fb7151c63b2e466))
* **sharing:** group sync screens behind the GROUP_SYNC switch ([d9d662b](https://github.com/pesaclarity/pesaclarity-app/commit/d9d662b0d83aaea7df82ce0499352beb95f4d566))
* **sharing:** group sync screens behind the GROUP_SYNC switch ([aa7dab3](https://github.com/pesaclarity/pesaclarity-app/commit/aa7dab34d044fe63a2eab3af2356c83222a587e7))
* **spaces:** group approvals for shared spaces ([90507d5](https://github.com/pesaclarity/pesaclarity-app/commit/90507d53bfb9c98eed809e99c217ad3df89e28bf))
* **spaces:** group approvals for shared spaces ([c7d7c35](https://github.com/pesaclarity/pesaclarity-app/commit/c7d7c35fbdbec8d5437bb1b92b6968b9cfc8dcd7))
* **spaces:** share a Household or chama space by encrypted file (0031 stage 1) ([58d60a8](https://github.com/pesaclarity/pesaclarity-app/commit/58d60a83813cc7831f3c8640c4fddd03e9052f6d))


### Fixes

* **activity:** keep a row's subtitle words whole at large text ([f5b3c7c](https://github.com/pesaclarity/pesaclarity-app/commit/f5b3c7cb3602de969463781aae04301d31eb4588))
* **balances:** give old agent cash its Cash side, warn when cash is below zero ([657cc09](https://github.com/pesaclarity/pesaclarity-app/commit/657cc099b48df6f18a5e7cc4805ffba063a9e667))
* **balances:** give old agent cash its Cash side, warn when cash is below zero ([c2a1079](https://github.com/pesaclarity/pesaclarity-app/commit/c2a10793cb5dee704dfcf237c3674d6466dd2d69))
* **balances:** totals follow a corrected balance and leave out untracked lines ([22900c2](https://github.com/pesaclarity/pesaclarity-app/commit/22900c20a5f997157976699259f707280bcf758a))
* **balances:** totals follow a corrected balance and leave out untracked lines ([0a6b1c7](https://github.com/pesaclarity/pesaclarity-app/commit/0a6b1c70222dc04f02c92f16a66d21b680e5e677))
* **categoriser:** ship the model trained on payees as statements and SMS give them ([21bfe08](https://github.com/pesaclarity/pesaclarity-app/commit/21bfe080653e98b47845240b361cb5d0f4d276ad))
* **categoriser:** ship the model trained on payees as statements and SMS give them ([ccb0c25](https://github.com/pesaclarity/pesaclarity-app/commit/ccb0c25fdb665914993b05ff2af26b39081332bf))
* **ios:** list privacy permissions in the AltStore source ([4c35200](https://github.com/pesaclarity/pesaclarity-app/commit/4c352002da6edb905a873b9f4e4b56d52192e446))
* **ios:** list privacy permissions in the AltStore source ([eb3f996](https://github.com/pesaclarity/pesaclarity-app/commit/eb3f9962ad2d1c46dbc752da357f3faa44d6099f))
* **ledger:** agent cash goes into a Cash account ([5b031f0](https://github.com/pesaclarity/pesaclarity-app/commit/5b031f0c2a81d71548a45ed668b1fb2855d80ff4))
* **ledger:** agent cash goes into a Cash account ([5d342db](https://github.com/pesaclarity/pesaclarity-app/commit/5d342dbfeb46f3af9b88de41079eb7e7e99de1d8))
* **ledger:** cash at an agent is the person's own money ([f8b7d0e](https://github.com/pesaclarity/pesaclarity-app/commit/f8b7d0eb54da8b75217165012b064a1293883b39))
* **ledger:** cash at an agent is the person's own money ([dae84c3](https://github.com/pesaclarity/pesaclarity-app/commit/dae84c3dd270f18c2f44227fa133c67cc22a5381))
* **ledger:** count Fuliza's access fee once ([9ea1ba5](https://github.com/pesaclarity/pesaclarity-app/commit/9ea1ba51f095b4018c10c045e85c0cca4ba48f2a))
* **ledger:** count Fuliza's access fee once ([a0d89a3](https://github.com/pesaclarity/pesaclarity-app/commit/a0d89a33f4c0b35b2821b4fc7e665a2024e64733))
* safe to spend follows the pay cycle, not the calendar month ([28a60bd](https://github.com/pesaclarity/pesaclarity-app/commit/28a60bd45d32517b8f9a6812b1011d8b213a95e7))
* safe to spend follows the pay cycle, not the calendar month ([d51778e](https://github.com/pesaclarity/pesaclarity-app/commit/d51778e81f75b7380bcf4696b4130c31922a4417))
* **spaces:** join a shared space in two steps; scan codes with the camera ([4383640](https://github.com/pesaclarity/pesaclarity-app/commit/4383640c8de81b0b2690c917e93fdf0022193934))
* **totals:** one spending rule, summary rows that add up, Plan refreshes ([6a0fc5f](https://github.com/pesaclarity/pesaclarity-app/commit/6a0fc5f32a34d98a67eee316f3e2ba49158a6bc8))
* **totals:** one spending rule, summary rows that add up, Plan refreshes ([edf725e](https://github.com/pesaclarity/pesaclarity-app/commit/edf725ecb1a278e60152c249b1a7568f9c541661))

## [0.5.8](https://github.com/pesaclarity/pesaclarity-app/compare/v0.5.7...v0.5.8) (2026-11-23)


### Features

* **accounts:** main line first, and a typed number for each line ([5e7de6f](https://github.com/pesaclarity/pesaclarity-app/commit/5e7de6f6fc8a4b7d9aa6abe86dfe07aaf95e63bc))
* **accounts:** manage many M-Pesa lines ([eda2fbb](https://github.com/pesaclarity/pesaclarity-app/commit/eda2fbb7b10cc9b3f031f5435d57c8bd7d8ef88d))


### Fixes

* **release-notes:** stop a note at the footer rule and generated-by lines ([2f6b3bf](https://github.com/pesaclarity/pesaclarity-app/commit/2f6b3bf9edda1703e4c8cdf5114ef4459955d8e3))
* SACCOs in What you own and owe; Plan leaves out family loan repayments ([bd1c50e](https://github.com/pesaclarity/pesaclarity-app/commit/bd1c50ef61efdf1279490ac8205f7634751a2c32))

## [0.5.7](https://github.com/pesaclarity/pesaclarity-app/compare/v0.5.6...v0.5.7) (2026-11-22)


### Features

* **accounts:** edit, hide or remove an account ([16ef2b3](https://github.com/pesaclarity/pesaclarity-app/commit/16ef2b3491e99778542541e796af6589220a5b89))
* **accounts:** SACCOs as one account with deposits, shares and loan ([c7de50f](https://github.com/pesaclarity/pesaclarity-app/commit/c7de50fcb63cbc6bbbfa49587b3ef49df145babc))
* **goals:** keep a savings goal aside from Safe to spend and On hand ([b93879d](https://github.com/pesaclarity/pesaclarity-app/commit/b93879df3e226b23e4c50fc6a6fc595929417655))
* **habits:** no-spend days, a plain streak and the Sunday check-in ([9be0bce](https://github.com/pesaclarity/pesaclarity-app/commit/9be0bce6adcac5d125d7a2c4080c4b53fc5a2442))
* keep a goal aside; no-spend days and the Sunday check-in ([fe9e828](https://github.com/pesaclarity/pesaclarity-app/commit/fe9e8281214015170e38c0ef81c9285ff5cd689b))
* paste M-Pesa messages on iPhone, and About you in setup ([59ee20b](https://github.com/pesaclarity/pesaclarity-app/commit/59ee20be079f7c6ebf8c74a482144125a576e5cb))
* paste M-Pesa messages on iPhone, and About you in setup ([ca62d29](https://github.com/pesaclarity/pesaclarity-app/commit/ca62d290bc9d72278db5d1fa9c600d58285680f2))
* **plan:** budget alerts and a bills calendar ([c5929aa](https://github.com/pesaclarity/pesaclarity-app/commit/c5929aa88c3b91c5337f4f27a451d7d85bd162d1))

## [0.5.6](https://github.com/pesaclarity/pesaclarity-app/compare/v0.5.5...v0.5.6) (2026-11-22)


### Features

* **accounts:** ask before adding the M-Pesa family (0026 item 5) ([e39a6cd](https://github.com/pesaclarity/pesaclarity-app/commit/e39a6cd7a1962d4614360938ab6ae760d0573e38))
* **accounts:** ask before adding the M-Pesa family (0026 item 5) ([f3332aa](https://github.com/pesaclarity/pesaclarity-app/commit/f3332aa694616770099284e475205f624ba691e3))
* **accounts:** the M-Pesa family of accounts (0026) ([b01473d](https://github.com/pesaclarity/pesaclarity-app/commit/b01473d2a0fefed149a53b765e9959352c215c18))
* **accounts:** the M-Pesa family of accounts (0026) ([8ac1cab](https://github.com/pesaclarity/pesaclarity-app/commit/8ac1cab4cb3abe5cbc4f1a4c6c34a42657473e4c))
* **fuliza:** track Fuliza only for people who use it ([cd53935](https://github.com/pesaclarity/pesaclarity-app/commit/cd539355cb30f1ab6b6c4c3eccabfd868c5b9f8d))
* **fuliza:** track Fuliza only for people who use it ([f41c0ed](https://github.com/pesaclarity/pesaclarity-app/commit/f41c0ed26af49b4dafe813a2feea546d2d0981cb))
* **goals:** show Lent and borrowed under the goals, above net worth ([57011ef](https://github.com/pesaclarity/pesaclarity-app/commit/57011ef81072903d0293c9ab95d14a531b041907))
* **journal:** everything reads the journal, and the replay month (0018 stages 4 and 5) ([56cf5c1](https://github.com/pesaclarity/pesaclarity-app/commit/56cf5c156c296095e059ad546d28d39c632f7bd1))
* **lending:** file a transaction as money lent or borrowed ([ef050c1](https://github.com/pesaclarity/pesaclarity-app/commit/ef050c149d008a08e37ff2c55e9602b0ffda2f47))
* **statements:** import KCB statements ([b29c265](https://github.com/pesaclarity/pesaclarity-app/commit/b29c26564cc417713addc180b8ae0606187ac57f))


### Fixes

* **fuliza:** read the switch apart from the ledger, and say it in the README ([98aab16](https://github.com/pesaclarity/pesaclarity-app/commit/98aab168b0496f0bac01f1f3fa2cec1bba33b266))
* **insights:** follow the ledger, so Insights fills once transactions come ([77cad4b](https://github.com/pesaclarity/pesaclarity-app/commit/77cad4bc4d03d9417b45122b9122164287df8ae6))
* **sms:** read every space's accounts on start and on return ([50a3322](https://github.com/pesaclarity/pesaclarity-app/commit/50a3322bc03716f33d1d6ed96f75f8a5c2251a48))

## [0.5.5](https://github.com/pesaclarity/pesaclarity-app/compare/v0.5.4...v0.5.5) (2026-11-22)


### Features

* **ledger:** one rule that stops double entries for every account (0030) ([73b5bf1](https://github.com/pesaclarity/pesaclarity-app/commit/73b5bf1c83ca22ce2eedd6b5024c40b3ba0045ed))
* **sms:** two M-Pesa lines on one phone ([e24eef8](https://github.com/pesaclarity/pesaclarity-app/commit/e24eef8bf730e21036a13b5f92ead87a1e55f1b2))
* **spaces:** money between spaces (decision 0027) ([c3085b4](https://github.com/pesaclarity/pesaclarity-app/commit/c3085b442a35769982a3146f24ebbc541734f6d1))
* **spaces:** put money in, pay yourself by bank, restore check and clear data question (0027) ([47e833e](https://github.com/pesaclarity/pesaclarity-app/commit/47e833e2cdfa8545d158b6a3b04ce3a5ac1af184))
* **spaces:** the rest of money between spaces (0027): put money in, pay by bank, restore check, clear data ([adf6e9e](https://github.com/pesaclarity/pesaclarity-app/commit/adf6e9e27bc1dffb5b367740a9c3d29435adbac5))


### Fixes

* **firefly:** send Held for another space, so a switch adds up there ([a8f1d56](https://github.com/pesaclarity/pesaclarity-app/commit/a8f1d5609a9eb8b58471c39c140d382ac1a3644a))
* **spaces:** every M-Pesa line for Put money in; a restore never fails on its check ([3d6aadc](https://github.com/pesaclarity/pesaclarity-app/commit/3d6aadccc25631b40a6ec093b06d71933dafb878))

## [0.5.4](https://github.com/pesaclarity/pesaclarity-app/compare/v0.5.3...v0.5.4) (2026-11-21)


### Features

* **firefly:** Firefly III screen, Profile row and sending on start ([a4b2965](https://github.com/pesaclarity/pesaclarity-app/commit/a4b2965a4f4f9ac3586fdcae3bf4fa24a2dde5d3))
* **firefly:** send a space's transactions to the person's own Firefly III ([acb68d7](https://github.com/pesaclarity/pesaclarity-app/commit/acb68d757b0f6bfcb407fcdd1d1c8bb58f72e4fd))
* **theme:** show the chosen filter pill and count chip as red text, with no fill ([abc2048](https://github.com/pesaclarity/pesaclarity-app/commit/abc204883082ab490af26e88909a048126047eda))


### Fixes

* **firefly:** read nothing more while sending is off ([27dece1](https://github.com/pesaclarity/pesaclarity-app/commit/27dece19bc0fd007b5a79d071f6bd1960bce1f49))
* **privacy:** policy 2.5, sending to your own Firefly III ([d923509](https://github.com/pesaclarity/pesaclarity-app/commit/d9235096a99196b786e677f6e130c11b18e20fc1))
* **spaces:** store each message in one space, and take out copies on update ([69f76d0](https://github.com/pesaclarity/pesaclarity-app/commit/69f76d05564a1e66be8af23b14e5925a9ad5f41d))

## [0.5.3](https://github.com/pesaclarity/pesaclarity-app/compare/v0.5.2...v0.5.3) (2026-11-21)


### Features

* **activity:** show own transfers across currencies as the mockups ([2f15c32](https://github.com/pesaclarity/pesaclarity-app/commit/2f15c3247786d90e5eb261f99ae60a09ebfdadfe))
* **app-status:** pin the production signing key ([dcf1847](https://github.com/pesaclarity/pesaclarity-app/commit/dcf1847d9c0e5893124b0a1b5a07e07cc5ba82c8))
* **categoriser:** suggest with the PyTorch categoriser on rayo, fine-tuned in Dart ([a34e8e7](https://github.com/pesaclarity/pesaclarity-app/commit/a34e8e78b4830e9e2b754ac5b0be980e6412e745))
* **categoriser:** the rules decide where they are certain, the model the rest ([414afa4](https://github.com/pesaclarity/pesaclarity-app/commit/414afa466649b1062b9ac772f438922abb4eb082))
* **categoriser:** well-known payees win over the model too ([c2b0778](https://github.com/pesaclarity/pesaclarity-app/commit/c2b0778f5b1231f6d6bc95daf88896a4af7695ac))
* **debts:** show when a loan's next instalment is due ([33366b9](https://github.com/pesaclarity/pesaclarity-app/commit/33366b9531c6f98d19db7e2dc12ee0021f317f6d))
* **goals:** save a goal in a savings app's goal ([8981805](https://github.com/pesaclarity/pesaclarity-app/commit/8981805cfe52c04dc72139b13a43fcc2cb53d173))
* **income:** leave savings accounts out of money arriving ([6b1ddbc](https://github.com/pesaclarity/pesaclarity-app/commit/6b1ddbc3e98faf09945ccc757b99fa8a189eced8))
* **journal:** clear Money in transit when own transfers pair, with fees ([3aaa161](https://github.com/pesaclarity/pesaclarity-app/commit/3aaa1614ca58b2967cb1096fd4dfd5bedb65454c))
* **ledger:** pair own transfers across currencies and post their exchange ([a3b3905](https://github.com/pesaclarity/pesaclarity-app/commit/a3b3905a7f4a3237aa49e82d994b21cc87532197))
* **ledger:** rule for own transfers across currencies ([d7a934e](https://github.com/pesaclarity/pesaclarity-app/commit/d7a934ef9664a7d913a0a5dd9afc53ddd413460e))
* **plan:** count money moved into savings as saved ([c31929b](https://github.com/pesaclarity/pesaclarity-app/commit/c31929b224a478da4e16a5697b43017359b49cc3))
* read KCB's messages into one transfer, debt repayment or payment each ([1941431](https://github.com/pesaclarity/pesaclarity-app/commit/1941431a0efb7943ee658cf96b9ff60b029c9959))
* **savings:** keep Chumz as a savings account fed from M-Pesa ([db82c46](https://github.com/pesaclarity/pesaclarity-app/commit/db82c466f55abe9a254188987850f5b5c7f84cf8))
* **savings:** know Chumz by the paybill its payments print ([4ce1962](https://github.com/pesaclarity/pesaclarity-app/commit/4ce1962423eab526d928c4c290a895bb4a3f3ea5))
* **savings:** store savings accounts, their goals and typed balances ([0449367](https://github.com/pesaclarity/pesaclarity-app/commit/0449367ff88589b8c7b5f7de3ed2e49faf016320))
* **savings:** work out a savings goal's interest from typed balances ([49a41dc](https://github.com/pesaclarity/pesaclarity-app/commit/49a41dc5dc8d2aa36c175739185a9b35d038a618))
* **security:** add a setting to allow screenshots and screen recording ([d759e6b](https://github.com/pesaclarity/pesaclarity-app/commit/d759e6b35c0e49bbbca1d038fc14611b2f6a7ed3))
* **sms:** drop known notices such as KCB's declined card payments ([dda39bb](https://github.com/pesaclarity/pesaclarity-app/commit/dda39bb5f70f8d56bbb7eb6d3ba96add41e91c4c))
* **spaces:** keep a savings account whole when records move or clear ([5f2d460](https://github.com/pesaclarity/pesaclarity-app/commit/5f2d460f227366218ff3572c54624d510c0ce48a))
* **theme:** show the selected side of a switch as red text, with no fill ([3e4f855](https://github.com/pesaclarity/pesaclarity-app/commit/3e4f855bcd53af51f4c0422dc633a4baed08e2fe))


### Fixes

* **a11y:** Ask's tap targets and previews; check Ask's screens again ([2a18cff](https://github.com/pesaclarity/pesaclarity-app/commit/2a18cffb76852d81a8d79b390559eef8a5019804))
* **a11y:** Conversations title and Ask's suggestions whole at large text ([419d05e](https://github.com/pesaclarity/pesaclarity-app/commit/419d05eaf8138d4751b21d1b92ac7e04328040e5))
* **a11y:** keep words whole at large text ([58fd1bf](https://github.com/pesaclarity/pesaclarity-app/commit/58fd1bfa7572af2eb1729e52312ef17643b9c4eb))
* **a11y:** move a row's end part under its title when the title only just fits ([74a418d](https://github.com/pesaclarity/pesaclarity-app/commit/74a418d7a47f8fc67da7d6a05d29ee7e2dad10b2))
* **backup:** restore a backup file only into its own space ([3bf25f3](https://github.com/pesaclarity/pesaclarity-app/commit/3bf25f368eccc169b8cf8796ca7def21db6e8c36))
* **ledger:** count money from KCB into M-Pesa once when both send a message ([9116248](https://github.com/pesaclarity/pesaclarity-app/commit/9116248b065e49a7f480d835dfb887cc86656bdb))
* **ledger:** offer own-transfer sides only in the same currency ([5360ac1](https://github.com/pesaclarity/pesaclarity-app/commit/5360ac165bd202c8d941a34ad21b1fb5d5e3e03d))
* **sms:** let go of only the iPhone messages a scan read ([723a180](https://github.com/pesaclarity/pesaclarity-app/commit/723a180d332fc835d6522319b81d6e0a73078d32))
* **sms:** read missed messages whenever the app returns to the front ([5b843b4](https://github.com/pesaclarity/pesaclarity-app/commit/5b843b4a7e1c71af91e98f3e9eb24cdf2f59648a))
* **sms:** read missed messages whenever the app returns to the front ([215547b](https://github.com/pesaclarity/pesaclarity-app/commit/215547b8cbab9021de72e6a5056ee75ffb8e44ec))
* **sms:** read missed messages whenever the app returns to the front ([#344](https://github.com/pesaclarity/pesaclarity-app/issues/344)) ([5b843b4](https://github.com/pesaclarity/pesaclarity-app/commit/5b843b4a7e1c71af91e98f3e9eb24cdf2f59648a))
* **sms:** read only the open space's accounts right after a switch ([82a72ec](https://github.com/pesaclarity/pesaclarity-app/commit/82a72ecfc99478a91b8e2677992a8c1496945ca8))
* **spaces:** accounts keep their opening balance after Clear data ([2fb2493](https://github.com/pesaclarity/pesaclarity-app/commit/2fb2493f8f8c92bfd45dce605ecb2c8c2488f844))
* **spaces:** keep a two-message payment gone after it is cleared or moved ([e5a6ead](https://github.com/pesaclarity/pesaclarity-app/commit/e5a6eadbb6e3449c4d2e9c7486a5599506fe3126))
* **spaces:** keep the list of spaces when Personal is restored ([a5756aa](https://github.com/pesaclarity/pesaclarity-app/commit/a5756aa64f39289419e56a7a39432010a7222e93))
* **spaces:** leave a moved payment's balance behind ([2d4de42](https://github.com/pesaclarity/pesaclarity-app/commit/2d4de422edbb32d29b73cffca92741e8b6596420))
* **spaces:** leave a payment's debt and goal behind when it moves ([94f63c1](https://github.com/pesaclarity/pesaclarity-app/commit/94f63c1945a1f4a5bdd996d90774d6b1a8b9bed3))
* **spaces:** read each account in one space only ([36793b0](https://github.com/pesaclarity/pesaclarity-app/commit/36793b0a23909e164adbec42fb88fce3057c6a86))
* **spaces:** show each space its own balances after a switch ([a17c894](https://github.com/pesaclarity/pesaclarity-app/commit/a17c894bd9c61a62ca38354c1d4ea560b729da9f))
* **spaces:** stop a deleted business's rules moving money ([4abbb9b](https://github.com/pesaclarity/pesaclarity-app/commit/4abbb9b8ecf12961d30944e9aff5c7209b6df4f4))
* **tool:** create the reader recording's rayo session as the app's rayo reads it ([f4c4b06](https://github.com/pesaclarity/pesaclarity-app/commit/f4c4b06b738d87adf1272b145143e18075c178cf))

## [0.5.2](https://github.com/pesaclarity/pesaclarity-app/compare/v0.5.1...v0.5.2) (2026-11-19)


### Features

* a pure, untinted palette in light and dark ([5ddd873](https://github.com/pesaclarity/pesaclarity-app/commit/5ddd873f452efa1404c7659a2505ca07f51fb5f3))
* a softer dark mode ([224b391](https://github.com/pesaclarity/pesaclarity-app/commit/224b3914b0f43f6e74163ffcd91a49a69422dbfe))
* ask before the F-Droid build's daily update check ([cb23d40](https://github.com/pesaclarity/pesaclarity-app/commit/cb23d400c110b866b6f63af048bc799366466bef))
* **ask:** ship the PyTorch Ask reader v4 (run 16) ([542aeec](https://github.com/pesaclarity/pesaclarity-app/commit/542aeec0d28c15b34840bdffeb0839277e4fe0b0))
* crash report sheet and the counting and crash report choices in Privacy ([cd9a4d8](https://github.com/pesaclarity/pesaclarity-app/commit/cd9a4d88233dec96dfa0f032289286d7a2f1d2a8))
* follow the iOS design guidelines ([#307](https://github.com/pesaclarity/pesaclarity-app/issues/307)) ([1afc31d](https://github.com/pesaclarity/pesaclarity-app/commit/1afc31db06167d309b12936ff8065ae23af1cdb3))
* keep crash reports for the next start and send them only as the person chose ([75a577c](https://github.com/pesaclarity/pesaclarity-app/commit/75a577c3183033c91ae8e07346764f5642db3861))
* **privacy:** policy 2.4, the monthly count and crash reports ([e8462a1](https://github.com/pesaclarity/pesaclarity-app/commit/e8462a19bf73e1fbe34e08231f0a51d62f587a9a))
* **privacy:** policy 2.4, the monthly count and crash reports ([9131280](https://github.com/pesaclarity/pesaclarity-app/commit/913128039812000b5d16831d21a48ff3c50b706d))
* **reader:** read messages with the PyTorch reader on rayo ([c2a71eb](https://github.com/pesaclarity/pesaclarity-app/commit/c2a71eb8b1b928aa808940bfd3f01e9cafa52174))
* send a monthly counting token with the update check ([6039ca3](https://github.com/pesaclarity/pesaclarity-app/commit/6039ca31e4a499f4a420aba7ed5e1c4d39fb2832))


### Fixes

* a neutral grey for the second chart colour in dark mode ([04b9180](https://github.com/pesaclarity/pesaclarity-app/commit/04b918088608c40441d43f9fab1db29edf58765d))
* **a11y:** darker small text on tinted cards ([914a023](https://github.com/pesaclarity/pesaclarity-app/commit/914a02307c8c242d055ffb59dc7af9d942faec04))
* **a11y:** draw every tab label at one size ([bcfab9a](https://github.com/pesaclarity/pesaclarity-app/commit/bcfab9ae54f613408619197e615527640f70b20e))
* **a11y:** follow the phone's reduce-motion setting ([b302d18](https://github.com/pesaclarity/pesaclarity-app/commit/b302d1812c0588a82455642868a810d88d5af57e))
* **a11y:** keep an amount's currency code and number on one line ([fa0d8e8](https://github.com/pesaclarity/pesaclarity-app/commit/fa0d8e81fa3f53dade8d676617356168fc48e47b))
* **a11y:** keep screens whole at larger text sizes ([a549498](https://github.com/pesaclarity/pesaclarity-app/commit/a549498936a4993640b161c4f49efdb25af7e019))
* **a11y:** keep Sell tiles in a row the same height ([61c7a7d](https://github.com/pesaclarity/pesaclarity-app/commit/61c7a7d62fdd3ab5096987a9f30ad2481e32895f))
* **a11y:** labels above fields so they stay whole at large text ([abd012b](https://github.com/pesaclarity/pesaclarity-app/commit/abd012b689d2ba960abc8c67bdb3a19bd120eca1))
* **a11y:** labels above fields, names on two lines, darker small text ([#303](https://github.com/pesaclarity/pesaclarity-app/issues/303)) ([9be4136](https://github.com/pesaclarity/pesaclarity-app/commit/9be41360b0a639ec465a0fd34f8ab3f12f26878b))
* **a11y:** labels above fields, two-line names, darker small print ([9be4136](https://github.com/pesaclarity/pesaclarity-app/commit/9be41360b0a639ec465a0fd34f8ab3f12f26878b))
* **a11y:** let names in Activity and Money wrap to two lines ([7267c1a](https://github.com/pesaclarity/pesaclarity-app/commit/7267c1aaaa1d50a3fbd47dc29fae06f18848b16e))
* **a11y:** make small tap targets at least 48 by 48 ([2b7b986](https://github.com/pesaclarity/pesaclarity-app/commit/2b7b986312b9486324206386a8c1c17b1bca26ae))
* **a11y:** read amounts, headers and messages well with screen readers ([f2f4055](https://github.com/pesaclarity/pesaclarity-app/commit/f2f4055d1f1675c156aa3730425a678215a3a99d))
* **a11y:** read the debt what-if slider as an amount, and hide its interest ([5cf3ecd](https://github.com/pesaclarity/pesaclarity-app/commit/5cf3ecd06d73d6d22e89c9ba5bee7ad69182cb5c))
* move to rayo with the security fixes and faster kernels ([883a9f8](https://github.com/pesaclarity/pesaclarity-app/commit/883a9f8e7a5db124e36e0e22261ded3b9d655b8c))
* never let the counting token hold up the update check ([71309eb](https://github.com/pesaclarity/pesaclarity-app/commit/71309eb1cf8417bde522ec3268eb8354f9c675ff))
* **policy:** privacy policy 2.3, the hashed sign-in email, app lock and site search ([7aae60f](https://github.com/pesaclarity/pesaclarity-app/commit/7aae60fb865fcabbf890ce78f161912d14517689))
* put a tab's buttons above its title on iPhone ([#309](https://github.com/pesaclarity/pesaclarity-app/issues/309)) ([df83225](https://github.com/pesaclarity/pesaclarity-app/commit/df83225e33e1307f1b94ecdfbf16240b1d859569))
* show the Plan income bar ([4fea862](https://github.com/pesaclarity/pesaclarity-app/commit/4fea862d8301c031ee86af6f2af16412802bcf65))
* tell Debt and Tax reserve apart on the Plan bar ([#301](https://github.com/pesaclarity/pesaclarity-app/issues/301)) ([54b2f3e](https://github.com/pesaclarity/pesaclarity-app/commit/54b2f3edf240955c65303f73467c80553eacc18f))
* tell the Plan bar's groups apart in dark ([#305](https://github.com/pesaclarity/pesaclarity-app/issues/305)) ([259a52b](https://github.com/pesaclarity/pesaclarity-app/commit/259a52b057227a23d063ae2cb7978cba9c6024bc))
* the iPhone launch screen uses the pure page colours ([8b90c3e](https://github.com/pesaclarity/pesaclarity-app/commit/8b90c3ee2a7e890c7c08051a11b723f5a5d3909e))


### Performance

* build Activity's rows as they scroll in ([d435141](https://github.com/pesaclarity/pesaclarity-app/commit/d435141cb57958196ec2c8c934c30efbebf08f3f))
* build the book account name map once ([07b6284](https://github.com/pesaclarity/pesaclarity-app/commit/07b6284edf7363d8d662a4d80c9a43aba1c6187f))
* decode the logo near the size of its tile ([4d9548e](https://github.com/pesaclarity/pesaclarity-app/commit/4d9548e58ea388cb0652585696ee15195841cf5d))
* index transactions by date ([92a2369](https://github.com/pesaclarity/pesaclarity-app/commit/92a23695decd1711c243f62a97505ac1c38aa440))
* read journal entries and postings column by column ([5ff4ed4](https://github.com/pesaclarity/pesaclarity-app/commit/5ff4ed416b7c6e1c8b4e497149ff89dba6bd34c4))
* read ledger entries column by column ([89f6811](https://github.com/pesaclarity/pesaclarity-app/commit/89f681138b62e357946e62c42bc5185794ecff01))
* read the space and the look at once before the first frame ([fc185ab](https://github.com/pesaclarity/pesaclarity-app/commit/fc185ab967eb8edba430a865acaf88a571049999))
* share one read of the whole ledger per change ([af0ba96](https://github.com/pesaclarity/pesaclarity-app/commit/af0ba965022df42eaf4c08f8b173b365250d6280))
* write a journal repost in one batch ([d84eccd](https://github.com/pesaclarity/pesaclarity-app/commit/d84eccdccab04c11c15716a03db9fb3a5cb10642))

## [0.5.1](https://github.com/pesaclarity/pesaclarity-app/compare/v0.5.0...v0.5.1) (2026-11-18)


### Documentation

* privacy policy 2.2: the website section now says the site keeps your light or dark theme choice in your browser; nothing about the app changed ([#281](https://github.com/pesaclarity/pesaclarity-app/issues/281))

## [0.5.0](https://github.com/pesaclarity/pesaclarity-app/compare/v0.4.0...v0.5.0) (2026-11-18)


### Features

* ask reader v3 on rayo a64d855 ([#276](https://github.com/pesaclarity/pesaclarity-app/issues/276)) ([c6d4e54](https://github.com/pesaclarity/pesaclarity-app/commit/c6d4e54dd424c40e001122589a6e0f64358930be))
* run the Ask models on rayo, and remove TFLite ([#275](https://github.com/pesaclarity/pesaclarity-app/issues/275)) ([cf82f84](https://github.com/pesaclarity/pesaclarity-app/commit/cf82f84748006d28dff32653be5be1f340e2131a))

## [0.4.0](https://github.com/pesaclarity/pesaclarity-app/compare/v0.3.0...v0.4.0) (2026-11-17)


### Features

* read messages again with newer readers ([#267](https://github.com/pesaclarity/pesaclarity-app/issues/267)) ([8061cb0](https://github.com/pesaclarity/pesaclarity-app/commit/8061cb01b97ac294ce3d9b8a6639da251e318196))
* run the Ask reader in pure Dart in every build ([#268](https://github.com/pesaclarity/pesaclarity-app/issues/268)) ([b3ff09c](https://github.com/pesaclarity/pesaclarity-app/commit/b3ff09c63cd55cb797057766fbe320e9b00819dd))
* show update notices from the server, signed and pinned ([#266](https://github.com/pesaclarity/pesaclarity-app/issues/266)) ([858b569](https://github.com/pesaclarity/pesaclarity-app/commit/858b569b2b4ab775236b62fd4107a0d6bf0f87b9))

## [0.3.0](https://github.com/pesaclarity/pesaclarity-app/compare/v0.2.0...v0.3.0) (2026-11-17)


### Features

* Ask reader that catches names and money in ([#259](https://github.com/pesaclarity/pesaclarity-app/issues/259)) ([d341889](https://github.com/pesaclarity/pesaclarity-app/commit/d3418899552b2fd63c9d86907bd8eb360e79a45b))
* Ask replies worded on the phone by the small writer ([#237](https://github.com/pesaclarity/pesaclarity-app/issues/237)) ([bec3092](https://github.com/pesaclarity/pesaclarity-app/commit/bec3092b619da413718d31fdc3774e33c79f8fa9))
* Ask, questions about your money answered on the phone ([#234](https://github.com/pesaclarity/pesaclarity-app/issues/234)) ([2ec9e43](https://github.com/pesaclarity/pesaclarity-app/commit/2ec9e4371709fe953a686fd3ae209a9a8f0c383f))
* refined light and dark theme, red lead cards kept ([#251](https://github.com/pesaclarity/pesaclarity-app/issues/251)) ([#231](https://github.com/pesaclarity/pesaclarity-app/issues/231)) ([071582f](https://github.com/pesaclarity/pesaclarity-app/commit/071582f4d599bb2cd2dc6e0764fc841ffe8d1a5e))
* give through CitaPay, with the amount in cents ([#235](https://github.com/pesaclarity/pesaclarity-app/issues/235)) ([6d24d62](https://github.com/pesaclarity/pesaclarity-app/commit/6d24d622743e2ce56a70c5b368b55aa9d168d211))
* Home shows how much is not yet sorted ([#248](https://github.com/pesaclarity/pesaclarity-app/issues/248)) ([20e05bc](https://github.com/pesaclarity/pesaclarity-app/commit/20e05bcad22e836599b14f61c698785dc4384b5a))


### Fixes

* amounts never split across lines in tiles ([#242](https://github.com/pesaclarity/pesaclarity-app/issues/242)) ([57fb638](https://github.com/pesaclarity/pesaclarity-app/commit/57fb63822172b3f79b1c9d9e44028d31093fb16d))
* Ask answers the question asked (payee counts, money in) ([#240](https://github.com/pesaclarity/pesaclarity-app/issues/240)) ([df2ee5a](https://github.com/pesaclarity/pesaclarity-app/commit/df2ee5af7f19010b2d0f16fcf7c3ee7242039cdd))
* Ask replies read plainly (below zero, no filler, empty months, unsorted, money in) ([#238](https://github.com/pesaclarity/pesaclarity-app/issues/238)) ([b7cc193](https://github.com/pesaclarity/pesaclarity-app/commit/b7cc193647df3bc6f7322330ebb5cfeb35e9a521))
* Health Index counts Fuliza charges from the journal, like Insights ([#230](https://github.com/pesaclarity/pesaclarity-app/issues/230)) ([86fcf9c](https://github.com/pesaclarity/pesaclarity-app/commit/86fcf9ca1ab367617b32349428df58169f08a8f8))
* one way into Debts from empty Goals ([#245](https://github.com/pesaclarity/pesaclarity-app/issues/245)) ([eae38e2](https://github.com/pesaclarity/pesaclarity-app/commit/eae38e24a4a9c2ce06493008f56084e319dd05a8))
* screen headers wrap instead of overflowing at large text ([#243](https://github.com/pesaclarity/pesaclarity-app/issues/243)) ([6f51568](https://github.com/pesaclarity/pesaclarity-app/commit/6f51568c5ede62707275cfaabdea00261f8d61dc))
* tiles two to a row before one, and two-way switches stack instead of breaking words ([#244](https://github.com/pesaclarity/pesaclarity-app/issues/244)) ([0ddc34c](https://github.com/pesaclarity/pesaclarity-app/commit/0ddc34c21eda71484c1a3ffeaafff85d7dca20a3))


### Performance

* read the journal once per change ([#239](https://github.com/pesaclarity/pesaclarity-app/issues/239)) ([0ffe840](https://github.com/pesaclarity/pesaclarity-app/commit/0ffe8404e62d2d8021fee9c8ee3b7ba71539a3d5))

## [0.2.0](https://github.com/pesaclarity/pesaclarity-app/compare/v0.1.0...v0.2.0) (2026-11-16)


### Features

* a business day that ends after midnight ([#195](https://github.com/pesaclarity/pesaclarity-app/issues/195)) ([17d4275](https://github.com/pesaclarity/pesaclarity-app/commit/17d4275a93f90c52db6bb496da27823b3001e86c))
* add automatic transaction categorisation and database schema migration ([f276b68](https://github.com/pesaclarity/pesaclarity-app/commit/f276b6818c6334079e47f58168e6b33895dfd029))
* add the terms ([#115](https://github.com/pesaclarity/pesaclarity-app/issues/115)) ([0817fe6](https://github.com/pesaclarity/pesaclarity-app/commit/0817fe6d83c2aca77e72c4274588fa0b48dbf211))
* App Attest for vault uploads on iPhone ([#98](https://github.com/pesaclarity/pesaclarity-app/issues/98)) ([d4e03dd](https://github.com/pesaclarity/pesaclarity-app/commit/d4e03dd35e3518883818a23ef8240ca85ab6af79))
* ask what money from mixed senders was for ([#138](https://github.com/pesaclarity/pesaclarity-app/issues/138)) ([9ff1fbc](https://github.com/pesaclarity/pesaclarity-app/commit/9ff1fbc3762b2015d5d01b0c569a9418afe11c6a))
* back up each space on its own ([#148](https://github.com/pesaclarity/pesaclarity-app/issues/148)) ([2c45774](https://github.com/pesaclarity/pesaclarity-app/commit/2c45774ce422a3ba2f790b80dbd48d287e60cde5))
* base currency, picked at setup and switchable, with public exchange rates ([#82](https://github.com/pesaclarity/pesaclarity-app/issues/82)) ([00a6457](https://github.com/pesaclarity/pesaclarity-app/commit/00a64571fba3d3cf64bea0184ee1204820e7f282))
* Bought, Got paid and Paid on a business's Today ([#163](https://github.com/pesaclarity/pesaclarity-app/issues/163)) ([fa0b43c](https://github.com/pesaclarity/pesaclarity-app/commit/fa0b43c7f05b1b0e91c4c1d032d03b1e6e18a616))
* business bar and the Money tab ([#161](https://github.com/pesaclarity/pesaclarity-app/issues/161)) ([1457725](https://github.com/pesaclarity/pesaclarity-app/commit/1457725571e7327566ebe8c5573d42fdf814b6e3))
* business follow-ups for reports, tax and documents ([#176](https://github.com/pesaclarity/pesaclarity-app/issues/176)) ([1c39305](https://github.com/pesaclarity/pesaclarity-app/commit/1c39305d42af9cad9f2f73c99150f0ab1d163660))
* business insights, full records and reports ([#169](https://github.com/pesaclarity/pesaclarity-app/issues/169)) ([f8ce9ef](https://github.com/pesaclarity/pesaclarity-app/commit/f8ce9efbc8bf2ce6fa1c5a0887c92b507cbac8ff))
* business or personal for each account ([#159](https://github.com/pesaclarity/pesaclarity-app/issues/159)) ([370041d](https://github.com/pesaclarity/pesaclarity-app/commit/370041d208f2f96dca42a5e063206d27836739a7))
* check unmatched messages with the message reader ([49921e0](https://github.com/pesaclarity/pesaclarity-app/commit/49921e05a3a275101e46897a51560d111b8cf429))
* check unmatched messages with the message reader ([#104](https://github.com/pesaclarity/pesaclarity-app/issues/104)) ([46d4158](https://github.com/pesaclarity/pesaclarity-app/commit/46d4158fdc23fc84c715f5be20a36957c3adfbe1))
* choose how far back messages are read ([#125](https://github.com/pesaclarity/pesaclarity-app/issues/125)) ([38db3f7](https://github.com/pesaclarity/pesaclarity-app/commit/38db3f7b519f982c477c064a65c4247d6fbcabe1))
* choose which space the app opens in ([#146](https://github.com/pesaclarity/pesaclarity-app/issues/146)) ([013216e](https://github.com/pesaclarity/pesaclarity-app/commit/013216ee7baaedab064f54e7de75b37134907eb5))
* clear a date range, choose the category when moving ([#213](https://github.com/pesaclarity/pesaclarity-app/issues/213)) ([cfe734a](https://github.com/pesaclarity/pesaclarity-app/commit/cfe734a952d5f28b193fb7ec4dbfa82cb1b4d25b))
* close the day with the drawer count ([#168](https://github.com/pesaclarity/pesaclarity-app/issues/168)) ([93340e2](https://github.com/pesaclarity/pesaclarity-app/commit/93340e2f10d6f649cadee12d84ecba19d9d63a87))
* credit the exchange rates provider ([#85](https://github.com/pesaclarity/pesaclarity-app/issues/85)) ([cfa4885](https://github.com/pesaclarity/pesaclarity-app/commit/cfa48859a1fb3d0fba526bda6c86e98d54986a12))
* documents attached to invoices ([#174](https://github.com/pesaclarity/pesaclarity-app/issues/174)) ([2bf22c8](https://github.com/pesaclarity/pesaclarity-app/commit/2bf22c88406f706710e229b3f1d0a01cd2d4e2c2))
* double-entry books for each space ([#157](https://github.com/pesaclarity/pesaclarity-app/issues/157)) ([8fec9b8](https://github.com/pesaclarity/pesaclarity-app/commit/8fec9b8c195837747008326a776b2262d1d66aed))
* double-entry journal, stage 1 ([#222](https://github.com/pesaclarity/pesaclarity-app/issues/222)) ([35af05c](https://github.com/pesaclarity/pesaclarity-app/commit/35af05cf72c91e5cbb74f72aa2a7873532b50a6c))
* double-entry journal, stage 2 ([#226](https://github.com/pesaclarity/pesaclarity-app/issues/226)) ([8532671](https://github.com/pesaclarity/pesaclarity-app/commit/8532671e0bcfdaacdc224d0ef057dcafce96f370))
* each amount in its own currency, accounts at the same bank, drop-down choices ([#191](https://github.com/pesaclarity/pesaclarity-app/issues/191)) ([a040814](https://github.com/pesaclarity/pesaclarity-app/commit/a040814f914b7fde90bde03a2d19e3e014534f9a))
* email a copy of the privacy policy without an email app ([#153](https://github.com/pesaclarity/pesaclarity-app/issues/153)) ([80d035b](https://github.com/pesaclarity/pesaclarity-app/commit/80d035bbb4e05602c80e47a4cd673215522d3787))
* fine-tune the categoriser on the phone ([#154](https://github.com/pesaclarity/pesaclarity-app/issues/154)) ([a46d605](https://github.com/pesaclarity/pesaclarity-app/commit/a46d60565e09c38f3ba6c7572221fd8c45c8819a))
* give Fuliza and snacks their own categories ([#87](https://github.com/pesaclarity/pesaclarity-app/issues/87)) ([0366397](https://github.com/pesaclarity/pesaclarity-app/commit/03663972e8ed996cbd371208856bb27d248f034d))
* hours logged by day and week ([#172](https://github.com/pesaclarity/pesaclarity-app/issues/172)) ([3a87bdf](https://github.com/pesaclarity/pesaclarity-app/commit/3a87bdfbd5868d58893019a7b2342b9e5b8f1d22))
* Insights findings and drill-down to transactions ([#124](https://github.com/pesaclarity/pesaclarity-app/issues/124)) ([f13e427](https://github.com/pesaclarity/pesaclarity-app/commit/f13e427a84b2a6e629b5e4a2756f9779538364e2))
* invoices from hours or items, with withholding tax ([#173](https://github.com/pesaclarity/pesaclarity-app/issues/173)) ([d0a17a0](https://github.com/pesaclarity/pesaclarity-app/commit/d0a17a092b79f9c888af6f35b269f4ba99c22c3a))
* iPhone app with Shortcuts capture and iOS look ([db0b714](https://github.com/pesaclarity/pesaclarity-app/commit/db0b714b930a811db081bd5ff385210eb3d2f8cb))
* iPhone app with Shortcuts capture and iOS look ([#95](https://github.com/pesaclarity/pesaclarity-app/issues/95)) ([d945995](https://github.com/pesaclarity/pesaclarity-app/commit/d945995c70ff638b1913dbe9384167fefb0ca957))
* iPhone setup offers a statement for past months ([#147](https://github.com/pesaclarity/pesaclarity-app/issues/147)) ([b156918](https://github.com/pesaclarity/pesaclarity-app/commit/b156918f75df0a01db964f47b7098998407c085b))
* iPhone uses the Android design ([#126](https://github.com/pesaclarity/pesaclarity-app/issues/126)) ([a4c20e0](https://github.com/pesaclarity/pesaclarity-app/commit/a4c20e01462622c277cbbc0ce52165806053ece8))
* kinds of space with their own categories and Home ([#143](https://github.com/pesaclarity/pesaclarity-app/issues/143)) ([f0c0f92](https://github.com/pesaclarity/pesaclarity-app/commit/f0c0f92ff56f089f2a6285d8920d8341926f07a8))
* let owners choose the style of reports, documents and fields ([#180](https://github.com/pesaclarity/pesaclarity-app/issues/180)) ([284b497](https://github.com/pesaclarity/pesaclarity-app/commit/284b49794842116093c03a44c6ece476bb734a07))
* make money last until the next money ([#139](https://github.com/pesaclarity/pesaclarity-app/issues/139)) ([83fe2f4](https://github.com/pesaclarity/pesaclarity-app/commit/83fe2f4859cdc3ee51b7dd607088cc148903eec5))
* manage spaces ([#211](https://github.com/pesaclarity/pesaclarity-app/issues/211)) ([a6dd22e](https://github.com/pesaclarity/pesaclarity-app/commit/a6dd22ed535ff558f114675684c74ef1362d9c32))
* move a transaction to another space ([#145](https://github.com/pesaclarity/pesaclarity-app/issues/145)) ([9941f08](https://github.com/pesaclarity/pesaclarity-app/commit/9941f08f41ff28743f86431b36aa53d854bb143b))
* offer Airtel Money in My accounts ([#116](https://github.com/pesaclarity/pesaclarity-app/issues/116)) ([4cacb2b](https://github.com/pesaclarity/pesaclarity-app/commit/4cacb2bc9b95c4e1a4625885f77cea695b7ada02))
* offer Loop in My accounts ([#112](https://github.com/pesaclarity/pesaclarity-app/issues/112)) ([3967756](https://github.com/pesaclarity/pesaclarity-app/commit/3967756e9b5227adb558858bf287c79716d7bdf0))
* one item sold several ways, bought in packs ([#196](https://github.com/pesaclarity/pesaclarity-app/issues/196)) ([fbd7163](https://github.com/pesaclarity/pesaclarity-app/commit/fbd7163e96bd76c478a807f7ee3226b875107aaf))
* open tabs, paid together at the end ([#197](https://github.com/pesaclarity/pesaclarity-app/issues/197)) ([d79a925](https://github.com/pesaclarity/pesaclarity-app/commit/d79a925c876a244c05ede18641f2a26dd45bfbf8))
* Pay yourself, and payments that don't match the sale ([#165](https://github.com/pesaclarity/pesaclarity-app/issues/165)) ([5b015c9](https://github.com/pesaclarity/pesaclarity-app/commit/5b015c96f68e1c493b1c1045170583f81ee79b98))
* People for a business, with statements ([#164](https://github.com/pesaclarity/pesaclarity-app/issues/164)) ([86e837e](https://github.com/pesaclarity/pesaclarity-app/commit/86e837ed5e2793ea3e90cded6c2fcdc29faf665f))
* plan until the next money for every kind of income ([#136](https://github.com/pesaclarity/pesaclarity-app/issues/136)) ([603f509](https://github.com/pesaclarity/pesaclarity-app/commit/603f50975e4b3734290c5a1c3d07230ec87df13b))
* print receipts, invoices, statements, reports and the day's summary ([#193](https://github.com/pesaclarity/pesaclarity-app/issues/193)) ([002100c](https://github.com/pesaclarity/pesaclarity-app/commit/002100c7fc332a63117982d55c67a32c3c495332))
* privacy policy 1.3 and App Attest on iPhone ([399b8aa](https://github.com/pesaclarity/pesaclarity-app/commit/399b8aafde432cf2938dd0bbc75478e703680997))
* promote dev to main (business day, units, tabs) ([ecc7981](https://github.com/pesaclarity/pesaclarity-app/commit/ecc79819d36a3d6ad6b1bec9174d064b7d4e3379))
* promote dev to main (many currencies, drop-down choices, faithful builds) ([d77ffad](https://github.com/pesaclarity/pesaclarity-app/commit/d77ffad265f25c7a254d6012c4eae6e9fd0faa8c))
* promote dev to main (one look across the app) ([cec3ddf](https://github.com/pesaclarity/pesaclarity-app/commit/cec3ddf50de518f75c992df92c06f1737d4514a3))
* promote dev to main (printing) ([b30b988](https://github.com/pesaclarity/pesaclarity-app/commit/b30b98816ea44cf44a11e3692bd52481c087901d))
* read Equity Bank alerts ([#110](https://github.com/pesaclarity/pesaclarity-app/issues/110)) ([a8e52c4](https://github.com/pesaclarity/pesaclarity-app/commit/a8e52c489f54bbd1c49295757a1b680aa0823477))
* read money messages from notifications ([#78](https://github.com/pesaclarity/pesaclarity-app/issues/78)) ([4bf87b6](https://github.com/pesaclarity/pesaclarity-app/commit/4bf87b63f5de4cf633bf00fe060ecded6088401c))
* receipts with document settings ([#171](https://github.com/pesaclarity/pesaclarity-app/issues/171)) ([1506358](https://github.com/pesaclarity/pesaclarity-app/commit/1506358bce3cddd388ea413e92b5ad2a427f327a))
* reminders with messages, country codes and contacts ([#167](https://github.com/pesaclarity/pesaclarity-app/issues/167)) ([7c4d2a7](https://github.com/pesaclarity/pesaclarity-app/commit/7c4d2a7c70dc302411f94cc87f1dd0b125ce6fd5))
* selector fields with most-used categories ([#93](https://github.com/pesaclarity/pesaclarity-app/issues/93)) ([3ccce98](https://github.com/pesaclarity/pesaclarity-app/commit/3ccce98ef7303f4e5bd1a4be6d32edc904723823))
* Sell and Pay for a business ([#162](https://github.com/pesaclarity/pesaclarity-app/issues/162)) ([72dab7c](https://github.com/pesaclarity/pesaclarity-app/commit/72dab7cc4bb0ed879ec5eed7538e059e242baa43))
* show the build version in Profile ([ef7ae4b](https://github.com/pesaclarity/pesaclarity-app/commit/ef7ae4b1ca3ea0a228d957d9536c080895208d98))
* show the build version in Profile ([0018d94](https://github.com/pesaclarity/pesaclarity-app/commit/0018d94947a27acfb7c6a5bbfed005165c0440bd))
* SideStore source for iPhone test builds ([#219](https://github.com/pesaclarity/pesaclarity-app/issues/219)) ([14ed0be](https://github.com/pesaclarity/pesaclarity-app/commit/14ed0be502d90fbb8a82c6fe120645a00af2b80a))
* spaces with their own encrypted data ([#141](https://github.com/pesaclarity/pesaclarity-app/issues/141)) ([e5daad0](https://github.com/pesaclarity/pesaclarity-app/commit/e5daad0923ae0c5bbfa3ded3ce1bd5cb76c24102))
* spending charts on Insights ([#80](https://github.com/pesaclarity/pesaclarity-app/issues/80)) ([415ba0a](https://github.com/pesaclarity/pesaclarity-app/commit/415ba0a9f0ac56151060ac799e6de6645400f4b5))
* stock for a business, with Sell tiles and counts ([#166](https://github.com/pesaclarity/pesaclarity-app/issues/166)) ([6e1c01a](https://github.com/pesaclarity/pesaclarity-app/commit/6e1c01a4f1252edcd63c30736db9fe867f14a43f))
* Support Pesa Clarity in the F-Droid build ([#209](https://github.com/pesaclarity/pesaclarity-app/issues/209)) ([c6187fa](https://github.com/pesaclarity/pesaclarity-app/commit/c6187fabb1af4865477f473dbe168b6b43c88537))
* support, allowance and gift income categories ([#137](https://github.com/pesaclarity/pesaclarity-app/issues/137)) ([b3a50b6](https://github.com/pesaclarity/pesaclarity-app/commit/b3a50b6337cf1443a117946aa8b043fd536d4f8b))
* tax estimates with the tax pack and withheld tax ([#170](https://github.com/pesaclarity/pesaclarity-app/issues/170)) ([a2e69fc](https://github.com/pesaclarity/pesaclarity-app/commit/a2e69fc4bd5053d78bcd5f0a696ec393f3403662))
* the approved look, red only where it counts ([#203](https://github.com/pesaclarity/pesaclarity-app/issues/203)) ([d8c16c5](https://github.com/pesaclarity/pesaclarity-app/commit/d8c16c5eb515e6ef0a91b203fe5a37101cf375ea))
* track subscriptions ([#81](https://github.com/pesaclarity/pesaclarity-app/issues/81)) ([c1efb35](https://github.com/pesaclarity/pesaclarity-app/commit/c1efb352213b8016e10e0acba3c775c14b9dc64f))
* unsigned iPhone build for sideloading ([#218](https://github.com/pesaclarity/pesaclarity-app/issues/218)) ([5a877c6](https://github.com/pesaclarity/pesaclarity-app/commit/5a877c67a88d307d954ad00eefc627ddd431ed0a))
* vault signs in with the account ([3570d44](https://github.com/pesaclarity/pesaclarity-app/commit/3570d44654082f0d5b220e07d3b0ccb29e0a3f82))
* vault signs in with the account ([#102](https://github.com/pesaclarity/pesaclarity-app/issues/102)) ([7625507](https://github.com/pesaclarity/pesaclarity-app/commit/76255079fa715e428c0107c98f13111efe90ae9e))
* week by week with a kibubu for business and gigs ([#140](https://github.com/pesaclarity/pesaclarity-app/issues/140)) ([369a4d8](https://github.com/pesaclarity/pesaclarity-app/commit/369a4d8067881e7de18e9ffd7c6e97528e3c867b))
* what a business sells, and start its records ([#160](https://github.com/pesaclarity/pesaclarity-app/issues/160)) ([ee36c98](https://github.com/pesaclarity/pesaclarity-app/commit/ee36c98ba08506a30b92a3ebac9b2facb39dcde7))


### Fixes

* balances that add up (Fuliza, own transfers, set the balance, cash) ([#220](https://github.com/pesaclarity/pesaclarity-app/issues/220)) ([2ff347a](https://github.com/pesaclarity/pesaclarity-app/commit/2ff347a2fc611639c64b37a57e5b18b3d11fb5c9))
* bring back the details that inform ([#207](https://github.com/pesaclarity/pesaclarity-app/issues/207)) ([9c6adb4](https://github.com/pesaclarity/pesaclarity-app/commit/9c6adb4735a9940c730b95a5ab5fdeb7f0a54985))
* clear Fuliza from M-Pesa balances and resolve balance gaps ([#221](https://github.com/pesaclarity/pesaclarity-app/issues/221)) ([62bda0b](https://github.com/pesaclarity/pesaclarity-app/commit/62bda0bff323c3ee7d8505ec8ca8d5e998209d31))
* long category names no longer split the account, such as M-Pesa ([#205](https://github.com/pesaclarity/pesaclarity-app/issues/205)) ([ba3656f](https://github.com/pesaclarity/pesaclarity-app/commit/ba3656f640be986574e785ee4021f42417211401))
* one way to hide amounts, one eye everywhere ([#201](https://github.com/pesaclarity/pesaclarity-app/issues/201)) ([20819f4](https://github.com/pesaclarity/pesaclarity-app/commit/20819f43d66252e1dca6771d4c1dde6cf94edcf4))
* point Xiaomi phones to Obtainium when SMS is blocked ([#217](https://github.com/pesaclarity/pesaclarity-app/issues/217)) ([2d956b3](https://github.com/pesaclarity/pesaclarity-app/commit/2d956b3360dc315d319962d7a8d74d40ed116f1f))
* promote dev to main (account names stay whole) ([ac9f764](https://github.com/pesaclarity/pesaclarity-app/commit/ac9f7640a2f1b43316345f1b7c95b063fa6bda8b))
* promote dev to main (safe to spend at most a usual day) ([f2d67b7](https://github.com/pesaclarity/pesaclarity-app/commit/f2d67b785178725896668d84c4681fcf1e9c23d0))
* safe to spend is at most a usual day, not everything on hand ([#199](https://github.com/pesaclarity/pesaclarity-app/issues/199)) ([fcdd5aa](https://github.com/pesaclarity/pesaclarity-app/commit/fcdd5aa21f116b06fb31b2e5c50b3c40b46cb49d))
* step-by-step help to allow messages, restricted settings included ([#151](https://github.com/pesaclarity/pesaclarity-app/issues/151)) ([4badd78](https://github.com/pesaclarity/pesaclarity-app/commit/4badd78ae8b93e6300431a134a3a29a8a9cf5453))
* use the user's timezone for dates as well as day starts ([12c47f9](https://github.com/pesaclarity/pesaclarity-app/commit/12c47f9e13d0682151fd3dfa59d0ba42a2305c33))
* wait for unlock before checking learning, so setup can continue ([#156](https://github.com/pesaclarity/pesaclarity-app/issues/156)) ([986a2cb](https://github.com/pesaclarity/pesaclarity-app/commit/986a2cb6f39397d60c8213f2cf8df6844a71de61))


### Performance

* optimize app launching and running on small devices ([37915e9](https://github.com/pesaclarity/pesaclarity-app/commit/37915e96b07c3e5e24035d2e3dd4c59fa48c50ae))


### Reverts

* read money messages from notifications ([#79](https://github.com/pesaclarity/pesaclarity-app/issues/79)) ([0319257](https://github.com/pesaclarity/pesaclarity-app/commit/03192572d107654fd03c2030f1bd04acb834260d))

## 0.1.0

The proof of concept before release notes were generated: SMS capture, Home, Activity, Plan, Goals, Debts, Insights, encrypted backups, sign-in, statement import and the light and dark themes.
