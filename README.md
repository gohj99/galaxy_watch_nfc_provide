# Galaxy Watch NFC Provide

Standalone KernelSU systemless module by **gohj99**. The module ID is fixed:

```text
galaxy_watch_nfc_provide
```

The test APK is a separate project in the adjacent `nfc_tools_test_apk` folder. It is not included in this repository or module ZIP.

## Module behavior

- Copies the device's own `libnfc-nci.conf`, enables polling bits `0x0F`, and declares `android.hardware.nfc`.
- Keeps an editable module copy of the device's `libnfc-nxp.conf` and a private original backup. An upgrade preserves the currently visible NXP edits, including an explicitly configured UID.
- On devices with `/system/etc/nfc_rule_configs.xml`, derives an overlay from that policy and redirects `route_aid`, `route_iso_dep`, `route_tech` and `route_system_code` to `DH` (device host) in every existing rule. Region mappings, listening masks and other attributes are preserved. Unsupported XML layouts abort installation; devices without this Samsung policy skip this overlay.
- Includes optional root UID diagnostics and guarded controller operations. No UID is hardcoded in the module. Installation does not issue `CORE_SET_CONFIG`.

Magic Mount-rs owns mounting and removal. The module never remounts firmware partitions or creates its own bind mounts. Disable the older `nfc_reader_unlock` module before installing this one, then reboot.

Host routing changes default off-host behavior and may affect Samsung Wallet or secure-element cards while enabled. A host route is a prerequisite for using `LA_NFCID1` as an NFC-A card UID on supported NXP controllers; it does not prove that a particular device emits the requested UID. Verify with an independent reader. It also does not implement MIFARE Classic memory, keys or authentication.

## Configuration and backups

On the tested Watch7, the editable NXP source is:

```text
/data/adb/modules/galaxy_watch_nfc_provide/system/vendor/etc/libnfc-nxp.conf
```

The Samsung policy overlay is generated during installation at:

```text
/data/adb/modules/galaxy_watch_nfc_provide/system/etc/nfc_rule_configs.xml
```

Private originals are stored under `/data/adb/galaxy_watch_nfc_provide/config/` and `/data/adb/galaxy_watch_nfc_provide/routing/`, with hashes and firmware fingerprints. Originals are never replaced during ordinary upgrades. Uninstalling and rebooting reveals the untouched firmware files; private backups remain available.

Files are owned by root with mode `0644` and the original SELinux context. A root-authorized application can write the NXP module copy **in place**. Do not replace it with a rename or `sed -i`, since Magic Mount-rs binds the existing inode. There is no import script or unprivileged write service. NFC must reload the configuration after edits; a new routing overlay requires a reboot for manager mounting and Samsung service startup.

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

Output: `dist/galaxy_watch_nfc_provide-v1.0.5.zip`, suitable for KernelSU/BakaSU. Module ZIP installation does not require APK signing. Optional release signing uses a separate private key outside this repository. Neither private signing material nor test APKs are included.

The host-routing transformation is tested for unrelated-byte preservation, XML semantics, repeat application and unsupported-policy rejection. It has also been run against the connected SM-L315F policy in an Android shell without altering the live policy. Installing, rebooting and checking Samsung's resolved route plus an external UID reading are still required to validate the new routing behavior.
