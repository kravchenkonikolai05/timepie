// Port of Models.swift, WeekMath.swift and Store.swift. The JSON on disk is the
// same format the Mac app writes, so files can move between the two.

// MARK: - Weeks (start on Monday, local time)

export function startOfDay(d) {
  const x = new Date(d);
  x.setHours(0, 0, 0, 0);
  return x;
}

export function addDays(n, d) {
  const x = new Date(d);
  x.setDate(x.getDate() + n);
  return x;
}

export const addWeeks = (n, d) => addDays(7 * n, d);

export function weekStart(d) {
  const x = startOfDay(d);
  return addDays(-((x.getDay() + 6) % 7), x);
}

export const weekEnd = (d) => addDays(7, weekStart(d));
export const isSameWeek = (a, b) => weekStart(a).getTime() === weekStart(b).getTime();

export function monthStart(d) {
  const x = startOfDay(d);
  x.setDate(1);
  return x;
}

export function addMonths(n, d) {
  const x = new Date(d);
  x.setDate(1);
  x.setMonth(x.getMonth() + n);
  // Keep the day where the month has it, else the month's last day (Jan 31 → Feb 28).
  const last = new Date(x.getFullYear(), x.getMonth() + 1, 0).getDate();
  x.setDate(Math.min(new Date(d).getDate(), last));
  return x;
}

/** The first day of the next month. */
export const monthEnd = (d) => addMonths(1, monthStart(d));

/** Whole days from one start-of-day to another. */
/** Days of a week counted so far: up to and including today in this week, all seven in a past one, none in one to come. */
export const daysElapsed = (week, today) => Math.min(7, Math.max(0, daysBetween(weekStart(week), today) + 1));

export const daysBetween = (a, b) => Math.round((startOfDay(b) - startOfDay(a)) / 86400000);

const monthShort = (d) => d.toLocaleDateString(undefined, { month: 'short' });

/** "Sep 15 – 21" / "Sep 29 – Oct 5" */
export function weekLabel(d) {
  const start = weekStart(d);
  const end = addDays(6, start);
  return start.getMonth() === end.getMonth()
    ? `${monthShort(start)} ${start.getDate()} – ${end.getDate()}`
    : `${monthShort(start)} ${start.getDate()} – ${monthShort(end)} ${end.getDate()}`;
}

// MARK: - Calendar dates on disk ("2026-09-16"), never timestamps — they can't drift.

export const DayStamp = {
  string(d) {
    return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
  },
  parse(raw) {
    const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(raw ?? '');
    if (m) return new Date(+m[1], +m[2] - 1, +m[3]);
    // Legacy timestamps: the stored instant was local midnight.
    const t = Date.parse(raw);
    return startOfDay(Number.isNaN(t) ? new Date() : new Date(t));
  },
};

/** ISO-8601 without fractional seconds — what Swift's `.iso8601` strategy reads. */
const isoNow = () => new Date().toISOString().replace(/\.\d{3}Z$/, 'Z');
const newID = () => crypto.randomUUID().toUpperCase();

// MARK: - Durations read as "8h 30m"

