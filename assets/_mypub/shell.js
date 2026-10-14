// 外枠ページ (site/<slug>/index.html と、版に固定した site/<slug>/v/<n>/index.html) の振る舞い。
// 元の HTML を iframe に読み込み、URL の #アンカーと title を外枠と揃える。
// 外枠と元の HTML は同じオリジンなので、iframe の中の location と document に直接触れる。
(() => {
  const frame = document.querySelector("iframe.page");
  // 自分の範囲は外枠ページ自身のディレクトリ。最新版なら /<slug>/、版に固定したページなら /<slug>/v/<n>/ になる。
  // URL の最初の区切りで決めると、版の中から最新版へのリンクを踏んだとき、外枠は版のまま iframe だけが移ってしまう。
  const myDir = location.pathname.slice(0, location.pathname.lastIndexOf("/") + 1);
  // /<slug>/v/ の下は版の置き場なので、最新版の外枠から見ても範囲の外として外枠ごと移る。
  // 公開するディレクトリの直下に v/ は置けない (bin/mypub が拒否する) ので、元の HTML のファイルとは重ならない。
  const inScope = (pathname) => pathname.startsWith(myDir) && !pathname.startsWith(`${myDir}v/`);

  // 元の HTML の URL (/<slug>/_page、/<slug>/v/<n>/_page) を、外枠ページの URL (/<slug>/、/<slug>/v/<n>/) に読み替える。
  const toShellUrl = (url) => {
    const m = url.pathname.match(/^(\/[a-z0-9][a-z0-9-]*\/(?:v\/[0-9]+\/)?)_page(?:\.html)?$/);
    return m ? `${m[1]}${url.search}${url.hash}` : url.href;
  };

  const syncHash = () => {
    const hash = frame.contentWindow.location.hash;
    history.replaceState(null, "", hash || location.pathname + location.search);
  };

  // 外部のサイトはページごと開き、別の mypub のページは外枠ごと移る。
  // 同じページの中 (ディレクトリごと公開したアプリの別ファイルを含む) は iframe の中で移る。
  const onClick = (event) => {
    if (event.defaultPrevented || event.button !== 0) return;
    if (event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return;
    const a = event.target.closest && event.target.closest("a[href]");
    if (!a || (a.target && a.target !== "_self")) return;
    const url = new URL(a.href, frame.contentWindow.location.href);
    if (url.origin !== location.origin) {
      a.target = "_top";
    } else if (!inScope(url.pathname)) {
      event.preventDefault();
      location.href = toShellUrl(url);
    }
  };

  frame.addEventListener("load", () => {
    let win;
    try {
      win = frame.contentWindow;
      void win.location.pathname;
    } catch {
      return; // 別オリジンへ移った。手が出せないのでそのままにする
    }
    // クリック以外 (スクリプトなど) で別のページへ移ったときも外枠ごと移る。
    if (!inScope(win.location.pathname)) {
      location.replace(toShellUrl(new URL(win.location.href)));
      return;
    }
    if (win.document.title) document.title = win.document.title;
    syncHash();
    win.addEventListener("hashchange", syncHash);
    win.document.addEventListener("click", onClick);
    win.focus();
  });

  // 外枠の URL の #アンカーを書き換えられたら、iframe の中もそこへ移る。
  window.addEventListener("hashchange", () => {
    frame.contentWindow.location.hash = location.hash;
  });

  frame.src = frame.dataset.src + location.hash;

  // ヘッダーの版番号 (.ver) を、版を選んで外枠ごと移るセレクタに置き換える。
  // 版の一覧は外枠ページに埋め込まず、/<slug>/v/index.json から読む。埋め込むと publish のたびに全版の外枠ページが書き換わる。
  // 読めなかったときと JS が無いときは、版の一覧ページへの静的なリンクがそのまま残る。
  const verLink = document.querySelector(".bar .ver");
  if (!verLink) return; // 版が 1 つの slug の最新版の外枠には版番号が無い
  const slug = location.pathname.split("/")[1];
  const pinned = location.pathname.match(/^\/[^/]+\/v\/([0-9]+)\//);
  const shellUrl = (value, latest) => {
    if (value === "list") return `/${slug}/v/`;
    return Number(value) === latest ? `/${slug}/` : `/${slug}/v/${value}/`;
  };

  fetch(`/${slug}/v/index.json`, { cache: "no-cache" })
    .then((res) => (res.ok ? res.json() : Promise.reject(new Error(res.statusText))))
    .then(({ latest, versions }) => {
      if (!Array.isArray(versions) || versions.length < 2) return;
      const current = pinned ? Number(pinned[1]) : latest;
      if (!versions.some((v) => v.n === current)) return;

      const select = document.createElement("select");
      select.className = "ver";
      select.title = "版を切り替える";
      select.setAttribute("aria-label", "版");
      // note は publish したときの入力なので、textContent で入れる。
      for (const v of versions) {
        const parts = [`v${v.n}`, String(v.at).slice(0, 10)];
        if (v.n === latest) parts.push("最新");
        if (v.note) parts.push(v.note);
        const opt = document.createElement("option");
        opt.value = String(v.n);
        opt.textContent = parts.join(" · ");
        select.append(opt);
      }
      const list = document.createElement("option");
      list.value = "list";
      list.textContent = "版の一覧…";
      select.append(list);

      const reset = () => {
        select.value = String(current);
      };
      reset();
      select.addEventListener("change", () => {
        location.href = shellUrl(select.value, latest) + location.hash;
      });
      // 戻るボタンで bfcache から戻ったとき、選んだ版のままにならないようにする。
      window.addEventListener("pageshow", reset);
      verLink.replaceWith(select);
    })
    .catch(() => {});
})();
