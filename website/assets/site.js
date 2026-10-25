// Fills in the latest release from GitHub, and wires the copy and sound buttons.
(() => {
  const REPO = 'ai-suifeng/agent-clean-mac';
  const fallback = `https://github.com/${REPO}/releases/latest`;

  // Every download link starts at the releases page and is upgraded to the .dmg once the API answers.
  fetch(`https://api.github.com/repos/${REPO}/releases/latest`, { headers: { Accept: 'application/vnd.github+json' } })
    .then((r) => (r.ok ? r.json() : Promise.reject(r.status)))
    .then((rel) => {
      const assets = rel.assets || [];
      const dmg = assets.find((a) => a.name === 'AgentSweep.dmg') || assets.find((a) => a.name.endsWith('.dmg'));
      const version = (rel.tag_name || '').replace(/^v/, '');
      document.querySelectorAll('[data-download]').forEach((a) => { a.href = dmg ? dmg.browser_download_url : fallback; });
      document.querySelectorAll('[data-version]').forEach((el) => { if (version) el.textContent = version; });
      const date = rel.published_at ? new Date(rel.published_at) : null;
      document.querySelectorAll('[data-date]').forEach((el) => {
        if (date) el.textContent = date.toLocaleDateString(document.documentElement.lang, { year: 'numeric', month: 'short', day: 'numeric' });
      });
    })
    .catch(() => { /* links already point at the releases page */ });

  document.querySelectorAll('[data-copy]').forEach((btn) => {
    btn.addEventListener('click', async () => {
      const text = document.getElementById(btn.dataset.copy).textContent.trim();
      const done = btn.dataset.done || 'Copied';
      const label = btn.textContent;
      try {
        await navigator.clipboard.writeText(text);
        btn.textContent = done;
      } catch {
        const range = document.createRange();
        range.selectNodeContents(document.getElementById(btn.dataset.copy));
        const sel = window.getSelection();
        sel.removeAllRanges();
        sel.addRange(range);
      }
      setTimeout(() => { btn.textContent = label; }, 1600);
    });
  });

  const sound = document.querySelector('[data-sound]');
  if (sound) {
    const videos = document.querySelectorAll('.stage video');
    sound.addEventListener('click', () => {
      const visible = [...videos].find((v) => v.offsetParent !== null) || videos[0];
      const turnOn = visible.muted;
      videos.forEach((v) => { v.muted = !turnOn || v !== visible; });
      if (turnOn) { visible.currentTime = 0; visible.play(); }
      sound.textContent = turnOn ? sound.dataset.on : sound.dataset.off;
    });
  }
})();