export const Duration = {
  format(minutes) {
    const m = Math.max(0, minutes);
    const h = Math.floor(m / 60);
    const mins = m % 60;
    if (h === 0) return `${mins}m`;
    if (mins === 0) return `${h}h`;
    return `${h}h ${mins}m`;
  },

  /** Hours to one decimal, roughly: "~3,5h", "~2h" — in the user's own number style. */
  approxHours(minutes) {
    const h = Math.max(0, minutes) / 60;
    return `~${new Intl.NumberFormat(undefined, { maximumFractionDigits: 1 }).format(h)}h`;
  },

  /** A running stopwatch: "12:34", or "1:02:15" once it passes an hour. */
  clock(seconds) {
    const s = Math.max(0, seconds);
    const h = Math.floor(s / 3600);
    const m = Math.floor((s % 3600) / 60);
    const sec = s % 60;
    const pad = (n) => String(n).padStart(2, '0');
    return h > 0 ? `${h}:${pad(m)}:${pad(sec)}` : `${m}:${pad(sec)}`;
  },

  /** Accepts "1h45", "1h 45m", "90", "90m", "1.5h", "2h". */
  parse(raw) {
    const toInt = (s) => (/^[+-]?\d+$/.test(s) ? parseInt(s, 10) : null);
    const toDouble = (s) => (/^[+-]?(\d+\.?\d*|\.\d+)$/.test(s) ? parseFloat(s) : null);

    const s = raw.toLowerCase().trim();
    if (!s) return null;

    const hIndex = s.indexOf('h');
    if (hIndex >= 0) {
      const hours = toDouble(s.slice(0, hIndex).trim());
      const rest = s.slice(hIndex + 1).replaceAll('m', '').trim();
      if (hours === null) return null;
      const extra = rest ? (toInt(rest) ?? 0) : 0;
      return Math.round(hours * 60) + extra;
    }

    const cleaned = s.replaceAll('m', '').trim();
    const mins = toInt(cleaned);
    if (mins !== null) return mins;
    const dec = toDouble(cleaned);
    return dec === null ? null : Math.round(dec * 60);
  },
};

// MARK: - Palette slots

export const SLOT_COUNT = 8;

/** Lowest slot not already taken, else overflow grey. */
export function nextSlot(taken) {
  for (let slot = 0; slot < SLOT_COUNT; slot++) if (!taken.includes(slot)) return slot;
  return SLOT_COUNT;
}

// MARK: - Store

/**
 * Everything lives in one human-readable JSON file, held in memory and rewritten on
 * every change. Entries keep `day` as its "yyyy-MM-dd" string; those compare correctly
 * as plain strings, so a week is just a string range.
 */
export class Store {
  activities = [];
  entries = [];
  folders = [];
  #undoStack = [];
  #undoLimit = 50;
  #listeners = new Set();
  #persist;

  constructor(json, persist) {
    this.#persist = persist;
    if (!json) return;
    try {
      const payload = JSON.parse(json);
      this.activities = payload.activities ?? [];
      this.folders = payload.folders ?? [];
      this.entries = (payload.entries ?? []).map((e) => ({ ...e, day: DayStamp.string(DayStamp.parse(e.day)) }));
    } catch {
      return;
    }
    // "Delete" used to mean "archive"; anything still archived is purged.
    const archived = new Set(this.activities.filter((a) => a.archived).map((a) => a.id));
    if (archived.size) {
      this.activities = this.activities.filter((a) => !archived.has(a.id));
      this.entries = this.entries.filter((e) => !archived.has(e.activityID));
      this.#save();
    }
  }

  subscribe(fn) {
    this.#listeners.add(fn);
    return () => this.#listeners.delete(fn);
  }

  get canUndo() {
    return this.#undoStack.length > 0;
  }

  get payload() {
    return { activities: this.activities, entries: this.entries, folders: this.folders, version: 1 };
  }

