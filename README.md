# magisk-installerx-aosp

自动化同步上游 [InstallerX Revived](https://github.com/wxxsfxyzm/InstallerX-Revived) 并将应用包名替换为原生系统包名 `com.android.packageinstaller` 的 AOSP 系统级安装器 Magisk / KernelSU / APatch 模块。

---

## ✨ 模块特性

* **原生系统替换**：将官方应用包名修改为 `com.android.packageinstaller`，替换系统默认原生安装器，接管所有安装 Intent。
* **全自动构建与发布**：
  * 每 6 小时自动检测上游 Release（包含最新 Preview 预览版与正式版）。
  * 上游有更新时自动在 GitHub Actions 中完成反编译、包名替换、重新对齐（zipalign）与 V2/V3 签名。
  * 自动发布 Release，包含 `AOSP.zip` 模块与独立 APK。
* **签名一致性**：通过固化的 Keystore 密钥签名，支持跨版本直接覆盖更新，无需卸载。

---

## 📥 下载安装

前往 [Releases 页面](../../releases) 下载最新版本：
* **`AOSP.zip`**：使用 Magisk / KernelSU / APatch 刷入并重启设备即可。
* **`InstallerX-Revived-online-<version>.apk`**：已修改为系统包名的独立 APK 文件。

---

## 🛠️ 本地手动构建

如需在本地构建，执行以下步骤：

```bash
# 赋予执行权限
chmod +x scripts/build.sh

# 自动拉取上游最新版本构建
./scripts/build.sh

# 或指定构建特定 Tag
./scripts/build.sh 26.10.35d7c7a
```

构建完成后产物将保存在 `dist/` 目录下：
* `dist/AOSP.zip`
* `dist/InstallerX-Revived-online-<version>.apk`

---

## 📄 鸣谢

* [InstallerX-Revived](https://github.com/wxxsfxyzm/InstallerX-Revived) by [wxxsfxyzm](https://github.com/wxxsfxyzm)
* [Apktool](https://github.com/iBotPeaches/Apktool) by Connor Tumbleson & Ryszard Wiśniewski
