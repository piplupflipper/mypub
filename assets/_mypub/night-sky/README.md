# night-sky

一覧ページ (`site/index.html`) の背景に敷く夜空。
WebGL で雲を描き、WebGL が使えない間は CSS の雲を出す。

## コピー元

```text
Source: piplupflipper/components/src/backgrounds/night-sky
Copied from commit: 1ebae4a0d711046131f8d0822bcc704e613c2f38
Copied on: 2026-10-14
```

- `night-sky.css` はコピー元の `night-sky.css` をそのまま置いたもの
- `night-sky.js` はコピー元の `vanilla.ts` と `renderer.ts` を 1 本の ES module にまとめたもの。コピー元のリポジトリで次を実行して作った

```sh
npx rolldown src/backgrounds/night-sky/vanilla.ts --format esm --file night-sky.js
```

mypub には JS のビルド工程を置かない (配信ディレクトリの組み立てだけを bin/mypub build が行う)。
コピー元が変わったときは、同じ手順で作り直して差し替える。

## 使い方

```html
<link rel="stylesheet" href="/_mypub/night-sky/night-sky.css">
<script type="module">
  import { mountNightSkyBackground } from "/_mypub/night-sky/night-sky.js";
  mountNightSkyBackground(document.body);
</script>
```

背景は `z-index: 0` の fixed 要素なので、前景には `position: relative; z-index: 1` を付ける。
配色と速度の変え方はコピー元の README にある。
