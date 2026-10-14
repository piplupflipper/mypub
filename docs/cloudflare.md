# Cloudflare 側の設定

Worker の作成、Workers Builds、カスタムドメイン、Access、応答ヘッダー、Free プランの上限を書く。
ダッシュボードの画面名は 2026-10-09 時点のもので、各節の出典のページに手順がある。
マシン側の準備は [setup.md](setup.md) にある。

このリポジトリは public なので、アカウント固有の値 (Worker の名前、カスタムドメイン、Access の設定値、障害の記録) は書かない。
それらは記事リポジトリの docs に置く。

## 設定の置き場

| 設定 | 場所 |
|---|---|
| Worker の名前 | 記事リポジトリの `cloudflare.config.ts` の `name` |
| カスタムドメイン | 記事リポジトリの `cloudflare.config.ts` の `domains` |
| 公開 URL | 記事リポジトリの `mypub.conf` の `BASE_URL` |
| workers.dev の URL | 記事リポジトリの `cloudflare.config.ts` の `workersDev` (`false` で 404 を返す) |
| Version URL (版ごとの確認用 URL) | 記事リポジトリの `cloudflare.config.ts` の `previewUrls` (`false`) |
| 配信するディレクトリ | 記事リポジトリの `wrangler.config.ts` の `assetsDirectory` (`dist`) |
| 応答ヘッダー | 本体の `assets/_headers` (build が `dist/_headers` にコピーする) |

カスタムドメインと `BASE_URL` は同じホスト名にする。
ダッシュボードで作る Worker の名前は `cloudflare.config.ts` の `name` と一致させる。
一致しないと、デプロイが「設定ファイルの name が Worker の名前と一致しない」というエラーで失敗する (2026-10-09 に確認)。

記事リポジトリの設定ファイルの例。

```ts
// cloudflare.config.ts
import { defineConfig } from "cf/config";
export default defineConfig({
  worker: {
    name: "<Worker の名前>",
    compatibilityDate: "2026-10-06",
    domains: ["<カスタムドメイン>"],
    workersDev: false,
    previewUrls: false,
  },
});
```

```ts
// wrangler.config.ts
import { defineWranglerConfig } from "wrangler/experimental-config";
export default defineWranglerConfig({
  assetsDirectory: "dist",
});
```

```json
{
  "name": "<記事リポジトリの名前>",
  "private": true,
  "type": "module",
  "devDependencies": {
    "cf": "1.0.0-beta.13",
    "wrangler": "^4.149.0"
  }
}
```

## 初期設定

Access を設定し終えるまで、本番 URL は誰でも読める。
ページを公開する前に、次の順で設定と確認を済ませる。

### 1. Git 連携で Worker を作る

出典: <https://developers.cloudflare.com/workers/ci-cd/builds/>

1. Cloudflare ダッシュボードの Workers & Pages で「Create application」を選び、「Import a repository」の「Get started」を選ぶ
2. GitHub アカウントを連携し、記事リポジトリを選ぶ
3. Worker 名を `cloudflare.config.ts` の `name` と同じにする
4. 対象ブランチを `main`、ビルドコマンドを `./build.sh`、デプロイコマンドを `npx cf deploy` にして「Save and Deploy」を選ぶ

Workers Builds は依存パッケージを自動で入れ、既定の node は 24 系である。
ビルドイメージには git と curl があり、jq は無い。`build.sh` が jq を取ってくるのはそのためである。
出典: <https://developers.cloudflare.com/workers/ci-cd/builds/build-image/>

Workers Builds は、記事リポジトリの clone と一緒に public の submodule (`core/`) も checkout する (2026-10-14 に使い捨てのリポジトリで確認)。
公式 docs に submodule の記述は無いので、`build.sh` でも `git submodule update --init` を実行して、どちらでも動くようにしている。
submodule の URL は https にする。ビルド環境に ssh 鍵は無い。

デプロイコマンドの既定は `npx wrangler deploy` で、変更できる。
wrangler だけでは `cloudflare.config.ts` と `wrangler.config.ts` を読まないので、必ず `npx cf deploy` にする。
出典: <https://developers.cloudflare.com/workers/ci-cd/builds/configuration/>

