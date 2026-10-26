# Guild Squads — Player guide

Español → [PLAYER-GUIDE.md](../es/PLAYER-GUIDE.md)

A WoW Forever addon (interface 16001) to form squads of 5 inside your guild, compete week by week, get into the Hall of Fame and sign up for raids. Everything stays inside the guild. If something breaks, run `/gsq diag` and send the report (see *Troubleshooting*).

Guide for guild masters, officers and raid leaders: [GM-GUIDE.md](GM-GUIDE.md).

## First steps

1. Unzip into `Interface\AddOns\GuildSquads` and log in with a character that is in a guild.
2. Type `/gsq` (or click the minimap button). The first time, a 4-step welcome shows up; see it again with `/gsq welcome`.
3. **My profile**: pick your main and secondary role, the hours you play (weekdays / weekend, 4 time slots) and your goals (leveling, dungeons, farming, world PvP, battlegrounds, raids). Save. Class, level and race are detected.
4. **Squads** or **Finder**: ask to join a squad with room, or start your own with **Create squad**.
5. Play with your squad: the **Ranking** adds up by itself.

## The tabs

**My squad.** Your squad: members with role and class, "last seen", squad achievements (dated, or greyed with their progress) and the **This wipe** panel (points per category, cap and guild position). Buttons: *Call the squad* (tells online members where you are; once every 5 min, not in PvP instances) and *Invite to group* (only on click, out of combat). The captain also sees **requests** (accept ✔ or reject) and can move someone to the bench, kick or hand over the captaincy.

**Squads.** Every squad in the guild with its crest, motto, tags and free slots. Inactive squads (nobody online for N days) are dimmed and listed last. Ask to join from here.

**Finder.** Two lists: *Squads with room* and *Players without squad*. Filter by role, class, level, shared hours, goal and online. Each suggestion says why it fits.

**My profile.** Your data and **My achievements** (grid with date or progress). A badge granted by the GM shows *Granted by the GM: reason* in its tooltip; an achievement the GM disabled stays at the end under *Legacy* if you had already earned it. While your profile has never been saved, or has no role or no main goal, the tab shows a **"!"** marker; it goes away once complete. If you leave with unsaved changes, it warns you with three choices: **Save and exit** (saves, then switches tab; if the save is refused, you stay), **Discard** or **Keep editing**.

**Create squad.** Two steps: name, motto and tags (max 3); then the crest (icon, colour and border) with a live preview. If the GM requires approval, an officer has to approve it.

**Ranking.** Squad standings by category (Leveling, Dungeons, Raids, PvP, World PvP and Overall). At the top choose *Wipe* (current and the 8 previous) or *Season*. Your squad is pinned on top. Hover a squad for the breakdown. *How is it scored?* explains it in game. *Export ranking* copies the top 10 for Discord.

**Raids.** Raids published by the raid leaders. Filters *Upcoming*, *My raids* and *Past*. On each card answer in one click: **Yes**, **Maybe**, **No** or **Bench**, with a short comment (60 characters) for the RL. A reminder shows inside the addon one hour before. If no raid is published, the tab is hidden.

**Hall of Fame.** Guild races: Top 100 to each level, Top 10 per class and per race, first kills of each boss, full dungeon and raid clears, full PvE content (Top 3), PvP rank per season (not available on the 1.60.1 client: hidden automatically), honorable kills, battlegrounds, professions, exalted reputations, plus any custom races the GM creates. Each entry shows the realm time and how it was confirmed: *exact*, *approx.*, *witnesses* or *reported by the player*. *Export Top* copies it for Discord. Races the GM disabled that already had entries are under *Legacy (n)*. Full catalog: [ACHIEVEMENTS.md](ACHIEVEMENTS.md).

**Settings.** Everyone can see them; only the GM can change them ("Only the GM can change this"). *Moderation > Data* has Export, Import and Sync.

## Commands

| Command | What it does |
|---|---|
| `/gsq` | Opens or closes the window (there is also a key binding "Guild Squads: open"). |
| `/gsq help` | Lists the commands. |
| `/gsq sync` | Asks the guild for the data you are missing. Once per minute. |
| `/gsq export` | Text backup: Ctrl+A, Ctrl+C and keep it somewhere. |
| `/gsq import` | Paste a backup and press Import. It tells you how many records were applied and how many rejected. |
| `/gsq diag` | Copyable diagnostics report (also saved in SavedVariables). |
| `/gsq minimap` | Shows the minimap button again. |
| `/gsq news` · `/gsq welcome` | What's new · welcome guide. |

## How scoring works, in plain words

