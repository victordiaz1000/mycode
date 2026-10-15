// ============================================================
// BYM Classic — page de présentation
// Interactivité : thème du site, menu mobile, scrollspy,
// lightbox des aperçus, changelog GitHub.
// Tout est en vanilla JS, sans dépendance.
// ============================================================
(() => {
  'use strict';

  document.addEventListener('DOMContentLoaded', () => {
    initSiteTheme();
    initSmoothScroll();
    initBurger();
    initScrollspy();
    initLightbox();
    initChangelog();
    initYear();
  });

  // ----------------------------------------------------------
  // Thème du site (clair / sombre), persisté
  // ----------------------------------------------------------
  function initSiteTheme() {
    const root = document.documentElement;
    const btn = document.getElementById('theme-toggle');
    const meta = document.querySelector('meta[name="theme-color"]');

    const stored = localStorage.getItem('bym-site-theme');
    const prefersLight = window.matchMedia('(prefers-color-scheme: light)').matches;
    setTheme(stored || (prefersLight ? 'light' : 'dark'));

    btn?.addEventListener('click', () => {
      const next = root.dataset.theme === 'light' ? 'dark' : 'light';
      localStorage.setItem('bym-site-theme', next);
      setTheme(next);
    });

    function setTheme(theme) {
      root.dataset.theme = theme;
      if (meta) meta.setAttribute('content', theme === 'light' ? '#f7f1e5' : '#1a130e');
      btn?.setAttribute('aria-label',
        theme === 'light' ? 'Passer en thème sombre' : 'Passer en thème clair');
    }
  }

  // ----------------------------------------------------------
  // Défilement doux sur les ancres (compatibilité navigateurs)
  // ----------------------------------------------------------
  function initSmoothScroll() {
    document.querySelectorAll('a[href^="#"]').forEach((link) => {
      link.addEventListener('click', (e) => {
        const id = link.getAttribute('href').slice(1);
        const target = document.getElementById(id);
        if (target) {
          e.preventDefault();
          target.scrollIntoView({ behavior: 'smooth', block: 'start' });
          // referme le menu mobile après navigation
          document.getElementById('nav-menu')?.classList.remove('is-open');
          document.getElementById('nav-burger')?.setAttribute('aria-expanded', 'false');
        }
      });
    });
  }

  // ----------------------------------------------------------
  // Menu mobile
  // ----------------------------------------------------------
  function initBurger() {
    const burger = document.getElementById('nav-burger');
    const menu = document.getElementById('nav-menu');
    if (!burger || !menu) return;

    burger.addEventListener('click', () => {
      const open = menu.classList.toggle('is-open');
      burger.setAttribute('aria-expanded', String(open));
      burger.setAttribute('aria-label', open ? 'Fermer le menu' : 'Ouvrir le menu');
    });
  }

  // ----------------------------------------------------------
  // Scrollspy : met en évidence le lien de la section visible
  // ----------------------------------------------------------
  function initScrollspy() {
    const links = [...document.querySelectorAll('.nav-links a[href^="#"]')];
    const map = new Map();
    links.forEach((l) => {
      const sec = document.getElementById(l.getAttribute('href').slice(1));
      if (sec) map.set(sec, l);
    });
    if (!map.size || !('IntersectionObserver' in window)) return;

    const obs = new IntersectionObserver((entries) => {
      entries.forEach((entry) => {
        if (!entry.isIntersecting) return;
        links.forEach((l) => l.classList.remove('is-active'));
        map.get(entry.target)?.classList.add('is-active');
      });
    }, { rootMargin: '-40% 0px -55% 0px' });

    map.forEach((_link, sec) => obs.observe(sec));
  }

  // ----------------------------------------------------------
  // Lightbox pour la galerie (flèches + clavier)
  // ----------------------------------------------------------
  function initLightbox() {
    const box = document.getElementById('lightbox');
    const img = document.getElementById('lb-img');
    const caption = document.getElementById('lb-caption');
    if (!box || !img || !caption) return;

    const items = [...document.querySelectorAll('a[data-lightbox]')];
    let index = 0;
    let lastFocus = null;

    items.forEach((link, i) => {
      link.addEventListener('click', (e) => {
        e.preventDefault();
        lastFocus = document.activeElement;
        open(i);
      });
    });

    box.querySelector('.lb-close')?.addEventListener('click', close);
    box.querySelector('.lb-prev')?.addEventListener('click', () => step(-1));
    box.querySelector('.lb-next')?.addEventListener('click', () => step(1));
    box.addEventListener('click', (e) => { if (e.target === box) close(); });

    document.addEventListener('keydown', (e) => {
      if (box.hidden) return;
      if (e.key === 'Escape') close();
      if (e.key === 'ArrowLeft') step(-1);
      if (e.key === 'ArrowRight') step(1);
    });

    function open(i) {
      index = i;
      show();
      box.hidden = false;
      document.body.style.overflow = 'hidden';
      box.querySelector('.lb-close')?.focus();
    }
    function close() {
      box.hidden = true;
      document.body.style.overflow = '';
      lastFocus?.focus?.();
    }
    function step(delta) {
      index = (index + delta + items.length) % items.length;
      show();
    }
    function show() {
      const link = items[index];
      const thumb = link.querySelector('img');
      img.src = link.getAttribute('href');
      img.alt = thumb?.alt || '';
      caption.textContent = `${thumb?.alt || ''} — ${index + 1} / ${items.length}`;
    }
  }

  // ----------------------------------------------------------
  // Changelog : rafraîchi depuis l'API GitHub Releases
  // (repli silencieux sur le contenu statique en cas d'échec)
  // ----------------------------------------------------------
  function initChangelog() {
    const list = document.getElementById('changelog-list');
    if (!list) return;

    fetch('https://api.github.com/repos/victordiaz1000/bym-classic/releases?per_page=6')
      .then((r) => (r.ok ? r.json() : Promise.reject(new Error(r.status))))
      .then((releases) => {
        if (!Array.isArray(releases) || !releases.length) return;
        const blocks = releases.map(buildRelease).filter(Boolean);
        if (!blocks.length) return;
        list.replaceChildren(...blocks);
        const note = document.getElementById('releases-note');
        if (note) note.hidden = false;
        // met à jour le bouton du hero avec la plus récente version
        const firstApk = releases
          .flatMap((r) => (r.assets || []).map((a) => ({ r, a })))
          .find(({ a }) => /\.apk$/i.test(a.name || ''));
        const dl = document.getElementById('download');
        if (firstApk && dl) {
          dl.href = firstApk.a.browser_download_url;
          dl.textContent = `⬇ Télécharger l'APK (${firstApk.r.tag_name})`;
        }
      })
      .catch(() => { /* hors ligne ou quota API : le contenu statique reste */ });

    function buildRelease(release) {
      const block = document.createElement('div');
      block.className = 'release';

      const head = document.createElement('div');
      head.className = 'release-head';
      const tag = document.createElement('span');
      tag.className = 'release-tag';
      tag.textContent = release.tag_name;
      const date = document.createElement('span');
      date.className = 'release-date';
      const d = release.published_at ? new Date(release.published_at) : null;
      date.textContent = d && !isNaN(d)
        ? d.toLocaleDateString('fr-FR', { year: 'numeric', month: 'long' })
        : '';
      head.append(tag, date);

      const ul = document.createElement('ul');
      const lines = (release.body || '')
        .split('\n')
        .map((l) => l.replace(/^[-*\s]+/, '').trim())
        .filter(Boolean)
        .slice(0, 8);
      (lines.length ? lines : ['Voir les détails sur GitHub.']).forEach((line) => {
        const li = document.createElement('li');
        li.textContent = line;
        ul.append(li);
      });

      block.append(head, ul);

      const apk = (release.assets || []).find((a) => /\.apk$/i.test(a.name || ''));
      if (apk) {
        const a = document.createElement('a');
        a.className = 'release-link';
        a.href = apk.browser_download_url;
        a.setAttribute('download', '');
        a.textContent = 'Télécharger';
        block.append(a);
      } else {
        const a = document.createElement('a');
        a.className = 'release-link';
        a.href = release.html_url;
        a.target = '_blank';
        a.rel = 'noopener';
        a.textContent = 'Voir sur GitHub';
        block.append(a);
      }
      return block;
    }
  }

  // ----------------------------------------------------------
  function initYear() {
    const el = document.getElementById('year');
    if (el) el.textContent = String(new Date().getFullYear());
  }
})();
