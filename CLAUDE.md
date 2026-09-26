# CLAUDE.md — Reverie（副屏音乐 + 额度面板）

给 Claude Code 的项目说明。这是一个 **macOS 原生菜单栏 App**，独占一块 5 寸副屏（**Wokyis，1280×720，1x**），三页：音乐（网易云 / Apple Music 正在播放）、额度（Claude / Codex，数据直接问本机命令行）、消费（本机 Claude Code / Codex 记录按 API 价格折算成美元）。2026-09-25 按圆桌方案整体重做，方案与账本在 `docs/roundtable/2026-09-25-reverie-redesign/`，视觉定稿在 `design/directions/`（v2）。

## 架构

```
播放 → macOS「正在播放」(MediaRemote) → mediaremote-adapter（/usr/bin/perl 绕过 15.4+ 限制）
     → stream / get 的 JSON → PlaybackReducer（按「来源 + 歌曲」认身份，允许名单过滤）→ NowPlayingStore
claude -p 控制请求 get_usage / codex app-server account/rateLimits/read → UsageProbe → QuotaParse → QuotaStore（每 N 分钟，默认 5）
副屏：SubscreenPanel（非激活 NSPanel、屏蔽级）+ WindowStateMachine（接管 / 让出 / 副屏缺失）+ WindowEvictor（把落到副屏的别的窗口挪回主屏）
```

## 目录

- `app/Sources/` 按职责分目录：App（入口、AppDelegate、单实例 / 快捷键 / 自启）、Screen（面板、状态机、驱逐器与几何）、Music（归并器、数据、网易云接口、红心）、Quota（命令行取数、解析、定时刷新、登录入口）、Cost（价格表、记录解析、增量扫描与缓存）、UI（字号颜色常量、字体方案、组件、两页、根视图）、Settings（设置存储、主屏设置窗口）、Fixtures（确定性快照）。
- 第一行写 `// reverie:logic` 的是纯逻辑文件，只依赖 Foundation / CoreGraphics，`app/test.sh` 只编它们和 `app/Tests/`。
- `app/Resources/Fonts/` — 阿里妈妈方圆体可变字体（原样内嵌，许可允许，版权归阿里妈妈，设置页已注明）。
- `scripts/` — `deploy.sh` / `rollback.sh`（按原状态恢复，`--plan-only` 可看步骤）、`test-deploy-plan.sh`（25 例）、`check-window.swift`（窗口位置与健康检查）、`test-windows/`（造浮动窗、拒绝移动的窗）。
- `mediaremote-adapter/` — 第三方适配器（独立仓库，上游 commit 3ac3d4b，主仓库 .gitignore 掉），clang 编到 `build/MediaRemoteAdapter.framework`。

## 构建、测试、部署

```bash
bash app/test.sh                                  # 纯逻辑单元测试（6 组）
bash app/build.sh                                 # 编译 + 打包适配器与字体 + 只认 Reverie Local 签名，失败即非零退出
bash scripts/deploy.sh app/Reverie.app            # 部署到 /Applications，保持原来的加载 / 自启 / 运行状态
bash scripts/deploy.sh app/Reverie.app --enable-autostart   # 首次部署并打开开机自启
bash scripts/rollback.sh <备份的 Reverie.app>          # 退回某个备份（改版前的旧版在备份目录里）
```

> **签名**：必须是稳定证书 **`Reverie Local`**（`~/.config/reverie-codesign/`），否则「辅助功能」授权会失效。build.sh 不再回退 ad-hoc。
> **macOS 27 注意**：`launchctl print-disabled` 输出是 `enabled` / `disabled`，不是 true / false。

## 验证界面

```bash
REVERIE_FIXTURE=quota-design REVERIE_SNAPSHOT=/tmp/x.png app/Reverie.app/Contents/MacOS/Reverie   # 固定数据、固定时钟，逐字节可复现
REVERIE_SNAPSHOT=/tmp/x.png REVERIE_PAGE=quota app/Reverie.app/Contents/MacOS/Reverie            # 实时数据快照（不拿锁、不起 stream、不上屏）
swift scripts/check-window.swift                                                                  # 副屏上现在有哪些窗口
```

- fixture 场景：music-playing / paused / idle / lyrics / other，quota-design / 1 / 4 / 6 / 0 / missing / stale / unavailable。出图存 `docs/roundtable/.../rounds/fixtures/`。
- `REVERIE_FONT=alimama`（可配 `REVERIE_FONT_WEIGHT` `REVERIE_FONT_BEVEL`）用方圆体渲染 fixture。
- `ScrollView` 在离屏 `ImageRenderer` 里不渲染，歌词用固定行高 + 偏移；离屏渲染大半径 blur 会出块，背景用渐变光晕。
- 实机副屏可以 `screencapture -x -D 2 x.png` 截。

## 界面（2026-09-25 定稿，v2）

