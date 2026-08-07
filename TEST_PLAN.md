# Stillhabit — Manual Test Plan

Work top to bottom. Each item is a checkbox with the exact steps and what you should see.
Best run on a real device (notifications, haptics, and widgets behave more honestly there),
with a second pass on the simulator for the paywall lock timing.

**Legend:** ✅ = pass, ❌ = fail (note what happened), ➖ = skipped

---

## 1. First launch & grace period

- [ ] **Fresh install** — Delete the app, reinstall, open it.
  *Expect:* Today screen with the leaf empty state ("A quiet place for daily rituals") and a "Begin your first habit" button. No paywall.
- [ ] **Grace countdown** — Open Settings (slider icon).
  *Expect:* Subscription section reads "Everything unlocked for now"; an hourglass footnote at the bottom shows the time remaining in the 72-hour window.
- [ ] **Grace unlocks everything** — During the window: add a 4th habit, check the color picker shows the extended premium palette.
  *Expect:* No paywall anywhere; full palette available.

## 2. Adding habits

- [ ] **Basic add** — Tap "+", type a name, tap Begin.
  *Expect:* Sheet closes once; habit appears in the list with the chosen color.
- [ ] **Double-tap safety** — On a new habit, tap "Begin" twice fast.
  *Expect:* Exactly one habit created, no crash.
- [ ] **The Why** — Add a habit with a "Why" line.
  *Expect:* The italic why text appears on the card at the right moment (before logging).
- [ ] **Color palette** — Pick each swatch; confirm selection ring follows.
- [ ] **Cadence: Daily** — Create one. *Expect:* appears every day.
- [ ] **Cadence: Specific days** — Pick only today's weekday + one other. *Expect:* shows today. Then create one that excludes today. *Expect:* it does NOT appear in the Today list.
- [ ] **Cadence: Weekly target** — Set "3× per week". *Expect:* appears daily until 3 completions this week, then shows as met.
- [ ] **Type: Check-in** — One tap completes the day.
- [ ] **Type: Numeric** — Set e.g. 64 oz water. *Expect:* quick-add pills increment progress; day completes when target is reached.
- [ ] **Type: Duration** — Set e.g. 5 min. Start the timer, background the app for a minute, return.
  *Expect:* elapsed time stayed accurate; day completes at the target.
- [ ] **Empty title** — "Begin" with a blank/whitespace name. *Expect:* nothing saved.

## 3. Today list

- [ ] **Complete / un-complete** — Tap a habit done, then undo it.
  *Expect:* progress bar and "X of Y" update; completion sound/haptic plays on complete.
- [ ] **Progress bar** — Completes proportionally; shows "— a quiet day, well kept" at 100%.
- [ ] **Sort: Manual + drag reorder** — Settings → Today's Order → Manual. Long-press-drag a card to a new spot. Kill and relaunch the app.
  *Expect:* order persists.
- [ ] **Sort: Incomplete first / Completed first** — Switch modes.
  *Expect:* list regroups; drag reorder is disabled outside Manual.
- [ ] **Week dot calendar** — 7 dots under the header; today ringed in sage; filled dots match past completions. Tap the row.
  *Expect:* Weekly analytics sheet opens.
- [ ] **Still Moment** — Complete every scheduled habit for today.
  *Expect:* singing-bowl chime, warm glow blooming over the background, heartbeat haptic, centered "Everything is still." message; everything settles back after ~4 s. Un-complete one habit and re-complete it — the moment plays again.
- [ ] **Still Moment is Pro-gated** — With grace expired and no subscription (see §7), complete all habits.
  *Expect:* day completes, bar fills, but no chime/glow.

## 4. Habit detail

- [ ] **Open** — Tap a habit card. *Expect:* detail sheet: month rhythm grid, 90-day heatmap, insights, three stats (current streak, best streak, total).
- [ ] **Heatmap tap** — Toggle a past day on the heatmap. *Expect:* streaks recompute live.
- [ ] **Edit schedule** — Change cadence in detail. *Expect:* Today list reflects it immediately; history preserved.
- [ ] **Edit reminder** — Enable a reminder, change time/sound/haptic. *Expect:* saved and rescheduled (verify in §8).
- [ ] **Deleted underneath** — Open detail, then (widget or second device not needed — just check) the sheet closes itself gracefully if the habit is deleted; no crash.

## 5. Rest, delete & resting habits

- [ ] **Rest** — Swipe/use the card action to rest a habit. *Expect:* leaves Today; "Resting · N" link appears at the bottom.
- [ ] **Resting sheet** — Open it; wake the habit back up. *Expect:* returns to Today with history intact.
- [ ] **Delete** — Delete a habit with a reminder set. *Expect:* gone from list; its notification never fires again.

## 6. Settings

- [ ] **Appearance** — Switch System / Light / Dark. *Expect:* whole app (including sheets and paywall) follows instantly; persists across relaunch.
- [ ] **Ambient sound** — Select Forest, then Rain. *Expect:* audio plays immediately; volume slider works; "Loop continuously" off = plays once then silence; Off disables the controls.
- [ ] **Ambient pause** — With sound on, background the app. *Expect:* audio pauses; resumes on return.
- [ ] **Manage Subscription** — Opens Apple's subscriptions page.
- [ ] **Restore Purchases** — With no purchase: *Expect:* "No previous purchases were found for this account."
- [ ] **Send Feedback** — Tap it. *Expect:* mail composer addressed to **support@atkinsmedia.io**, subject "Stillhabit feedback".
- [ ] **Erase All Habits & Data** — Tap, confirm.
  *Expect:* confirmation alert first; after confirming, all habits gone, "A clean slate." footer, sheet closes itself, grace window restarts, widgets clear.

