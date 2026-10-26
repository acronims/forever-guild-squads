# Guild Squads

Guild Squads is a guild-only addon for **World of Warcraft: Forever** (interface 16001). Build a squad of five with your guildmates, find people who play when you play, compete as squads every week, race for the guild's Hall of Fame and organise 10, 20 and 40-player raid rosters. The guild master stays in control of the rules.

**Version 1.0.0.** It is tested outside the game with a mocked client and a multi-client simulator; please report anything that misbehaves in the client on the issue tracker.

**The guild master shapes the achievements.** In Settings > Achievements (visible to the guild master only) you can enable or disable every achievement and Hall of Fame race, one by one, per group or all at once; change the size and the visible name of an open Top; create up to 50 achievements of your own on what the addon already measures (a level, a boss, squad battleground wins, a profession skill, an Exalted reputation, or a badge you grant); and grant badges by hand with a reason. Disabled entries keep counting quietly and what players already earned stays visible under **Legacy**. A granted badge never puts anyone in a Top.

## Features

**Profiles and squads**
- Member profile: class, level and race are detected; you choose a main and secondary role, the hours you usually play and your goals (leveling, dungeons, farming, world PvP, battlegrounds, raids).
- Squads of 5 with an optional bench of up to 2 (the guild master decides). Each squad has a name, a crest (icon, colour and border), a motto and up to 3 goal tags.
- Captains invite, accept requests, move players to the bench, hand over the captaincy or disband. "Call the squad" and "Invite to group" work only on your click and out of combat.

**Finder**
- Two lists: squads with room and players without a squad.
- Filter by role, class, level, shared hours, goal and who is online. Every suggestion explains why it fits.

**Guild master settings**
- Visible to everyone, editable only by the guild master: who can create squads (by rank name), officer approval, bench size, officer ranks, inactivity days, maximum number of squads, banned words.
- Competition weights and weekly caps, the season name and dates, celebrations, the boss catalog and raid leaders.
- Officers can disband a squad or reset an offensive name or crest.
- **Achievements catalog** (guild master only): on/off per achievement or race (one by one, per group or all), Top size and visible name of open races, custom achievements and granted badges with a mandatory reason.

**Rankings (PvE and PvP)**
- Five categories plus Overall: Leveling, Dungeons, Raids, PvP (battlegrounds) and World PvP (honorable kills outside instances). Optional: captures from the Overlord addon if you use it.
- Scores are counted per **wipe** (the weekly reset, Wednesday 09:00 realm time) with a cap per category, so nobody wins just by playing longer. Points are shared out among the squad's active members, so big squads do not win by size.
- **Seasons** named and dated by the guild master; a season's score is the sum of its wipes. Browse the current and previous wipes and seasons.
- A "This wipe" panel in My squad and a "How is it scored?" button.

**Hall of Fame**
- Races in the guild: Top 100 to each level milestone, Top 10 per class and per race, first kills of every boss, full dungeon and raid clears, full PvE content (Top 3), honorable kills, battlegrounds, professions and exalted reputations. PvP rank races are not available on the 1.60.1 client (hidden automatically) and Legacy Points races stay as "pending data" there (the client has no API for them).
- Each entry shows the realm time and how it was confirmed (exact, approximate, witnesses or reported by the player). The guild master can annul an entry with a reason; the history is kept.

**Achievements**
- Dated squad and personal achievements (first 60 of the squad, full squad at 60, first dungeon together, 10/50/100 bosses together, squad of the wipe and of the season, first battleground won together and more), with progress in the tooltip and a "My achievements" grid.
- Celebrations: an in-addon notice always; announcing in guild chat is **off by default** and the guild master decides what is announced.

**Raid rosters (10 / 20 / 40)**
- Raids tab for raid leaders, officers and the guild master: build a roster by adding whole squads or single players into groups G1 to G8, with a composition bar and warnings (missing tanks, no curse removal and so on).
- Members answer Yes, Maybe, No or Bench in one click, with a short comment. A reminder shows inside the addon one hour before.
- "Invite confirmed" invites one batch per click, out of combat. Attendance is recorded and shown as a percentage of the last 8 raids.
- "Next week" copies a roster, and weekly rosters create their own draft. Export any roster as text for Discord.

**Diagnostics**
- `/gsq diag` opens a copyable report of which client APIs exist, event counters and sync state. It is also saved in the addon's SavedVariables file.

## How sync and trust work

Everything travels over the guild addon channel; there is no server. Each player's client checks every record against the guild roster: only the guild master changes the settings, only you change your profile, only the captain (or the guild master) edits a squad. A record is accepted live from its author and relayed only by the guild master or an officer, so with no guild master or officer online you only get what the authors themselves send. A boss kill or a battleground counts for the rankings only when at least two squad members with the addon report it. Scores are computed on each client from these events; totals are never sent. Nothing is sent during boss encounters or PvP matches.

## Privacy

Your data stays inside your guild. The addon only talks to guildmates over the guild addon channel (and addon whispers to guild members), never makes network requests and keeps no economy data. `/gsq export` and `/gsq import` give you a text backup you control.

## Commands

- `/gsq` opens the window, `/gsq help` lists the commands.
- `/gsq sync` asks guildmates for the latest data.
- `/gsq export` and `/gsq import` save and restore a text backup.
- `/gsq diag` shows the diagnostics report.
- `/gsq minimap` shows the minimap button again.
- `/gsq welcome` shows the welcome guide again.

## Free and open source

Free, MIT licensed, no ads, no donations, no premium version and no in-game economy involved in anything. Languages: English and Spanish. Source and issue tracker: github.com/acronims/forever-guild-squads.
