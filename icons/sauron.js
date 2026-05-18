/*
 * Sauron progressive enhancement layer.
 *
 * Loaded from $SAURON_ICON_PATH/sauron.js by every start_html() call
 * in cgi/sauron.cgi and cgi/browser.cgi. Every feature is additive:
 * if this file fails to load (or is blocked) the server-rendered
 * HTML must remain fully usable.
 *
 *   - table.s-list[data-sortable]: column-header sort with aria-sort.
 *   - input[data-filter-table="#id"]: client-side substring filter.
 *   - .s-topbar__nav: arrow-key navigation between top-bar links.
 *   - form[data-confirm], button[data-confirm]: explicit confirm dialog
 *     before a destructive submit goes through.
 */

(function () {
    'use strict';

    /* Sort threshold: a Sauron host list with ~5000 rows can choke a
     * naive DOM sort, so opt out and surface why instead of locking up. */
    var SORT_MAX_ROWS_DEFAULT = 1000;

    function $(sel, root) { return (root || document).querySelector(sel); }
    function $$(sel, root) { return Array.prototype.slice.call((root || document).querySelectorAll(sel)); }

    /* ---- Sortable tables ----------------------------------------------
     * Opt-in via <table class="s-list" data-sortable>. We use the first
     * <tr class="s-list__head"> as the header row; data rows are all
     * .s-list__row siblings of that header. */
    function attachSortable(table) {
        var max = parseInt(table.getAttribute('data-sort-max-rows') || SORT_MAX_ROWS_DEFAULT, 10);
        var headRow = $('tr.s-list__head', table) || table.tBodies[0] && table.tBodies[0].rows[0];
        if (!headRow) return;
        var rows = $$('tr.s-list__row', table);
        if (rows.length === 0) return;
        if (rows.length > max) {
            table.setAttribute('data-sort-disabled', 'too-many-rows');
            return;
        }

        var headers = $$('th', headRow);
        headers.forEach(function (th, colIndex) {
            th.setAttribute('role', 'columnheader');
            th.setAttribute('aria-sort', 'none');
            th.setAttribute('tabindex', '0');
            th.classList.add('s-list__th--sortable');

            function sortBy(direction) {
                var sorted = rows.slice().sort(function (a, b) {
                    var av = cellText(a, colIndex);
                    var bv = cellText(b, colIndex);
                    var na = parseFloat(av);
                    var nb = parseFloat(bv);
                    var cmp;
                    if (!isNaN(na) && !isNaN(nb) && av.trim() !== '' && bv.trim() !== '') {
                        cmp = na - nb;
                    } else {
                        cmp = av.localeCompare(bv, undefined, { numeric: true, sensitivity: 'base' });
                    }
                    return direction === 'asc' ? cmp : -cmp;
                });
                var parent = rows[0].parentNode;
                sorted.forEach(function (r) { parent.appendChild(r); });
                headers.forEach(function (h) { h.setAttribute('aria-sort', 'none'); });
                th.setAttribute('aria-sort', direction === 'asc' ? 'ascending' : 'descending');
            }

            function toggle() {
                var current = th.getAttribute('aria-sort');
                sortBy(current === 'ascending' ? 'desc' : 'asc');
            }

            th.addEventListener('click', toggle);
            th.addEventListener('keydown', function (e) {
                if (e.key === 'Enter' || e.key === ' ') {
                    e.preventDefault();
                    toggle();
                }
            });
        });
    }

    function cellText(row, colIndex) {
        var cell = row.cells[colIndex];
        return cell ? (cell.textContent || cell.innerText || '') : '';
    }

    /* ---- Table filter -------------------------------------------------
     * <input data-filter-table="#some-id"> hides rows in the referenced
     * table whose visible text doesn't contain the query (case-insensitive). */
    function attachFilter(input) {
        var sel = input.getAttribute('data-filter-table');
        var table = sel && document.querySelector(sel);
        if (!table) return;
        var rows = $$('tr.s-list__row', table);
        function apply() {
            var q = input.value.toLowerCase().trim();
            rows.forEach(function (r) {
                var hit = q === '' || (r.textContent || '').toLowerCase().indexOf(q) !== -1;
                r.style.display = hit ? '' : 'none';
            });
        }
        input.addEventListener('input', apply);
        apply();
    }

    /* ---- Topbar keyboard nav ------------------------------------------
     * Left/Right move focus between visible .s-topbar__link anchors; Home
     * jumps to the first, End to the last. Tab still works normally. */
    function attachTopbarNav(nav) {
        var links = $$('a.s-topbar__link', nav);
        if (links.length === 0) return;
        nav.addEventListener('keydown', function (e) {
            var idx = links.indexOf(document.activeElement);
            if (idx < 0) return;
            var next = null;
            if (e.key === 'ArrowRight')      next = links[(idx + 1) % links.length];
            else if (e.key === 'ArrowLeft')  next = links[(idx - 1 + links.length) % links.length];
            else if (e.key === 'Home')       next = links[0];
            else if (e.key === 'End')        next = links[links.length - 1];
            if (next) { e.preventDefault(); next.focus(); }
        });
    }

    /* ---- Confirm-before-submit ----------------------------------------
     * Any <form data-confirm="message"> intercepts its first submit and
     * asks the operator to confirm. The same attribute on a <button> or
     * <input type=submit> is honored per-click so a form can have both a
     * benign and a destructive submit. */
    function attachConfirmForms() {
        $$('form[data-confirm]').forEach(function (form) {
            form.addEventListener('submit', function (e) {
                if (form.dataset.confirmed === '1') return;
                if (!window.confirm(form.getAttribute('data-confirm'))) {
                    e.preventDefault();
                } else {
                    form.dataset.confirmed = '1';
                }
            });
        });
        $$('button[data-confirm], input[type="submit"][data-confirm]').forEach(function (btn) {
            btn.addEventListener('click', function (e) {
                if (!window.confirm(btn.getAttribute('data-confirm'))) {
                    e.preventDefault();
                }
            });
        });
    }

    /* attachStickyActions removed: appending a <div> into a <table> element
     * is invalid HTML and causes browsers to eject the div outside the table,
     * breaking the form layout. Button styling is handled globally by CSS. */

    /* ---- Login autofocus ----------------------------------------------
     * Replaces an inline <script> that called document.getElementById('login')
     * .focus() from the bottom of the login form. */
    function focusLogin() {
        var first = document.getElementById('login');
        if (first && typeof first.focus === 'function') first.focus();
    }


    /* ---- Context warning -----------------------------------------------
     * When no server or zone is selected (data-serverid/zoneid = 0),
     * inject a hint link into the context bar so the operator knows
     * what to do next. Removed and re-added on every AJAX page swap. */
    function attachContextWarning() {
        var crumb = document.querySelector('.s-context-bar__crumb');
        if (!crumb) return;
        var old = crumb.querySelector('.s-ctx-hint');
        if (old) old.remove();
        var sid = parseInt(crumb.getAttribute('data-serverid') || '0', 10);
        var zid = parseInt(crumb.getAttribute('data-zoneid') || '0', 10);
        if (sid > 0 && zid > 0) return;
        var hintHref  = sid === 0 ? '?menu=servers' : '?menu=zones';
        var hintLabel = sid === 0 ? 'No server selected' : 'No zone selected';
        var hint = document.createElement('span');
        hint.className = 's-ctx-hint';
        var hintA = document.createElement('a');
        hintA.href = hintHref;
        hintA.className = 's-ctx-hint__link';
        hintA.textContent = hintLabel;
        hint.appendChild(hintA);
        crumb.appendChild(hint);
    }

    /* ---- Optimistic context-bar update -----------------------------------
     * Update the crumb immediately on server/zone selection — before the
     * AJAX round-trip completes — so the hint disappears instantly.
     *
     * The crumb is rendered at the top of the page before the menu handler
     * saves the new session state, so AJAX responses always carry stale
     * zeroes for data-serverid/zoneid and missing Zone/Server segments.
     * We store the pending values and re-apply them after every swap until
     * the server confirms the selection in a later response. */

    var _optZone = '';    /* pending zone name; cleared when server confirms */
    var _optServer = '';  /* pending server name; cleared when server confirms */

    function _insertZoneInCrumb(crumb, zone) {
        /* If a Zone segment already exists, just update its text. */
        var labels = crumb.querySelectorAll('.s-context-bar__label');
        for (var li = 0; li < labels.length; li++) {
            if (labels[li].textContent.replace(':', '').trim() === 'Zone') {
                var ns = labels[li].nextElementSibling;
                if (ns && ns.classList.contains('s-context-bar__segment')) ns.textContent = zone;
                return;
            }
        }
        /* Insert sep + Zone label + segment before the first sep (before SID). */
        var ref = crumb.querySelector('.s-context-bar__sep');
        var sep = document.createElement('span');
        sep.className = 's-context-bar__sep';
        sep.setAttribute('aria-hidden', 'true');
        sep.textContent = '\u203a';
        var lbl = document.createElement('span');
        lbl.className = 's-context-bar__label';
        lbl.textContent = 'Zone';
        var seg = document.createElement('span');
        seg.className = 's-context-bar__segment';
        seg.textContent = zone;
        if (ref) {
            crumb.insertBefore(seg, ref);
            crumb.insertBefore(lbl, seg);
            crumb.insertBefore(sep, lbl);
        } else {
            crumb.appendChild(sep); crumb.appendChild(lbl); crumb.appendChild(seg);
        }
    }

    function _insertServerInCrumb(crumb, name) {
        var labels = crumb.querySelectorAll('.s-context-bar__label');
        for (var li = 0; li < labels.length; li++) {
            if (labels[li].textContent.replace(':', '').trim() === 'Server') {
                var ns = labels[li].nextElementSibling;
                if (ns && ns.classList.contains('s-context-bar__segment')) ns.textContent = name;
                return;
            }
        }
        /* Prepend Server label + segment before everything else. */
        var seg = document.createElement('span');
        seg.className = 's-context-bar__segment';
        seg.textContent = name;
        var lbl = document.createElement('span');
        lbl.className = 's-context-bar__label';
        lbl.textContent = 'Server';
        crumb.insertBefore(seg, crumb.firstChild);
        crumb.insertBefore(lbl, seg);
    }

    /* Runs once at boot — not in init() — to avoid stacking listeners. */
    (function attachOptimisticContext() {
        /* Server selection: submit button name=server_select_submit. */
        document.addEventListener('click', function (e) {
            var btn = e.target.closest('input[name="server_select_submit"]');
            if (!btn) return;
            var form = btn.form;
            if (!form) return;
            var sel = form.querySelector('select[name="server_list"]');
            if (!sel || sel.selectedIndex < 0) return;
            var sid = parseInt(sel.value, 10);
            if (!(sid > 0)) return;
            _optServer = sel.options[sel.selectedIndex].text.trim();
            var crumb = document.querySelector('.s-context-bar__crumb');
            if (crumb) {
                crumb.setAttribute('data-serverid', sid);
                _insertServerInCrumb(crumb, _optServer);
            }
            attachContextWarning();
        }, true);

        /* Zone selection: links with ?menu=zones&selected_zone=name. */
        document.addEventListener('click', function (e) {
            var a = e.target.closest('a[href]');
            if (!a) return;
            var href = a.getAttribute('href') || '';
            var m = href.match(/[?&]selected_zone=([^&#]+)/);
            if (!m) return;
            _optZone = decodeURIComponent(m[1].replace(/\+/g, ' '));
            var crumb = document.querySelector('.s-context-bar__crumb');
            if (crumb) {
                crumb.setAttribute('data-zoneid', '1');
                _insertZoneInCrumb(crumb, _optZone);
            }
            attachContextWarning();
        }, true);
    }());

    /* ---- Theme update after save --------------------------------------
     * When the theme settings page saves, it emits <meta id="s-theme-update">
     * with data-bg/fg/name. init() calls this to apply CSS vars immediately
     * (<script> inside innerHTML is never executed by browsers). */
    function applyThemeUpdate() {
        var m = document.getElementById('s-theme-update');
        if (!m) return;
        var bg = m.getAttribute('data-bg');
        var fg = m.getAttribute('data-fg');
        var nm = m.getAttribute('data-name');
        var r  = document.documentElement.style;
        if (bg) {
            r.setProperty('--s-env-color',     bg);
            r.setProperty('--s-primary',       bg);
            r.setProperty('--s-primary-light', bg);
        }
        if (fg) r.setProperty('--s-env-fg', fg);
        var tb = document.querySelector('.s-topbar');
        if (tb) { if (bg) tb.style.background = bg; if (fg) tb.style.color = fg; }
        /* Scope to .s-topbar direct children so we don't accidentally find
         * the preview bar's .s-topbar__env span instead of the real one. */
        var badge = document.querySelector('.s-topbar > .s-topbar__env');
        var title = document.querySelector('.s-topbar__title');
        if (nm) {
            if (!badge) {
                badge = document.createElement('span');
                badge.className = 's-topbar__env';
                if (title) title.after(badge);
            }
            if (badge) badge.textContent = nm;
        } else if (badge) {
            badge.remove();
        }
    }

    /* ---- Deployment theme form ----------------------------------------
     * Activates the colour picker ↔ text field sync and live preview on
     * the theme settings page. Called by init() so it works after AJAX
     * swap (inline <script> inside innerHTML is never executed). */
    function attachThemeForm() {
        var bg  = document.getElementById('t_bg');
        if (!bg) return;
        var bgp = document.getElementById('t_bg_p');
        var fg  = document.getElementById('t_fg');
        var fgp = document.getElementById('t_fg_p');
        var nm  = document.getElementById('t_nm');
        var bar = document.getElementById('s-theme-prev-bar');
        var hbg = document.querySelector('[name=theme_bgcolor]');
        var hfg = document.querySelector('[name=theme_fgcolor]');
        var hnm = document.querySelector('[name=theme_envname]');

        function upd() {
            if (bar) { bar.style.background = bg.value; bar.style.color = fg.value; }
            var e = bar && bar.querySelector('.s-topbar__env');
            if (nm.value && !e && bar) {
                e = document.createElement('span');
                e.className = 's-topbar__env';
                bar.insertBefore(e, bar.lastElementChild);
            }
            if (e) { if (nm.value) e.textContent = nm.value; else e.remove(); }
            if (hbg) hbg.value = bg.value;
            if (hfg) hfg.value = fg.value;
            if (hnm) hnm.value = nm.value;
        }

        if (bgp) bgp.addEventListener('input', function () { bg.value  = this.value; upd(); });
        bg.addEventListener('input', function () {
            if (/^#[0-9a-fA-F]{3,8}$/.test(this.value) && bgp) bgp.value = this.value;
            upd();
        });
        if (fgp) fgp.addEventListener('input', function () { fg.value  = this.value; upd(); });
        if (fg) fg.addEventListener('input', function () {
            if (/^#[0-9a-fA-F]{3,8}$/.test(this.value) && fgp) fgp.value = this.value;
            upd();
        });
        if (nm) nm.addEventListener('input', upd);
        upd();
    }

    /* ---- Boot ---------------------------------------------------------- */
    function init() {
        $$('table.s-list[data-sortable]').forEach(attachSortable);
        $$('input[data-filter-table]').forEach(attachFilter);
        $$('.s-topbar__nav').forEach(attachTopbarNav);
        attachConfirmForms();
        focusLogin();
        attachContextWarning();
        applyThemeUpdate();
        attachThemeForm();
    }

    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', init);
    } else {
        init();
    }

    /* ---- Progress bar ------------------------------------------------------ */
    var _bar = document.createElement('div');
    _bar.id = 's-nprogress';
    _bar.style.cssText = 'position:fixed;top:0;left:0;width:0;height:2px;' +
        'background:var(--s-link,#0d6efd);z-index:9999;pointer-events:none;' +
        'transition:width 0.4s ease,opacity 0.3s ease';
    document.head.appendChild(_bar);

    function _barStart() {
        _bar.style.transition = 'width 0.4s ease,opacity 0.3s ease';
        _bar.style.opacity = '1';
        _bar.style.width = '70%';
    }
    function _barFinish() {
        _bar.style.transition = 'width 0.1s ease';
        _bar.style.width = '100%';
        setTimeout(function () {
            _bar.style.transition = 'opacity 0.25s ease';
            _bar.style.opacity = '0';
            setTimeout(function () { _bar.style.width = '0'; _bar.style.opacity = '1'; }, 280);
        }, 120);
    }

    /* ---- AJAX navigation (Turbolinks-style) --------------------------------
     * Fetch the target page, swap .s-main + .s-sidebar + context bar in place.
     * The topbar stays untouched — no full-page reload flash.
     * Falls back to normal navigation on network error or for file downloads. */

    function _swapPage(html, url) {
        var doc = (new DOMParser()).parseFromString(html, 'text/html');

        /* Bail out if the response isn't a Sauron page (e.g. redirect to login). */
        if (!doc.querySelector('.s-main')) { location.href = url; return; }
        /* If the current page has no shell (login / logout standalone), a
         * swap is impossible — fall back to full navigation so the shell
         * is built from scratch by the server. */
        if (!document.querySelector('.s-main')) { location.href = url; return; }

        ['.s-main', '.s-sidebar', '.s-topbar__nav',
         '.s-context-bar__crumb', '.s-context-bar__actions'].forEach(function (sel) {
            var n = doc.querySelector(sel), o = document.querySelector(sel);
            if (!n || !o) return;
            o.innerHTML = n.innerHTML;
            /* innerHTML copies children only — not the element's own attributes.
             * Sync data-* attrs, keeping whichever value is higher so a
             * pending optimistic update is not overwritten by the stale zero
             * the server emits (crumb renders before the handler saves state).
             * Then re-insert any optimistic server/zone name that the response
             * content is missing, and clear the pending value once the server
             * confirms it with a non-zero attr in its own response. */
            if (sel === '.s-context-bar__crumb') {
                var nvsid = parseInt(n.getAttribute('data-serverid') || '0', 10);
                var nvzid = parseInt(n.getAttribute('data-zoneid') || '0', 10);
                var ovsid = parseInt(o.getAttribute('data-serverid') || '0', 10);
                var ovzid = parseInt(o.getAttribute('data-zoneid') || '0', 10);
                o.setAttribute('data-serverid', Math.max(nvsid, ovsid));
                o.setAttribute('data-zoneid',   Math.max(nvzid, ovzid));
                /* Server confirmed — clear pending name so we trust its content. */
                if (nvsid > 0) _optServer = '';
                if (nvzid > 0) _optZone   = '';
                /* Re-insert pending names the response content is missing. */
                if (_optServer) _insertServerInCrumb(o, _optServer);
                if (_optZone)   _insertZoneInCrumb(o, _optZone);
            }
        });

        document.title = doc.title || document.title;
        if (url && url !== location.href) {
            history.pushState({ sauron: 1 }, document.title, url);
        }
        init();
        _barFinish();
    }

    function _ajaxGet(url) {
        _barStart();
        fetch(url, { credentials: 'same-origin' })
            .then(function (r) {
                return r.text().then(function (h) { return { html: h, url: r.url }; });
            })
            .then(function (r) { _swapPage(r.html, r.url); })
            .catch(function () { location.href = url; });
    }

    /* Track which submit button triggered the form's submit event. */
    var _lastSubmit = null;
    document.addEventListener('click', function (e) {
        var b = e.target.closest('input[type="submit"],button[type="submit"]');
        _lastSubmit = b || null;
    }, true);

    /* Link clicks → AJAX GET. */
    document.addEventListener('click', function (e) {
        var a = e.target.closest('a[href]');
        if (!a || e.ctrlKey || e.metaKey || e.shiftKey || e.altKey) return;
        var href = a.getAttribute('href');
        if (!href || href.charAt(0) === '#' || /^javascript:/i.test(href)) return;
        if (a.getAttribute('target')) return;  /* target links (e.g. logout target=_top) */
        if (/\.(csv|pdf|zip|xls)($|\?)/i.test(href)) return;  /* file download */
        e.preventDefault();
        _ajaxGet(href);
    });

    /* Form submits → AJAX POST/GET. */
    document.addEventListener('submit', function (e) {
        var form = e.target;
        if (!form || form.method === 'dialog') return;
        if (e.defaultPrevented) return;          /* confirm dialog cancelled it */
        /* Let browser handle forms that target a named frame or new window. */
        if (form.target && form.target !== '' && form.target !== '_self') return;
        if (form.querySelector('input[type="file"]')) return;  /* file upload */
        if (form.querySelector('input[name="login"]')) return; /* login — needs full reload for cookie */

        /* CSV download buttons: let browser handle directly. */
        /* Use e.submitter (modern) with _lastSubmit as fallback for older browsers.
         * This ensures Enter-key submissions also carry the correct button value. */
        var sub = e.submitter || _lastSubmit;
        if (sub && /csv|download/i.test((sub.name || '') + (sub.value || ''))) return;
        if (form.querySelector('input[name="results.csv"]')) return;

        e.preventDefault();
        _barStart();

        var data = new FormData(form);
        if (sub && sub.name && sub.form === form) {
            data.set(sub.name, sub.value || '');
        }
        _lastSubmit = null;

        var method = (form.method || 'get').toUpperCase();
        var action = form.action || location.href;
        var opts   = { credentials: 'same-origin', method: method };

        if (method === 'POST') {
            opts.body    = new URLSearchParams(data);
            opts.headers = { 'Content-Type': 'application/x-www-form-urlencoded' };
        } else {
            action = action.split('?')[0] + '?' + new URLSearchParams(data);
        }

        fetch(action, opts)
            .then(function (r) {
                return r.text().then(function (h) { return { html: h, url: r.url }; });
            })
            .then(function (r) { _swapPage(r.html, r.url); })
            .catch(function () { form.submit(); });
    });

    /* Back / forward buttons. */
    window.addEventListener('popstate', function () { _ajaxGet(location.href); });

})();
