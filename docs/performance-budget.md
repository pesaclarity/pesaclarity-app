# Performance budget: 2 GB phones

The spec promises the app "works on 2 GB RAM Android Go phones". These are the targets a release must meet on that class of phone, and how to measure them. Measure release or profile builds only; debug builds are much slower.

## Reference phone

An Android Go phone with 2 GB RAM and a quad-core Cortex-A53, Android 11 Go edition or newer. Without one, use an emulator with 2048 MB RAM running an Android Go system image (`ro.config.low_ram=true`), and treat its numbers as a guide only.

## Targets

| Measure | Target | Notes |
| --- | --- | --- |
| Cold start to first frame | 2.0 s or less | `TotalTime` from `am start -W` |
| Cold start to Home with numbers | 3.0 s or less | With 12 months of data (about 6,000 transactions) |
| Memory on Home, steady | 150 MB PSS or less | After 30 s idle |
| Memory peak, first 90-day SMS scan | 220 MB PSS or less | 2,000 messages from selected senders |
| Scrolling Activity | 95% of frames under 16 ms | 1,000 transactions, profile build |
| Download size | 25 MB or less | arm64 `foss` APK |

Stay well under Android's low-memory-killer thresholds: on a Go phone a background app above about 200 MB is often killed, which loses the lock state and any unsaved work.

## How to measure

Cold start (repeat five times, take the median):

```sh
adb shell am force-stop com.pesaclarity.app
adb shell am start -W -S -n com.pesaclarity.app/.MainActivity
```

Flutter startup timeline, including time to first frame:

```sh
flutter run --profile --flavor foss --trace-startup
# writes build/start_up_info.json
```

Memory (PSS, in kB):

```sh
adb shell dumpsys meminfo com.pesaclarity.app | grep -E "TOTAL PSS|TOTAL:"
```

For a memory timeline and leaks, run a profile build and open the DevTools Memory view.

Frame times: run a profile build, scroll Activity for ten seconds, and read the frame chart in DevTools Performance, or `adb shell dumpsys gfxinfo com.pesaclarity.app`.

Download size:

```sh
flutter build apk --release --flavor foss --target-platform android-arm64 --analyze-size
```

## Data for measuring

Use synthetic data only: generate SMS with the samples in `test/helpers/sms_samples.dart` and the domain test fixtures, scaled to the counts above. Never measure with real messages.

## When a target is missed

Record the numbers and the phone in the release issue. Common causes: work on the UI isolate during the SMS scan (move parsing to a background isolate), loading all transactions instead of a window, and large images or fonts.