- 三页共用顶栏：左边时间日期（额度页是「额度 · 更新于 · 提醒」，消费页是「消费 · 7 天/本月 切换」），右边「音乐 / 额度 / 消费 · 设置 · 退出」平时隐藏、鼠标移到右上角出现。翻页：点切换钮、副屏上两指横滑（三页循环）、⌃⌥⌘R、菜单栏。
- 音乐页：528 封面 + 封面色氛围光；来源、歌名、歌手 · 专辑、当前一句与下一句歌词（点它进歌词模式）、渐变进度条、胶囊控制条、红心。状态：播放中、暂停（封面压暗）、未播放（大时钟）、其它应用在播放（控制不可点）。
- 歌词模式：封面 360、五行歌词、底部一条控制。
- 额度页：按来源分块，同心圆环 + 图例（彩色大数字 = 剩余或已用），白点 = 按时间应剩的位置，偏快标黄；来源名旁边是订阅档位小牌（Max / Pro）；只有一项时只画一个大圆环、数字在中间；卡片下面一条周期进度（本周已过 N%、还剩多久）。最多 6 项、每个来源最多 4 项；过期整块降饱和；已过重置时间写「已过重置时间」。
- 消费页：和额度页同版式。数据来自 `~/.claude/projects/**/*.jsonl`（assistant 消息的 message.usage，按 message.id + requestId 去重，`<synthetic>` 跳过）与 `~/.codex/sessions/**/*.jsonl`（turn_context 定模型，token_count 的 last_token_usage 每条算一次请求，input 含 cached）。价格表在 `Cost/CostModel.swift`（models.dev，2026-09-26），改了要同步 `Pricing.version` 让缓存重建。缓存 `~/Library/Application Support/Reverie/cost-cache.json` 按文件记解析位置，只看 35 天内改过的文件；出图用 `REVERIE_FIXTURE=cost-design` 或 `REVERIE_PAGE=cost`（第一次会等扫描，最多 3 分钟）。
- 字号只从 `UI/Theme.swift` 的 `T.Size` 取，最小 24px，大数字 64px（宽额度卡片 76px，单项圆环中间 100px），热区 ≥ 72px。
- 颜色只从 `T.palette`（`Palette`）取：夜读（默认）/ 石墨 / 夜蓝 / 暖炭 / 浅色 / 跟随系统；界面里不直接写白色黑色，用 `T.ink()` / `T.shadow()`。fixture 用 `REVERIE_THEME=light` 等出图。
- 字体两套：系统圆体（SF Pro Rounded + 圆体），阿里妈妈方圆体（设置里调粗细、圆角）；日文假名单独用日文字体。
- 设置在主屏（菜单栏图标 → 设置…，或副屏右上角齿轮）：Claude Code / Codex 登录状态与「重新登录」（在终端打开 `claude auth login` / `codex login`）、刷新间隔、背景配色、字体、主文字颜色、歌词翻译、没在放歌时切到额度页、播放来源允许名单、额度显示项与顺序、目标副屏、「接管副屏」开关、开机自启。

## 副屏锁定的规则

- 目标屏按记住的显示器 UUID → 名字 Wokyis 找，找不到就隐藏，绝不退到主屏（旧版会盖住主屏）。
- 非激活面板：点副屏不抢主屏焦点；副屏上没有 ⌘Q，退出走菜单栏。
- 驱逐器：层级 0–24、非系统进程、与副屏相交超 8px 的窗口挪回主屏；挪不动（无授权、匹配失败、拉扯）就让出（Reverie 整个隐藏），菜单栏提示；日志 `~/Library/Logs/Reverie/evictor.log`。
- 单实例：`~/Library/Application Support/Reverie/instance.lock` 上 flock；只有持锁的实例清理残留 stream。SIGTERM 走正常退出。

## 收藏（红心）

1. **网易云读状态**：读网易云本地 SQLite 明文缓存 `~/Library/Containers/com.netease.163music/Data/Documents/storage/sqlite_storage.sqlite3`：`historyPlaylists` 里 `jsonStr LIKE '%喜欢的音乐"%'` 找歌单 id，`playlistTrackIds` 的 `trackIds[].id` 是收藏集合（`NeteaseService.likedSongIDs()`，每 30 秒刷新）；当前曲目的网易云 id 来自 cloudsearch 匹配。
2. **网易云写**：osascript 点「控制」菜单，菜单项名随状态变（「喜欢歌曲」/「取消喜欢」，都是 ⌘L），脚本两者都判断（`Controls.likeScript`）。需要「辅助功能」授权。
3. **Apple Music**：`AppleMusicLike` 用 NSAppleScript 读写 `favorited of current track`，先判断 Music 在运行才发事件；首次会弹「控制音乐」的自动化授权。
4. 其它来源不支持红心，按钮变灰。

## 其它踩坑

- 后台窗口第一次点击会被吞：`FirstMouseHostingView` 重写 `acceptsFirstMouse`。
- 额度：Reverie 只起命令行子进程、不读令牌；子进程用干净环境（桌面端会话的 ANTHROPIC_* 变量会让 get_usage 拿不到额度）。命令行没登录时 get_usage 仍回 success，只是 `rate_limits_available` 为 false。
- 显示器休眠时 loginwindow 会升起锁屏遮罩（即使「需要密码」设为永不），这时窗口检查失败、部署会回滚；部署用 `caffeinate -d -i bash scripts/deploy.sh …`。
- 开机自启要系统设置 → 通用 → 登录项与扩展里 Reverie 的「允许在后台」打开。
- 适配器 stream：`diff:false` 是完整状态（空字典 = 没在播），`diff:true` 要合并、`null` 值表示删键。`send`：2 播放暂停，4 下一首，5 上一首。
- macOS 27.0 / Mac mini M4 / Swift 6.4。

## 用户偏好（重要）

- 用中文交流。
- 不要自由拖拽编辑布局了（嫌麻烦），版式由我们排好；字体/颜色可调即可。
- 很在意美观和细节，改完最好用 `REVERIE_SNAPSHOT` 渲染出来自查再交付。

<!-- ruruos-project-memory:start -->