- **Wipe** = the competition week. It starts on Wednesday at 09:00 realm time (EU, with summer time). Each category has a **cap per wipe** (100 by default; the GM can change it), so playing more hours is not enough.
- **Season** = a named period set by the GM (by default "Season 1" from 4 Nov 2026). A season's points are the sum of its wipes, each one already capped.
- **Leveling**: every level a member gains while in the squad.
- **Dungeons and raids**: every boss killed; more squad members present = more points. The same boss counts once a day per squad. The first squad of the guild to kill a raid boss gets a bonus.
- **PvP**: battlegrounds played with squad mates (a win is worth 10, a loss 3). **World PvP**: 1 point per 5 honorable kills outside instances. If you use the Overlord addon, its captures can score (the GM decides).
- **Sharing**: points are divided among the active members (at least 3), so a big squad does not win by size.
- **Witnesses**: a boss or a battleground only counts when **at least 2 squad members with the addon** report it within 3 minutes. Playing with people without the addon does not score.
- **Changing squads**: you take your points from the current wipe with you; closed wipes stay with the old squad.
- Nobody sends totals: each client computes the ranking from the same events. That is why two people may see different numbers for a few minutes, until they have the same data.

## Hall of Fame: how entries are confirmed

- **Level**: *exact* when you report it and the guild roster confirms it; *approx.* when 2 players with the addon see it within 10 minutes (or one GM/officer).
- **Bosses and battlegrounds**: 2 reports within 3 minutes; with only one, it stays "pending" for 24 h.
- **Counters** (honorable kills, professions, reputation): reported by the player. Your first reading is a *baseline* and does not score; what you gain after it counts.
- Data arriving late or with an odd jump is kept *unverified* and stays out of the Top until a GM or officer confirms it.
- The GM can annul an entry with a reason (and revert it). The next one moves up.

## Troubleshooting

**My data is gone after logging in again.** The Forever client has been seen writing SavedVariables on exit but not reading them back. What to do: run `/gsq export` now and then and keep the text; if you lose data, `/gsq import`. Also, on login you get it back from the guild if a GM or officer is online (`/gsq sync`).

**Nothing syncs / I don't see other squads.** Other people's data reaches you only live from its author, or relayed by the **GM or an officer**. With no GM or officer online you only receive what the authors themselves publish at that moment. Wait for one to log in and run `/gsq sync`. In big guilds catching up takes a few minutes (on purpose, so the channel is not flooded).

**Nothing is announced in guild chat.** Guild chat celebrations are **off by default**; the GM turns them on in Settings > Celebrate (*Announce in guild chat*, *What is announced*: 1st place / Top 3 / Any entry, and *Also announce squad achievements*). The in-addon notice always shows. The chat message uses the language of the client that announces it, which may not be yours.

**My professions do not show in the Hall of Fame.** Check the `prof path=… n=…` line in `/gsq diag`: if it says `none` or `empty` with `n=0`, the client is not giving the addon your professions; send us the report.

**My boss did not score.** Was another squad member with the addon in the group? Did you already kill it today? Is the competition on and the category weight above 0? The addon sends nothing during combat: it sends after the encounter.

**I can't join the squad.** The captain has to accept you **and** your profile has to point to that squad. A character can be in one squad only.

**The button is grey.** Hover it: the tooltip says why (you are not the captain, the squad is full, select a card first...).

**Report for the developer.** `/gsq diag`, Ctrl+A, Ctrl+C and paste it in the issue. Or send the file `WTF\Account\<ACCOUNT>\SavedVariables\GuildSquads.lua` (in the Forever client folder).


## What `/gsq diag` shows

It opens a window with the report to copy (Ctrl+A, Ctrl+C); the same copy is kept in SavedVariables. Besides the version, event counters and client APIs, it adds these lines:

- `events=<N> wipe=<wipe> v=<version>` (Progress): stored scoring events and the current wipe.
- `hall obs=<N> closed=<N> chatErr=<error> pvpRank=ok|unsupported`: Hall of Fame observations, closed races, the last guild-chat announcement error and whether the client exposes the PvP rank.
- `prof path=<path> n=<N>`: which client API read your professions (`GetProfessions`, `C_SkillInfo`, `empty` or `none`) and how many it found.
- `raid apis <API>=yes|no … rosters=<N>`: which group/raid APIs the client has and how many raid rosters exist.
- `comm sent= recv= failed= pending=`: addon messages sent, received, failed and queued.
- `sync bad= relayRefused= future= errors= quarantine= guild=`: refused records (malformed, unauthorised relay, future date), quarantined ones, and the loaded guild.
- `[roster] me=<key> found=yes|no entries=<N> surnames=<N>`: whether your character was found in the guild roster (character surnames are supported).
- `catalog achdef=<N> custom=<N> grants=<N> off=<N>`: the GM's achievement catalog (entries, custom achievements, granted badges, disabled).

## FAQ

**Does anything leave the guild?** No. Only the guild addon channel and addon whispers to guild members. No internet requests.

**Do I need the addon to be in the Hall of Fame?** Levels of members without the addon are seen through the guild roster (from when someone with the addon observes them, not backwards). Bosses, PvP and counters need the addon.

**Can I be in two squads?** No, one per character. Your alts can be in others.

**What about my alts in another guild?** Data is stored per guild; an alt in another guild does not touch your main guild's data.

**Does it cost anything?** No. Free, MIT, no ads, no donations and no gold involved.