  #save() {
    this.#persist(JSON.stringify(sortKeys(this.payload), null, 2));
    this.#listeners.forEach((fn) => fn());
  }

  /** Snapshot, mutate, persist — the single path every edit takes. */
  #mutate(block) {
    this.#undoStack.push(structuredClone({ activities: this.activities, entries: this.entries, folders: this.folders }));
    if (this.#undoStack.length > this.#undoLimit) this.#undoStack.shift();
    block();
    this.#save();
  }

  undo() {
    const previous = this.#undoStack.pop();
    if (!previous) return;
    this.activities = previous.activities;
    this.entries = previous.entries;
    // Showing or hiding a folder's tasks isn't an edit, so undo leaves it alone.
    const collapsed = new Map(this.folders.map((f) => [f.id, f.collapsed]));
    this.folders = previous.folders.map((f) => ({ ...f, collapsed: collapsed.get(f.id) ?? f.collapsed }));
    this.#save();
  }

  // MARK: Reading

  get visibleActivities() {
    return this.activities.filter((a) => !a.archived).sort((a, b) => a.sortIndex - b.sortIndex);
  }

  /** Everything started on or before this week, plus anything with time logged in it. */
  activitiesForWeek(start) {
    const logged = new Set(this.entriesIn(start, weekEnd(start)).map((e) => e.activityID));
    const startMs = start.getTime();
    return this.visibleActivities.filter((a) => {
      if (a.endWeek && weekStart(DayStamp.parse(a.endWeek)).getTime() <= startMs) return false;
      return this.#firstWeekStart(a).getTime() <= startMs || logged.has(a.id);
    });
  }

  /**
   * The week's list as drawn: folders and loose tasks in order, each folder with the
   * tasks it holds that week. A folder shows from the week it was made, and in any
   * earlier week that has one of its tasks.
   * Items are { kind: 'folder', id, folder, tasks } or { kind: 'activity', id, activity }.
   */
  outlineForWeek(start) {
    const tasks = this.activitiesForWeek(start);
    const known = new Set(this.folders.map((f) => f.id));
    const startMs = start.getTime();
    const shown = this.folders.filter((f) =>
      this.#firstWeekStart(f).getTime() <= startMs || tasks.some((a) => a.folderID === f.id));
    return [
      ...shown.map((f) => [f.sortIndex, { kind: 'folder', id: f.id, folder: f, tasks: tasks.filter((a) => a.folderID === f.id) }]),
      ...tasks.filter((a) => !known.has(a.folderID)).map((a) => [a.sortIndex, { kind: 'activity', id: a.id, activity: a }]),
    ].sort((x, y) => x[0] - y[0]).map((x) => x[1]);
  }

  /**
   * One group of siblings' ids in order: the top level (folders and loose tasks) when
   * `parent` is null, otherwise that folder's tasks. With a week, only what it shows.
   */
  #siblings(parent, week) {
    if (week) {
      const items = this.outlineForWeek(weekStart(week));
      if (!parent) return items.map((x) => x.id);
      return items.find((x) => x.id === parent)?.tasks.map((a) => a.id) ?? [];
    }
    if (parent) return this.visibleActivities.filter((a) => a.folderID === parent).map((a) => a.id);
    const known = new Set(this.folders.map((f) => f.id));
    return [...this.folders, ...this.visibleActivities.filter((a) => !known.has(a.folderID))]
      .sort((x, y) => x.sortIndex - y.sortIndex)
      .map((x) => x.id);
  }

  /** Every task in the order the lists draw them, ignoring weeks. */
  get orderedActivities() {
    const tasks = this.visibleActivities;
    const known = new Set(this.folders.map((f) => f.id));
    return [
      ...this.folders.map((f) => [f.sortIndex, tasks.filter((a) => a.folderID === f.id)]),
      ...tasks.filter((a) => !known.has(a.folderID)).map((a) => [a.sortIndex, [a]]),
    ].sort((x, y) => x[0] - y[0]).flatMap((x) => x[1]);
  }

  entriesIn(start, end) {
    const lo = DayStamp.string(start);
    const hi = DayStamp.string(end);
    return this.entries.filter((e) => e.day >= lo && e.day < hi);
  }

  minutes(activityID, start, end) {
    return this.entriesIn(start, end)
      .filter((e) => e.activityID === activityID)
      .reduce((sum, e) => sum + e.minutes, 0);
  }

  /** Every activity's time between two days, in one pass over the entries. */
  minutesByActivity(start, end) {
    const out = new Map();
    for (const e of this.entriesIn(start, end)) out.set(e.activityID, (out.get(e.activityID) ?? 0) + e.minutes);
    return out;
  }

  /** Each day's time between two days, keyed by its "2026-09-16" stamp. */
  minutesByDay(start, end) {
    const known = new Set(this.activities.map((a) => a.id));
    const out = new Map();
    for (const e of this.entriesIn(start, end)) {
      if (known.has(e.activityID)) out.set(e.day, (out.get(e.day) ?? 0) + e.minutes);
    }
    return out;
  }

  /** The first and last day anything was logged on, or null before anything has been. */
  get loggedSpan() {
    if (!this.entries.length) return null;
    const days = this.entries.map((e) => e.day).sort();
    return { first: DayStamp.parse(days[0]), last: DayStamp.parse(days.at(-1)) };
  }

  /** Only activities that still exist, so the header can't disagree with the donut. */
  totalMinutes(start, end) {
    const known = new Set(this.activities.map((a) => a.id));
    const sum = this.entriesIn(start, end)
      .filter((e) => known.has(e.activityID))
      .reduce((s, e) => s + e.minutes, 0);
    return Math.max(0, sum);
  }

  // MARK: Writing

  #entry(activityID, day, minutes, isAdjustment) {
    return { id: newID(), activityID, day: DayStamp.string(day), minutes, isAdjustment, createdAt: isoNow() };
  }

  add(minutes, activityID, day) {
    this.#mutate(() => this.entries.push(this.#entry(activityID, day, minutes, false)));
  }

  /**
   * A timer session, split at each midnight it ran past: 23:00 to 01:00 is an hour on
   * each day, and a session over Sunday night counts toward both weeks. The pieces are
   * rounded so they always add up to the session's rounded length.
   */
  logSession(activityID, start, end) {
    const pieces = [];
    let dayStart = new Date(start);
    let loggedSoFar = 0;
    while (dayStart < end) {
      const upTo = new Date(Math.min(addDays(1, startOfDay(dayStart)).getTime(), end.getTime()));
      const total = Math.round((upTo - start) / 60000);
      if (total > loggedSoFar) {
        pieces.push([startOfDay(dayStart), total - loggedSoFar]);
        loggedSoFar = total;
      }
      dayStart = upTo;
    }
    // Anything under half a minute rounds to nothing and isn't worth an entry.
    if (!pieces.length) return;
    this.#mutate(() => pieces.forEach(([d, m]) => this.entries.push(this.#entry(activityID, d, m, false))));
  }

  /**
   * The typed value is a week *total*; the difference is written as adjustments. Time
   * added goes on the logging day. Time taken away takes back the most recently logged
   * time first — lowering a total is nearly always correcting something you just did,
   * like a click too many or a timer left running — and never takes a day below zero.
   */
  setTotal(target, activityID, start, end, day) {
    const delta = Math.max(0, target) - this.minutes(activityID, start, end);
    if (delta === 0) return;
    let changes = [[day, delta]];
    if (delta < 0) {
      const logged = this.entriesIn(start, end).filter((e) => e.activityID === activityID);
      const byDay = new Map();
      for (const e of logged) byDay.set(e.day, (byDay.get(e.day) ?? 0) + e.minutes);
      const taken = new Map();
      let left = -delta;
      // Times only keep whole seconds, so ties (a session's pieces, quick clicks) go by
      // the order they were logged in.
      const newestFirst = logged.map((e, i) => [e, i])
        .sort(([a, i], [b, j]) => Date.parse(b.createdAt) - Date.parse(a.createdAt) || j - i)
        .map(([e]) => e);
      for (const e of newestFirst) {
        if (left <= 0) break;
        if (e.minutes <= 0) continue;
        const take = Math.min(e.minutes, byDay.get(e.day) ?? 0, left);
        if (take <= 0) continue;
        taken.set(e.day, (taken.get(e.day) ?? 0) + take);
        byDay.set(e.day, byDay.get(e.day) - take);
        left -= take;
      }
      changes = [...taken].sort(([a], [b]) => (a < b ? -1 : 1)).map(([d, m]) => [DayStamp.parse(d), -m]);
    }
    this.#mutate(() => changes.forEach(([d, m]) => this.entries.push(this.#entry(activityID, d, m, true))));
  }

  /** Takes back one logged amount, from the log. */
  deleteEntry(id) {
    if (!this.entries.some((e) => e.id === id)) return;
    this.#mutate(() => {
      this.entries = this.entries.filter((e) => e.id !== id);
    });
  }

  /** Puts an entry on another day; when it was added stays. */
  moveEntry(id, day) {
    const stamp = DayStamp.string(day);
    const entry = this.entries.find((e) => e.id === id);
    if (!entry || entry.day === stamp) return;
    this.#mutate(() => {
      this.entries = this.entries.map((e) => (e.id === id ? { ...e, day: stamp } : e));
    });
  }

  addActivity(name, inWeek) {
    this.#mutate(() => {
      const taken = this.activitiesForWeek(inWeek).map((a) => a.colorSlot);
      const nextIndex = this.#nextSortIndex();
      this.activities.push({
        id: newID(),
        name,
        colorSlot: nextSlot(taken),
        sortIndex: nextIndex,
        archived: false,
        createdAt: isoNow(),
        firstWeek: DayStamp.string(weekStart(inWeek)),
      });
    });
  }

  #update(id, fields) {
    const i = this.activities.findIndex((a) => a.id === id);
    if (i < 0) return;
    this.#mutate(() => {
      this.activities[i] = { ...this.activities[i], ...fields };
    });
  }

  setColor(id, slot) {
    this.#update(id, { colorSlot: slot });
  }

  rename(id, name) {
    this.#update(id, { name });
  }

  /** New things go to the bottom of the list. */
  #nextSortIndex() {
    return Math.max(-1, ...this.activities.map((a) => a.sortIndex), ...this.folders.map((f) => f.sortIndex)) + 1;
  }

  addFolder(name, inWeek) {
    this.#mutate(() => {
      this.folders.push({
        id: newID(),
        name,
        sortIndex: this.#nextSortIndex(),
        collapsed: false,
        createdAt: isoNow(),
        firstWeek: DayStamp.string(weekStart(inWeek)),
      });
    });
  }

  renameFolder(id, name) {
    if (!this.folders.some((f) => f.id === id)) return;
    this.#mutate(() => {
      this.folders = this.folders.map((f) => (f.id === id ? { ...f, name } : f));
    });
  }

  /** Hiding or showing a folder's tasks is a view preference, so it skips undo. */
  setCollapsed(id, collapsed) {
    this.folders = this.folders.map((f) => (f.id === id ? { ...f, collapsed } : f));
    this.#save();
  }

  /** Deleting a folder keeps its tasks: they move out to the top level, in its place. */
  deleteFolder(id) {
    if (!this.folders.some((f) => f.id === id)) return;
    const tasks = this.#siblings(id, null);
    const top = this.#siblings(null, null).flatMap((x) => (x === id ? tasks : [x]));
    this.#mutate(() => {
      this.folders = this.folders.filter((f) => f.id !== id);
      this.activities = this.activities.map((a) => (a.folderID === id ? { ...a, folderID: null } : a));
      this.#renumber(top);
    });
  }

  /**
   * Moves a task or folder to `index` among what this week shows in `parent` — a
   * folder's id, or null for the top level. Folders only live at the top level.
   *
   * There is a single order shared by every week, so the item is placed beside the
   * same neighbour in the full list. Items this week doesn't show keep their places.
   */
  move(id, parent, index, inWeek) {
    const isFolder = this.folders.some((f) => f.id === id);
    const activity = this.activities.find((a) => a.id === id);
    if (!isFolder && !activity) return;
    if (isFolder) parent = null;
    parent = parent ?? null;

    const shown = this.#siblings(parent, inWeek).filter((x) => x !== id);
    const all = this.#siblings(parent, null).filter((x) => x !== id);
    const k = Math.min(Math.max(index, 0), shown.length);
    const at = k < shown.length
      ? all.indexOf(shown[k])
      : shown.length ? all.indexOf(shown[shown.length - 1]) + 1 : all.length;
    all.splice(at < 0 ? all.length : at, 0, id);

    const current = this.#siblings(parent, null);
    const sameOrder = all.length === current.length && all.every((x, i) => x === current[i]);
    if ((activity?.folderID ?? null) === parent && sameOrder) return;
    this.#mutate(() => {
      if (activity) this.activities = this.activities.map((a) => (a.id === id ? { ...a, folderID: parent } : a));
      this.#renumber(all);
    });
  }

  /** Sort indices only matter among siblings, so one group is renumbered at a time. */
  #renumber(ids) {
    const order = new Map(ids.map((x, i) => [x, i]));
    const apply = (x) => (order.has(x.id) ? { ...x, sortIndex: order.get(x.id) } : x);
    this.activities = this.activities.map(apply);
    this.folders = this.folders.map(apply);
  }

  #firstWeekStart(a) {
    return weekStart(a.firstWeek ? DayStamp.parse(a.firstWeek) : new Date(a.createdAt));
  }

  /**
   * Removes the activity from this week and every later one, with the time logged there.
   * Earlier weeks keep the row and their hours; if no earlier week ever showed it, it
   * goes entirely. Undo restores all of it.
   */
  delete(id, fromWeek) {
    const activity = this.activities.find((a) => a.id === id);
    if (!activity) return;
    const start = weekStart(fromWeek);
    const startDay = DayStamp.string(start);
    const shownEarlier = this.#firstWeekStart(activity).getTime() < start.getTime()
      || this.entries.some((e) => e.activityID === id && e.day < startDay);
    this.#mutate(() => {
      this.entries = this.entries.filter((e) => e.activityID !== id || e.day < startDay);
      this.activities = shownEarlier
        ? this.activities.map((a) => (a.id === id ? { ...a, endWeek: startDay } : a))
        : this.activities.filter((a) => a.id !== id);
    });
  }
}

