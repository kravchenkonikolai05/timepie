// Port of ContentView, ActivityRow, DonutChart and HistoryStrip.
import { html, render, useState, useEffect, useLayoutEffect, useRef } from './vendor/preact-htm.js';
import * as W from './model.js';
import { Friends, displayCode, groupTitle } from './friends.js';

const { Duration, SLOT_COUNT } = W;
const api = window.timepie;

const store = new W.Store(await api.load(), (json) => api.save(json));
const friends = new Friends(await api.loadFriends(), (json) => api.saveFriends(json));

// Every change goes out to the group, if you're in one.
friends.storeChanged(store, 0, true);
store.subscribe(() => friends.storeChanged(store));

// Ctrl+Z: text fields keep their own undo, everything else undoes the store.
api.onUndo(() => {
  if (isTyping()) document.execCommand('undo');
  else store.undo();
});

const isTyping = () => ['INPUT', 'TEXTAREA'].includes(document.activeElement?.tagName);
const slotColor = (slot) => `var(--c${slot >= 0 && slot < SLOT_COUNT ? slot : SLOT_COUNT})`;
/** Stops a double-click on a control from also toggling the row's timer. */
const stop = (e) => e.stopPropagation();

function useStore() {
  const [, bump] = useState(0);
  useEffect(() => store.subscribe(() => bump((n) => n + 1)), []);
  return store;
}

function useFriends() {
  const [, bump] = useState(0);
  useEffect(() => friends.subscribe(() => bump((n) => n + 1)), []);
  return friends;
}

// MARK: - Glyphs (stand-ins for the SF Symbols)

const Chevron = ({ dir, size = 12 }) => {
  const d = { left: 'M8 2 L4 6 L8 10', right: 'M4 2 L8 6 L4 10', down: 'M2 4 L6 8 L10 4' }[dir];
  return html`<svg width=${size} height=${size} viewBox="0 0 12 12" fill="none" stroke="currentColor"
    stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"><path d=${d} /></svg>`;
};
const PlayGlyph = () => html`<svg width="10" height="10" viewBox="0 0 10 10"><path d="M2 1 L9 5 L2 9 Z" fill="currentColor" /></svg>`;
const StopGlyph = () => html`<svg width="10" height="10" viewBox="0 0 10 10"><rect x="1.5" y="1.5" width="7" height="7" rx="1.2" fill="currentColor" /></svg>`;
const FolderGlyph = () => html`<svg width="14" height="12" viewBox="0 0 14 12" fill="none" stroke="currentColor"
  stroke-width="1.1" stroke-linejoin="round"><path d="M1 2.5 Q1 1.5 2 1.5 H5 L6.5 3 H12 Q13 3 13 4 V9.5 Q13 10.5 12 10.5 H2 Q1 10.5 1 9.5 Z" /></svg>`;
const FolderPlusGlyph = () => html`<svg width="16" height="13" viewBox="0 0 16 13" fill="none" stroke="currentColor"
  stroke-width="1.1" stroke-linejoin="round" stroke-linecap="round">
  <path d="M13 5.5 V4 Q13 3 12 3 H6.5 L5 1.5 H2 Q1 1.5 1 2.5 V9.5 Q1 10.5 2 10.5 H8.5" /><path d="M12.5 7.5 V12 M10.25 9.75 H14.75" /></svg>`;
const PeopleGlyph = () => html`<svg width="18" height="14" viewBox="0 0 18 14" fill="none" stroke="currentColor"
  stroke-width="1.2" stroke-linecap="round"><circle cx="6.5" cy="4" r="2.6" /><path d="M1.5 12.5 Q1.5 8 6.5 8 Q11.5 8 11.5 12.5" />
  <circle cx="12.5" cy="4.2" r="2.1" /><path d="M12.5 7.8 Q16.5 7.8 16.5 12" /></svg>`;
const CalendarGlyph = () => html`<svg width="16" height="16" viewBox="0 0 16 16" fill="none" stroke="currentColor"
  stroke-width="1.3"><rect x="2" y="3" width="12" height="11" rx="2" /><path d="M2 6.5h12M5 1.5v3M11 1.5v3" /></svg>`;
const TrophyGlyph = () => html`<svg width="16" height="16" viewBox="0 0 16 16" fill="none" stroke="currentColor"
  stroke-width="1.3" stroke-linejoin="round"><path d="M4.5 2h7v4a3.5 3.5 0 0 1-7 0V2Z" />
  <path d="M4.5 3.5H2.5v1a2.5 2.5 0 0 0 2.2 2.5M11.5 3.5h2v1a2.5 2.5 0 0 1-2.2 2.5M8 9.5V12M5.5 14h5M6 12h4" /></svg>`;
const GearGlyph = () => html`<svg width="16" height="16" viewBox="0 0 16 16" fill="none" stroke="currentColor"
  stroke-width="1.3" stroke-linejoin="round"><circle cx="8" cy="8" r="2.2" />
  <path d="M6.9 1.5h2.2l.4 1.9 1.3.7 1.8-.7 1.1 1.9-1.4 1.3v1.6l1.4 1.3-1.1 1.9-1.8-.7-1.3.7-.4 1.9H6.9l-.4-1.9-1.3-.7-1.8.7-1.1-1.9 1.4-1.3V7.2L1.3 5.9l1.1-1.9 1.8.7 1.3-.7.4-1.9Z" /></svg>`;
const MenuGlyph = () => html`<svg width="16" height="16" viewBox="0 0 16 16" fill="none" stroke="currentColor"
  stroke-width="1.4" stroke-linecap="round"><path d="M2.5 4h11M2.5 8h11M2.5 12h11" /></svg>`;
const LogGlyph = () => html`<svg width="16" height="16" viewBox="0 0 16 16" fill="none" stroke="currentColor"
  stroke-width="1.2" stroke-linecap="round" stroke-linejoin="round"><rect x="2.5" y="2.5" width="11" height="12" rx="2" />
  <path d="M6 1.5 H10 V3.5 H6 Z" /><path d="M5.5 7 H10.5 M5.5 9.5 H10.5 M5.5 12 H8.5" /></svg>`;
const TrashGlyph = () => html`<svg width="12" height="12" viewBox="0 0 12 12" fill="none" stroke="currentColor"
  stroke-width="1.1" stroke-linecap="round" stroke-linejoin="round"><path d="M1.5 3 H10.5 M4.5 3 V1.5 H7.5 V3" />
  <path d="M2.5 3 L3.2 10.5 H8.8 L9.5 3" /></svg>`;
const SmallCalendarGlyph = () => html`<svg width="12" height="12" viewBox="0 0 12 12" fill="none" stroke="currentColor"
  stroke-width="1.1" stroke-linecap="round" stroke-linejoin="round"><rect x="1.5" y="2.5" width="9" height="8" rx="1.2" />
  <path d="M1.5 5 H10.5 M4 1.2 V3.4 M8 1.2 V3.4" /></svg>`;
const PlusCircle = () => html`<svg width="14" height="14" viewBox="0 0 14 14" fill="none" stroke="currentColor" stroke-width="1.2">
  <circle cx="7" cy="7" r="6" /><path d="M7 4 V10 M4 7 H10" stroke-linecap="round" /></svg>`;

// MARK: - App

