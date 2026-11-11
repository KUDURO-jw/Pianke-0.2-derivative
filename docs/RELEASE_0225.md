# 片刻·焕新版 0.2.25

## 修复：片库页崩溃（0.2.23 引入）

**问题**：进入片库时白屏或页面无法滚动，日志里反复出现
`Unsupported operation: Infinity or NaN toInt`。

**根因**：0.2.23 为了提升滚动性能，把骨架屏网格从 `childAspectRatio`
改成固定行高 `mainAxisExtent`。骨架屏在片库页是被 `SliverToBoxAdapter`
包着的，父级给出的约束是「高度无界」（`0 <= h <= Infinity`）。

`GridView` 默认要撑满父级高度，在无界约束下算出的行步长是 Infinity，
随后 `scrollOffset / rowStride` 得到 Infinity，
在 `getMinChildIndexForScrollOffset` 里 `toInt()` 直接抛异常。

`childAspectRatio` 走的是另一条布局路径，不会触发这个问题——
所以这是我上一版改动引入的回归，不是原有缺陷。

**修复**：

- 骨架网格加 `shrinkWrap: true`，按内容高度布局，不再去撑满无界父级。
- `_libraryCardExtent` 增加有限性校验，非法值回退到 300，
  防止将来改成按宽度换算时再次流出非法值。

## 新增回归测试

5 项测试覆盖骨架屏在各类父级约束下的行为：

- `SliverToBoxAdapter` 包裹（片库页真实用法）
- `Column` + `SingleChildScrollView` 包裹
- 直接放在有界 `Scaffold` body
- 2 倍字体下的无界场景
- 断言 `shrinkWrap` 为真、`mainAxisExtent` 为有限正数

## 说明

- 验证：静态分析零问题；前端测试 135 项（新增 5 项）、
  业务测试 194 项、视觉基线 6 项全部通过；动效令牌检查通过。
- 0.2.23 的滚动性能优化仍然有效（实测 458ms → 331ms），
  本版只是修掉了它在无界约束下的崩溃。

本版递增为 0.2.25（31），沿用 `app.pianke.personal` 与既有发布证书，
可从 0.2.24（30）直接覆盖更新，无需卸载。

### 验证边界

崩溃场景在测试框架内复现并验证修复；真机上的实际表现需安装后确认。
