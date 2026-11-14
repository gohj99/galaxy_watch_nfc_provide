# Galaxy Watch NFC Provide

[English](README.md) | [简体中文](README.zh-CN.md)

这是一个适用于 KernelSU/BakaSU 的 NFC systemless 模块，用于编辑设备现有的 NFC 配置。模块会保留原始文件备份，不会把 UID 写死，也不会替换 NFC 服务。

本模块已在 Galaxy Watch 7 44mm 上测试成功。设计上适用于 Wear OS 设备，但其他型号和厂商仍需要自行验证兼容性。

模块 ID：

```text
galaxy_watch_nfc_provide
```

## 安装

1. 从 GitHub 的 **Releases** 页面下载对应版本的 ZIP，例如 `galaxy_watch_nfc_provide-v1.0.7.zip`。
2. 在 KernelSU 或 BakaSU 中安装 ZIP。
3. 如果安装了旧的 `nfc_reader_unlock` 模块，请先停用。
4. 重启设备，让模块覆盖文件完成挂载。

模块使用 Magic Mount-rs 管理挂载和移除，不会自行 remount 固件分区，也不会创建额外的 bind mount。

## 配置文件

模块会在文件存在时创建以下可编辑副本：

```text
/data/adb/modules/galaxy_watch_nfc_provide/system/vendor/etc/libnfc-nxp.conf
/data/adb/modules/galaxy_watch_nfc_provide/system/etc/nfc_rule_configs.xml
```

原始文件保存在：

```text
/data/adb/galaxy_watch_nfc_provide/config/
/data/adb/galaxy_watch_nfc_provide/routing/
```

请原地写入修改，不要使用 `mv` 或 `sed -i` 替换文件；Magic Mount-rs 绑定的是原文件 inode。升级时会保留当前可见配置。

## 修改配置后生效

修改 `libnfc-nxp.conf` 或 `nfc_rule_configs.xml` 后，执行以下命令重新初始化 NFC：

```bash
su -c 'cmd nfc disable-nfc'
sleep 2
su -c 'cmd nfc enable-nfc'
```

安装或升级模块后仍需要重启设备以挂载新的覆盖文件。重新初始化 NFC 不等于验证实体标签 UID 或钱包应用兼容性。

## 检查安装

以下命令只读检查配置、挂载和 NFC 服务状态：

```bash
su -c '/data/adb/modules/galaxy_watch_nfc_provide/verify.sh'
su -c '/data/adb/modules/galaxy_watch_nfc_provide/nfcconf status'
```

## 可选 UID 工具

UID 工具默认只读，只有明确执行修改命令才会尝试改变控制器配置：

```bash
su -c '/data/adb/modules/galaxy_watch_nfc_provide/uidctl probe'
su -c '/data/adb/modules/galaxy_watch_nfc_provide/uidctl get'
su -c '/data/adb/modules/galaxy_watch_nfc_provide/uidctl status'
```

实验性修改使用四字节十六进制 UID：

```bash
su -c '/data/adb/modules/galaxy_watch_nfc_provide/uidctl set AABBCCDD'
su -c '/data/adb/modules/galaxy_watch_nfc_provide/uidctl persist AABBCCDD'
su -c '/data/adb/modules/galaxy_watch_nfc_provide/uidctl reset'
```

不要在刷卡、钱包或其他 NFC 活动期间执行这些命令。模块会保存设备基线；如果厂商配置哈希发生变化，会拒绝不安全的 UID 操作。模块不实现 MIFARE Classic 存储、密钥或认证。

## 构建和测试

本地构建需要 JDK 17、Android SDK Platform 36 和 Build Tools 36.0.0：

```bash
python tools/build_module.py
python tools/test_core.py
python tools/test_routing.py
```

构建产物写入 `dist/`，包括模块 ZIP、SHA-256 校验文件和 `build-report.json`。这些文件会被 Git 忽略。模块脚本源码位于 `scripts/`，打包时会放回 ZIP 根目录所需的位置。

## GitHub Releases

GitHub Actions 监听 `master`、Pull Request 和手动运行。workflow 会读取 `module.prop` 中的版本号，并自动加上 `v` 前缀：

```text
module.prop: version=1.0.7
Git tag:      v1.0.7
```

对于非 Pull Request 运行，workflow 会先检查 `v1.0.7` 这个 Release 是否存在。如果不存在，就构建模块，在当前提交上自动创建 `v1.0.7` tag，并发布 GitHub Release。你不需要手动创建 tag；如果 Release 已存在，workflow 会保持它不变。

Release 资产为：

```text
galaxy_watch_nfc_provide-v1.0.7.zip
galaxy_watch_nfc_provide-v1.0.7.zip.sha256
build-report.json
```

Pull Request 只执行验证，不会创建 tag 或 Release。workflow 不会上传 GitHub Actions **Artifacts**。发布文件由 GitHub 管理，不会提交到仓库的 `releases/` 或 `dist/` 目录。

## 许可证

本项目使用 GNU General Public License v3 或更高版本，详见 `LICENSE`。
