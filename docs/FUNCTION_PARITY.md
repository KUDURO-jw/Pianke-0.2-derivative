# 功能对照与验收依据

基线：B `9220c0e07725bddc1c8256485b5f005d63600360`。原有功能入口全部保留；本次变更主要在 UI 层。下表的“核对”指源代码、回调和业务路径核对，不能替代真机验收。自动检查结果另附交付构建记录。

| 功能 | 原入口 → 新入口 | 业务依据 | 核对内容 |
|---|---|---|---|
| 片库搜索、筛选与分页 | 片库 → 片库 | MovieProvider / StorageService | 搜索防抖、全部/未看/已看、总数、滚动加载保留 |
| 删除影片 | 海报长按 → 海报长按 | MovieProvider.deleteMovie | 确认/取消及关联清理不变 |
| 豆瓣搜索添加 | 添加影片/搜索 → 同入口 | MovieScraperService.searchMovies | 搜索、分页、逐部添加、去重与错误反馈 |
| 单片/跳转链接导入 | 添加影片/豆瓣链接 → 同入口 | scrapeMovie / fetchMoviePreview | 真网络抓取、预览、确认添加 |
| 片单批量导入 | 添加影片/豆瓣链接 → 同入口 | scrapeDoulist / addScrapedMovies | 进度、陆续显示、单部/全部添加及重复统计 |
| 手动添加 | 添加影片/手动添加 → 同入口 | addManualMovie | 名称、年份、导演及原校验 |
| 影片详情 | 片库/海报 → 同入口 | getMovieById | 海报、评分、演职员、元信息、简介展开与外链 |
| 剧集进度 | 详情/分集 → 同入口 | WatchStatus / updateMovie | 分集勾选与全部看完判定一致 |
| 个人评分、短评 | 详情/个人区域 → 同入口 | updateMovie | 修改、保存和原有触发行为 |
| 标签 | 详情/我的标签 → 同入口 | CollectionProvider / StorageService | 标签选择、新建、颜色、保存关联 |
| 多次观影 | 详情/记录一次观影 → 同入口 | ViewingSession / MovieProvider | 同片多条独立记录 |
| 编辑/删除记录 | 详情/记录操作 → 同入口 | updateViewingSession / deleteViewingSession | 原数据载入、保存和列表刷新 |
| 观影字段 | 记录编辑面板 → 同入口 | showViewingSessionEditor | 日期、心情、评分、同伴/自定义、短评、重看 |
| 观影时间线 | 观影 → 观影 | querySessions / loadMoreWatchedHistory | 顺序、分页及影片详情跳转 |
| 观影统计 | 观影/统计 → 同入口 | queryViewingStats | 本月、累计、最高分、连续天数、类型分布 |
| 观影月历 | 观影内嵌日历 → 同入口，另加日历按钮 | HistoryMonthData / MovieProvider | 上下月、今天、滑动切月、海报与日期明细面板 |
| 手动合集 | 片库/我的合集 → 同入口 | CollectionProvider | 创建、改名、图标、删除 |
| 合集成员 | 合集详情/管理影片 → 同入口 | addMovieToCollection / removeMovieFromCollection | 搜索、勾选、完成、长按移出与确认 |
| 智能合集 | 我的合集/智能合集 → 同入口 | querySmartCollections | 类型/年代/导演/地区原自动归类 |
| 详情加入合集 | 详情/加入合集 → 同入口 | collectionIdsForMovie | 多选关联及完成反馈 |
| 全库/合集抽片 | 抽片/开始、合集/抽片 → 同入口 | DrawPage / DrawSelection | 原候选范围、全选/仅未看、分页和计数 |
| 四种模式 | 抽片模式选择 → 同入口 | DrawMode / DrawService | 纯随机、公平、优先未看、三选一 |
| 选择状态隔离 | 切换模式 → 同操作 | DrawSelectionState | 各模式独立勾选，不跨合集串候选 |
| 多维筛选 | 抽片/筛选 → 同入口 | DrawFilter / smartFilter | 时长、类型、年代、地区、评分、导演、标签、重置与应用 |
| 抽取动画和三选一 | 开始抽片 → 同入口 | DrawPage / DrawService | 结果仍由原算法产生；减少动态效果时省略洗牌动画 |
| 结果处理 | 抽片结果 → 同入口 | DrawOutcome / DrawHistoryProvider | pending/接受/跳过、重抽、详情、记录观影 |
| 抽片历史 | 抽片首页/历史 → 同入口 | DrawHistoryProvider | 原记录、时间、候选数量、分页与跳转 |
| 三种主题 | 设置/外观 → 同入口 | ThemeProvider | 系统/浅色/深色及持久化 |
| JSON 备份 | 设置/数据备份 → 同入口 | BackupService | 完整快照导出、分享/保存、选择文件与取消 |
| 合并恢复/旧版兼容 | 设置/从备份恢复 → 同入口 | BackupService / StorageService | schema 1–3、旧 watched 数据补会话、去重及统计 |
| WebDAV 配置 | 设置/坚果云同步 → 同入口 | WebDavSyncService / FlutterSecureStorage | 账号、应用密码、目录、保存及连接测试 |
| WebDAV 手动同步 | 上传/恢复/同步 → 同入口 | WebDavClient / SyncPlanner | SHA-256、临时文件/MOVE、进度、异常 |
| WebDAV 自动同步 | 启动与前台恢复 → 同生命周期 | AppLifecycleShell | 不阻塞启动、下载后刷新 Provider |
| 冲突与覆盖 | 原同步弹窗 → 对应新样式弹窗 | synchronize / replaceBackupData | 选择本地/云端、取消、覆盖确认与安全备份 |
| 更新检查 | 设置/检查更新 → 焕新版独立渠道 | UpdateService | 手动读取 update-ui.json，浏览器下载，不影响旧版 update.json |
| 开源信息与版本 | 设置/关于 → 同入口 | PackageInfo / LICENSE / NOTICE | 上游作者、协议、UI 来源、独立包名与版本 |

