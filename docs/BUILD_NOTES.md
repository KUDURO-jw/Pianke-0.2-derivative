# 可复现构建说明

本版源工程不含 SDK、编译产物和签名材料。使用 Flutter 3.44.0、Dart 3.12.0、JDK 17、Gradle 8.14 bin、AGP 8.11.1、Kotlin 2.2.20；pubspec.lock 不变。SDK 主平台 API 36 / Build Tools 35.0.0，插件还要求 API 33、34、35，原生构建要求 NDK 28.2.13676358、CMake 3.22.1。

```powershell
flutter pub get --enforce-lockfile
flutter analyze --no-pub
flutter test --no-pub
flutter build apk --release --target-platform android-arm64 --no-pub
```

默认输出 `build/app/outputs/flutter-apk/app-release.apk`。`android/gradle.properties` 的 `disable-abi-filtering=true` 用于保留工程的 arm64 过滤器，防止 Flutter 3.44 重置为全架构。不要为单 arm64 构建额外添加 `--split-per-abi`。

默认 Release 构建使用当前电脑已有 debug keystore。需要正式签名时自行在 android/key.properties 填入 storeFile、storePassword、keyAlias、keyPassword，私钥与密码不得提交或打包。不同证书无法覆盖安装本次交付的应用。

本次使用官方 Flutter 3.44.0 源码归档搭建命令行 SDK，engine 固定为 `4c525dac5ebe5971c5708ef73558ed8edcf4a362`。本机 env.ps1 中的 FLUTTER_PREBUILT_ENGINE_VERSION 仅为该归档式 SDK 所需；使用官方完整 Flutter SDK 时无需此变量。SDK 的本地 Git 元数据不代表 Flutter 上游源码提交，不作为应用业务基线。

因官方下载速度问题，Gradle bin 使用镜像续传并核对官方 SHA-256：`61ad310d3c7d3e5da131b76bbf22b5a4c0786e9d892dae8c1658d4b484de3caa`。本机 GRADLE_USER_HOME/init.d 使用 Maven 下载镜像，工程仓库声明保持原状，未改动依赖版本。

Flutter 提示现有 package_info_plus/share_plus 尚使用 KGP，涉及未来 Flutter 兼容性；当前锁定版本已成功构建，未为消除提示而升级依赖。另有框架内置 CupertinoIcons 字体引用提示；应用界面不引用 CupertinoIcons，使用已打包的 MaterialIcons，未增加无用图标依赖。

真实页面渲染测试在 Windows 上可用本机微软雅黑字体，字体仅供测试加载。无该字体时仍可运行逻辑/布局测试。test/visual 下旧组件视觉基线已更新为本版外观；这些测试样本不会进入安装包。
