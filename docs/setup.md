# マシンごとの準備

新しいマシンで `mypub` コマンドを使えるようにする手順、本体を開発する手順、デプロイに使う cf CLI の位置づけを書く。
Cloudflare 側の設定は [cloudflare.md](cloudflare.md) にある。

## 準備

`mypub` コマンドは git と jq を使う。jq は OS のパッケージで入れておく (例: `sudo apt install jq`)。

本体はこのリポジトリだが、コマンドは記事リポジトリの submodule (`core/`) として置いたものを使う。
記事リポジトリを `--recurse-submodules` で clone し、`make setup` を実行する。

```bash
ghq get --recurse-submodules git@github.com:<owner>/<記事リポジトリ>.git
cd ~/ghq/github.com/<owner>/<記事リポジトリ>
make setup
```

`make setup` は記事リポジトリの `Makefile` が include する本体の `mk/content.mk` にあり、次を順に実行する。

1. `git submodule update --init`: `--recurse-submodules` を付けずに clone していても `core/` を取る。ただし `core/` が空だと `Makefile` が `mk/content.mk` を読めないので、そのときは先に手で `git submodule update --init` を実行する
2. `mise trust && mise install` (mise があるとき): 信頼しないと、このディレクトリで mise の shim (gh, node など) がエラーになる。`mise install` で node が入る
3. `npm ci`: cf と wrangler が入る。`make serve`、`make status`、`mypub deploy` に使う
4. `core/bin/mypub install`

`install` は次の symlink を張る。

- `~/.local/bin/mypub` から `core/bin/mypub` へ
- `~/.claude/skills/mypub-publish` から `core/skills/mypub-publish` へ

`mypub` は自分が置かれた submodule の親を記事リポジトリとして使う (`git rev-parse --show-superproject-working-tree`)。
submodule として置かずに使うときは、環境変数 `MYPUB_CONTENT_DIR` に記事リポジトリの場所を入れる。

## 本体の版を上げる

記事リポジトリは本体の commit を gitlink で固定している。
本体の main を進めても、記事リポジトリで上げるまで配信もコマンドも変わらない。
上げるときは記事リポジトリで `make core` を実行する。

```bash
cd <記事リポジトリ>
make core
```

`make core` は次の順に進む。

1. 記事リポジトリに未 commit の変更が無いことを確かめる
2. upstream があれば `git pull --rebase` し、push していない commit が無いことを確かめる (`mypub deploy` と同じ検査)
3. `git submodule update --remote core` で `core/` を本体の `origin/main` に上げる。記事リポジトリが記録している commit と同じなら「既に最新です」と出して終わる
4. `git add core` して commit する。メッセージの 1 行目は `core: <旧 commit>..<新 commit>` で、本文は `git -C core log --oneline <旧>..<新>` の出力である
5. upstream があれば push する

`make core` の実行中に `core/mk/content.mk` 自体が書き換わっても問題は無い。
make は makefile を最初に読み切ってから recipe を実行するからである。

別のマシンで記事リポジトリを pull すると gitlink は進むが、`core/` の作業ツリーは古い commit のまま残る。
その状態で `mypub` を実行すると「記事リポジトリが記録している本体の commit と core/ の checkout が違います」と出て止まる。
`git submodule update --init` で揃えてからやり直す。
`mypub` が自分で `git submodule update` しないのは、実行中の `core/bin/mypub` を書き換えることになるからである。

## 本体を開発する

本体は別に clone して直し、記事リポジトリの `core/` では直さない (`core/` は detached HEAD で、push 先の設定も無い)。

```bash
ghq get git@github.com:piplupflipper/mypub.git
```

直した本体を手元の記事で試すときは、記事リポジトリの `core/` に開発中の commit を取り込み、`mypub build` の出力を見る。
記事リポジトリは commit しない (`git add core` しなければ gitlink は変わらない)。

```bash
cd <記事リポジトリ>
git -C core fetch <本体の作業ツリーの path> <ブランチ>
git -C core checkout FETCH_HEAD
./build.sh                          # dist/ ができる
git -C core checkout "$(git rev-parse HEAD:core)"   # 試し終わったら記録の commit に戻す
```

本体を public にしているので、アカウント固有の値 (Worker の名前、カスタムドメイン、Access の設定値) はこのリポジトリに書かず、記事リポジトリの docs に置く。

## 認証

`mypub publish`、`mypub ls`、`mypub rm`、`mypub versions`、`mypub rollback` など、`deploy` 以外のコマンドは git だけで動くので、Cloudflare の認証は要らない。

`mypub deploy` は cf で Cloudflare に直接デプロイするので、使うマシンで認証を済ませる。

```bash
npx cf auth login               # ブラウザのないマシンでは --no-browser を付ける
```

環境変数 `CLOUDFLARE_API_TOKEN` と `CLOUDFLARE_ACCOUNT_ID` でも認証できる。
cf は wrangler のログイン情報を引き継がないので、`wrangler login` 済みでも cf 側で認証し直す。
出典: <https://developers.cloudflare.com/cf/ci/>, <https://developers.cloudflare.com/cf/wrangler/>

## cf と wrangler

デプロイのコマンドは wrangler の後継である cf CLI を使う。
cf はオープンベータで、コマンドと設定ファイルの形は安定版までに変わりうる。
出典: <https://developers.cloudflare.com/cf/>

静的ファイルだけのプロジェクトでは、cf は build と deploy を wrangler に委譲する。
そのため記事リポジトリの `package.json` には cf と wrangler の両方を入れる。
出典: <https://developers.cloudflare.com/cf/projects/>

設定ファイルは 2 つに分かれていて、どちらも記事リポジトリにある。

| ファイル | 持つもの |
|---|---|
| `cloudflare.config.ts` | Worker の名前、カスタムドメイン、workers.dev と Version URL の無効化 |
| `wrangler.config.ts` | static assets のディレクトリ (`dist`) |

`cf build` はビルド結果を `.cloudflare/output/` に書く。
`cf deploy --prebuilt --dry-run` を実行すると、認証なしでデプロイ内容の検証だけができる。
出典: <https://developers.cloudflare.com/cf/projects/>