/** Matches the Mac app's `.sortedKeys` output so diffs between the two stay clean. */
function sortKeys(value) {
  if (Array.isArray(value)) return value.map(sortKeys);
  if (value && typeof value === 'object') {
    return Object.fromEntries(Object.keys(value).sort().map((k) => [k, sortKeys(value[k])]));
  }
  return value;
}

// MARK: - The stats page's span (port of StatsSelection.swift)

/**
 * The stretch of days the stats page shows, and how clicks on its calendar move it.
 * A click shows that day. In Interval, clicks come in pairs instead: the first day,
 * then the last, and the click after that starts the next interval.
 * Each function returns a new selection.
 */
export const Stats = {
  modes: [['day', 'Day'], ['month', 'Month'], ['interval', 'Interval'], ['allTime', 'All Time']],

  initial(today = new Date()) {
    const day = startOfDay(today);
    // `focus` is the day last clicked: where Day and Interval begin when picked.
    // `anchored`: an interval's first day was just clicked, so the next click ends it.
    return { mode: 'day', start: day, end: day, shownMonth: monthStart(day), focus: day, anchored: false };
  },

  dayCount: (s) => daysBetween(s.start, s.end) + 1,

  /**
   * How the breakdown reads: the whole stretch, or a typical day, week or month of it,
   * with how many days one of each is. A month is an average one.
   */
  averages: [['total', 'Total', 0], ['day', 'Per Day', 1], ['week', 'Per Week', 7], ['month', 'Per Month', 365.2425 / 12]],

  /**
   * The days an average is taken over: the selected ones you could have logged, so
   * neither days still to come nor days from before you started count as zero.
   */
  countedDays(s, logged, today = new Date()) {
    if (!logged) return 0;
    const first = logged.first > s.start ? logged.first : s.start;
    const day = startOfDay(today);
    const lastLoggable = logged.last > day ? logged.last : day;
    const last = lastLoggable < s.end ? lastLoggable : s.end;
    return Math.max(0, daysBetween(first, last) + 1);
  },

  /** The averages worth offering over `counted` days: each needs at least two of its unit. */
  averagesFor: (counted) => Stats.averages.filter(([key, , days]) => key === 'total' || counted >= 2 * days),

  /** `minutes` over `counted` days, as a typical `average`. */
  averaged(minutes, counted, average) {
    const days = Stats.averages.find(([key]) => key === average)?.[2] ?? 0;
    if (!days || counted <= 0) return minutes;
    return Math.round((minutes * days) / counted);
  },

  /** What the next click does, while that isn't obvious. */
  hint(s) {
    if (s.mode === 'interval' && !s.anchored && s.start.getTime() === s.end.getTime()) return 'Click the first day';
    if (s.mode === 'interval' && s.anchored) return 'Click the last day';
    return null;
  },

  click(s, date) {
    const day = startOfDay(date);
    if (s.mode === 'interval' && s.anchored) {
      if (day.getTime() === s.start.getTime()) return s;
      const [start, end] = day < s.start ? [day, s.start] : [s.start, day];
      return { ...s, start, end, focus: day, anchored: false };
    }
    // Outside Interval a click is just that day, even from Month or All Time.
    const mode = s.mode === 'interval' ? 'interval' : 'day';
    return { ...s, mode, start: day, end: day, focus: day, anchored: mode === 'interval' };
  },

  /** `logged` is the first and last day with time on it, for All Time. */
  pick(s, mode, logged, today = new Date()) {
    const next = { ...s, mode, anchored: false };
    if (mode === 'allTime') {
      const day = startOfDay(today);
      next.start = logged && logged.first < day ? logged.first : day;
      next.end = logged && logged.last > day ? logged.last : day;
      return next;
    }
    if (mode === 'month') {
      next.start = s.shownMonth;
      next.end = addDays(-1, monthEnd(s.shownMonth));
    } else {
      next.start = s.focus;
      next.end = s.focus;
    }
    next.shownMonth = monthStart(next.start);
    return next;
  },

  /** The previous or next day, month or interval of the same length. */
  step(s, n) {
    let start, end;
    if (s.mode === 'day') {
      start = end = addDays(n, s.start);
    } else if (s.mode === 'month') {
      start = addMonths(n, s.start);
      end = addDays(-1, monthEnd(start));
    } else if (s.mode === 'interval') {
      const length = Stats.dayCount(s);
      start = addDays(n * length, s.start);
      end = addDays(n * length, s.end);
    } else {
      return s;
    }
    return { ...s, start, end, focus: start, anchored: false, shownMonth: monthStart(start) };
  },

  /** The step the arrows take, for their labels. */
  unitName: (s) => ({ day: 'day', month: 'month' })[s.mode] ?? 'interval',

  /** "Today", "Mon, Oct 26", "October 2026", "Oct 3 – 17", "All Time". */
  title(s) {
    if (s.mode === 'allTime') return 'All Time';
    if (s.mode === 'month') return s.start.toLocaleDateString(undefined, { month: 'long', year: 'numeric' });
    const thisYear = new Date().getFullYear();
    if (s.start.getTime() === s.end.getTime()) {
      const today = startOfDay(new Date());
      if (s.start.getTime() === today.getTime()) return 'Today';
      if (s.start.getTime() === addDays(-1, today).getTime()) return 'Yesterday';
      return s.start.getFullYear() === thisYear
        ? s.start.toLocaleDateString(undefined, { weekday: 'short', month: 'short', day: 'numeric' })
        : s.start.toLocaleDateString(undefined, { month: 'short', day: 'numeric', year: 'numeric' });
    }
    // Left to the system, which knows how a range of dates reads in your language.
    const sameYear = s.start.getFullYear() === thisYear && s.end.getFullYear() === thisYear;
    return new Intl.DateTimeFormat(undefined, { month: 'short', day: 'numeric', ...(sameYear ? {} : { year: 'numeric' }) })
      .formatRange(s.start, s.end);
  },
};

// MARK: - Settings

/** Preferences, kept on this computer. Each one is a key here and a row on the settings page. */
export const Settings = {
  defaults: { showDayAverage: false },
  load() {
    try { return { ...this.defaults, ...JSON.parse(localStorage.getItem('settings') || '{}') }; }
    catch { return { ...this.defaults }; }
  },
  save(settings) {
    try { localStorage.setItem('settings', JSON.stringify(settings)); } catch {}
  },
};
