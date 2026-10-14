---
name: mypub-publish
description: 生成済みの HTML を自分専用の公開先 mypub（Cloudflare Workers の static assets と Cloudflare Access。URL は記事リポジトリの mypub.conf にある BASE_URL の下の `/<slug>/`）へ公開・更新・削除する手順。`mypub publish` コマンドで記事リポジトリ piplupflipper/mypub-content に commit して push し、Workers Builds（Cloudflare の Git 連携）が本体 piplupflipper/mypub の `mypub build` で配信ディレクトリを組み立ててデプロイする。閲覧できるのは Access で許可した本人だけで、社外のネットワークからも読める。「自分用に公開して」「mypub に出して」と頼まれたときに使う。社内に共有する HTML は htmlpub-publish、Claude のアカウント内で見る HTML は Artifact を使う。
---

# mypub への公開と更新

生成済みの HTML を、本人だけが読める公開先 mypub へ載せる工程を扱う。
HTML の中身の作り方は扱わない。

## 構成

mypub は 2 つのリポジトリでできている。

| リポジトリ | 中身 | 公開範囲 |
|---|---|---|
| piplupflipper/mypub（本体） | `mypub` コマンド、外枠ページの CSS と JS、一覧ページ、この skill | public |
| piplupflipper/mypub-content（記事リポジトリ） | 公開した HTML (`pages/<slug>/`)、slug ごとのメタデータ `pages.json`、公開 URL (`mypub.conf`)、Cloudflare の設定 | private |

記事リポジトリは本体を `core/` に git submodule として持つ。
`mypub` コマンドは記事リポジトリの `core/bin/mypub` で、`~/.local/bin/mypub` はそこへの symlink である。
コマンドは記事リポジトリだけを commit、push する。
push すると Workers Builds が記事リポジトリをビルドし（`build.sh` が `core/bin/mypub build` を呼ぶ）、配信ディレクトリを組み立ててデプロイする。

## 公開先の使い分け

| 公開先 | 読める人 | skill |
|---|---|---|
| mypub | Cloudflare Access で許可した本人 | 本 skill |
| htmlpub | 社内ネットワークの利用者 | `htmlpub-publish` |
| Claude Artifact | 公開した Claude アカウント | Artifact ツール |

ユーザーが公開先を指定しないときは、どこへ出すかを確認する。
業務のコードや調査結果を含む HTML を mypub に置いてよいかは、ユーザーが決める。
配信先は個人の Cloudflare アカウントなので、内容が業務のものと分かるときは公開前に確認する。

## 公開する

```bash
mypub publish <file.html> [slug] [--genre <名前>] [--desc <一行説明>] [--note <理由>]   # 単一ファイル。pages/<slug>/_page.html になる
mypub publish <dir> [slug] [--genre <名前>] [--desc <一行説明>] [--note <理由>]         # index.html を含むディレクトリ。中身ごと pages/<slug>/ になり、index.html は _page.html になる
```

- 標準出力の最後の行が公開 URL。これをユーザーに伝える
- slug は英小文字、数字、ハイフン。省略するとファイル名（`index.html` なら親ディレクトリ名）から作る
- 既存の slug を指定すると、`/<slug>/` で配信する最新版を丸ごと置き換え、前の中身は過去版として残る。更新もこのコマンドで行う（詳しくは「版」の節）
- 新規か更新かを取り違えないよう、先に `mypub ls` で既存の slug を確かめる
- `--genre` は一覧ページで絞り込みに使うジャンル、`--desc` はカードに出す一行説明。update で省くと前の値を引き継ぐ。既存のジャンルは `mypub ls` の 4 列目で確かめ、なるべく揃える
- 公開した HTML は記事リポジトリの `pages/<slug>/_page.html` に置かれる。配信では `/<slug>/` がヘッダー付きの外枠ページ（元の HTML を iframe で読み込む）、`/<slug>/_page` が元の HTML になる。ディレクトリごと公開するときは `_page.html` という名前のファイルと `v` という名前のディレクトリを置けない
- `--note` は版に残す変更理由。版の一覧に出る。更新の理由が分かるときは付ける
- コマンドは記事リポジトリを pull し、HTML をコピーし、`pages.json` を更新し、commit して push する。外枠ページや一覧は作らない（Workers Builds のビルドで作る）。どの作業ディレクトリからでも実行できる
- 記事リポジトリに未 commit の変更があると失敗する。その場合は勝手に破棄せず、ユーザーに伝える
- 「記事リポジトリが記録している本体の commit と core/ の checkout が違います」と出て止まったら、記事リポジトリで `git submodule update --init` を実行してからやり直す。本体の版が記事リポジトリ側で上がったのに、手元の `core/` が古いときに起きる
- 記事リポジトリの `mypub.conf` に `BASE_URL` が無いか雛形のままだと失敗する。Cloudflare 側の初期設定が済んでいないので、ユーザーに伝える

HTML は自己完結（CSS と JS をインライン）にしておくと、単一ファイルで公開できる。
画像などの別ファイルが要るなら、ディレクトリにまとめて相対パスで参照する。
1 ファイルの上限は 25 MiB である。

## 版

同じ slug に publish するたびに、中身が変わっていれば版が 1 つ積まれる。
版は記事リポジトリの `pages/<slug>/v/<n>/` に置かれ、`pages/<slug>/_page.html` は最新版の写しになる。

