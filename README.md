# Reverie

A macOS menu-bar app that turns a small secondary display into a now-playing panel and an AI-usage dashboard.

<p align="center"><img src="docs/screenshots/music.png" width="640"><img src="docs/screenshots/quota.png" width="640"></p>
<p align="center"><img src="docs/screenshots/lyrics.png" width="640"><img src="docs/screenshots/cost.png" width="640"></p>

**Three pages**, switched by hovering the top-right corner, a two-finger horizontal swipe, ⌃⌥⌘R, or the menu-bar icon:

- **Music** — cover art, title, lyrics (NetEase Cloud Music / Apple Music), progress, prev / play / next / like. The background is the cover art blurred and stretched, so every song recolors the page.
- **Quota** — Claude Code and Codex rate limits (5-hour, weekly, per-model such as Fable), subscription tier, cycle progress and a "burning fast" badge. Read directly from the `claude` and `codex` CLIs on this Mac; no third-party service.
- **Cost** — what your local Claude Code and Codex usage *would* cost at API prices, per model, last 7 days or this month, with a daily bar chart. (Subscribers pay a flat fee; this is a reference number, not a bill.)

Designed on a 5-inch 1280×720 panel; the 1280×720 canvas scales to any display size (letterboxed when the aspect ratio differs). Text is never smaller than 24 px and every hit target is at least 72 px, so it works from across the desk.

## Install

Requirements: macOS 14+, Xcode Command Line Tools, `cmake`, and — for the quota/cost pages — [Claude Code](https://claude.com/claude-code) and/or [Codex CLI](https://github.com/openai/codex) logged in.

```bash
git clone https://github.com/Rurutia-Artemis/Reverie.git
cd Reverie
bash scripts/setup.sh        # fetches and builds mediaremote-adapter (pinned commit)
bash scripts/make-cert.sh    # one-time: a self-signed "Reverie Local" code-signing certificate
bash app/build.sh            # app/Reverie.app
bash scripts/deploy.sh app/Reverie.app --enable-autostart   # installs to /Applications and starts at login
```

Why the certificate: macOS ties Accessibility / Automation grants to the signing identity. A stable self-signed identity keeps those grants across rebuilds; without it `build.sh` falls back to ad-hoc signing and you re-grant after every build.

First launch picks the smallest non-primary display and remembers it. Change it in Settings → 副屏.

## Permissions it asks for

- **Accessibility** — to move stray windows off the secondary display and to toggle NetEase "like" via its menu.
- **Automation → Music** — to read / toggle "favorited" in Apple Music.
- **Login item** — if you enable autostart.

## Privacy

Everything runs locally.

- Now-playing data comes from macOS MediaRemote via [mediaremote-adapter](https://github.com/ungive/mediaremote-adapter).
- Lyrics and hi-res covers are fetched from NetEase's public API by title + artist. That is the only network call.
- Quota is read by spawning `claude -p` (control request `get_usage`, no prompt is sent, no quota is used) and `codex app-server` (`account/rateLimits/read`). Reverie never reads or stores tokens. The Claude subscription multiplier (e.g. "20x") is read with `/usr/bin/security` from the credential item Claude Code itself stores; only the tier field is kept.
- Cost is computed from `~/.claude/projects/**/*.jsonl` and `~/.codex/sessions/**/*.jsonl` with prices from [models.dev](https://models.dev); an incremental cache lives in `~/Library/Application Support/Reverie/`.

## Development

```bash
bash app/test.sh                                              # pure-logic unit tests
REVERIE_FIXTURE=quota-design REVERIE_SNAPSHOT=/tmp/x.png app/Reverie.app/Contents/MacOS/Reverie   # deterministic render
REVERIE_SNAPSHOT=/tmp/x.png REVERIE_PAGE=cost REVERIE_SNAPSHOT_SIZE=1920x1080 app/Reverie.app/Contents/MacOS/Reverie   # live render at any size
swift scripts/check-window.swift                              # what is on the target display right now
```

`CLAUDE.md` describes the architecture and conventions in detail (in Chinese). Design tokens live in `app/Sources/UI/Theme.swift`.

## Credits

- [mediaremote-adapter](https://github.com/ungive/mediaremote-adapter) — now-playing on macOS 15.4+
- [CodexBar](https://github.com/steipete/CodexBar) — reference for the CLI probes and pricing table
- Font: 阿里妈妈方圆体 (Alimama FangYuanTi VF) © Taobao (China) Software Co., Ltd., bundled under its free commercial license

License: MIT.

---

## 中文说明

一个 macOS 菜单栏小程序，把一块小副屏变成正在播放面板和 AI 用量面板。三页：**音乐**（网易云 / Apple Music 的封面、歌名、歌词、进度、上一首 / 播放 / 下一首 / 红心，背景随封面变色）、**额度**（Claude Code 与 Codex 的 5 小时、每周、按模型额度，订阅档位，周期进度，「用得偏快」提醒；直接问本机命令行，不经过第三方）、**消费**（本机记录按 API 价格折算成美元，按模型拆开，7 天或本月；订阅用户实际付的是月费，这只是参考数）。

翻页：鼠标移到副屏右上角点「音乐 / 额度 / 消费」，或两指横滑，或 ⌃⌥⌘R，或菜单栏图标。右上角还有设置和退出。界面按 1280×720 排版，其它分辨率等比缩放。

**安装**：见上面的命令。`scripts/setup.sh` 拉取并编译适配器，`scripts/make-cert.sh` 建一个自签证书让签名身份稳定（否则每次重编都要重新给辅助功能授权），`app/build.sh` 编译，`scripts/deploy.sh` 装到「应用程序」并可开机自启。第一次运行会记住最小的那块非主屏，设置里可以改。

**需要的授权**：辅助功能（挪窗口、网易云红心）、自动化 → 音乐（Apple Music 红心）、登录项（开机自启）。

**隐私**：全部本机运行。歌词和高清封面按歌名 + 歌手向网易云公开接口取，这是唯一的联网。额度靠起 `claude -p`（控制请求 `get_usage`，不提问不耗额度）和 `codex app-server` 读，不读也不存令牌；Claude 的订阅倍数（20x）用系统 `security` 命令读 Claude Code 自己存的凭证项，只取档位字段。消费统计读 `~/.claude/projects` 与 `~/.codex/sessions` 下的记录，价格来自 models.dev，增量缓存在 `~/Library/Application Support/Reverie/`。

更多开发说明见 `CLAUDE.md`。许可证 MIT；方圆体按阿里妈妈免费商用许可内嵌，版权归淘宝（中国）软件有限公司。