function App() {
  const store = useStore();
  const [viewedWeek, setViewedWeek] = useState(() => W.weekStart(new Date()));
  // Today, kept up to date so a window left open overnight moves on with the date.
  const [today, setToday] = useState(() => W.startOfDay(new Date()));
  const [hoveredID, setHoveredID] = useState(null);
  // The group's leaderboard in place of your own chart and rows.
  const [showingFriends, setShowingFriends] = useState(false);
  // The log of what's been added this week, dropped down from the header.
  const [showingLog, setShowingLog] = useState(false);
  // Your time over any day, month or interval in place of the week.
  const [showingStats, setShowingStats] = useState(false);
  const [stats, setStats] = useState(() => W.Stats.initial());
  // The board everyone can join, for the week on screen.
  const [showingGlobal, setShowingGlobal] = useState(false);
  // Preferences, in place of the week like the pages above.
  const [showingSettings, setShowingSettings] = useState(false);
  const [settings, setSettingsState] = useState(() => W.Settings.load());
  const setSetting = (key, value) => setSettingsState((s) => {
    const next = { ...s, [key]: value };
    W.Settings.save(next);
    return next;
  });
  // The row being dragged by its handle: { id, isFolder, from, offset, stride, slot, into }.
  // `slot` is where the gap is, as an index into the rows without the lifted one;
  // `into` is a folder the lifted task is held over, to drop it in.
  const [drag, setDrag] = useState(null);
  // A running timer is deliberately *not* persisted: it dies with the app. Nothing is
  // written until you stop it, so a crash loses the session rather than inventing one.
  const [running, setRunning] = useState(null);
  const [now, setNow] = useState(Date.now());

  const runningRef = useRef(running);
  runningRef.current = running;
  const weekRef = useRef(viewedWeek);
  weekRef.current = viewedWeek;
  const showingStatsRef = useRef(showingStats);
  showingStatsRef.current = showingStats;

  useEffect(() => {
    if (!running) return;
    const t = setInterval(() => setNow(Date.now()), 1000);
    return () => clearInterval(t);
  }, [running]);

  // The groups see a running timer, renamed or recoloured along with its activity.
  const runningActivity = running && store.activities.find((a) => a.id === running.activityID);
  useEffect(() => {
    friends.setTimer(runningActivity
      ? { name: runningActivity.name, colorSlot: runningActivity.colorSlot, startedAt: running.startedAt }
      : null);
  }, [runningActivity?.name, runningActivity?.colorSlot, running?.startedAt]);

  // Whether a newer TimePie is out, checked now and every few hours. Closing the notice
  // hides it until next launch.
  const [update, setUpdate] = useState(null);
  const [updateDismissed, setUpdateDismissed] = useState(false);
  useEffect(() => {
    const check = () => api.checkUpdate().then((u) => {
      if (u && isNewer(u.latest, u.current)) setUpdate(u);
    });
    check();
    const t = setInterval(check, 6 * 60 * 60 * 1000);
    return () => clearInterval(t);
  }, []);

  // The leaderboard keeps itself current while it's on screen, often enough to catch a
  // friend starting a timer.
  useEffect(() => {
    if (!showingFriends) return;
    friends.refresh();
    const t = setInterval(() => friends.refresh(), 30000);
    return () => clearInterval(t);
  }, [showingFriends]);

  const select = (week) => setViewedWeek(W.weekStart(week));

  // The day a click attributes to: today in this week, the Monday of any other. Worked
  // out at the moment of the click, so it can never be left behind on a day that has passed.
  const loggingDay = () => (W.isSameWeek(viewedWeek, new Date()) ? W.startOfDay(new Date()) : viewedWeek);

  // Checked every second rather than on an event, so midnight, waking from sleep and a
  // changed clock or time zone are all caught the same way. Whatever was showing the
  // old today follows on to the new one: this week moves to the next on Monday, and an
  // untouched stats page to the new day. A week or day you went back to stays put.
  useEffect(() => {
    const t = setInterval(() => {
      const day = W.startOfDay(new Date());
      if (day.getTime() === today.getTime()) return;
      setToday(day);
      setViewedWeek((week) => (week.getTime() === W.weekStart(today).getTime() ? W.weekStart(day) : week));
      setStats((s) => (JSON.stringify(s) === JSON.stringify(W.Stats.initial(today)) ? W.Stats.initial(day) : s));
    }, 1000);
    return () => clearInterval(t);
  }, [today]);

  /** ← / →: a week, or on the stats page whatever span it shows. */
  const step = (n) => {
    if (showingStatsRef.current) setStats((s) => W.Stats.step(s, n));
    else select(W.addWeeks(n, weekRef.current));
  };

  // The pages that take the week's place take turns.
  const pageSetters = [setShowingStats, setShowingFriends, setShowingGlobal, setShowingSettings];
  const toggler = (own) => () => pageSetters.forEach((set) => (set === own ? set((v) => !v) : set(false)));
  const toggleStats = toggler(setShowingStats);
  const toggleFriends = toggler(setShowingFriends);
  const toggleGlobal = toggler(setShowingGlobal);
  const toggleSettings = toggler(setShowingSettings);

  // ← and → step through weeks, unless a text field is taking the arrow keys. Escape
  // leaves whichever page is open and goes back to the week — once any menu or the log
  // that's open on top has closed itself.
  useEffect(() => {
    const onKey = (e) => {
      if (isTyping() || e.ctrlKey || e.altKey || e.metaKey) return;
      if (e.key === 'ArrowLeft') step(-1);
      if (e.key === 'ArrowRight') step(1);
      if (e.key === 'Escape' && !document.querySelector('.pages-menu-list, .log-panel')) {
        pageSetters.forEach((set) => set(false));
      }
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, []);

  const weekEnd = W.weekEnd(viewedWeek);
  const outline = store.outlineForWeek(viewedWeek);
  // Every task in the week in list order, hidden ones included — the chart's slices.
  const activities = outline.flatMap((x) => (x.kind === 'folder' ? x.tasks : [x.activity]));
  const minutesFor = (a) => store.minutes(a.id, viewedWeek, weekEnd);
  const weekTotal = store.totalMinutes(viewedWeek, weekEnd);
  const takenSlots = new Set(activities.map((a) => a.colorSlot));
  const elapsed = running ? Math.max(0, Math.floor((now - running.startedAt) / 1000)) : 0;

  /**
   * The rows on screen, each with the folder it sits in as `parent`. A collapsed
   * folder's tasks are left out, and so are those of a folder being dragged.
   */
  const visibleRows = (hiding = drag?.id) => outline.flatMap((x) => {
    if (x.kind === 'activity') return [{ ...x, parent: null }];
    const hidden = x.folder.collapsed || x.id === hiding;
    return [{ ...x, parent: null },
      ...(hidden ? [] : x.tasks.map((a) => ({ kind: 'activity', id: a.id, activity: a, parent: x.id })))];
  });
  const rows = visibleRows();

  /**
   * Moves the gap to follow the lifted row, a place at a time once it covers more than
   * half of its neighbour. A task passing over a folder pauses there instead: held over
   * the middle of the folder's row, it would drop into the folder.
   */
  const settle = (d, others) => {
    const top = d.offset / d.stride + d.from; // the lifted row's top edge, in rows
    let slot = d.slot;
    let into = null;
    for (;;) {
      const down = top > slot;
      const overlap = Math.abs(top - slot);
      const n = down ? slot : slot - 1;
      if (n < 0 || n >= others.length) break;
      if (!d.isFolder && others[n].kind === 'folder') {
        if (overlap > 0.7) { slot += down ? 1 : -1; continue; }
        if (overlap >= 0.3) into = others[n].id;
        break;
      }
      if (overlap <= 0.5) break;
      slot += down ? 1 : -1;
    }
    return { ...d, slot, into };
  };

  const dragRow = (id, isFolder, index, dy, stride) => {
    setDrag((d) => {
      const lifted = d ?? { id, isFolder, from: index, slot: index, into: null };
      const others = visibleRows(id).filter((r) => r.id !== id);
      // Kept within the list, so the row can't be dragged off either end.
      const offset = Math.min(Math.max(dy, -lifted.from * stride), (others.length - lifted.from) * stride);
      return settle({ ...lifted, offset, stride }, others);
    });
  };

  /** How far a row is pushed to open the gap; the lifted row follows the cursor. */
  const displacement = (index) => {
    if (!drag) return 0;
    if (index === drag.from) return drag.offset;
    const k = index < drag.from ? index : index - 1;
    return ((k < drag.slot ? k : k + 1) - index) * drag.stride;
  };

  /** Where the lifted row would land: { parent (a folder, or null), index }. */
  const dropTarget = (d) => {
    if (d.into) return { parent: d.into, index: Infinity };
    const others = visibleRows(d.id).filter((r) => r.id !== d.id);
    const before = others.slice(0, d.slot);
    const topLevel = before.filter((r) => !r.parent).length;
    // Folders don't nest; one dropped among a folder's tasks lands after it.
    if (d.isFolder) return { parent: null, index: topLevel };
    // Between two of a folder's tasks, or above its first: in that folder.
    const below = others[d.slot];
    if (below?.parent) return { parent: below.parent, index: before.filter((r) => r.parent === below.parent).length };
    // Straight under an open folder that has nothing else in it.
    const above = before[before.length - 1];
    if (above?.kind === 'folder' && !above.folder.collapsed) return { parent: above.id, index: 0 };
    return { parent: null, index: topLevel };
  };

  const endDrag = () => {
    if (drag) {
      const target = dropTarget(drag);
      store.move(drag.id, target.parent, target.index, viewedWeek);
    }
    setDrag(null);
  };

  const stopTimer = () => {
    const timer = runningRef.current;
    if (!timer) return;
    setRunning(null);
    runningRef.current = null;
    store.logSession(timer.activityID, new Date(timer.startedAt), new Date());
  };

  const toggleTimer = (activity) => {
    if (runningRef.current?.activityID === activity.id) return stopTimer();
    // One timer at a time: starting a new one logs and closes the old.
    stopTimer();
    const startedAt = Date.now();
    setNow(startedAt);
    setRunning({ activityID: activity.id, startedAt });
  };

  const slices = activities.map((a) => ({
    id: a.id, name: a.name, minutes: Math.max(0, minutesFor(a)), colorSlot: a.colorSlot,
  }));

  const thisWeek = W.weekStart(today);
  const thumbs = Array.from({ length: 12 }, (_, i) => {
    const start = W.addWeeks(i - 11, thisWeek);
    const end = W.weekEnd(start);
    return {
      id: start.getTime(),
      start,
      label: W.weekLabel(start),
      totalMinutes: store.totalMinutes(start, end),
      slices: store.activitiesForWeek(start)
        .map((a) => ({ id: a.id, name: a.name, minutes: store.minutes(a.id, start, end), colorSlot: a.colorSlot }))
        .filter((s) => s.minutes > 0),
    };
  });

  // The pages in the header's ☰ menu.
  const pages = [
    { label: 'Stats', Glyph: CalendarGlyph, on: showingStats, toggle: toggleStats,
      title: showingStats ? 'Back to your week' : 'Your time over any day, month or interval' },
    { label: 'Log', Glyph: LogGlyph, on: showingLog, toggle: () => setShowingLog((v) => !v),
      title: 'Everything logged this week', className: 'log-toggle' },
    { label: 'Friends', Glyph: PeopleGlyph, on: showingFriends, toggle: toggleFriends,
      title: showingFriends ? 'Back to your week' : 'Compare this week with friends' },
    { label: 'Leaderboard', Glyph: TrophyGlyph, on: showingGlobal, toggle: toggleGlobal,
      title: showingGlobal ? 'Back to your week' : 'This week\u2019s totals for everyone using TimePie' },
    { label: 'Settings', Glyph: GearGlyph, on: showingSettings, toggle: toggleSettings,
      title: showingSettings ? 'Back to your week' : 'Settings' },
  ];

  // "~3,5h": the week's total spread over its days so far, if that's switched on.
  // Today only counts once it lifts the average, so it doesn't sink every morning
  // before any work is in; a short day pulls it down at midnight instead.
  const daysSoFar = W.daysElapsed(viewedWeek, today);
  let perDay = daysSoFar > 0 ? weekTotal / daysSoFar : 0;
  if (daysSoFar > 1 && W.isSameWeek(viewedWeek, today)) {
    perDay = Math.max(perDay, store.totalMinutes(viewedWeek, today) / (daysSoFar - 1));
  }
  const dayAverage = settings.showDayAverage && weekTotal > 0 && daysSoFar > 0
    ? Duration.approxHours(perDay) : null;

  // On the stats page the header shows its span, and the arrows step through it.
  const unit = showingStats ? W.Stats.unitName(stats) : 'week';
  const stuck = showingStats && stats.mode === 'allTime';

  return html`
    <div class="app">
      <div class="header">
        <button class="chev" onClick=${() => step(-1)} title="Previous ${unit} (←)" disabled=${stuck}>
          <${Chevron} dir="left" />
        </button>
        <div class="week-label">
          <span class="title">${showingStats ? W.Stats.title(stats) : W.weekLabel(viewedWeek)}</span>
          <span class="sep">·</span>
          <span class="total num">${Duration.format(showingStats
            ? store.totalMinutes(stats.start, W.addDays(1, stats.end))
            : weekTotal)}</span>
        </div>
        <button class="chev" onClick=${() => step(1)} title="Next ${unit} (→)" disabled=${stuck}>
          <${Chevron} dir="right" />
        </button>
        <div class="header-tools">
          <${PagesMenu} pages=${pages} />
        </div>
        ${showingLog && html`<${LogPanel} week=${viewedWeek} onClose=${() => setShowingLog(false)} />`}
      </div>

      ${update && !updateDismissed && html`
        <${UpdateNotice} update=${update} onClose=${() => setUpdateDismissed(true)} />`}

      ${showingSettings ? html`<${SettingsView} settings=${settings} onSet=${setSetting} />`
        : showingStats ? html`<${StatsView} selection=${stats} onChange=${setStats} />`
        : showingGlobal ? html`<${GlobalView} week=${viewedWeek} />`
        : showingFriends ? html`<${FriendsView} week=${viewedWeek} />` : html`
      <div class="chart">
        <${Donut} slices=${slices} size=${250} hoveredID=${hoveredID} onHover=${setHoveredID}
          caption=${dayAverage} animate />
      </div>

      <div class="rows ${drag ? 'reordering' : ''}">
        ${rows.map((r, index) => {
          if (r.kind === 'folder') {
            const f = r.folder;
            return html`
              <${FolderRow}
                key=${r.id}
                folder=${f}
                taskCount=${r.tasks.length}
                minutes=${r.tasks.reduce((sum, a) => sum + Math.max(0, minutesFor(a)), 0)}
                isHovered=${drag ? drag.id === r.id : hoveredID === r.id}
                isDragging=${drag?.id === r.id}
                isDropTarget=${drag?.into === r.id}
                offset=${displacement(index)}
                runningSeconds=${f.collapsed && r.tasks.some((a) => a.id === running?.activityID) ? elapsed : null}
                onHover=${(on) => setHoveredID(on ? r.id : null)}
                onToggle=${() => store.setCollapsed(r.id, !f.collapsed)}
                onRename=${(name) => store.renameFolder(r.id, name)}
                onDelete=${() => store.deleteFolder(r.id)}
                onDrag=${(dy, stride) => dragRow(r.id, true, index, dy, stride)}
                onDragEnd=${endDrag}
              />`;
          }
          const a = r.activity;
          return html`
          <${ActivityRow}
            key=${a.id}
            activity=${a}
            minutes=${minutesFor(a)}
            isHovered=${drag ? drag.id === a.id : hoveredID === a.id}
            isDragging=${drag?.id === a.id}
            inFolder=${drag?.id === a.id ? !!dropTarget(drag).parent : !!r.parent}
            offset=${displacement(index)}
            onDrag=${(dy, stride) => dragRow(a.id, false, index, dy, stride)}
            onDragEnd=${endDrag}
            isRunning=${running?.activityID === a.id}
            elapsedSeconds=${running?.activityID === a.id ? elapsed : 0}
            takenSlots=${takenSlots}
            onHover=${(on) => setHoveredID(on ? a.id : null)}
            onAdd=${(m) => store.add(m, a.id, loggingDay())}
            onSetTotal=${(m) => store.setTotal(m, a.id, viewedWeek, weekEnd, loggingDay())}
            onToggleTimer=${() => toggleTimer(a)}
            onSetColor=${(slot) => store.setColor(a.id, slot)}
            onRename=${(name) => store.rename(a.id, name)}
            onDelete=${() => {
              // Don't leave a timer running against something that's gone.
              if (runningRef.current?.activityID === a.id) setRunning(null);
              store.delete(a.id, viewedWeek);
            }}
          />`;
        })}
        <${AddActivityField} onAdd=${(name) => store.addActivity(name, viewedWeek)}
          onAddFolder=${(name) => store.addFolder(name, viewedWeek)} />
      </div>

      <${HistoryStrip} weeks=${thumbs} selected=${viewedWeek.getTime()} onSelect=${select} />`}
    </div>
  `;
}

// MARK: - Stats

/**
 * Your time over any stretch of days — one day, a month, an interval or all of it —
 * picked on a calendar. Read-only: logging stays on the week.
 */
function StatsView({ selection: s, onChange }) {
  const store = useStore();
  const [hoveredID, setHoveredID] = useState(null);
  // The average last picked. It comes back whenever the selection is long enough for it.
  const [average, setAverage] = useState('total');

  const byActivity = store.minutesByActivity(s.start, W.addDays(1, s.end));
  const days = W.Stats.countedDays(s, store.loggedSpan);
  const averages = W.Stats.averagesFor(days);
  const shownAverage = averages.some(([key]) => key === average) ? average : 'total';
  const slices = store.orderedActivities.map((a) => ({
    id: a.id, name: a.name, colorSlot: a.colorSlot,
    minutes: W.Stats.averaged(Math.max(0, byActivity.get(a.id) ?? 0), days, shownAverage),
  }));
  const total = slices.reduce((sum, x) => sum + x.minutes, 0);
  // What the chart is made of, biggest first.
  const shown = slices.filter((x) => x.minutes > 0).sort((a, b) => b.minutes - a.minutes);

  return html`
    <div class="stats">
      <div class="segmented stats-modes">
        ${W.Stats.modes.map(([mode, label]) => html`
          <button key=${mode} class=${s.mode === mode ? 'on' : ''}
            onClick=${() => onChange(W.Stats.pick(s, mode, store.loggedSpan))}>${label}</button>`)}
      </div>

      <${StatsCalendar} selection=${s} onChange=${onChange} />

      <div class="stats-chart">
        <${Donut} slices=${slices} size=${220} hoveredID=${hoveredID} onHover=${setHoveredID} animate />
        ${total > 0 && days > 1 && html`
          <div class="stats-average num">${shownAverage === 'total'
            ? `${days} days · ${Duration.format(Math.floor(total / days))} a day`
            : `Averaged over ${days} days`}</div>`}
      </div>

      ${averages.length > 1 && html`
        <div class="segmented stats-averages" title="Show the whole stretch, or a typical day, week or month of it">
          ${averages.map(([key, label]) => html`
            <button key=${key} class=${shownAverage === key ? 'on' : ''}
              onClick=${() => setAverage(key)}>${label}</button>`)}
        </div>`}

      <div class="card stats-breakdown">
        ${shown.length === 0 && html`
          <div class="log-empty">${s.mode === 'allTime' ? 'Nothing logged yet' : 'Nothing logged'}</div>`}
        ${shown.map((x) => html`
          <div key=${x.id} class="stats-row num ${hoveredID === x.id ? 'hovered' : ''}"
            onMouseEnter=${() => setHoveredID(x.id)} onMouseLeave=${() => setHoveredID(null)}>
            <span class="dot" style=${{ background: slotColor(x.colorSlot) }} />
            <span class="name">${x.name}</span>
            <span class="spacer" />
            <span class="percent">${Math.round((x.minutes / Math.max(total, 1)) * 100)}%</span>
            <span class="amount">${Duration.format(x.minutes)}</span>
          </div>`)}
      </div>
    </div>
  `;
}

/**
 * A month at a time, Monday first. The selected days are joined by one band, and a dot
 * marks each day with time logged on it.
 */
function StatsCalendar({ selection: s, onChange }) {
  const store = useStore();
  // Six full weeks, so the grid keeps its height from month to month.
  const first = W.weekStart(s.shownMonth);
  const days = Array.from({ length: 42 }, (_, i) => W.addDays(i, first));
  const logged = store.minutesByDay(days[0], W.addDays(1, days[41]));
  const today = W.startOfDay(new Date()).getTime();
  const thisMonth = W.monthStart(new Date()).getTime();
  const span = s.start.getTime() !== s.end.getTime();
  const showMonth = (month) => onChange({ ...s, shownMonth: month });
  const hint = W.Stats.hint(s);

  return html`
    <div class="card calendar">
      <div class="cal-head">
        <span class="cal-month">${s.shownMonth.toLocaleDateString(undefined, { month: 'long', year: 'numeric' })}</span>
        <span class="spacer" />
        <button class="cal-today" disabled=${s.shownMonth.getTime() === thisMonth}
          onClick=${() => showMonth(W.monthStart(new Date()))}>Today</button>
        <button class="chev" title="Previous month" onClick=${() => showMonth(W.addMonths(-1, s.shownMonth))}>
          <${Chevron} dir="left" />
        </button>
        <button class="chev" title="Next month" onClick=${() => showMonth(W.addMonths(1, s.shownMonth))}>
          <${Chevron} dir="right" />
        </button>
      </div>
      <div class="cal-grid">
        ${days.slice(0, 7).map((d) => html`
          <div key=${d.getDay()} class="cal-weekday">${d.toLocaleDateString(undefined, { weekday: 'narrow' })}</div>`)}
        ${days.map((d, i) => {
          const t = d.getTime();
          const isEnd = t === s.start.getTime() || t === s.end.getTime();
          const classes = [
            'cal-day',
            d.getMonth() !== s.shownMonth.getMonth() && 'outside',
            t === today && 'today',
            isEnd && 'end',
            span && t >= s.start.getTime() && t <= s.end.getTime() && 'in-range',
            span && t === s.start.getTime() && 'range-start',
            span && t === s.end.getTime() && 'range-end',
            i % 7 === 0 && 'row-start',
            i % 7 === 6 && 'row-end',
          ].filter(Boolean).join(' ');
          return html`
            <button key=${t} class=${classes} title=${d.toLocaleDateString(undefined, { dateStyle: 'full' })}
              onClick=${() => onChange(W.Stats.click(s, d))}>
              <span class="cal-circle">
                ${d.getDate()}
                <i class=${(logged.get(W.DayStamp.string(d)) ?? 0) > 0 ? 'logged' : ''} />
              </span>
            </button>`;
        })}
      </div>
      <div class="caption cal-hint">${hint ?? '\u00a0'}</div>
    </div>
  `;
}

/** The header's pages — stats, log, friends, leaderboard, settings — in one ☰ menu. */
function PagesMenu({ pages }) {
  const [open, setOpen] = useState(false);
  const ref = useRef();
  useEffect(() => {
    if (!open) return;
    const away = (e) => !ref.current?.contains(e.target) && setOpen(false);
    const esc = (e) => e.key === 'Escape' && setOpen(false);
    document.addEventListener('mousedown', away);
    document.addEventListener('keydown', esc);
    return () => {
      document.removeEventListener('mousedown', away);
      document.removeEventListener('keydown', esc);
    };
  }, [open]);

  return html`
    <div class="pages-menu" ref=${ref}>
      <button class="tool log-toggle ${open || pages.some((p) => p.on) ? 'on' : ''}" onClick=${() => setOpen((v) => !v)}
        title="Stats, log, friends, leaderboard and settings"><${MenuGlyph} /></button>
      ${open && html`
        <div class="pages-menu-list">
          ${pages.map((p) => html`
            <button key=${p.label} class="pages-menu-item ${p.className ?? ''} ${p.on ? 'on' : ''}" title=${p.title}
              onClick=${() => { setOpen(false); p.toggle(); }}>
              <${p.Glyph} /><span>${p.label}</span>${p.on && html`<span class="check">✓</span>`}
            </button>`)}
        </div>`}
    </div>
  `;
}

// MARK: - Log

/**
 * Every amount logged into the viewed week, newest first, grouped by the day it was
 * added — so you can check whether you already logged something, and take back what
 * you logged twice. Ctrl+Z brings a deleted one back.
 */
function LogPanel({ week, onClose }) {
  const store = useStore();
  const ref = useRef();
  useEffect(() => {
    // The toggle closes it itself, so a click on it doesn't count as clicking away.
    const away = (e) => !ref.current?.contains(e.target) && !e.target.closest('.log-toggle') && onClose();
    const esc = (e) => e.key === 'Escape' && onClose();
    document.addEventListener('mousedown', away);
    document.addEventListener('keydown', esc);
    return () => {
      document.removeEventListener('mousedown', away);
      document.removeEventListener('keydown', esc);
    };
  }, []);

  // Entries whose activity is gone count nowhere else, so they're left out here too.
  const byID = new Map(store.activities.map((a) => [a.id, a]));
  const sorted = store.entriesIn(week, W.weekEnd(week))
    .filter((e) => byID.has(e.activityID))
    .map((e) => ({ entry: e, added: new Date(e.createdAt) }))
    .sort((a, b) => b.added - a.added);

  // Clicks in a row on the same task, for the same day, stack into one line, so ten
  // clicks of +1h read as +10h. Typed-in totals and time taken off stay on their own
  // line, so a correction is never hidden inside the time it corrects.
  const lines = [];
  for (const { entry, added } of sorted) {
    const last = lines.at(-1);
    const stacks = last && !last.entry.isAdjustment && !entry.isAdjustment
      && entry.activityID === last.entry.activityID && entry.day === last.entry.day
      && (entry.minutes < 0) === (last.entry.minutes < 0)
      && W.startOfDay(added).getTime() === W.startOfDay(last.added).getTime();
    if (stacks) {
      last.entries.push(entry);
      last.minutes += entry.minutes;
      last.oldest = added;
    } else {
      lines.push({ entry, entries: [entry], minutes: entry.minutes, added, oldest: added,
        activity: byID.get(entry.activityID) });
    }
  }

  // Consecutive lines added on the same day, under that day.
  const sections = [];
  for (const line of lines) {
    const day = W.startOfDay(line.added).getTime();
    if (sections.at(-1)?.day === day) sections.at(-1).lines.push(line);
    else sections.push({ day, lines: [line] });
  }

  return html`
    <div class="log-panel" ref=${ref}>
      <div class="log-title">Log</div>
      ${sections.length === 0
        ? html`<div class="log-empty">Nothing logged this week</div>`
        : html`<div class="log-scroll">
          ${sections.map((s) => html`
            <div key=${s.day} class="log-day">${dayTitle(new Date(s.day))}</div>
            ${s.lines.map(({ entry, entries, minutes, activity, added, oldest }) => html`
              <div key=${entry.id} class="log-row">
                <span class="dot" style=${{ background: slotColor(activity.colorSlot) }} />
                <div class="log-what">
                  <span class="name">${activity.name}</span>
                  <span class="caption">${logDetail(entry, added, oldest)}</span>
                </div>
                <span class="spacer" />
                <span class="num log-amount ${minutes < 0 ? 'negative' : ''}">
                  ${(minutes < 0 ? '−' : '+') + Duration.format(Math.abs(minutes))}</span>
                <${MoveDay} entry=${entry} ids=${entries.map((e) => e.id)} />
                <button class="log-delete" onClick=${() => store.deleteEntries(entries.map((e) => e.id))}
                  title=${entries.length > 1
                    ? `Delete these ${entries.length} entries (Ctrl+Z brings them back)`
                    : 'Delete this entry (Ctrl+Z brings it back)'}><${TrashGlyph} /></button>
              </div>`)}`)}
        </div>`}
    </div>
  `;
}

/**
 * Moves an entry to another day of its own week. Days still to come are left out: time
 * can't have been spent on them yet. A native select under the glyph gives the menu.
 */
function MoveDay({ entry, ids }) {
  const store = useStore();
  const today = W.startOfDay(new Date());
  const start = W.weekStart(W.DayStamp.parse(entry.day));
  const days = Array.from({ length: 7 }, (_, i) => W.addDays(i, start)).filter((d) => d <= today);
  return html`
    <label class="log-delete log-move" title="Move this entry to another day">
      <${SmallCalendarGlyph} />
      <select value=${entry.day} onChange=${(e) => store.moveEntries(ids, W.DayStamp.parse(e.target.value))}>
        ${days.map((d) => html`<option key=${d.getTime()} value=${W.DayStamp.string(d)}>${dayTitle(d)}</option>`)}
      </select>
    </label>`;
}

/** When it was added, and anything that sets it apart. */
function logDetail(entry, added, oldest = added) {
  // A stack shows when its first and last entries were added.
  const time = (d) => d.toLocaleTimeString(undefined, { hour: 'numeric', minute: '2-digit' });
  const parts = [time(oldest) === time(added) ? time(added) : `${time(oldest)}–${time(added)}`];
  const day = W.DayStamp.parse(entry.day);
  if (day.getTime() !== W.startOfDay(added).getTime()) {
    // A weekday alone only says which day within the week it was added in.
    const sameWeek = W.isSameWeek(day, added);
    parts.push(`for ${day.toLocaleDateString(undefined, sameWeek
      ? { weekday: 'long' }
      : { weekday: 'short', month: 'short', day: 'numeric' })}`);
  }
  if (entry.isAdjustment) parts.push('total edited');
  return parts.join(' · ');
}

function dayTitle(day) {
  const today = W.startOfDay(new Date());
  if (day.getTime() === today.getTime()) return 'Today';
  if (day.getTime() === W.addDays(-1, today).getTime()) return 'Yesterday';
  return day.toLocaleDateString(undefined, { weekday: 'long', day: 'numeric', month: 'short' });
}

// MARK: - Updates

/** "1.10.0" is newer than "1.9.2": compared number by number, not as text. */
function isNewer(a, b) {
  const x = a.split('.').map((n) => parseInt(n, 10) || 0), y = b.split('.').map((n) => parseInt(n, 10) || 0);
  for (let i = 0; i < Math.max(x.length, y.length); i++) {
    if ((x[i] ?? 0) !== (y[i] ?? 0)) return (x[i] ?? 0) > (y[i] ?? 0);
  }
  return false;
}

/**
 * A newer TimePie is out: a small card in the corner saying what's new, with the way to it
 * and a way to close it.
 */
function UpdateNotice({ update, onClose }) {
  return html`
    <div class="update-notice" role="status">
      <span class="update-icon">↓</span>
      <div class="update-body">
        <div class="update-title">TimePie ${update.latest} is out</div>
        ${update.highlights.length
          ? html`<ul class="update-list">${update.highlights.map((line) => html`<li key=${line}>${line}</li>`)}</ul>`
          : html`<div class="caption">Download the new one and replace this copy.</div>`}
        <button class="btn primary small" onClick=${() => api.openPage(update.page)}
          title="The latest release, with downloads for Mac and Windows">Open GitHub</button>
      </div>
      <button class="update-close" onClick=${onClose} title="Close. It comes back next time you open TimePie.">✕</button>
    </div>
  `;
}

// MARK: - Donut

/** Angles in radians, starting at 12 o'clock and running clockwise. */
function arcsFor(slices) {
  const total = slices.reduce((s, x) => s + Math.max(0, x.minutes), 0);
  if (total === 0) return [];
  let cursor = -Math.PI / 2;
  return slices.filter((s) => s.minutes > 0).map((s) => {
    const sweep = (s.minutes / total) * 2 * Math.PI;
    const arc = { id: s.id, colorSlot: s.colorSlot, start: cursor, end: cursor + sweep };
    cursor += sweep;
    return arc;
  });
}

/** Split in two so even a full 360° slice draws (an SVG arc can't end where it starts). */
function arcPath(cx, cy, r, a0, a1) {
  const pt = (a) => `${(cx + r * Math.cos(a)).toFixed(3)} ${(cy + r * Math.sin(a)).toFixed(3)}`;
  const mid = (a0 + a1) / 2;
  return `M ${pt(a0)} A ${r} ${r} 0 0 1 ${pt(mid)} A ${r} ${r} 0 0 1 ${pt(a1)}`;
}

/** Wedges grow smoothly when time is added, rather than snapping to their new size. */
function useTweenedArcs(targets, animate) {
  const key = targets.map((t) => `${t.id}:${t.colorSlot}:${t.start.toFixed(5)}:${t.end.toFixed(5)}`).join('|');
  const [shown, setShown] = useState(targets);
  const shownRef = useRef(targets);

  useEffect(() => {
    if (!animate) return;
    const from = new Map(shownRef.current.map((a) => [a.id, a]));
    const t0 = performance.now();
    let raf;
    const step = (t) => {
      const p = Math.min(1, Math.max(0, (t - t0) / 350));
      const e = p < 0.5 ? 2 * p * p : 1 - Math.pow(-2 * p + 2, 2) / 2;
      const frame = targets.map((a) => {
        const f = from.get(a.id) ?? { start: a.start, end: a.start };
        return { ...a, start: f.start + (a.start - f.start) * e, end: f.end + (a.end - f.end) * e };
      });
      shownRef.current = frame;
      setShown(frame);
      if (p < 1) raf = requestAnimationFrame(step);
    };
    raf = requestAnimationFrame(step);
    return () => cancelAnimationFrame(raf);
  }, [key]);

  return animate ? shown : targets;
}

/** Part-to-whole at a glance. 100% is the time you logged, not the whole week. */
function Donut({ slices, size, hoveredID, onHover, caption = null, compact = false, animate = false }) {
  const total = slices.reduce((s, x) => s + Math.max(0, x.minutes), 0);
  const ringWidth = size * (compact ? 0.30 : 0.28);
  const outerR = size / 2;
  const midR = outerR - ringWidth / 2;
  const innerR = outerR - ringWidth;
  const c = size / 2;

  const targets = arcsFor(slices);
  const arcs = useTweenedArcs(targets, animate);

  // Which wedge the pointer is over comes from its angle and radius, not from
  // whichever overlapping shape happens to be on top.
  const onMove = (e) => {
    if (compact || !onHover) return;
    const rect = e.currentTarget.getBoundingClientRect();
    const dx = e.clientX - rect.left - c;
    const dy = e.clientY - rect.top - c;
    const r = Math.hypot(dx, dy);
    if (r < innerR || r > outerR) return onHover(null);
    let angle = Math.atan2(dy, dx) + Math.PI / 2;
    if (angle < 0) angle += 2 * Math.PI;
    const hit = targets.find((a) => angle >= a.start + Math.PI / 2 && angle < a.end + Math.PI / 2);
    onHover(hit ? hit.id : null);
  };

  return html`
    <div class="donut" style=${{ width: size + 'px', height: size + 'px' }}>
      <svg width=${size} height=${size} viewBox="0 0 ${size} ${size}"
        onMouseMove=${onMove} onMouseLeave=${() => !compact && onHover?.(null)}>
        ${total === 0
          ? html`<circle cx=${c} cy=${c} r=${Math.max(0, (size - ringWidth) / 2 - 0.5)} fill="none"
              stroke="var(--muted)" stroke-opacity="0.35" stroke-width="1" />`
          : arcs.map((a) => html`
              <path key=${a.id} d=${arcPath(c, c, midR, a.start, a.end)} fill="none"
                stroke=${slotColor(a.colorSlot)}
                stroke-width=${hoveredID === a.id ? ringWidth + 6 : ringWidth}
                stroke-linecap="butt" />`)}
      </svg>
      ${!compact && html`<${CenterFigure} minutes=${total} width=${innerR * 2 - 16}
        caption=${hoveredID ? null : caption} />`}
    </div>
  `;
}

/** The one number the app leads with; shrinks (to half, at most) rather than clipping. */
function CenterFigure({ minutes, width, caption }) {
  const ref = useRef();
  const text = Duration.format(minutes);
  useLayoutEffect(() => {
    const el = ref.current;
    el.style.fontSize = '34px';
    const natural = el.offsetWidth;
    if (natural > width) el.style.fontSize = `${34 * Math.max(0.5, width / natural)}px`;
  }, [text, width]);
  return html`<div class="center-figure ${minutes === 0 ? 'empty' : ''}">
    <span ref=${ref}>${text}</span>
    ${caption && html`<span class="center-caption num">${caption}</span>`}
  </div>`;
}

// MARK: - Settings

/** Preferences, in place of the week. One card of rows; new settings are new rows. */
function SettingsView({ settings, onSet }) {
  return html`
    <div class="friends">
      <div class="settings-heading">Chart</div>
      <div class="card group-card">
        <label class="setting">
          <span>
            <div>Show average per day</div>
            <div class="caption">Under the week’s total: what it comes to per day so far, like ~3,5h.</div>
          </span>
          <input type="checkbox" class="switch" checked=${settings.showDayAverage}
            onChange=${(e) => onSet('showDayAverage', e.currentTarget.checked)} />
        </label>
      </div>
    </div>
  `;
}

// MARK: - Activity row

/**
 * Three zones — name, total, controls. The outer two expand equally, so the fixed-width
 * total column lands dead centre and stays aligned across every row.
 */
function ActivityRow(props) {
  const { activity, minutes, isHovered, isRunning, elapsedSeconds, takenSlots, isDragging, offset, inFolder } = props;
  const [editingHours, setEditingHours] = useState(false);
  const [editingName, setEditingName] = useState(false);
  const [pickingColor, setPickingColor] = useState(false);

  const onContextMenu = async (e) => {
    e.preventDefault();
    const choice = await api.contextMenu([{ id: 'rename', label: 'Rename…' }, '-', { id: 'delete', label: 'Delete' }]);
    if (choice === 'rename') setEditingName(true);
    if (choice === 'delete') props.onDelete();
  };

  return html`
    <div class="row ${isHovered ? 'hovered' : ''} ${isDragging ? 'dragging' : ''} ${inFolder ? 'in-folder' : ''}"
      style=${offset ? { transform: `translateY(${offset}px)` } : null}
      onMouseEnter=${() => props.onHover(true)} onMouseLeave=${() => props.onHover(false)}
      onDblClick=${props.onToggleTimer} onContextMenu=${onContextMenu}
      title=${isRunning ? 'Double-click to stop' : 'Double-click to start a timer'}>

      <div class="zone-name">
        <button class="dot-btn" title="Change colour" onDblClick=${stop}
          onClick=${() => setPickingColor((v) => !v)}>
          <span class="dot" style=${{ background: slotColor(activity.colorSlot) }} />
        </button>
        ${pickingColor && html`
          <${ColorSwatchPicker} current=${activity.colorSlot} taken=${takenSlots}
            onClose=${() => setPickingColor(false)}
            onPick=${(slot) => { props.onSetColor(slot); setPickingColor(false); }} />`}

        ${editingName
          ? html`<${InlineField} initial=${activity.name}
              onCommit=${(v) => { const t = v.trim(); if (t) props.onRename(t); setEditingName(false); }}
              onCancel=${() => setEditingName(false)} />`
          : html`<span class="name">${activity.name}</span>`}

        <span class="spacer" />
        ${isRunning && html`<span class="stopwatch num">${Duration.clock(elapsedSeconds)}</span>`}
      </div>

      <div class="zone-total" onDblClick=${stop}>
        ${editingHours
          ? html`<${InlineField} initial=${minutes === 0 ? '' : Duration.format(minutes)}
              onCommit=${(v) => { const m = Duration.parse(v); if (m !== null) props.onSetTotal(m); setEditingHours(false); }}
              onCancel=${() => setEditingHours(false)} />`
          : html`<div class="total num ${minutes === 0 ? 'zero' : ''}"
              title="Click to type this week's total — 1h45, 90, 1.5h, 2h"
              onClick=${() => setEditingHours(true)}>${Duration.format(minutes)}</div>`}
      </div>

      <div class="zone-controls" onDblClick=${stop}>
        <button class="btn icon" onClick=${props.onToggleTimer}
          style=${isRunning ? { color: slotColor(activity.colorSlot) } : null}
          title=${isRunning ? 'Stop and log this session' : 'Start a timer'}>
          ${isRunning ? html`<${StopGlyph} />` : html`<${PlayGlyph} />`}
        </button>
        <button class="btn" onClick=${() => props.onAdd(30)}>+30m</button>
        <button class="btn" onClick=${() => props.onAdd(60)}>+1h</button>
        <${DragHandle} onDrag=${props.onDrag} onDragEnd=${props.onDragEnd} />
      </div>
    </div>
  `;
}

/**
 * A folder's header: click it to hide or show the tasks beneath it. It has no colour or
 * time of its own, so the total is its tasks' for the week and isn't editable.
 */
function FolderRow(props) {
  const { folder, taskCount, minutes, isHovered, isDragging, isDropTarget, offset, runningSeconds } = props;
  const [editingName, setEditingName] = useState(false);

  const onContextMenu = async (e) => {
    e.preventDefault();
    const choice = await api.contextMenu([
      { id: 'rename', label: 'Rename…' }, '-', { id: 'delete', label: 'Delete Folder (Keeps Its Tasks)' },
    ]);
    if (choice === 'rename') setEditingName(true);
    if (choice === 'delete') props.onDelete();
  };

  return html`
    <div class="row folder-row ${isHovered ? 'hovered' : ''} ${isDragging ? 'dragging' : ''} ${isDropTarget ? 'drop-target' : ''}"
      style=${offset ? { transform: `translateY(${offset}px)` } : null}
      onMouseEnter=${() => props.onHover(true)} onMouseLeave=${() => props.onHover(false)}
      onClick=${() => !editingName && props.onToggle()} onContextMenu=${onContextMenu}
      title=${folder.collapsed ? 'Click to show its tasks' : 'Click to hide its tasks'}>

      <div class="zone-name">
        <span class="chevron ${folder.collapsed ? '' : 'open'}"><${Chevron} dir="right" size=${10} /></span>
        <${FolderGlyph} />
        ${editingName
          ? html`<${InlineField} initial=${folder.name}
              onCommit=${(v) => { const t = v.trim(); if (t) props.onRename(t); setEditingName(false); }}
              onCancel=${() => setEditingName(false)} />`
          : html`<span class="name folder-name">${folder.name}</span>`}
        ${folder.collapsed && taskCount > 0 && html`<span class="count">${taskCount}</span>`}
        <span class="spacer" />
        ${runningSeconds != null && html`<span class="stopwatch num">${Duration.clock(runningSeconds)}</span>`}
      </div>

      <div class="zone-total">
        <div class="total folder-total num ${minutes === 0 ? 'zero' : ''}">${Duration.format(minutes)}</div>
      </div>

      <div class="zone-controls" onClick=${stop}>
        <${DragHandle} onDrag=${props.onDrag} onDragEnd=${props.onDragEnd} />
      </div>
    </div>
  `;
}

/** Three dots stacked vertically. Press and hold to drag the row up or down. */
function DragHandle({ onDrag, onDragEnd }) {
  const start = useRef(null);
  const onPointerDown = (e) => {
    if (e.button !== 0) return;
    e.preventDefault();
    // Captured, so the drag keeps going even when the pointer outruns the row.
    e.currentTarget.setPointerCapture(e.pointerId);
    const row = e.currentTarget.closest('.row');
    start.current = { y: e.clientY, stride: row.getBoundingClientRect().height + 2 };
    onDrag(0, start.current.stride);
  };
  const onPointerMove = (e) => {
    if (start.current) onDrag(e.clientY - start.current.y, start.current.stride);
  };
  const finish = () => {
    if (!start.current) return;
    start.current = null;
    onDragEnd();
  };
  return html`<div class="grip" title="Drag to reorder"
    onPointerDown=${onPointerDown} onPointerMove=${onPointerMove}
    onPointerUp=${finish} onPointerCancel=${finish}>
    <span /><span /><span />
  </div>`;
}

/** A text field that commits on Enter or when you click away, and cancels on Esc. */
function InlineField({ initial, onCommit, onCancel }) {
  const ref = useRef();
  const done = useRef(false);
  useLayoutEffect(() => {
    ref.current.focus();
    ref.current.select();
  }, []);
  const finish = (fn) => {
    if (done.current) return;
    done.current = true;
    fn();
  };
  return html`<input ref=${ref} class="field" value=${initial} onDblClick=${stop}
    onKeyDown=${(e) => {
      if (e.key === 'Enter') finish(() => onCommit(e.currentTarget.value));
      if (e.key === 'Escape') finish(onCancel);
    }}
    onBlur=${(e) => finish(() => onCommit(e.currentTarget.value))} />`;
}

/** The eight validated palette slots plus the neutral overflow, as pickable swatches. */
function ColorSwatchPicker({ current, taken, onPick, onClose }) {
  const ref = useRef();
  useEffect(() => {
    const away = (e) => !ref.current?.parentElement.contains(e.target) && onClose();
    const esc = (e) => e.key === 'Escape' && onClose();
    document.addEventListener('mousedown', away);
    document.addEventListener('keydown', esc);
    return () => {
      document.removeEventListener('mousedown', away);
      document.removeEventListener('keydown', esc);
    };
  }, []);

  return html`
    <div class="popover" ref=${ref} onDblClick=${stop}>
      <div class="caption">Colour</div>
      <div class="swatches">
        ${Array.from({ length: SLOT_COUNT + 1 }, (_, slot) => html`
          <button class="swatch ${slot === current ? 'current' : ''}" onClick=${() => onPick(slot)}
            title=${slot === SLOT_COUNT ? 'Neutral grey (past the eight-colour palette)' : `Palette colour ${slot + 1}`}>
            <span class="fill" style=${{ background: slotColor(slot) }} />
            ${taken.has(slot) && slot !== current && html`<span class="taken" />`}
          </button>`)}
      </div>
      <div class="hint">A dot marks a colour another activity already uses.</div>
    </div>
  `;
}

/** The inline `+` below the rows — a field you type into, never a dialog. */
/** The inline `+` below the rows. The folder button at its right end names a new folder. */
function AddActivityField({ onAdd, onAddFolder }) {
  const [mode, setMode] = useState(null); // 'activity' | 'folder' | null
  const [draft, setDraft] = useState('');
  const ref = useRef();

  useEffect(() => {
    if (mode) ref.current?.focus();
  }, [mode]);

  const collapse = () => {
    setDraft('');
    setMode(null);
  };

  const commit = () => {
    const t = draft.trim();
    if (mode === 'folder') {
      if (t) onAddFolder(t);
      return collapse();
    }
    if (t) onAdd(t);
    // Stay open — adding several in a row is the common case on first launch.
    setDraft('');
  };

  return html`
    <div class="add-field ${mode ? 'expanded' : ''}" onClick=${() => !mode && setMode('activity')}>
      ${mode === 'folder' ? html`<${FolderPlusGlyph} />` : html`<${PlusCircle} />`}
      ${mode
        ? html`<input ref=${ref} placeholder=${mode === 'folder' ? 'New folder' : 'New activity'} value=${draft}
            onInput=${(e) => setDraft(e.currentTarget.value)}
            onKeyDown=${(e) => {
              if (e.key === 'Enter') commit();
              if (e.key === 'Escape') collapse();
            }}
            onBlur=${() => !draft.trim() && collapse()} />`
        : html`<span>new activity</span>
            <span class="spacer" />
            <button class="add-folder" title="New folder"
              onClick=${(e) => { e.stopPropagation(); setMode('folder'); }}><${FolderPlusGlyph} /></button>`}
    </div>
  `;
}

// MARK: - History

/** Past weeks as small donuts, collapsed to a thin bar until you want it. */
function HistoryStrip({ weeks, selected, onSelect }) {
  const [expanded, setExpanded] = useState(false);
  const scroller = useRef();

  // Weeks run oldest → newest, so open at the right edge (this week).
  useLayoutEffect(() => {
    if (expanded && scroller.current) scroller.current.scrollLeft = scroller.current.scrollWidth;
  }, [expanded]);

  // A plain mouse wheel only scrolls vertically; turn it sideways here.
  const onWheel = (e) => {
    if (Math.abs(e.deltaY) > Math.abs(e.deltaX)) e.currentTarget.scrollLeft += e.deltaY;
  };

  return html`
    <div class="history">
      <button class="history-toggle" onClick=${() => setExpanded((v) => !v)}>
        <${Chevron} dir=${expanded ? 'down' : 'right'} size=${9} />
        <span class="grow">history</span>
        ${!expanded && html`
          <span class="minis">
            ${weeks.slice(-8).map((w) => html`
              <span key=${w.id} class=${w.totalMinutes === 0 ? 'faint' : ''}>
                <${Donut} slices=${w.slices} size=${16} compact />
              </span>`)}
          </span>`}
      </button>
      ${expanded && html`
        <div class="history-weeks" ref=${scroller} onWheel=${onWheel}>
          ${weeks.map((w) => html`
            <button key=${w.id} class="week-thumb ${w.id === selected ? 'selected' : ''}"
              title="Jump to ${w.label}" onClick=${() => onSelect(w.start)}>
              <span class=${w.totalMinutes === 0 ? 'faint' : ''}>
                <${Donut} slices=${w.slices} size=${34} compact />
              </span>
              <span class="label">${w.label}</span>
              <span class="mins num">${Duration.format(w.totalMinutes)}</span>
            </button>`)}
        </div>`}
    </div>
  `;
}

// MARK: - Friends (port of FriendsView.swift)

/**
 * A group's week as a leaderboard. It follows the week the window is on, so the
 * arrows move it like everything else.
 */
function FriendsView({ week }) {
  const friends = useFriends();
  // Starting or joining one more group, over the one on screen.
  const [adding, setAdding] = useState(false);
  const group = friends.current;
  // Keyed by group, so each starts fresh: nothing open, and its own drafts.
  return html`
    <div class="friends">
      ${group && !adding
        ? html`<${GroupPicker} onAdd=${() => setAdding(true)} />
          <${Leaderboard} key=${'board-' + group.code} standings=${friends.standings(week)} />
          <${GroupCard} key=${'card-' + group.code} group=${group} />`
        : html`<${JoinGroupCard} onDone=${() => setAdding(false)}
            onCancel=${friends.groups.length ? () => setAdding(false) : null} />`}
      ${friends.problem && html`<div class="friends-problem">⚠︎ ${friends.problem}</div>`}
    </div>
  `;
}

// MARK: - The global board

/**
 * The board everyone using TimePie can join: one week's totals, highest first. It follows
 * the week on screen, like the friends page. Joining asks for a name and spells out what
 * leaves the computer.
 */
function GlobalView({ week }) {
  const friends = useFriends();
  const me = friends.global;
  const weekKey = week.getTime();

  // Kept current while it's on screen, and fetched afresh for each week.
  useEffect(() => {
    if (!me) return;
    friends.refreshGlobal(week);
    const t = setInterval(() => friends.refreshGlobal(week), 60000);
    return () => clearInterval(t);
  }, [weekKey, !!me]);

  return html`
    <div class="friends">
      ${me
        ? html`<${GlobalBoard} board=${friends.globalBoard(week)} me=${me} />
          <${GlobalYouCard} me=${me} />`
        : html`<${JoinGlobalCard} />`}
      ${friends.problem && html`<div class="friends-problem">⚠︎ ${friends.problem}</div>`}
    </div>
  `;
}

function GlobalBoard({ board, me }) {
  const line = (place, name, total, isMe) => html`
    <div class="standing global-line ${isMe ? 'mine' : ''}">
      <div class="standing-summary">
        <span class="place num ${place === 1 ? 'first' : ''}">${place}</span>
        <span class="name ${isMe ? 'me' : ''}">${name}</span>
        ${isMe && html`<span class="you">You</span>`}
        <span class="spacer" />
        <span class="standing-total num">${Duration.format(total)}</span>
      </div>
    </div>`;
  if (!board) return html`<div class="card board"><div class="board-note">Loading…</div></div>`;
  const onTop = board.top.some((r) => r.id === me.memberID);
  return html`
    <div class="card board">
      ${board.top.map((r) => html`<div key=${r.id}>${line(r.place, r.name, r.total, r.id === me.memberID)}</div>`)}
      ${board.top.length === 0 && html`<div class="board-note">Nobody has logged time this week yet.</div>`}
      ${board.me && !onTop && html`
        <div class="global-gap">…</div>
        ${line(board.me.place, me.name, board.me.total, true)}`}
    </div>
    ${board.count > 0 && html`<div class="caption global-count">
      ${board.count === 1 ? '1 person' : `${board.count} people`} logged time this week</div>`}
  `;
}

/** The name you go by on the board, what it shows of you, and the way off it. */
function GlobalYouCard({ me }) {
  const friends = useFriends();
  const [name, setName] = useState(me.name);
  const [confirming, setConfirming] = useState(false);
  // Leaving the page keeps what you typed, as Enter would.
  const nameRef = useRef(name);
  nameRef.current = name;
  useEffect(() => () => friends.renameGlobal(nameRef.current), []);

  return html`
    <div class="card group-card">
      <label class="setting narrow">
        <span>Your name</span>
        <input class="field" value=${name} onInput=${(e) => setName(e.currentTarget.value)}
          onKeyDown=${(e) => e.key === 'Enter' && friends.renameGlobal(name)}
          onBlur=${() => friends.renameGlobal(name)} />
      </label>
      <div class="group-foot">
        <span class="caption">Shared with everyone: this name and your total time for each of the last 12 weeks.</span>
        <span class="spacer" />
        ${confirming
          ? html`<button class="btn" onClick=${() => setConfirming(false)}>Cancel</button>
            <button class="btn danger" onClick=${() => friends.leaveGlobal()}
              title="Your name and weekly totals are deleted from the server">Leave Leaderboard</button>`
          : html`<button class="btn danger" onClick=${() => setConfirming(true)}>Leave</button>`}
      </div>
    </div>
  `;
}

/** What joining means, before anything is sent. */
function JoinGlobalCard() {
  const friends = useFriends();
  // The name you go by in your groups, if you're in any.
  const [name, setName] = useState(() => friends.groups.at(-1)?.name ?? '');
  const hasName = name.trim().length > 0;
  const join = () => hasName && !friends.working && friends.joinGlobal(name);

  return html`
    <div class="card join-card">
      <div class="join-icon"><${TrophyGlyph} /></div>
      <div class="join-title">Leaderboard</div>
      <div class="join-text">See how your week compares with everyone using TimePie.</div>
      <div class="global-notice">
        <div class="global-notice-title">If you join, anyone using TimePie can see:</div>
        <div>• The name you enter below</div>
        <div>• Your total time for each of the last 12 weeks, kept up to date as you log</div>
        <div class="global-notice-never">Never what you worked on, how your time splits up, your entries
          or a running timer. Leaving deletes it all from the server.</div>
      </div>
      <label class="setting narrow">
        <span>Your name</span>
        <input class="field" placeholder="Shown to everyone" value=${name}
          onInput=${(e) => setName(e.currentTarget.value)}
          onKeyDown=${(e) => e.key === 'Enter' && join()} />
      </label>
      <button class="btn primary" disabled=${!hasName || friends.working} onClick=${join}>Join the Leaderboard</button>
      ${friends.working && html`<div class="caption">Working…</div>`}
    </div>
  `;
}

/** Which of your groups is on screen, and the way into another. */
function GroupPicker({ onAdd }) {
  const friends = useFriends();
  const groups = friends.groups;
  return html`
    <div class="group-picker">
      ${groups.length > 1 && groups.length <= 4 && html`
        <div class="segmented">
          ${groups.map((g) => html`
            <button key=${g.code} class=${g.code === friends.selectedCode ? 'on' : ''}
              onClick=${() => friends.select(g.code)}>${groupTitle(g)}</button>`)}
        </div>`}
      ${groups.length > 4 && html`
        <select class="field group-select" value=${friends.selectedCode}
          onChange=${(e) => friends.select(e.currentTarget.value)}>
          ${groups.map((g) => html`<option key=${g.code} value=${g.code}>${groupTitle(g)}</option>`)}
        </select>`}
      <span class="spacer" />
      <button class="btn" onClick=${onAdd} title="Start or join another group">+ Add Group</button>
    </div>
  `;
}

/** Ready for the donut. The ids only need to be stable within one person's week. */
const slicesOf = (standing) => (standing.week?.slices ?? []).map((s, i) => ({ id: i, ...s }));

function Leaderboard({ standings }) {
  const [expanded, setExpanded] = useState(() => new Set());
  const toggle = (id) => setExpanded((open) => {
    const next = new Set(open);
    next.has(id) ? next.delete(id) : next.add(id);
    return next;
  });

  return html`
    <div class="card board">
      ${standings.map((s) => html`
        <div key=${s.id} class="standing ${s.total === 0 ? 'zero' : ''}">
          <div class="standing-summary" onClick=${() => s.total > 0 && toggle(s.id)}
            title=${s.total > 0 ? 'Click to see their week' : 'Nothing logged this week'}>
            <span class="place num ${s.place === 1 ? 'first' : ''}">${s.place ?? '–'}</span>
            <${Donut} slices=${slicesOf(s)} size=${22} compact />
            <span class="name ${s.isMe ? 'me' : ''}">${s.name}</span>
            ${s.isMe && html`<span class="you">You</span>`}
            ${s.live && html`<${LiveBadge} live=${s.live} />`}
            <span class="spacer" />
            <span class="standing-total num">${Duration.format(s.total)}</span>
          </div>
          ${expanded.has(s.id) && s.total > 0 && html`<${Breakdown} standing=${s} />`}
        </div>`)}
      ${standings.length === 1 && html`
        <div class="board-note">Nobody else is here yet. Send your friends the group code below.</div>`}
    </div>
  `;
}

/** A timer someone has running right now, counting up. */
function LiveBadge({ live }) {
  const [now, setNow] = useState(Date.now());
  useEffect(() => {
    const t = setInterval(() => setNow(Date.now()), 1000);
    return () => clearInterval(t);
  }, []);
  return html`
    <span class="live" title="Timing this right now">
      <span class="dot" style=${{ background: slotColor(live.colorSlot) }} />
      ${live.name != null && html`<span class="what">${live.name}</span>`}
      <span class="num">${Duration.clock(Math.floor((now - live.startedAt) / 1000))}</span>
    </span>
  `;
}

/** One person's donut and what it's made of, biggest first. */
function Breakdown({ standing }) {
  const slices = slicesOf(standing);
  return html`
    <div class="breakdown">
      <${Donut} slices=${slices} size=${96} compact />
      <div class="breakdown-list">
        ${[...slices].sort((a, b) => b.minutes - a.minutes).map((s) => html`
          <div key=${s.id} class="breakdown-row">
            <span class="dot" style=${{ background: slotColor(s.colorSlot) }} />
            <span class="name ${s.name == null ? 'hidden-name' : ''}">${s.name ?? 'Hidden'}</span>
            <span class="spacer" />
            <span class="num">${Duration.format(s.minutes)}</span>
          </div>`)}
      </div>
    </div>
  `;
}

/**
 * The group on screen, how you appear in it, and the way out. Only the code shows until
 * you open the settings.
 */
function GroupCard({ group: s }) {
  const friends = useFriends();
  const [showingSettings, setShowingSettings] = useState(false);
  const [name, setName] = useState(s.name);
  const [label, setLabel] = useState(s.label ?? '');
  const [copied, setCopied] = useState(false);
  const drafts = useRef();
  drafts.current = { name, label };

  // Someone else renamed the group: follow them, unless you're typing a name yourself.
  const heardLabel = useRef(s.label ?? '');
  useEffect(() => {
    const now = s.label ?? '';
    if (label === heardLabel.current) setLabel(now);
    heardLabel.current = now;
  }, [s.label]);

  const commitDrafts = () => {
    friends.rename(s.code, drafts.current.name);
    friends.setLabel(s.code, drafts.current.label);
  };
  // Leaving the screen, or this group, keeps what you typed, as Enter would.
  useEffect(() => commitDrafts, []);
  // So does closing the settings.
  const toggleSettings = () => {
    if (showingSettings) commitDrafts();
    setShowingSettings(!showingSettings);
  };

  const copy = () => {
    api.copy(displayCode(s.code));
    setCopied(true);
    setTimeout(() => setCopied(false), 1500);
  };

  const leave = () => {
    if (confirm(`Leave ${groupTitle(s)}?\n\nYour weeks are removed from its leaderboard. You can join again with the code.`)) friends.leave();
  };
  const blurOnEnter = (e) => { if (e.key === 'Enter' || e.key === 'Escape') e.currentTarget.blur(); };

  return html`
    <div class="card group-card">
      <div class="group-head">
        <div>
          <div class="caption">Group code</div>
          <div class="code">${displayCode(s.code)}</div>
        </div>
        <span class="spacer" />
        <button class="btn" onClick=${copy}>${copied ? 'Copied' : 'Copy Code'}</button>
        <button class="btn" onClick=${() => api.openPage(friends.pageURL)}
          title="The same leaderboard as a web page, for checking on your phone">Open in Browser</button>
        <button class="btn icon" onClick=${toggleSettings}
          title=${showingSettings ? 'Hide group settings' : 'Group name, your name, and leaving'}>
          <span class="chevron ${showingSettings ? 'flipped' : ''}"><${Chevron} dir="down" /></span>
        </button>
      </div>
      ${showingSettings && html`
      <div class="divider" />
      <label class="setting" title="Everyone in the group sees this name">
        <span>Group name</span>
        <input class="field" placeholder=${displayCode(s.code)} value=${label}
          onInput=${(e) => setLabel(e.currentTarget.value)}
          onKeyDown=${blurOnEnter} onBlur=${() => friends.setLabel(s.code, label)} />
      </label>
      <label class="setting">
        <span>Your name</span>
        <input class="field" value=${name} onInput=${(e) => setName(e.currentTarget.value)}
          onKeyDown=${blurOnEnter} onBlur=${() => friends.rename(s.code, name)} />
      </label>
      <label class="setting" title="Friends still see your total and the coloured slices, but not what they're called">
        <span>Hide my activity names</span>
        <input type="checkbox" class="switch" checked=${s.hideNames}
          onChange=${(e) => friends.setHideNames(s.code, e.currentTarget.checked)} />
      </label>
      <div class="group-foot">
        <span class="caption">Shared: your name, the last 12 weeks’ totals per activity, and a running timer.</span>
        <span class="spacer" />
        <button class="btn danger" onClick=${leave}>Leave Group</button>
      </div>`}
    </div>
  `;
}

/**
 * Start a group, or join one with a code: the first, or one more. `onCancel` goes back
 * to the group on screen, and is null when there isn't one.
 */
function JoinGroupCard({ onDone, onCancel }) {
  const friends = useFriends();
  // The name you go by in your other groups, if you have any.
  const [name, setName] = useState(() => friends.groups.at(-1)?.name ?? '');
  const [code, setCode] = useState('');
  const hasName = name.trim().length > 0;
  const join = () => hasName && code && friends.join(code, name).then((ok) => ok && onDone());

  return html`
    <div class="card join-card">
      <div class="join-icon"><${PeopleGlyph} /></div>
      <div class="join-title">${onCancel ? 'Add another group' : 'Compare weeks with friends'}</div>
      <div class="join-text">Start a group and send its code to your friends, or join theirs.
        Only weekly totals are shared, never the individual entries.</div>
      <label class="setting narrow">
        <span>Your name</span>
        <input class="field" placeholder="Shown to the group" value=${name}
          onInput=${(e) => setName(e.currentTarget.value)} />
      </label>
      <button class="btn primary" disabled=${!hasName || friends.working}
        onClick=${() => friends.startGroup(name).then((ok) => ok && onDone())}>Start a Group</button>
      <div class="or"><span />or join one<span /></div>
      <div class="join-row">
        <input class="field code-field" placeholder="Group code" value=${code}
          onInput=${(e) => setCode(e.currentTarget.value)}
          onKeyDown=${(e) => e.key === 'Enter' && join()} />
        <button class="btn" disabled=${!hasName || !code || friends.working} onClick=${join}>Join</button>
      </div>
      ${friends.working && html`<div class="caption">Working…</div>`}
      ${onCancel && html`<button class="btn" onClick=${onCancel}>Cancel</button>`}
    </div>
  `;
}

render(html`<${App} />`, document.getElementById('root'));
