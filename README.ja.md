<p align="center">
  <img src="./assets/readme/hero.svg" width="100%" alt="Reverie：余っている小さなサブディスプレイが、音楽パネルと AI 使用量ダッシュボードになる">
</p>

<p align="center"><a href="./README.md">English</a> · <a href="./README.zh-CN.md">中文</a> · <b>日本語</b></p>

# Reverie

小さなサブディスプレイを「再生中」パネルと AI 使用量ダッシュボードに変える、macOS のメニューバー常駐アプリです。

<p align="center"><img src="docs/screenshots/music.png" width="49%" alt="音楽ページ：ジャケット、曲名、再生位置と操作ボタン"> <img src="docs/screenshots/quota.png" width="49%" alt="クォータページ：Claude と Codex の利用上限リングとプラン表示"></p>
<p align="center"><img src="docs/screenshots/lyrics.png" width="49%" alt="歌詞モード：ジャケットの横に 5 行の同期歌詞"> <img src="docs/screenshots/cost.png" width="49%" alt="コストページ：モデル別の API 換算額と日別の棒グラフ"></p>

**3 つのページ**を、右上にマウスを寄せて出るボタン、二本指の横スワイプ、⌃⌥⌘R、またはメニューバーのアイコンで切り替えます。

- **音楽** — ジャケット、曲名、歌詞（NetEase Cloud Music / Apple Music）、再生位置、前へ / 再生 / 次へ / お気に入り。背景はジャケットをぼかして広げたもので、曲ごとにページの色が変わります。
- **クォータ** — Claude Code と Codex の利用上限（5 時間、週、Fable などモデル別）、契約プラン、周期の進み具合、「消費が速い」バッジ。この Mac の `claude` と `codex` CLI に直接問い合わせ、外部サービスは使いません。
- **コスト** — ローカルの Claude Code / Codex の使用量を **API 料金に換算**したらいくらか。モデル別、直近 7 日または今月、日別の棒グラフ付き。（定額プランの利用者が実際に払うのは月額なので、これは参考値であって請求額ではありません。）

5 インチ 1280×720 のパネル向けに設計。1280×720 のキャンバスをどんなサイズの画面にも等倍率で拡大縮小します（縦横比が違えば余白を付けます）。文字は最小 24 px、タップ領域は最小 72 px なので、机の向こうからでも読めます。

## インストール

必要なもの：macOS 14 以降、Xcode Command Line Tools、`cmake`。クォータ / コストページには、ログイン済みの [Claude Code](https://claude.com/claude-code) と / または [Codex CLI](https://github.com/openai/codex) が必要です。

```bash
git clone https://github.com/Rurutia-Artemis/Reverie.git
cd Reverie
bash scripts/setup.sh        # mediaremote-adapter を取得してビルド（コミット固定）
bash scripts/make-cert.sh    # 初回のみ：自己署名のコード署名証明書「Reverie Local」を作る
bash app/build.sh            # app/Reverie.app ができる
bash scripts/deploy.sh app/Reverie.app --enable-autostart   # /Applications に入れてログイン時に起動
```

証明書が要る理由：macOS はアクセシビリティやオートメーションの許可を署名 ID に紐づけます。署名 ID が安定していれば再ビルドしても許可が残りますが、証明書がないと `build.sh` はアドホック署名に落ち、ビルドのたびに許可をやり直すことになります。

初回起動時に、メイン以外で一番小さいディスプレイを選んで記憶します。変更は 設定 → 副屏 から。

## 求められる許可

- **アクセシビリティ** — サブディスプレイに来た他のウィンドウをメイン側へ戻す、NetEase のメニューから「お気に入り」を切り替える。
- **オートメーション → ミュージック** — Apple Music の「お気に入り」を読む / 切り替える。
- **ログイン項目** — 自動起動を有効にした場合のみ。

## プライバシー

すべてローカルで動きます。

- 再生中の情報は macOS の MediaRemote から、[mediaremote-adapter](https://github.com/ungive/mediaremote-adapter) 経由で取得します。
- 歌詞と高解像度ジャケットは「曲名 + アーティスト」で NetEase の公開 API から取得します。ネットワークに出るのはこれだけです。
- クォータは `claude -p`（制御リクエスト `get_usage`。プロンプトは送らず、クォータも消費しません）と `codex app-server`（`account/rateLimits/read`）を起動して読みます。Reverie はトークンを読みも保存もしません。Claude のプラン倍率（「20x」など）は Claude Code 自身が保存している資格情報項目を `/usr/bin/security` で読み、プラン欄だけを保持します。
- コストは `~/.claude/projects/**/*.jsonl` と `~/.codex/sessions/**/*.jsonl` から計算し、料金は [models.dev](https://models.dev) を使います。差分キャッシュは `~/Library/Application Support/Reverie/` にあります。

## 開発

```bash
bash app/test.sh                                              # 純ロジックの単体テスト
REVERIE_FIXTURE=quota-design REVERIE_SNAPSHOT=/tmp/x.png app/Reverie.app/Contents/MacOS/Reverie   # 固定データで描画（バイト単位で再現可能）
REVERIE_SNAPSHOT=/tmp/x.png REVERIE_PAGE=cost REVERIE_SNAPSHOT_SIZE=1920x1080 app/Reverie.app/Contents/MacOS/Reverie   # 実データを任意サイズで描画
swift scripts/check-window.swift                              # いまサブディスプレイにあるウィンドウ
```

アーキテクチャと決まりごとは `CLAUDE.md`（中国語）に詳しくあります。デザイントークンは `app/Sources/UI/Theme.swift`。アプリ内の文言は中国語です。

## クレジット

- [mediaremote-adapter](https://github.com/ungive/mediaremote-adapter) — macOS 15.4 以降での再生中情報の取得
- [CodexBar](https://github.com/steipete/CodexBar) — CLI の問い合わせ方法と料金表の参考
- フォント：阿里妈妈方圆体（Alimama FangYuanTi VF）© Taobao (China) Software Co., Ltd.、無償商用ライセンスに基づき同梱

ライセンス：MIT。
