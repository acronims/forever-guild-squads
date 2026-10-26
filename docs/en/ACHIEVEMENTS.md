# Guild Squads — Achievements and races ("Tops") catalog

Español → [ACHIEVEMENTS.md](../es/ACHIEVEMENTS.md)

What the addon recognises, how it is confirmed and how the GM tailors it. In-game usage: [PLAYER-GUIDE.md](PLAYER-GUIDE.md) (players) and [GM-GUIDE.md](GM-GUIDE.md), section *Settings > Achievements* (GM).

## 1. Three kinds of recognition

| Kind | What it is | How long it lasts | Example |
|---|---|---|---|
| **Race (Top N)** | A list **ordered by who got there first**. Once full, it closes for good. | Permanent: Hall of Fame | "Top 100 first to reach 60" |
| **Achievement** | A badge unlocked by meeting a condition, dated and with visible progress. | Permanent | "Squad at 60", "Forever route" |
| **Ranking** | Points per category, reset every wipe and added up per season. | Wipe / season | Dungeons ranking |

Everything is counted **inside the guild**. Sizes: **Top 100** for the general level races, **Top 3** for "full PvE content" and **Top 10** for everything else (the GM can shrink them, see §8).

## 2. Level races (per character)

| Id | Race | Size | Milestones |
|---|---|---|---|
| `lvl.all.<H>` | First guild characters to reach level H | **Top 100** | H = 10, 20, 30, 40, 50, 60 |
| `lvl.class.<CLASS>.<H>` | First of each **class** to reach level H | Top 10 | 9 classes × 6 milestones |
| `lvl.race.<RACE>.<H>` | First of each **race** to reach level H | Top 10 | Forever races × 6 milestones |

- Classes and races come from `UnitClass`/`UnitRace` and from the guild roster (`classFile`); a race that is not in the known list needs at least 2 distinct reporters before its race opens.
- **Detection:** the player's own client (`PLAYER_LEVEL_UP`) **and** any member with the addon who sees a guildmate level up in the guild roster (`GUILD_ROSTER_UPDATE`). That way characters **without the addon count too**, timestamped when the change was seen.
- **Which time counts:** *exact* when the player reports it and the roster confirms it; *approx.* when ≥ 2 roster observers see it within 10 minutes (or one GM/officer does). Exact tie: alphabetical order of the full name.
- **Not retroactive:** only what happens while at least one guild member runs the addon counts.

## 3. PvE races

In dungeons the **group** that kills the boss competes; the participants and their squad are recorded. In raids the **raid group** competes.

| Id | Race | Size | Condition |
|---|---|---|---|
| `dng.<DUNGEON>` | First groups to **clear** each dungeon | Top 10 | kill the final boss |
| `dng.<DUNGEON>.<BOSS>` | First to kill **each** dungeon boss | Top 10 | successful `ENCOUNTER_END` |
| `dng.all` | First **squads** to clear **all 9 new Forever dungeons** | Top 10 | all 9 cleared with ≥ 3 members of the same squad |
| `raid.<RAID>` | First groups to clear each raid | Top 10 | final boss |
| `raid.<RAID>.<BOSS>` | First to kill each raid boss | Top 10 | successful `ENCOUNTER_END` |
| `raid.all` | First to clear **every open raid** | Top 10 | Barrow Deeps, Hyjal Summit and Onyxia's Lair |
| `full.10` | **Full 10-player PvE content**: every dungeon + the 10-player raids | **Top 3** | squad alliance, see below |
| `full.20` | **Full 20-player PvE content**: every dungeon + the 20-player raids | **Top 3** | squad alliance |

- **Witnesses:** every boss kill needs **≥ 2 reports** from clients with the addon who were there, within 180 s. With a single report the kill stays *pending* for 24 h in case another one arrives.
- **Dungeons:** credited to **a single squad**, the one with ≥ 3 members in the group. If none reaches 3, the entry is a *mixed group*: it enters the Top but gives no squad achievement.
- **Squad alliance** (`raid.all`, `full.*`): on every kill, the squads present with ≥ 3 members are recorded. Every squad present in **≥ 70 %** of the required kills is credited; the entry is shared ("Dragons + Frost") and takes **a single place**. Squadless players who took part are listed as *support* in the tooltip. A raid "run" is that raid's kills in the 7 days before the final boss.
- **Bosses and final boss:** the catalog (`Core/Content.lua`) **learns** the bosses the first time they die with the addon around (name, encounterID and instance) and replicates them. The GM marks the **final boss** in Settings > Content. Without a final boss, the "clear" races stay *pending data*; the per-boss races work from day one.

## 4. PvP races

