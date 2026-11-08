# 片刻·焕新版

完整功能基于 [KUDURO-jw/Pianke-0.2-derivative](https://github.com/KUDURO-jw/Pianke-0.2-derivative)，基线提交 `9220c0e07725bddc1c8256485b5f005d63600360`。视觉与交互参考 [FlClash](https://github.com/chen08209/FlClash) 的 `be84736605527034689c95bf27828ff27d912c5e`，没有复制 FlClash 或 prism_ui 的代码和素材。

本版保留 Apache-2.0、原 LICENSE、NOTICE 及上游版权。改动文件包含修改声明。本版独立实现的界面改动同样以 Apache-2.0 提供。此版本与上游作者无隶属关系。

## 安装与迁移

- Android 应用名：片刻·焕新版；包名：`app.pianke.personal`。
- APK 面向 arm64 手机，最低 Android 7.0（API 24）。
- 使用个人电脑已有的 Android 调试密钥签署 **Release 模式** APK，不是正式发布密钥。
- 与原版独立安装。原版“设置 → 导出备份”，再在本版“设置 → 从备份恢复”选择 JSON。密码不会随备份迁移，需要重新填写。
- WebDAV 的覆盖、冲突和安全备份规则沿用功能上游。首次同步前请确认远程目录及希望保留的数据。
- 更新检查使用独立的 `update-ui.json`。0.2.6 起在应用内下载并显示进度，可取消、重试；校验 SHA-256 后点击“安装新版”，由 Android 确认安装。首次可能需允许片刻安装应用。不进行启动检查、后台轮询或静默安装，也不需要存储权限。旧版 `update.json` 保持独立。0.2.5 及更早版本仍需先手动覆盖安装 0.2.6，之后才有应用内下载功能。

## 构建

当前发布版本为 0.2.6（11）。新增应用内下载进度、取消与失败重试，并校验更新包的摘要、包名、版本和签名后打开系统安装确认。保留 0.2.5 的紧凑排版、独立分集、海报转场与底栏优化。详细变更与小米手机验收步骤见 `docs/UI_UPDATES.md`。实际手机下载和安装权限流程仍需真机验收。

使用 Flutter 3.44.0、Dart 3.12.0、JDK 17、Android API 36、Android Build Tools 35.0.0。依赖以 `pubspec.lock` 为准。实际构建按原生依赖要求安装了 NDK 28.2.13676358、CMake 3.22.1 及 API 33–35 平台；不需要 Android Studio、模拟器或系统镜像。

```powershell
flutter pub get --enforce-lockfile
flutter analyze --no-fatal-infos
flutter test test/services
flutter test test/ui
flutter build apk --release --target-platform android-arm64
```

默认签名沿用 B 的 debug signingConfig；可使用 `android/key.properties` 指定自己拥有的正式密钥。密钥与密码不包含在源码交付中。不需要 Android Studio 或模拟器。

功能对照与验证边界见 `docs/FUNCTION_PARITY.md`。上游 README 保留作为原始说明。

## 初版 0.2.0 交付验证

- Android Release 编译成功；APK 仅含 arm64-v8a，最低 API 24，目标 API 36，版本 0.2.0（4）。
- 静态分析零问题；完整测试 56 项通过，包括原业务测试、旧/新 JSON 备份回归、真实页面浅深色与小屏大字体、导航/会话编辑和组件视觉基线。
- 业务目录与锁文件共 29 个文件与上述基线保持一致。两项上游 WebDAV 测试补充了显式的云端冲突选择，未修改同步规则。
- UI 测试数据仅在 test 目录。截图用于排版核对，不进入应用数据；测试字体从本机读取，不打包系统字体。
- APK 签名、应用 ID、版本、唯一架构和 16KB 对齐均已检查。证书是现有 Android Debug 证书，不是正式发布签名。
- 未进行真机或模拟器测试。豆瓣在线抓取、真实坚果云账号、Android 文件选择/分享/安全存储及实际帧率仍需安装后验收。

源代码不包含签名私钥。将来覆盖升级本版时需保留本机现有密钥；改用其他证书将无法直接覆盖安装。
