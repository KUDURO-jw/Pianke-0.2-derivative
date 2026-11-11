# 片刻·焕新版 0.2.29

## 修复：撤销提示条不自动消失 + 下滑时闪屏

**问题一**：删除影片后的撤销提示条不会自己消失，必须手动下滑。
而且因为关闭事件永不触发，`commit()` 也不执行——界面显示已删除，
数据库里还留着，重启后影片会回来。

**问题二**：手动下滑取消时，屏幕会闪一下。

## 根因

原实现用 `ScaffoldMessenger.showSnackBar`。它的倒计时启动有一个前置条件：

```dart
if (_snackBars.isEmpty) {
  _snackBarController.forward();   // 只有队列空时才启动进入动画
}
```

而 `ScaffoldMessengerState.build` 里启动 `Timer` 又要求
`_snackBarController.isCompleted`。本项目的调用时序（确认对话框
`pop()` 之后立刻调用）会让 controller 停在未完成状态，于是
`Timer` 从不创建 → 提示条不消失 → `closed` 永不完成 → `commit()` 不执行。

下滑闪屏则来自 SnackBar 的退场动画：它走 Material 内置的整层淡出，
与本项目「页面转场不用淡入」的取向冲突，滑走那一下会露出背景。

## 修复：改为自绘提示条

不再依赖 `ScaffoldMessenger`，在 `Overlay` 上挂一条自绘提示条，
倒计时与退场动画完全自己持有。

**视觉严格对齐项目规范**：

- 深色胶囊 `#2A2A2E`，与全局 `snackBarTheme` 一致
- 连续圆角 `Radii.md` + `smoothing 0.6`
- 正文 `TypeScale.body` / `w500`，撤销按钮 `TypeScale.label` / `w700`
- 撤销按钮用主题强调色 `scheme.accent`，胶囊形 `Radii.pill`
- 阴影走 `Shadows.floating`
- 位置避开悬浮底栏，与 `AppToast` 同一套避让规则

**动画**：

- 入场：从下方 12dp 上浮 + 透明度 0→1，`Motion.panel`（150ms）
- 退场：反向播放同一段，不整层淡出，滑走时不会露出背景
- 下滑手势：向下快速拖动即关闭（与系统提示条习惯一致）
- 尊重「移除动画」：该开关打开时直接到位

## 新增测试

`test/ui/undo_banner_test.dart` 4 项：

1. 提示条在窗口结束后自动消失，并提交删除
2. 点「撤销」后提示条消失且不提交删除
3. 下滑关闭视为确认删除
4. 视觉参数符合项目规范（底色、强调色）

另外把 `shouldCommitDeleteAfter` 的入参从框架的
`SnackBarClosedReason` 换成项目自己的 `UndoDismissReason`，
不再依赖 Material 的内部枚举。

## 验证

- 静态分析零问题
- 前端测试 141 项全部通过（此前 3 项 skip 已移除）
- 业务测试 203 项、视觉基线 6 项通过
- 动效令牌检查通过

本版递增为 0.2.29（35），沿用 `app.pianke.personal` 与既有发布证书，
可从 0.2.28（34）直接覆盖更新，无需卸载。

### 验证边界

自动消失、撤销、下滑关闭、视觉参数均在测试中验证；
真机上的手感与观感需安装后确认。