## 7. Paywall & subscription

> To simulate grace expiry: Settings app → General → Date & Time → set the date 4+ days forward, then relaunch Stillhabit. (Or wait 72 h.)

- [ ] **Habit-limit trigger** — With grace expired and 3 active habits, tap "+".
  *Expect:* full-screen paywall (not a swipeable sheet — try swiping down; it must not dismiss).
- [ ] **Launch lock** — With grace expired, cold-launch the app.
  *Expect:* paywall covers the screen a moment after launch.
- [ ] **Editorial layout** — "Keep your quiet space." serif headline, italic subheadline, 4 sage-checkmark lines, Yearly card (sage border + BEST VALUE pill + savings line) above Monthly, footer links at 10 pt.
- [ ] **Plan selection** — Tap each card. *Expect:* selection haptic; sage border thickens + soft tint; renewal line under the button updates to the right price/period.
- [ ] **Close (free tier)** — Tap the faint ✕ top-left.
  *Expect:* returns to Today read-only-ish free tier (3-habit limit, base palette); paywall does not immediately reappear this session, but returns on next cold launch.
- [ ] **Legal links** — Terms opens Apple's EULA; Privacy opens the privacy page. ⚠️ Privacy URL must be live before App Review.
- [ ] **Purchase (sandbox)** — Use a Sandbox Apple ID / TestFlight. Buy Monthly, or Yearly on a second run.
  *Expect:* Apple sheet → success → paywall dismisses itself.
- [ ] **Post-purchase celebration** — Immediately after the paywall closes.
  *Expect:* two soft sage ripples + drifting petals over Today, heartbeat haptic, "Your quiet space is kept. / Welcome to Stillhabit Pro"; fades out on its own ~4 s; list stays tappable throughout.
- [ ] **No celebration on relaunch** — Kill and relaunch as a subscriber. *Expect:* NO celebration, no paywall; Settings reads "Stillhabit Pro — active".
- [ ] **Pro perks** — 4th habit allowed; premium palette back; Still Moment plays again.
- [ ] **Restore path** — Delete & reinstall (same sandbox account) → paywall → Restore Purchases. *Expect:* unlocks without charging.
- [ ] **Purchase cancelled** — Start a purchase, cancel the Apple sheet. *Expect:* no error alert, paywall stays, nothing unlocked.

## 8. Reminders & notifications

- [ ] **Permission ask** — First time enabling a reminder. *Expect:* system prompt; declining flips the toggle back off.
- [ ] **Fires on time** — Set a reminder 2 min out, lock the phone. *Expect:* notification arrives with the chosen sound; haptic signature plays.
- [ ] **Per-habit sound/haptic** — Two habits, different sounds. *Expect:* each notification uses its own.
- [ ] **Cadence-aware** — A specific-days habit only notifies on its days.
- [ ] **Cancel on rest/delete** — Rest or delete a habit with a pending reminder. *Expect:* it never fires.
- [ ] **Sync on relaunch** — Change a reminder time, force-quit, relaunch. *Expect:* fires at the new time.

## 9. Widgets

- [ ] **Add widgets** — Small and medium, from the home screen gallery. *Expect:* today's habits with correct colors and completion state.
- [ ] **Toggle from widget** — Tap a habit's circle in the medium widget. *Expect:* completes without opening the app; app reflects it when opened; widget updates.
- [ ] **Widget sync** — Add/rest/delete/complete a habit in the app. *Expect:* widget updates shortly after.

## 10. Accessibility & polish

- [ ] **Reduce Motion** (Settings → Accessibility → Motion) — Paywall entrance, petals/ripples, and Still Moment glow all calm down or skip; content still appears.
- [ ] **VoiceOver** — Swipe through Today: cards, week dots ("Monday — 50 percent complete"), "+" ("New habit"), paywall plans read price + period, celebration announces itself.
- [ ] **Dynamic Type** — Largest text size: nothing truncated into unreadability on Today, Add, Settings, Paywall.
- [ ] **Dark mode deep-pass** — Every screen in dark: paywall, detail heatmap, widgets, celebration.

## 11. Stability edge cases

- [ ] **Rapid taps** — Hammer "+", settings, a card, and the week row in quick succession. *Expect:* only one sheet ever opens; no crash.
- [ ] **Day rollover** — Leave the app open past midnight (or set the clock to 23:59). *Expect:* Today resets to the new day's schedule.
- [ ] **Background/foreground churn** — Swipe to home and back 5× fast, once with a sheet open. *Expect:* no crash, ambient sound resumes correctly.
- [ ] **Erase while sheets are involved** — Erase all data, then immediately add a new habit. *Expect:* clean slate behaves like a fresh install (grace restarted).

---

### Known setup notes

- **Sandbox purchases** require a Sandbox Apple ID (App Store Connect → Users → Sandbox Testers) or TestFlight; real cards are never charged.
- **Grace expiry** is device-clock based — moving the date forward 4 days is the fastest honest test. Move it back afterwards.
- **Privacy Policy URL** (`stillhabit.app/privacy`) must be a live page before submission.