- 中身が最新版と同じなら版は増えない。標準エラーに「中身が最新版 (v<n>) と同じなので、版を作りません」と出る。`--genre` や `--desc` で値が変わったときだけ commit する
- 版番号は再利用しない。一度使った番号は別の中身を指さない
- 過去版をブラウザで見るには `/<slug>/v/<n>/` を開く（その版に固定した外枠ページ）。版の一覧は `/<slug>/v/` にある
- 版が 2 つ以上ある slug は、外枠ページのヘッダーの版番号が版のセレクタになり、選んだ版の外枠ページへ移れる。末尾の「版の一覧…」で `/<slug>/v/` を開く。選択肢は配信の `/<slug>/v/index.json`（`mypub build` が `pages.json` から作る）から読む
- 版は消せない。slug ごと消すときだけ `mypub rm` を使う

```bash
mypub versions <slug>                       # 版の一覧。新しい版が上で、1 行に「v<n> (最新なら印) / 日時 / title / note / ロールバック元」のタブ区切り
mypub rollback <slug> <n> [--note <理由>]   # v<n> と同じ中身の版を v<最大+1> として積み、最新にして commit、push する
```

- 巻き戻しは `mypub rollback` で行う。過去版を `mypub get --version` で取り出して publish し直しても同じ中身になるが、版の一覧にロールバック元が残らない
- rollback は `latest` を戻さず、新しい版を積む。新しい版の note は `--note` の値で、省くと `rollback to v<n>` になる。版の一覧の「ロールバック元」に v<n> が出る
- `<n>` が最新版のとき、存在しない版のとき、中身が最新版と同じときは何もせず失敗する
- commit メッセージは `rollback: <slug> v<n> -> v<新しい番号>` になる
- 巻き戻しも公開内容を変える操作なので、ユーザーが頼んだときだけ行う。どの版に戻すかは `mypub versions` の出力をユーザーに見せて確かめる

## 一覧と削除

```bash
mypub ls                                          # 更新日 / slug / URL / ジャンル / title のタブ区切り
mypub meta <slug>                                 # ジャンル、一行説明、作成日、更新日、版の記録を JSON で出す
mypub meta <slug> [--genre <名前>] [--desc <説明>]  # ジャンルや一行説明だけを変えて commit、push する
mypub rm <slug>                                   # 全版を含めて削除し、commit、push する
```

削除は URL が読めなくなる操作なので、ユーザーが明示的に頼んだときだけ行う。

## 公開済みの HTML を取得する

公開済みのページは Access の認証の後ろにあるため、`curl` や WebFetch では読み戻せない。
最新版の実体は記事リポジトリの `pages/<slug>/_page.html`、過去版は `pages/<slug>/v/<n>/_page.html` にあり、次のコマンドで取り出す。
どれも外枠ページではなく、公開した元の HTML を返す。
`--version <n>` を付けると v<n> を、省くと最新版を取り出す。

```bash
mypub get <slug> [--version <n>]          # 最新を pull し、元の HTML の絶対パスを出す
mypub get <slug> <dest> [--version <n>]   # 最新を pull し、版の置き場を除いた中身を <dest>/ にコピーする。_page.html は index.html に戻す
mypub cat <slug> [--version <n>]          # 最新を pull し、元の HTML を標準出力に出す
```

- 「前に公開したページを直して」と頼まれたら、`mypub get <slug>` で場所を得て Read で読み、直した HTML を `mypub publish <file> <slug>` で同じ slug に出す
- 画像などを含むページは `mypub get <slug> <dest>` でディレクトリごと取り出し、直してから `mypub publish <dest> <slug>` で出す
- 過去の版を元に直すときは `mypub versions <slug>` で版番号を確かめ、`--version <n>` で取り出す。直さずにそのまま戻すだけなら `mypub rollback` を使う
- slug が分からないときは `mypub ls` で title から探す
- 記事リポジトリに未 commit の変更があると pull せず、手元の内容を返す。その旨が標準エラーに出るので、報告に含める

## 反映の確認

push の後、Workers Builds がビルドとデプロイを行うので、URL に反映されるまで 1 分ほどかかる。
ページは Access の認証の後ろにあるため、`curl` や WebFetch では中身を読み戻せない。
確認できるのは次の 2 点までで、報告では「ブラウザでの表示は確認していない」と明示する。

- `mypub publish` が URL を返して正常終了した（push まで通った）
- `mypub ls` に slug が載っている

急ぐときや Workers Builds のビルドが失敗したときは、`mypub deploy` で手元の `mypub build` と cf CLI から直接デプロイできる。
このコマンドには記事リポジトリでの `npm ci` と、Cloudflare の認証（`npx cf auth login`、または環境変数 `CLOUDFLARE_API_TOKEN` と `CLOUDFLARE_ACCOUNT_ID`）が要る。
通常の公開では使わない。

## チェックリスト

- [ ] 公開先が mypub でよいことを確かめた
- [ ] 既存ページの修正なら、`mypub get` で取り出した最新の HTML を元にした
- [ ] `mypub ls` で slug の重複を確かめた
- [ ] 既存 slug の更新なら、変更理由を `--note` に書いた
- [ ] `mypub publish` が返した URL をユーザーに伝えた
- [ ] 表示確認をしていないことを報告に書いた