カスタムドメインは最初のデプロイで作られ、Cloudflare がそのゾーンに DNS レコードと証明書を作る。
前提は、ドメインのゾーンが同じ Cloudflare アカウントにあることと、そのホスト名に既存の DNS レコードが無いことである。
出典: <https://developers.cloudflare.com/workers/configuration/routing/custom-domains/>

カスタムドメインを設定すると、`workers_dev` を明示しない限り workers.dev の URL は無効になる。
`cloudflare.config.ts` では `workersDev: false` で明示する。

#### cf CLI で作る

ダッシュボードを使わずに、cf CLI だけでも作れる (cf 1.0.0-beta.13 で 2026-10-14 に確認)。
先に手元で 1 回デプロイして Worker を作り、その Worker に Git 連携のビルド設定を付ける。

```bash
cd <記事リポジトリ>
./build.sh && npx cf deploy                 # Worker ができる
npx cf workers list | jq -r '.[] | select(.name=="<Worker の名前>") | .id'   # script tag (Worker 名ではない)
npx cf builds tokens list                   # デプロイに使う build token の UUID。無ければ cf builds tokens create
gh api repos/<owner>/<記事リポジトリ> --jq '.id, .owner.id'   # GitHub の repo id と account id
npx cf builds workers create \
  --script-tag <script tag> \
  --git-repository-provider-type github \
  --git-repository-provider-account-id <GitHub の account id> \
  --git-repository-provider-account-name <owner> \
  --git-repository-repo-id <GitHub の repo id> \
  --git-repository-repo-name <記事リポジトリ> \
  --git-repository-branch main \
  --production-settings-build-command "./build.sh" \
  --production-settings-deploy-command "npx cf deploy" \
  --production-settings-root-directory "/" \
  --production-settings-build-caching-enabled=false \
  --production-settings-build-token-uuid <build token の UUID> \
  --previews-enabled=false \
  --previews-base-config-build-command "" \
  --previews-base-config-deploy-command "npx wrangler preview" \
  --previews-base-config-build-token-uuid <build token の UUID>
```

Cloudflare の GitHub App が記事リポジトリにアクセスできることが前提である。
できないと、ビルドが clone で失敗する。

### 2. Access を設定する

Worker 単位の Access は、その Worker の workers.dev、カスタムドメイン、プレビューのすべてを保護する。
出典: <https://developers.cloudflare.com/workers/configuration/cloudflare-access/>

1. Workers & Pages で Worker を選び、「Access」タブの「Protect this Worker behind Access」を選ぶ
2. 「All traffic」を選び、認証ポリシーを選んで「Apply Access」を選ぶ
3. Zero Trust の Access の Applications で作られたアプリケーションを開き、許可する対象を自分のメールアドレスだけにする

Access は Worker に付く。Git 連携のリポジトリを付け替えても、Access の設定は残る。

### 3. 未ログインで読めないことを確かめる

```bash
curl -sI https://<カスタムドメイン>/ | head -n 5
```

ステータスが `302` で、`location` が `cloudflareaccess.com` のログイン画面を指していれば保護されている。
`200` が返るなら、まだ誰でも読める状態である。

## Access のセッション

Access はログイン時に 2 つの token を発行する。
team domain 側の global token と、Worker のホスト側の application token である。
application token が切れても global token が有効なら、IdP でのログインなしに application token が再発行される。
出典: <https://developers.cloudflare.com/cloudflare-one/access-controls/access-settings/session-management/>

組織全体の Global session (既定 24 時間) を延ばすと、同じ組織のほかの Access application も実質同じ期間ログイン不要になる。
許可ポリシーのセッション時間も、ポリシーを共有するほかの application に効く。
そのため、mypub の application のセッション時間だけを延ばす。

### cf でセッション時間を変える

`cf zero-trust access applications update` は PUT で、送らなかった項目は消える。
現在の設定を取得し、読み取り専用の項目を除いてから、変える項目だけを書き換えて送る。

```bash
APP=<application の ID>   # npx cf zero-trust access applications list で調べる
npx cf zero-trust access applications get "$APP" >app.json
BODY="$(jq -c 'del(.id, .uid, .aud, .created_at, .updated_at) | .policies |= map({id, precedence}) | .session_duration = "168h"' app.json)"
npx cf zero-trust access applications update "$APP" --body "$BODY"
```

### GitHub を IdP にする

