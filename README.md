# Galaxy Watch NFC Provide

Standalone KernelSU systemless module by **gohj99**. The module ID is fixed:

```text
galaxy_watch_nfc_provide
```

The test APK is a separate project in the adjacent `nfc_tools_test_apk` folder. It is not included in this repository or module ZIP.

## Module behavior

- Copies the device's own `libnfc-nci.conf`, enables polling bits `0x0F`, and declares `android.hardware.nfc`.
- Keeps an editable module copy of the device's `libnfc-nxp.conf` and a private original backup. An upgrade preserves the currently visible NXP edits, including an explicitly configured UID.
- On devices with `/system/etc/nfc_rule_configs.xml`, backs up the original and prepares an editable copy without changing any bytes or route destinations. A first installation retains the OEM defaults; upgrades retain the currently visible configuration, including application edits. Devices without this Samsung policy skip this overlay.
- Includes optional root UID diagnostics and guarded controller operations. No UID is hardcoded in the module. Installation does not issue `CORE_SET_CONFIG`.

Magic Mount-rs owns mounting and removal. The module never remounts firmware partitions or creates its own bind mounts. Disable the older `nfc_reader_unlock` module before installing this one, then reboot.

A root-authorized card-emulation application chooses when to change routing to `DH` (device host), set the desired UID, and restore the previous configuration afterwards. Changing default routes can affect off-host cards. The module provides editable configuration files and does not choose those values automatically or implement MIFARE Classic memory, keys or authentication.

On SM-L315F, the user reported repeated phone reads of `09F85906` with a manually configured NXP UID and the v1.0.5 host-routing policy. This is one tested setup, not a guarantee for all firmware or NFC modes.

## Configuration and backups

On the tested Watch7, the editable NXP source is:

```text
/data/adb/modules/galaxy_watch_nfc_provide/system/vendor/etc/libnfc-nxp.conf
```

The editable Samsung policy source is:

```text
/data/adb/modules/galaxy_watch_nfc_provide/system/etc/nfc_rule_configs.xml
```

Private originals are stored under `/data/adb/galaxy_watch_nfc_provide/config/` and `/data/adb/galaxy_watch_nfc_provide/routing/`, with hashes and firmware fingerprints. Originals are never replaced during ordinary upgrades. Uninstalling and rebooting reveals the untouched firmware files; private backups remain available.

Files are owned by root with mode `0644` and the original SELinux context. A root-authorized application can write the NXP module copy **in place**. Do not replace it with a rename or `sed -i`, since Magic Mount-rs binds the existing inode. There is no import script or unprivileged write service. Visible file bytes change with in-place writes, but that does not prove the NFC services have reloaded them. A new overlay requires a reboot for manager mounting. NXP configuration reload by NFC off/on was observed on the test watch; Samsung routing policy reload after runtime edits still needs separate verification, so a reboot is the confirmed way to apply both.

Upgrading from v1.0.5 preserves its currently active `DH` configuration. This release stops enforcing `DH`; it does not silently reset your working setup. An application can restore the backed-up `original.xml` into the existing module source inode when stock routing is wanted.

Read-only verification:

```sh
su -c '/data/adb/modules/galaxy_watch_nfc_provide/verify.sh'
su -c '/data/adb/modules/galaxy_watch_nfc_provide/nfcconf status'
```

These check configuration files, mounts and NFC state. They do not measure the air UID or prove wallet compatibility.

## Optional UID helper

```sh
su -c '/data/adb/modules/galaxy_watch_nfc_provide/uidctl probe'
su -c '/data/adb/modules/galaxy_watch_nfc_provide/uidctl get'
su -c '/data/adb/modules/galaxy_watch_nfc_provide/uidctl status'
```

Experimental mutations accept four-byte hexadecimal values:

```sh
su -c '/data/adb/modules/galaxy_watch_nfc_provide/uidctl set AABBCCDD'
su -c '/data/adb/modules/galaxy_watch_nfc_provide/uidctl persist AABBCCDD'
su -c '/data/adb/modules/galaxy_watch_nfc_provide/uidctl reset'
```

Persistence is off until explicitly requested. Operations use finite polling pauses, controller readback and bounded rollback. Samsung has one global vendor callback slot; avoid these operations during wallet/card activity. A controller readback is not an air UID measurement.

The saved factory baseline includes the vendor configuration hash. If you edit `libnfc-nxp.conf`, old SET/persist/reset commands may refuse with `Vendor configuration hash changed`. This is an intentional guard. The installer preserves an existing baseline and does not relabel a custom UID as the factory default. A configuration-only experiment should leave the old UID watcher disabled and keep its original baseline.

## Build and validation

```text
python tools/build_module.py
python tools/test_core.py
python tools/test_routing.py
```

Output: `dist/galaxy_watch_nfc_provide-v1.0.6.zip`, its `.zip.sha256` checksum and `dist/build-report.json`. This is a normal unsigned module ZIP for KernelSU/BakaSU. No signing key, certificate, Gradle project or test APK is needed.

Local builds use JDK 17 and Android SDK platform 36 / Build Tools 36.0.0. Set `JAVA_HOME` and `ANDROID_SDK_ROOT` (or `ANDROID_HOME`); the scripts also retain the existing Windows machine paths as fallbacks. Linux and Windows tool names are handled separately.

Routing storage tests cover exact original bytes, root edits, repeat preparation, upgrade preservation, inode preservation, backup and firmware guards, and devices without a Samsung policy. Core tests exercise the NCI and Type 4 helpers. An external reader is still required to check an air UID.

## GitHub cloud builds

The workflow in `.github/workflows/build.yml` runs on pushes to `main`, pull requests, `v*` tags and manual **Actions > Build module > Run workflow** requests. It sets up Python, JDK 17 and the Android SDK, runs syntax and behavior checks, builds an unsigned module ZIP, verifies its checksum and uploads the ZIP, checksum and build report under the run's **Artifacts** section.

For a tag build, the tag must match `module.prop` (for example, `v1.0.6`). The workflow only builds and uploads run artifacts; it does not require repository secrets. The test APK remains in its separate project.
