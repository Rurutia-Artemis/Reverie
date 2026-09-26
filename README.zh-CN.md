<p align="center">
  <img src="./assets/readme/hero.svg" width="100%" alt="Reverie：一块闲置的小副屏，变成音乐面板和 AI 用量面板">
</p>

<p align="center"><a href="./README.md">English</a> · <b>中文</b> · <a href="./README.ja.md">日本語</a></p>

# Reverie

一个 macOS 菜单栏小程序，把一块小副屏变成「正在播放」面板和 AI 用量面板。

<p align="center"><img src="docs/screenshots/music.png" width="49%" alt="音乐页：封面、歌名、进度和播放控制"> <img src="docs/screenshots/quota.png" width="49%" alt="额度页：Claude 与 Codex 的额度圆环和订阅档位"></p>
<p align="center"><img src="docs/screenshots/lyrics.png" width="49%" alt="歌词模式：封面旁边五行同步歌词"> <img src="docs/screenshots/cost.png" width="49%" alt="消费页：各模型按 API 价格折算的花费和按天柱状图"></p>

**三页**，鼠标移到副屏右上角点按钮、两指横滑、⌃⌥⌘R 或菜单栏图标都能切：

- **音乐** — 封面、歌名、歌词（网易云音乐 / Apple Music）、进度，上一首 / 播放 / 下一首 / 红心。背景是封面模糊后铺开的，每首歌都换一种颜色。
- **额度** — Claude Code 和 Codex 的额度（5 小时、每周、按模型如 Fable）、订阅档位、周期进度和「用得偏快」提醒。直接问本机的 `claude` 和 `codex` 命令行，不经过第三方服务。
- **消费** — 本机 Claude Code 和 Codex 的用量**按 API 价格折算**要花多少钱，按模型拆开，近 7 天或本月，每天一根柱。（订阅用户付的是固定月费，这只是参考数，不是账单。）

按 5 寸 1280×720 的屏设计，1280×720 的画布会等比缩放到任何尺寸的屏（比例不同就留边）。文字最小 24 px、热区最小 72 px，隔着桌子也看得清。

## 安装

需要：macOS 14+、Xcode Command Line Tools、`cmake`；额度和消费页还需要已登录的 [Claude Code](https://claude.com/claude-code) 和 / 或 [Codex CLI](https://github.com/openai/codex)。

```bash
git clone https://github.com/Rurutia-Artemis/Reverie.git
cd Reverie
bash scripts/setup.sh        # 拉取并编译 mediaremote-adapter（固定到指定提交）
bash scripts/make-cert.sh    # 只做一次：自签一个「Reverie Local」代码签名证书
bash app/build.sh            # 产出 app/Reverie.app
bash scripts/deploy.sh app/Reverie.app --enable-autostart   # 装到「应用程序」并开机自启
```

为什么要证书：macOS 把「辅助功能」「自动化」授权绑在签名身份上。签名身份稳定，重编也不用重新授权；没有证书时 `build.sh` 会退回临时签名，每次编完都得重新点授权。

第一次运行会自动选最小的那块非主屏并记住，可以在 设置 → 副屏 里改。

## 会请求的授权

- **辅助功能** — 把落到副屏的其它窗口挪回主屏；通过网易云菜单点红心。
- **自动化 → 音乐** — 读取 / 切换 Apple Music 的「喜欢」。
- **登录项** — 开了开机自启才会有。

## 隐私

全部在本机运行。

- 正在播放的信息来自 macOS MediaRemote，经 [mediaremote-adapter](https://github.com/ungive/mediaremote-adapter) 读取。
- 歌词和高清封面按「歌名 + 歌手」向网易云公开接口取，这是唯一的联网。
- 额度靠起 `claude -p`（控制请求 `get_usage`，不发提问、不耗额度）和 `codex app-server`（`account/rateLimits/read`）读取。Reverie 不读也不存令牌。Claude 的订阅倍数（例如「20x」）用 `/usr/bin/security` 读 Claude Code 自己存的凭证项，只保留档位字段。
- 消费由 `~/.claude/projects/**/*.jsonl` 和 `~/.codex/sessions/**/*.jsonl` 算出，价格来自 [models.dev](https://models.dev)；增量缓存在 `~/Library/Application Support/Reverie/`。

## 开发

```bash
bash app/test.sh                                              # 纯逻辑单元测试
REVERIE_FIXTURE=quota-design REVERIE_SNAPSHOT=/tmp/x.png app/Reverie.app/Contents/MacOS/Reverie   # 固定数据出图，逐字节可复现
REVERIE_SNAPSHOT=/tmp/x.png REVERIE_PAGE=cost REVERIE_SNAPSHOT_SIZE=1920x1080 app/Reverie.app/Contents/MacOS/Reverie   # 实时数据按任意分辨率出图
swift scripts/check-window.swift                              # 副屏上现在有哪些窗口
```

架构和约定的细节见 `CLAUDE.md`；字号颜色常量在 `app/Sources/UI/Theme.swift`。

## 致谢

- [mediaremote-adapter](https://github.com/ungive/mediaremote-adapter) — macOS 15.4+ 上读「正在播放」
- [CodexBar](https://github.com/steipete/CodexBar) — 命令行探测方式和价格表的参考
- 字体：阿里妈妈方圆体（Alimama FangYuanTi VF），版权归淘宝（中国）软件有限公司，按其免费商用许可内嵌

许可证：MIT。