1. GitHub の Settings の Developer settings にある OAuth Apps で OAuth App を作る。Homepage URL は `https://<team>.cloudflareaccess.com`、Authorization callback URL は `https://<team>.cloudflareaccess.com/cdn-cgi/access/callback` にする
2. Zero Trust の Integrations の Identity providers で GitHub を追加し、Client ID と Client secret を貼る
3. Test で接続を確かめる

GitHub アカウントのメールアドレスが許可ポリシーのアドレスと一致しないと、ログインは拒否される。
出典: <https://developers.cloudflare.com/cloudflare-one/integrations/identity-providers/github/>

どの IdP で入ったかは、Access のログの `connection` に出る。

```bash
npx cf zero-trust access logs access-requests list | jq -c '.[:5][] | {created_at, allowed, app_domain, connection}'
```

## Workers Builds の運用

push ごとのビルドは Workers Builds が行う。
状態はダッシュボードの Worker の Deployments でも、cf でも見られる。

```bash
npx cf workers list                                   # Worker の ID (id) を調べる
npx cf builds list --external-script-id <Worker の ID>  # ビルドの一覧
npx cf builds logs get <build_uuid>                   # ビルドのログ
npx cf builds triggers list --external-script-id <Worker の ID>  # トリガーの一覧
npx cf builds create <trigger_uuid> --branch main     # main のビルドを手で起動する
npx cf builds workers get <Worker の ID>              # Git 連携のビルド設定 (リポジトリ、コマンド)
```

### ビルドが初期化で止まる

ログが次の 2 行だけで止まることがある。

```
Build initialization failed: unable to verify Worker
Build failed to initialize and was timed out
```

リポジトリを clone する前に止まっているので、設定ファイルの中身は関係ない。
`npx cf builds create <trigger_uuid> --branch main` で同じトリガーを再実行すると成功することがある (2026-10-09 に確認)。

### Git 連携をつなぎ直したら、デプロイコマンドを確かめる

ダッシュボードで Git 連携をつなぎ直すと、トリガーのデプロイコマンドが既定の `npx wrangler deploy` に戻ることがある (2026-10-13 に確認)。
wrangler だけでは `cloudflare.config.ts` と `wrangler.config.ts` を読まない。
手元の `npx wrangler deploy --dry-run` は、Worker 名を `package.json` の名前と検出し、`wrangler.jsonc` を作ろうとした。
このままだと、Worker 名が一致しないエラーで失敗するか、別の Worker ができる。
つなぎ直したら、デプロイコマンドを `npx cf deploy` に、ビルドコマンドを `./build.sh` に戻す。

```bash
npx cf builds triggers list --external-script-id <Worker の ID>   # build_command と deploy_command を確かめる
npx cf builds triggers update <trigger_uuid> --build-command "./build.sh" --deploy-command "npx cf deploy"
```

### Git 連携のリポジトリを付け替える

`cf builds workers update` ではリポジトリを変えられない (cf 1.0.0-beta.13 の時点で、変えられるのはブランチとコマンド)。
ビルド設定を消して作り直す。Worker と Access は残る。

```bash
npx cf builds workers delete <Worker の ID> --force   # ビルド設定とトリガーを消す。Worker は消えない
npx cf builds workers create ...                      # 「cf CLI で作る」と同じ
```

### main 以外のブランチのビルドが失敗する

Worker を Git 連携で作ると「Deploy non-production branches」というトリガーも作られ、main 以外のブランチを push するたびに `npx cf preview` を実行する。
cf にこの命令は無く、プレビューの命令は `cf previews deploy` なので、このビルドは失敗する (2026-10-09 に確認)。
本番には影響しない。
Version URL を使わない設定なので、このトリガーは `npx cf builds triggers delete <trigger_uuid>` で消してよい。
cf CLI で `--previews-enabled=false` を付けて作ると、このトリガーは作られない。

## 応答ヘッダー (_headers)

`assets/_headers` は static assets の `_headers` 機構で、パスの型ごとに応答ヘッダーを足す。
build が `dist/_headers` にコピーする。
Worker のコードが作る応答には効かないが、mypub は Worker のコードを持たないので、すべての応答が対象になる。
出典: <https://developers.cloudflare.com/workers/static-assets/headers/>

| パスの型 | ヘッダー | 理由 |
|---|---|---|
| `/*` | `X-Robots-Tag: noindex, nofollow` | 検索エンジンに載せない |
| `/:slug/v/:n/_page` | `Cache-Control: private, max-age=31536000, immutable` | 版番号を再利用しないので、版に固定した元の HTML は一度作ったら変わらない |