| Id | Race | Size | Condition |
|---|---|---|---|
| `pvp.rank.<R>.s<SEASON>` | First to reach **PvP rank** R in the season | Top 10 | R = 5, 10, 12, 14; not available on the 1.60.1 client (hidden automatically) |
| `pvp.rank.class.<CLASS>.14.s<SEASON>` | First of each class to reach rank 14 in the season | Top 10 | same |
| `pvp.hk.<N>` | First to reach N honorable kills, counted from when they install the addon | Top 10 | N = 100, 1,000, 5,000 |
| `pvp.bg.<N>` | First **squads** to win N battlegrounds together | Top 10 | N = 10, 50, 100; ≥ 2 squad members in the BG |
| `pvp.bgmap.<MAP>` | First squads to win on each battleground | Top 10 | per map (the name comes from the game) |
| `wpvp.caps.<N>` | First to reach N captures with Overlord | Top 10 | N = 10, 100 (only with Overlord enabled) |

- **PvP rank** races are **per season**; the others are permanent.
- The rank is read with `UnitPVPRank`/`GetPVPRankInfo`. If the client has no `UnitPVPRank` (the case of WoW Forever 1.60.1), rank achievements and races are not shown and `/gsq diag` says `pvpRank=unsupported`.

## 5. Other races

| Id | Race | Size | Source |
|---|---|---|---|
| `prof.<PROFESSION>.<N>` | First to reach N in each profession | Top 10 | `GetProfessions`/`GetProfessionInfo`, `C_SkillInfo`. N = 150, 225, 300 |
| `rep.<FACTION>.exalted` | First to reach Exalted with each faction | Top 10 | `C_Reputation` or `GetFactionInfo` |
| `legacy.<N>` | First to earn N Legacy Points | Top 10 | N = 100, 500, 1,000. The 1.60.1 client has no API for them: the race shows as "pending data" |
| `squad.full60` | First **squads** with all 5 starters at 60 | Top 10 | guild roster |

If the API does not exist in the client, the race stays *pending data*, with no error.

## 6. Achievements (dated badges with progress)

