# Galaxy Watch NFC Provide

这是独立的 KernelSU systemless 模块仓库。模块 ID 固定为：

```text
galaxy_watch_nfc_provide
```

测试 APK 不在本仓库中，放在旁边的 `nfc_tools_test_apk` 目录。模块可以独立工作，不依赖该 APK。

安装这个模块前先在管理器中禁用旧的 `nfc_reader_unlock`，重启后再安装；两个模块覆盖同一份 NFC feature/轮询路径，不应同时启用。

## 模块功能

安装时读取设备自己的 `libnfc-nci.conf`，把 `POLLING_TECH_MASK` 与 `0x0F` 做按位或，生成 systemless overlay，并补充基础 `android.hardware.nfc` feature。其他 NFC、RF、时钟、路由和 vendor 配置保持设备原值。

模块同时包含实验性的 root UID 接口。安装阶段只做 Binder 能力探测和 `CORE_GET_CONFIG`，不会发送控制器 SET 命令。UID 持久化默认关闭。

没有机型或固件白名单不代表所有 NFC 控制器都兼容。无法安全解析的配置会中止安装，不写入猜测值。

## UID 命令

安装并重启后：

```sh
su -c '/data/adb/modules/galaxy_watch_nfc_provide/uidctl probe'
su -c '/data/adb/modules/galaxy_watch_nfc_provide/uidctl get'
su -c '/data/adb/modules/galaxy_watch_nfc_provide/uidctl status'
```

只接受 4 字节十六进制 UID：

```sh
su -c '/data/adb/modules/galaxy_watch_nfc_provide/uidctl set AABBCCDD'
su -c '/data/adb/modules/galaxy_watch_nfc_provide/uidctl persist AABBCCDD'
su -c '/data/adb/modules/galaxy_watch_nfc_provide/uidctl reset'
```

`set` 是临时操作；`persist` 才会保存并启动受锁保护、最多重试三次的 watcher；`reset` 关闭持久化并恢复安装时记录的设备默认参数。每次写入均使用三星 `pausePolling(long)`，写后读回校验，失败尝试回滚。不要在钱包、门禁或其他 NFC 事务中操作。控制器读回不等于外部读卡器看到的空口 UID。

部分三星固件对成功的 `CORE_SET_CONFIG` 只返回单字节状态 `00`，helper 将它与标准双字节 `0000` 一样视为成功。

状态目录为 `/data/adb/galaxy_watch_nfc_provide`，其中包含固件指纹和 UID 状态，应保持私有。

## 构建

源码仓库不包含测试 APK、私钥或密码文件：

```text
python tools/build_module.py
python tools/test_core.py
```

输出为可供 KernelSU/BakaSU 安装的模块 ZIP。该 ZIP 不需要 APK 签名；需要发布签名时，应在仓库外使用独立的发布密钥处理。

## 验证范围

主机测试覆盖配置解析、NFCID1 TLV、有限回滚和 Type 4 APDU。Galaxy Watch7 SM-L315F 已完成只读 `probe/get` 验证。构建和安装不会自动执行 UID SET，当前也没有把实体标签空口 UID 当作已验证结果。