## 数据与接口兼容

保留 `lib/models`、`lib/providers`、`lib/services` 的原代码，以及数据库名称、版本 7、备份版本 3、键名和 JSON 字段。独立包名隔离本机数据。所有新视觉组件仍通过原回调调用原业务，不注入演示数据。

## 验证边界

源代码路径核对覆盖上述全部功能；已有抽片、已看和 WebDAV 测试用于验证对应规则，新增 UI 测试用于导航状态、布局、面板和交互。豆瓣线上抓取、真实坚果云账号、Android 文件选择/分享、安全存储及安装后的帧率需由用户真机验收。未使用模拟器，不声称已完成真机测试。

## 执行结果（2026-11-08）

- 上表各功能的新入口与业务调用已作源码核对；所有原路由和业务目录保留。
- `flutter analyze --no-pub`：零问题。
- `flutter test --no-pub`：56 项通过。包含 20 项原业务测试、2 项备份兼容回归、28 项 UI 检查、6 项视觉基线。
- 备份回归调用原 `BackupService.importBackup`：验证 RandoMov/schema 1 补会话与重复合并，以及 schema 3 多次观影、自由同伴文本、合集与标签载荷。文件选择/存储 I/O 在测试中隔离，因此不等同于 Android 数据库集成测试。
- 2 项 WebDAV 安全备份测试补充 `conflictChoice: remote`，使场景符合原代码“双方变更须显式选择”规则。原 Provider、模型、服务、抽片算法、已看判定和锁文件未改动。
- 实际组件检查覆盖浅深色、320×640 小屏、2 倍文字、导航快速切换/状态保留/详情返回、键盘避让和原观影字段保存。
- Release APK 编译通过；包名、版本、arm64 唯一架构、v2 签名与 16KB 对齐校验通过。完整构建和校验原文存放在交付目录。
