/* A small, playable Black Hole in the page: hover the notch, tick tasks, run the timer, type a note. */
(() => {
  const stage = document.querySelector('.workspace');
  const notch = document.querySelector('.notch');
  if (!stage || !notch) return;
  const page = document.body;

  /* ---- open and close, the way the app does ---- */
  const open = () => page.classList.add('open');
  const close = () => {
    if (!stage.contains(document.activeElement)) page.classList.remove('open');
  };

  notch.addEventListener('mouseenter', open);
  notch.addEventListener('click', () => page.classList.toggle('open'));
  notch.addEventListener('keydown', (e) => {
    if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); page.classList.toggle('open'); }
  });
  stage.addEventListener('mouseleave', close);
  stage.querySelector('.demo-close').addEventListener('click', () => page.classList.remove('open'));
  document.addEventListener('keydown', (e) => { if (e.key === 'Escape') page.classList.remove('open'); });

  /* ---- tasks ---- */
  const list = stage.querySelector('.demo-tasks');
  const count = stage.querySelector('.demo-count');

  const refreshCount = () => {
    const rows = [...list.querySelectorAll('.demo-task')];
    count.textContent = `${rows.filter((r) => r.classList.contains('done')).length} / ${rows.length}`;
  };

  const wireTask = (row) => {
    row.querySelector('.demo-check').addEventListener('click', () => {
      row.classList.toggle('done');
      // Slightly stronger bar once the page moves, like a real menu bar over content.
  const onScroll = () => page.classList.toggle('scrolled', window.scrollY > 8);
  window.addEventListener('scroll', onScroll, { passive: true });
  onScroll();

  refreshCount();
    });
  };

  list.querySelectorAll('.demo-task').forEach(wireTask);

  const input = stage.querySelector('.demo-input');
  input.addEventListener('keydown', (event) => {
    if (event.key !== 'Enter' || !input.value.trim()) return;
    const row = document.createElement('div');
    row.className = 'demo-task';
    row.innerHTML = '<span class="demo-check"></span><span class="demo-title"></span>';
    row.querySelector('.demo-title').textContent = input.value.trim();
    list.appendChild(row);
    wireTask(row);
    input.value = '';
    refreshCount();
  });

  /* ---- focus timer ---- */
  const clock = stage.querySelector('.demo-clock');
  const state = stage.querySelector('.demo-state');
  const button = stage.querySelector('.demo-start');
  const island = stage.querySelector('.demo-island');
  const islandClock = island.querySelector('.demo-island-time');
  const ring = island.querySelector('.demo-ring-fill');

  const total = 25 * 60;
  let left = total;
  let ticking = null;

  const format = (seconds) =>
    `${String(Math.floor(seconds / 60)).padStart(2, '0')}:${String(seconds % 60).padStart(2, '0')}`;

  const paint = () => {
    clock.textContent = format(left);
    islandClock.textContent = format(left);
    const done = (total - left) / total;
    ring.style.strokeDashoffset = String(63 * (1 - done));
  };

  const stop = () => {
    clearInterval(ticking);
    ticking = null;
    button.textContent = left === total ? 'Start' : 'Resume';
    state.textContent = left === total ? 'Ready' : 'Paused';
    page.classList.remove('running');
  };

  button.addEventListener('click', () => {
    if (ticking) {
      stop();
      return;
    }
    button.textContent = 'Pause';
    state.textContent = 'Remaining';
    page.classList.add('running');
    ticking = setInterval(() => {
      left = Math.max(0, left - 1);
      paint();
      if (left === 0) {
        stop();
        state.textContent = "Time's up";
      }
    }, 1000);
  });

  /* ---- notepad ---- */
  const note = stage.querySelector('.demo-note');
  const words = stage.querySelector('.demo-words');
  const countWords = () => {
    const n = note.value.trim() ? note.value.trim().split(/\s+/).length : 0;
    words.textContent = `${n} ${n === 1 ? 'word' : 'words'}`;
  };
  note.addEventListener('input', countWords);

  refreshCount();
  paint();
  countWords();
})();
