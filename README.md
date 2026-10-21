# mypub 💅✨

自分だけが読める HTML の置き場〜🔒 の本体だよ。
HTML を `mypub publish` すると記事リポジトリに commit されて、Cloudflare Workers が配信してくれる☁️
見られるのは Cloudflare Access でログインした本人だけ💖

## 2 つのリポジトリ 📦📦

| リポジトリ | 中身 | 公開範囲 |
|---|---|---|
| 本体 (このリポジトリ) | `mypub` コマンド、外枠ページの CSS と JS、一覧ページ、エージェント用 skill、docs | public |
| 記事リポジトリ | 公開した HTML (`pages/<slug>/`)、slug ごとのメタデータ `pages.json`、公開 URL、Cloudflare の設定、`build.sh` | private |

記事リポジトリは本体を `core/` に git submodule として持つよ🔗
`mypub` コマンドは `core/bin/mypub` で、記事リポジトリの場所は submodule の親として自動で分かる。
記事リポジトリに push すると、Workers Builds (Cloudflare の Git 連携) が `build.sh` → `core/bin/mypub build` で配信ディレクトリを組み立ててデプロイするよ🚀
外枠ページや一覧の JSON は git に入れない。ビルドのたびに作る🔁

各ページは上に細いヘッダーが付いた外枠ページになってて、元の HTML はその中の iframe で表示されるよ🪟
版が 2 つ以上あると、ヘッダーの `v3` みたいな版番号がセレクタになって、そこから版を選んで切り替えられるよ🕰️ 末尾の「版の一覧…」で `/<slug>/v/` に飛べる
`/<slug>/v/<n>/` はその版に固定した URL で、上に「最新版を開く」のバナーが出る📌
`mypub deprecate` したページはヘッダーが赤くなって「非推奨」のピルが付くし、一覧から消えて墓場 (`/?view=graveyard`) に引っ越すよ🪦

## 使い方 🚀

```bash
mypub publish report.html            # slug はファイル名から📝
mypub publish report.html my-report  # slug を指定。同じ slug なら上書きして版を 1 つ積む🔁
mypub publish report.html my-report --note "例を追加"  # 版に変更理由を残す🗒️
mypub publish ./dist my-app          # index.html 入りのディレクトリごと📁
mypub publish report.html --genre howto --desc "一行説明"  # ジャンルと説明を付ける🏷️
mypub meta my-report --genre explainer  # ジャンルや説明だけ変える✏️
mypub ls                             # 公開してるページ一覧👀 非推奨のは出ない
mypub ls --deprecated                # 非推奨のページだけ一覧に🪦
mypub versions my-report             # 版の一覧。新しい版が上🕰️
mypub rollback my-report 1           # v1 と同じ中身の版を新しく積んで最新に⏪
mypub rollback my-report 1 --note "v2 の図が崩れた"  # 巻き戻しの理由を残す🗒️
mypub deprecate my-report            # 非推奨にする🪦 一覧から墓場へ
mypub undeprecate my-report          # 非推奨をやめて一覧に戻す🌱
mypub rm my-report                   # 削除🗑️ 版も全部消える
mypub get my-report                  # 公開済み HTML の場所を出す📂
mypub get my-report ./work           # 公開済みのディレクトリごとコピー📥
mypub get my-report ./work --version 2  # v2 を取り出す📥
mypub cat my-report                  # 公開済み HTML を標準出力に📄
mypub cat my-report --version 2      # v2 を標準出力に📄
mypub build                          # 配信ディレクトリを記事リポジトリの dist/ に組み立てる🔧 (Workers Builds がやるのと同じ)
mypub deploy                         # build して cf で直接デプロイ。急ぎのときだけ⚡
```

`publish`、`meta`、`deprecate`、`undeprecate`、`rollback`、`rm` は記事リポジトリを pull → 変更 → commit → push まで全部やってくれる✨
`--genre` と `--desc` は update のときに省くと前の値をそのまま使うよ👌
push したら Workers Builds が勝手にビルドしてデプロイするから、待ってればOK☁️

### 版 🕰️

- 同じ slug に publish すると、中身が変わったときだけ版が 1 つ積まれる。最新版と同じ中身なら版は増えない👌
- 版番号は使い回さない。`rollback` も過去の版を戻すんじゃなくて、同じ中身の版を `v<最大+1>` として積む⏪
- `/<slug>/` は最新版、`/<slug>/v/<n>/` は v<n> に固定した URL、`/<slug>/v/` は版の一覧📌
- ヘッダーの版のセレクタで選ぶと、その版の外枠ページへ移る🔀 選択肢は `/<slug>/v/index.json` から読むので、版の外枠ページは作った後に変わらない
- 版は消せないよ🙅 slug ごと消すなら `mypub rm`

### 非推奨と墓場 🪦

- 古くなったけど消したくないページは `mypub deprecate` で非推奨にできる。URL はそのまま読めるよ👌
- 記録は `pages.json` の slug に `"deprecated": true` を 1 行足すだけ。時刻とか理由とか後継は持たない✂️ `undeprecate` するとキーごと消える
- 一覧ページには出なくなって、見出しの右の「🪦 墓場 (n)」から行ける墓場 (`/?view=graveyard`) に並ぶ。検索とかジャンルの絞り込みは一覧と同じ🔎
- 外枠ページはヘッダーが赤くなって「非推奨」のピルと墓場へのリンクが付く🚨 版に固定した `/<slug>/v/<n>/` も、`v/index.json` を見て同じ見た目になる (外枠の HTML 自体は変わらない)
- 更新日は変わらないし、`publish`、`rollback`、`rm` は非推奨かどうかを気にしない。非推奨のまま publish すると非推奨のまま版が積まれるよ

