# irmamobile (PQ-Yivi)

The mobile client for the **PQ-Yivi** demo. Use this app to receive and manage credentials issued by the [PQ-Yivi email issuer](https://github.com/AVecsi/irma_email_issuer).

> This repository is part of the **PQ-Yivi** demo. For the email issuer, see the [irma_email_issuer](https://github.com/AVecsi/irma_email_issuer) repository. For the verifier see [pq-irmago](https://github.com/AVecsi/pq-irmago)

> **Note:** This app is a modified version of the original Yivi/IRMA app adapted for the PQ-Yivi demo. It is not intended for general use.

---

## Requirements

- [Flutter](https://flutter.dev/docs/get-started/install)
- [Go](https://golang.org/dl/)
- Java 17 (recommended)
- Android SDK with the following components:
  - Android SDK Command-line Tools
  - Android SDK Build-Tools
  - Android SDK Platform-Tools
  - NDK
  - CMake

---

## Setup

### 1. Clone the repository

```bash
git clone --recursive git@github.com:AVecsi/irmamobile.git
```

If you forgot `--recursive`, initialize the submodules manually:

```bash
cd irmamobile
git submodule init
git submodule update
```

### 2. Set up environment variables

```bash
echo 'export ANDROID_HOME="/YOUR/PATH/TO/android-sdk"' >> "$HOME/.bashrc"
echo 'export PATH="$ANDROID_HOME/tools:$ANDROID_HOME/platform-tools:$PATH"' >> "$HOME/.bashrc"
```

### 3. Install gomobile and build the Go bridge

```bash
go install golang.org/x/mobile/cmd/gomobile
gomobile init
./bind_go.sh
```

### 4. Run the app

Start an emulator or connect a physical device, then run:

```bash
flutter run --flavor alpha
```

> If you update anything in the Go bridge or `pq-irmago`, re-run `./bind_go.sh` before launching the app again.

---

## Troubleshooting

- **Submodules missing:** if `find ./irma_configuration` is empty, your submodules were not initialized — run `git submodule init && git submodule update`.
- **NDK not found:** set `ANDROID_NDK_HOME` to the correct version directory inside `$ANDROID_HOME/ndk/`.
- **`x_cgo_inittls` error in `bind_go.sh`:** you are likely using an incompatible NDK version or an outdated Go version.
- **Flutter can't find the APK:** make sure you include `--flavor alpha` in your run command.
- **Wrong Java version:** run `flutter config --jdk-dir <jdk_dir>` to point Flutter at Java 17.