版に固定した外枠ページ (`/<slug>/v/<n>/`) と最新版の `/<slug>/_page` には長期キャッシュを付けない。
外枠ページは、見た目を変えたときにビルドが全版の分を作り直す。
`/<slug>/_page` は publish のたびに中身が変わる。
`private` にするのは、Access の内側のページを共有キャッシュに置かせないためである。
出典: <https://www.rfc-editor.org/rfc/rfc9111#section-5.2.2.7>

### 仕様の要点

次は 2026-10-14 に上の Headers のページ (dateModified 2026-09-22) で確かめた。

- `:name` の placeholder は区切り以外のすべての文字に一致し、パスの区切りは `/` だけである。したがって `:slug` と `:n` はパスの区切り 1 つずつに一致する。原文は "Placeholders match all characters apart from the delimiter, which when part of the host, is a period (`.`) or a forward-slash (`/`) and may only be a forward-slash (`/`) when part of the path."
- 複数のルールに一致したリクエストは、全ルールのヘッダーを受け取る。同じヘッダー名が 2 回付くと、値はカンマで結合される (上書きではない)。`/*` が付けるのは `X-Robots-Tag` だけなので、`Cache-Control` の値が結合されて壊れることは無い。
- `_headers` のヘッダーは Cloudflare が既定で送るヘッダーを上書きする。既定の `Cache-Control` は `public, max-age=0, must-revalidate` である。
- 同じページは「リダイレクトはヘッダーより先に適用され、両方に一致したらリダイレクトが優先される」と書いている。ただし、ここで言うリダイレクトは `_redirects` のもので、`html_handling` のリダイレクトには触れていない。
- ルールは 100 個まで、1 行は 2,000 文字までである。

`html_handling` は既定の `auto-trailing-slash` のままで、`/<slug>/v/<n>/_page.html` へのリクエストは `/<slug>/v/<n>/_page` へ 307 でリダイレクトされ、`/<slug>/v/<n>/_page` は `_page.html` を 200 で返す。
出典: <https://developers.cloudflare.com/workers/static-assets/routing/advanced/html-handling/>

ルールがリクエストの URL (`/_page`) に当たるのか、配信するファイルのパス (`/_page.html`) に当たるのかは、docs に書かれていない。

### 版に固定した _page にヘッダーが付くかを確かめる

手元では 2026-10-14 に wrangler 4.149.0 の `wrangler dev` で確かめ、次の結果だった。

| リクエスト | 応答 | Cache-Control |
|---|---|---|
| `/demo/v/1/_page` | 200 | `private, max-age=31536000, immutable` |
| `/demo/v/1/_page.html` | 307 (`Location: /demo/v/1/_page`) | 無し |
| `/demo/v/1/` | 200 | `public, max-age=0, must-revalidate` (既定) |

本番の配信で同じになるかは、デプロイ後に次の手順で確かめる。結果は記事リポジトリの docs に書く。

1. ブラウザで `https://<カスタムドメイン>/<slug>/v/<n>/` を開き、開発者ツールの Network タブを開いて再読み込みする
2. `_page` のリクエストを選び、Response Headers に `cache-control: private, max-age=31536000, immutable` と `x-robots-tag: noindex, nofollow` があることを確かめる
3. `<slug>/v/<n>/` のリクエストの `cache-control` が既定の `public, max-age=0, must-revalidate` のままであることを確かめる
4. アドレスバーで `https://<カスタムドメイン>/<slug>/v/<n>/_page.html` を開き、307 の後の `_page` の応答に手順 2 と同じヘッダーがあることを確かめる

## Free プランの上限

| 項目 | 上限 | 出典 |
|---|---|---|
| 1 つの Worker のファイル数 | 20,000 | <https://developers.cloudflare.com/workers/platform/limits/> |
| 1 ファイルのサイズ | 25 MiB | 同上 |
| Workers Builds のビルド時間 | 月 3,000 分、同時 1 本、1 回 20 分まで | <https://developers.cloudflare.com/workers/ci-cd/builds/limits-and-pricing/> |

静的ファイルへのリクエストは無料で、回数の上限も無い。
出典: <https://developers.cloudflare.com/workers/static-assets/billing-and-limitations/>