## 中身 📦

本体 (このリポジトリ)。

```
bin/mypub                コマンド本体
assets/_mypub/           外枠ページの CSS と JS。build が配信ディレクトリの /_mypub/ にコピーする
assets/_mypub/open-night.css  共通のダークテーマのトークン。piplupflipper/components からコピー
assets/_mypub/night-sky/ 一覧ページの夜空背景。piplupflipper/components からコピー (中の README にコピー元の commit)
assets/index.html        一覧ページ。index.json を読んで組み立てる。?view=graveyard だと非推奨だけの墓場
assets/_headers          全ページ noindex 🙈 と、版に固定した _page の長期キャッシュ
skills/mypub-publish/    エージェント用 skill 🤖
docs/                    マシンの準備と Cloudflare 側の設定
```

記事リポジトリ。

```
core/                    本体 (このリポジトリ) の submodule
pages/<slug>/_page.html  公開した元の HTML。画像とかは同じディレクトリに
pages/<slug>/v/<n>/      版ごとの元の HTML と付属ファイル。pages/<slug>/_page.html は最新版の写し
pages.json               slug ごとのジャンル、説明、作成日、更新日、非推奨の印 (deprecated。非推奨のときだけ置く) と、版の記録 (latest、seq、versions[])
mypub.conf               公開 URL (BASE_URL)
build.sh                 Workers Builds のビルドコマンド。jq を用意して core/bin/mypub build dist を呼ぶ
cloudflare.config.ts     Worker の名前、カスタムドメイン、配信の設定
wrangler.config.ts       static assets のディレクトリ (dist)
package.json             cf と wrangler の版
mise.toml                node の版
dist/                    build の出力。git には入れない
```

`mypub build` が `dist/` に作るもの。

```
dist/<slug>/index.html   ヘッダー付きの外枠ページ。非推奨ならヘッダーが赤くて「非推奨」の印と墓場へのリンク付き
dist/<slug>/_page.html   元の HTML (pages/<slug>/ の写し)
dist/<slug>/v/<n>/       版の元の HTML と、その版に固定した外枠ページ
dist/<slug>/v/index.html 版の一覧ページ。ヘッダーは最新版の外枠と同じく非推奨を出す
dist/<slug>/v/index.json 版の一覧の JSON。ヘッダーの版のセレクタが読む。非推奨なら deprecated: true も入って、版に固定した外枠がそれを見てヘッダーを赤くする
dist/index.html          一覧ページ (assets/index.html の写し)
dist/index.json          一覧のデータ。非推奨のページだけ deprecated: true が付く
dist/_mypub/             外枠ページの CSS と JS (assets/_mypub/ の写し)
dist/_headers            応答ヘッダー (assets/_headers の写し)
```

## 記事リポジトリを新しく作る 🧱

private のリポジトリを作って、次を置く。

```bash
git submodule add https://github.com/piplupflipper/mypub.git core   # https にする。Workers Builds のビルド環境に ssh 鍵は無い
echo '{}' > pages.json
echo 'BASE_URL="https://<カスタムドメイン>"' > mypub.conf           # 末尾の / は付けない
```

`build.sh` はこれ。Workers Builds のビルドイメージには jq が無いので、無ければ取る。

```bash
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
git submodule update --init
if ! command -v jq >/dev/null 2>&1; then
  JQ_VERSION=1.7.1
  JQ_SHA256=5942c9b0934e510ee61eb3e30273f1b3fe2590df93933a93d7c58b81d19c8ff5
  mkdir -p .tools
  curl -fsSL -o .tools/jq "https://github.com/jqlang/jq/releases/download/jq-$JQ_VERSION/jq-linux-amd64"
  echo "$JQ_SHA256  .tools/jq" | sha256sum -c - >/dev/null
  chmod +x .tools/jq
  export PATH="$PWD/.tools:$PATH"
fi
core/bin/mypub build dist
```

`cloudflare.config.ts`、`wrangler.config.ts` (`assetsDirectory: "dist"`)、`package.json` (cf と wrangler)、`.gitignore` (`dist/`、`.tools/`、`node_modules/`、`.cloudflare/`、`.wrangler/`) は [docs/cloudflare.md](docs/cloudflare.md) を見て置く。
Workers Builds の設定は、ビルドコマンド `./build.sh`、デプロイコマンド `npx cf deploy`。

## 本体の版を上げる ⬆️

記事リポジトリが記録している本体の commit を進めて commit する。本体を直しても、記事リポジトリ側で上げるまで配信は変わらない。

```bash
cd <記事リポジトリ>
git submodule update --remote core && git add core && git commit -m "core: <本体の commit>"
git push
```

手元の `core/` が記事リポジトリの記録と違うと、`mypub` コマンドは止まる。`git submodule update --init` で揃える。

## もっと詳しく 📚

- 🛠️ [docs/setup.md](docs/setup.md): 新しいマシンでの準備、本体の開発、cf と wrangler の関係、認証
- ☁️ [docs/cloudflare.md](docs/cloudflare.md): Cloudflare 側の設定 (Worker、Workers Builds、カスタムドメイン、Access)、トラブったとき、Free プランの上限
