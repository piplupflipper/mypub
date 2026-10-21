# content.mk: 記事リポジトリの日々の操作 (準備、build、手元の配信、本体の版上げ、ビルドの状態) をまとめた make の入口。
# 本体 (core/) にあり、記事リポジトリの Makefile が次のように include して使う。
#
#   -include core/mk/content.mk
#   core/mk/content.mk:
#   	@echo "core/ が空です。git submodule update --init を実行してください" >&2; exit 1
#
# include の前の - と、続く core/mk/content.mk の規則は、submodule を取る前の clone で
# 「ファイルが無い」という make の素のエラーの代わりに、次にやることを出すためのもの。
# make は記事リポジトリの root ($(CURDIR)) で実行される前提で、相対パスはすべてそこから引く。

SHELL := bash
# recipe の途中で失敗したら止める。core の手順は 1 つでも失敗したら commit や push に進んではいけない。
.SHELLFLAGS := -euo pipefail -c
# recipe の全行を 1 つの shell で実行する。core の手順は変数と分岐を行をまたいで使う。
.ONESHELL:
.DEFAULT_GOAL := help

# 本体の submodule の場所と mypub コマンド。
CORE ?= core
MYPUB ?= $(CORE)/bin/mypub
# serve の待ち受けポート。8787 は wrangler の既定。
SERVE_PORT ?= 8787
# status で出すビルドの件数。
STATUS_COUNT ?= 10

# mise があれば mise の node と npm を使う。mise install の直後は PATH に shim が無いことがあるので、mise exec で通す。
# npx の --no-install は、npm ci していないときに最新版を勝手に取ってこないため (bin/mypub の cmd_deploy と同じ)。
RUN ?= $(if $(shell command -v mise),mise exec --,)
NPX ?= $(RUN) npx --no-install

# Worker の ID (script tag。Worker の名前ではない) は記事リポジトリの mypub.conf の WORKER_ID から読む。
# mypub.conf は bin/mypub が source する bash の KEY="value" 形式なので、ここでも bash で source して取り出す。
# = で遅延評価にして、status 以外の target では mypub.conf を読まない。
WORKER_ID ?= $(shell [ -f mypub.conf ] && bash -c 'source ./mypub.conf && printf %s "$${WORKER_ID:-}"')

.PHONY: help setup build serve deploy core status _preflight

help: ## この一覧を出す
	@awk -F ':.*## ' '/^[a-zA-Z_-]+:.*## / { printf "  %-8s %s\n", $$1, $$2 }' $(MAKEFILE_LIST)

# 記事リポジトリの root で実行されていることを確かめる。別の場所で打つと、build.sh や mypub.conf を取り違える。
_preflight:
	@for f in $(MYPUB) mypub.conf build.sh; do
	  [ -e "$$f" ] || { echo "$(CURDIR) に $$f がありません。記事リポジトリの root で make を実行してください" >&2; exit 1; }
	done

setup: _preflight ## 新しいマシンの準備 (submodule、mise、npm ci、mypub install)
	git submodule update --init
	if command -v mise >/dev/null 2>&1; then mise trust && mise install; fi
	$(RUN) npm ci
	$(MYPUB) install

build: _preflight ## dist/ を組み立てる (Workers Builds と同じ ./build.sh)
	./build.sh

# 配信は static assets の html_handling で、/<slug>/_page を _page.html で、/<slug>/ を index.html で返す。
# python3 -m http.server は拡張子なしの _page を 404 にするので使えない。
# cf dev は cloudflare.config.ts と wrangler.config.ts を読んで wrangler の dev サーバーを立て、
# html_handling と _headers を本番と同じ規則で再現する。npx wrangler dev だけでは wrangler.config.ts を読まず、
# 「Missing entry-point to Worker script or to assets directory」で止まる。
serve: _preflight ## dist/ を手元で配信する (cf dev。先に make build)
	@[ -f dist/index.html ] || { echo "dist/ がありません。先に make build を実行してください" >&2; exit 1; }
	$(NPX) cf dev --port $(SERVE_PORT)

deploy: _preflight ## build して cf で直接デプロイする (Workers Builds を待たないとき)
	$(MYPUB) deploy

# 本体を origin の main に上げて commit、push する。
# recipe の中で core/ を書き換えても、実行中のこのファイルは壊れない。make は makefile を最初に読み切ってから
# recipe を実行するからである。bin/mypub が自分で submodule update しないのは、bash が実行中のスクリプトを
# 少しずつ読むので、書き換えると途中から別の中身を実行しかねないためで、ここでは事情が違う。
core: _preflight ## 本体を origin/main に上げて commit、push する
	@die() { echo "make core: $$*" >&2; exit 1; }
	# 未 commit の変更があると pull --rebase できず、版上げの commit に関係ない変更が混ざる。
	[ -z "$$(git status --porcelain)" ] || die "記事リポジトリに未 commit の変更があります: $(CURDIR)"
	upstream=
	if git rev-parse --abbrev-ref '@{u}' >/dev/null 2>&1; then
	  upstream=1
	  git pull --rebase --quiet || die "git pull --rebase に失敗しました"
	  # push していない commit があると、版上げの push に知らない commit が相乗りする (bin/mypub の cmd_deploy と同じ検査)。
	  [ -z "$$(git log '@{u}..' --oneline)" ] || die "push していない commit があります。先に push してください"
	fi
	# 旧 hash は記事リポジトリが記録している gitlink から取る。pull で gitlink が進んでも core/ の checkout は古いままなので、checkout からは取らない。
	old="$$(git rev-parse HEAD:$(CORE))"
	git submodule update --init --remote -- $(CORE)
	new="$$(git -C $(CORE) rev-parse HEAD)"
	if [ "$$old" = "$$new" ]; then
	  echo "既に最新です ($$(git -C $(CORE) rev-parse --short "$$new"))"
	  exit 0
	fi
	git add -- $(CORE)
	{
	  printf 'core: %s..%s\n\n' "$$(git -C $(CORE) rev-parse --short "$$old")" "$$(git -C $(CORE) rev-parse --short "$$new")"
	  git -C $(CORE) log --oneline "$$old..$$new"
	} | git commit --quiet -F -
	git log -1 --format='%h %s'
	if [ -n "$$upstream" ]; then
	  git push --quiet || die "git push に失敗しました (commit は手元に残っています)"
	else
	  echo "upstream が無いので push を省略しました"
	fi

# cf builds list は JSON の配列を新しい順で返す。build_outcome は終わったビルドだけに入るので、無ければ status を出す。
status: _preflight ## Workers Builds の直近のビルドを出す (mypub.conf の WORKER_ID)
	@[ -n "$(WORKER_ID)" ] || { echo "mypub.conf に WORKER_ID を書いてください (npx cf workers list の id。Worker の名前ではない)" >&2; exit 1; }
	$(NPX) cf builds list --external-script-id $(WORKER_ID) --per-page $(STATUS_COUNT) | jq -r '
	  ["作成日時", "状態", "ブランチ", "commit", "build", "メッセージ"],
	  (.[] | [
	    (.created_on | sub("\\.[0-9]+Z$$"; "Z") | fromdate | localtime | strftime("%Y-%m-%d %H:%M")),
	    (.build_outcome // .status),
	    (.build_trigger_metadata.branch // "-"),
	    ((.build_trigger_metadata.commit_hash // "-")[:7]),
	    .build_uuid,
	    ((.build_trigger_metadata.commit_message // "") | split("\n")[0])
	  ]) | @tsv' | column -t -s $$'\t'