Names as shown by an English client; a Spanish client shows them in Spanish (see the [Spanish catalog](../es/ACHIEVEMENTS.md#6-logros-insignias-con-fecha-y-progreso)).

### Squad
| Id | Achievement | Condition | Visible progress |
|---|---|---|---|
| `first60` | First 60 of the squad | a member reaches 60 | highest level / 60 |
| `squad60` | Squad at 60 | all 5 starters at 60 | n / 5 |
| `firstDungeon` | First dungeon together | ≥ 2 members (boss with witnesses) | — |
| `forever` | Forever route | the 9 new dungeons together | n / 9 |
| `boss10` / `boss50` / `boss100` | 10/50/100 bosses together | witnessed bosses | n / target |
| `firstRaid` | First raid boss | ≥ 3 members on a raid boss | — |
| `sotw` / `sots` | Squad of the wipe / of the season | first in Overall at close | — |
| `firstBg` | First BG won together | ≥ 2 members | — |
| `hk100` | 100 squad HK | squad total | n / 100 |
| `conq` | Conquerors | 10 captures with Overlord | n / 10 |
| `allRoles` | Full team | 1 tank, 1 healer and 3 DPS by main role | — |
| `allClasses` | Rainbow | 5 different classes among the starters | n / 5 |
| `wipeTopAll` | Seamless | hit the cap in all 5 categories in one wipe | n / 5 |
| `wipes4` | Consistency | top 3 in Overall for 4 wipes in a row | n / 4 |
| `hallOfFame` | Legend | the squad appears in a race of Top 10 or smaller | — |

### Character
| Id | Achievement | Condition |
|---|---|---|
| `guildFirst60` | First of the guild to 60 | the guild's first 60 |
| `lvl<H>` | Level H (10…60) | reach level H with the addon installed |
| `top100.<H>` | Top 100 at H | a place in `lvl.all.<H>` |
| `top10class` | Top 10 of your class | a place in any `lvl.class.*` |
| `top10race` | Top 10 of your race | a place in any `lvl.race.*` |
| `first1` | First! | 1st place in any race |
| `dungeonsAll` | Forever explorer | the 9 new dungeons cleared (with any group) |
| `raider` | Raider | one boss of each open raid |
| `pvpRank<R>` | Rank R | reach PvP rank R; not available on the 1.60.1 client (hidden automatically) |

### Guild
| Id | Achievement | Condition |
|---|---|---|
| `allAboard` | All aboard | ≥ 80 % of active members (last 14 days) with the addon |

Settings and the Hall show "Guild Squads installed: X/Y members".

## 7. Common rules

1. **Race order:** by server time (`GetServerTime`). Exact tie: alphabetical order of the full name. An invalid entry (character outside the guild, inconsistent time) is dropped and the next one moves up.
2. **Witnesses:** bosses and BGs need ≥ 2 reports. Levels: the player's own client + the roster, or ≥ 2 roster observers. Counters (HK, professions, reputation) are reported by the player themself and carry the *reported by the player* mark; the first reading is the baseline.
3. **Unverified:** data that arrives late or with an odd jump shows with "?" and stays out of the Top until a GM or officer confirms it (`vconfirm` record).
4. **Closed race = immutable.** A full Top is frozen. Only the GM can **annul** an entry, with a mandatory reason; the annulment stays in the history and can be reverted.
5. **Characters who leave the guild:** their entry stays in the Hall with the *ex-member* tag.
6. **No gold and no economy** in any condition. No DPS or damage either.
7. **Privacy:** only visible inside the guild. *Export Top* copies the chosen Top as text for Discord.

### Data and sync
Observations (`RO` live, author only; `RP` catch-up pages, GM or officers only) are replicated over the guild addon channel; Tops and achievements are **computed locally** on every client. Closed races are compacted into a single row and are not resent when the hash matches.

### Celebrations
An in-addon notice **always** shows (bigger if you are #1). A guild-chat message **only if the GM enables it** in Settings > Celebrate (off by default): what is announced (1st place / Top 3 / any entry) and whether squad achievements are announced. **A single client** announces each event: the protagonist's if they have the addon; otherwise the highest-ranked one online (ties broken by name). At most 1 message every 10 s, no links, never during an encounter. The guild-chat message is written **in the language of the announcing client** (an English client announces in English, a Spanish one in Spanish); every reader's own addon window always uses their own language.

## 8. The GM and the catalog (Settings > Achievements)

The GM adapts this catalog to the guild without touching code (step by step: [GM-GUIDE.md](GM-GUIDE.md), section *Settings > Achievements*). The rules in §7 still hold: what is closed is immutable, every client re-validates everything against its own roster and results are computed locally.

**Records** (extension kinds, `M.registerKind`, order 12 and 13; signed **by the GM only**, rank 0, like `settings`):

| Record | id | Fields | Purpose |
|---|---|---|---|
| `achdef` | id of the achievement or race (`lvl.all.60`, `hallOfFame`, `gm.<slug>`…) | `on`, `size` (races only), `name` (≤ 32, no colours or links), `sts` (when the size was set); custom entries add `custom`, `metric`, `param`, `thr`, `scope` | enable/disable, Top size, visible name, custom achievements |
| `achgrant` | `ach .. "|" .. who` | `ach`, `who` (character or squad id), `reason` (mandatory), `on` | grant a badge by hand; `on = false` revokes it and keeps it in the history |

One record per achievement: each change travels alone and is resolved last-writer-wins (LWW) per id. A bulk change is N ordinary records, 3 per message, through the 1 msg/s queue.

**Enable / disable.** A disabled entry **keeps counting**: it is not shown in the Hall, the Ranking or My achievements and is never celebrated, but its observations are stored and, once re-enabled, it comes back with its history. Whatever was already earned shows under **Legacy** (dimmed, *legacy* tag).

**Top size.** Open races only; from 1 to the maximum of its family (100 `lvl.all.*`, 3 `full.*`, 10 the rest) and never below the entries it already has. The GM's client refuses the change on a closed race. Every client applies a deterministic rule: a frozen Top keeps its rows; a race that was already full at its original size when the GM changed it keeps that size; otherwise, the new size, floored at the entries it had at that moment (`sts`).

**Custom achievements (`gm.<slug>`, 50 max).** Top N races with the same observations and witnesses as the default ones:

| `metric` | `param` | `thr` | Scope |
|---|---|---|---|
| `level` | empty, `class:<CLASS>` or `race:<RACE>` | milestone 10…60 | character |
| `boss` | boss id from the learned catalog (`<instance>.<boss>`) | — | group (≥ 2 witnesses) |
| `bg` | empty or map | N squad wins | squad (≥ 2 of the squad in the BG) |
| `prof` | profession | skill ≥ N (reports arrive when crossing 150, 225 and 300) | character |
| `rep` | faction | 8 = Exalted (the only standing observed) | character |
| `manual` | — | — | badge (character or squad), via `achgrant` only |

Without the API in the client (professions, reputation) the race stays *pending data*, like the default ones. What a custom achievement measures cannot change once it is created.

**Grant by hand.** Badges only (the achievements in §6 and custom `manual` ones); it **never** creates an entry in a Top. The tooltip reads "Granted by the GM: <reason>".

**Compatibility.** A client that does not know a record kind ignores it without error (`Model.validShape` → `kind`, counted in `sync bad=`) and keeps syncing the rest. `/gsq diag` shows `catalog achdef=<n> custom=<n> grants=<n> off=<n>`.
