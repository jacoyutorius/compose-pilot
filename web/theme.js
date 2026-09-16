(() => {
  'use strict';

  const storageKey = 'compose-pilot-theme';
  const validThemes = new Set(['light', 'dark']);

  function storedTheme() {
    try {
      const value = window.localStorage.getItem(storageKey);
      return validThemes.has(value) ? value : null;
    } catch {
      return null;
    }
  }

  function systemTheme() {
    return window.matchMedia?.('(prefers-color-scheme: light)').matches ? 'light' : 'dark';
  }

  function apply(theme, persist = true) {
    const nextTheme = validThemes.has(theme) ? theme : systemTheme();
    document.documentElement.dataset.theme = nextTheme;
    if (persist) {
      try {
        window.localStorage.setItem(storageKey, nextTheme);
      } catch {
        // ストレージを利用できない環境でも、現在の画面にはテーマを適用する。
      }
    }
    return nextTheme;
  }

  apply(storedTheme() || systemTheme(), false);
  window.ComposePilotTheme = {
    apply,
    current: () => document.documentElement.dataset.theme || systemTheme()
  };
})();
