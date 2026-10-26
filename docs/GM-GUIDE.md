# Guild Squads — Guide for the GM, officers and raid leaders

For the guild master (GM, rank 0), officers and raid leaders (RL). Player basics are in [PLAYER-GUIDE.md](PLAYER-GUIDE.md). En español: [GUIA-GM.md](GUIA-GM.md).

## Who can do what

| Who | Can |
|---|---|
| **GM** (rank 0) | Change and share all Settings; edit any squad; annul and revert Hall of Fame entries; **tailor the catalog of achievements and races and grant badges** (Settings > Achievements, GM only); mark final bosses; close seasons; edit any raid roster. |
| **Officers** (the ranks the GM marks) | Approve new squads, disband a squad, reset an offensive name or crest; lead raids; edit other people's rosters if the GM allows it. They **relay data** to players who just logged in. |
| **RL** (GM's list) | Create, publish, invite and close their raids. |
| Captain | Their squad: invite, accept, bench, kick, hand over captaincy. |

The whole guild sees the Settings read-only. Each client checks against the guild roster who signed each change: a setting not coming from the GM is ignored.

## GM first steps

1. Install the addon and open `/gsq` > **Settings**.
2. Go through the 9 sections (below; **Achievements** is shown to you only). Change what you want and press **Save and share**. Leaving the tab with unsaved changes asks first.
3. Ask your officers to install it: with no GM or officer online, players who just logged in only receive what the authors publish live (see *Troubleshooting*).
4. Announce the addon in the guild. The in-addon welcome guides them (profile → squad → ranking).

## Settings, section by section

**Squads.** Minimum rank to create squads (by rank name), *Officers must approve new squads*, bench 0–2, which ranks are officers, days until "Inactive" (7/14/30/never), maximum squads (no limit/10/20/50).

**Competition.** On or off, weight per category (0–3; at 0 the category adds nothing), cap per category and wipe (50/100/150/200), weekly guild goal. The wipe reset (Wednesday 09:00 realm time) is shown but cannot be changed.

**Season.** Name, start and end (YYYY-MM-DD HH:MM realm time; empty end = open). **New season** closes the current one now and opens another (asks to confirm). Previous seasons are listed below. Default: "Season 1" from 4 Nov 2026 09:00.

**Integr.** Use Overlord (if installed; only its captures are read, 2 points each) and whether its recommendation hint is shown.

**Moderation.** Banned words (one per line, up to 50). Squad list with *Disband* and *Reset name/crest* (GM and officers, confirmed; reset leaves `Squad <code>` and the default crest). **Data**: Export, Import and Sync.

**Celebrate.** *Announce in guild chat* — **off by default**. *What is announced*: **1st place**, **Top 3** or **Any entry** (any entry in a Top). *Also announce squad achievements*. The announcer is the player concerned if they run the addon; otherwise the highest-ranked online member. One client announces each event, at most 1 message every 10 s, no links, never during an encounter. The in-addon notice always shows.

**Content.** Boss catalog learned automatically (each boss is stored the first time it dies with the addon). Mark the **final boss** of each dungeon or raid: without it the "complete" races do not open.

**Raids.** RL list (one guild character per line), *Officers may edit other people's rosters*, and the useful-classes table (`key:CLASS+CLASS:min size`) behind the composition warnings. Empty = defaults. The GM and officers can always lead.

**Achievements** (GM only). Decide which recognitions your guild uses. **Every change is shared at once** (no *Save and share*) and every client checks again that the GM signed it: officers cannot change it.
- **Group** (Level, Class, Race, Dungeons, Raids, PvP, Professions, Reputation, Squad, Character) and one row per achievement or race: checkbox (enabled), name, state (*open n/N*, *closed*, *pending data* or *badge*), **Top N** and **Rename**.
- **Disabling** hides the achievement or race in the Hall of Fame, the Ranking and My achievements, and it is never celebrated. **Nothing is deleted**: it keeps counting quietly and, when re-enabled, comes back with its whole history. What someone had already earned shows under **Legacy** (dimmed, tagged *legacy*): in the Hall, the *Legacy (n)* button; in My achievements and the My squad strip, at the end.
- **Enable all / Disable all** changes the selected group; **Global** changes the whole catalog. It first tells you how many records that is and how long it takes to reach everybody (1 message per second: a global "disable all" can take a couple of minutes).
- **Top N**: **open** races only, from 1 to the family maximum (100 for the overall level races, 10 for the rest, 3 for "full content") and never below the entries it already has. A closed race cannot change (the button says why).
- **Rename**: up to 32 characters, no colours or links. The internal id never changes; empty = default name.
- **New achievement** (50 at most): 1) what it measures — level (optionally of one class or race), a catalog boss in a group (≥2 witnesses), squad battleground wins (overall or on one map), a profession skill, Exalted reputation, or a **badge you grant**; 2) which one; 3) threshold and Top size; 4) name. It is computed from the same data and witnesses as the built-in ones. What it measures cannot change once created (its name, size and on/off can).
- **Grant**: pick the badge, the character (or squad, for squad badges) and a **mandatory reason**. The tooltip shows *Granted by the GM: reason*. It **never puts anyone in a Top** (Tops are ordered by who got there first). *Withdraw* removes it and keeps it in the history.
- Compatibility: a client that does not know a record kind ignores it without error (it keeps the built-in catalog).

## Moderating the Hall of Fame

- Right-click an entry: **Annul** with a reason (GM only). The next one moves up and the history is kept. *Revert* puts it back.
- Data arriving late or with odd jumps is kept *unverified*: only an online GM or officer confirms it when relaying it.
- A full Top is frozen; a closed race does not reopen.

## Raids: the RL workflow

1. **Raids > New raid.** Set a name ("Raid A Tuesday"), the raid (Barrow Deeps 10, Hyjal Summit 20, Onyxia's Lair 40 or a custom 10/20/40), date and realm time (`YYYY-MM-DD HH:MM` + Enter) and the tanks/healers/damage template as min-max (`2-2/2-3/5-6` + Enter). Tick *Every week* if it repeats.
2. **Build the roster** with "+" in the squads and players panel (filter by role, online, name or class; a number = minimum level). A squad goes whole into the first group with room; if it does not fit, the starters that fit go in and you get a warning; its bench players take free slots or the bench list (max 10). Nobody appears twice.
3. Check the **composition bar** and warnings ("missing 1 T", "1 D too many", "no curse removal"). **Save**.
4. **Publish**: listed players can now answer Yes / Maybe / No / Bench. Anyone in the guild may answer as a volunteer. You see the count and the comments.
5. At raid time: **Invite confirmed**. One batch per click, only out of combat (5 into a party; then it converts to a raid if the client allows it and arranges subgroups if you are leader or assistant). When they accept, **click again**.
6. **Close** when done: it saves attendance (who was in the raid from 30 min before to 3 h after). If you don't close it, it closes by itself 3 h later **if your client (or the GM's) is online**.
7. **Next week** copies the raid to +7 days at the same realm hour. **Export** gives the text for Discord. **Cancel raid** tells everyone listed.

A player's attendance % counts the last 8 raids with recorded attendance where they were listed or present.

## Useful commands for the GM

| Command | Why |
|---|---|
| `/gsq` · `/gsq help` | Window · list of commands. |
| `/gsq sync` | Asks for what is missing (once per minute). When you are online as GM, your client helps others catch up. |
| `/gsq export` / `/gsq import` | Text backup. On import every record is validated again; records you may not apply are rejected and counted. |
| `/gsq diag` | Diagnostics: which APIs the client has (`raid apis … rosters=`), event and send counters (`comm`), sync refusals (`sync bad= relayRefused= future= quarantine=`), guild-chat errors (`hall … chatErr=`) and the profession read path (`prof path= n=`). Line-by-line detail in the [player guide](PLAYER-GUIDE.md#what-gsq-diag-shows). |
| `/gsq ui` | Prints which templates and atlases the client has and which ones use the fallback. |
| `/gsq minimap` | Shows the minimap button again. |
| `/gsq debug` | Send/receive counters in chat and verbose log (for debugging). |

## Troubleshooting

**Nothing syncs without a GM or officer online.** By design: a record is accepted live from its author and relayed only by the GM or officers. If you want new players to catch up quickly, have an officer with the addon online at peak hours.

**Data seems lost after a restart.** The Forever client has been seen not reading SavedVariables back. Run `/gsq export` after changing settings or closing raids and keep the text; the others get it back from any online GM/officer.

**Guild chat announces nothing.** Celebrations are off by default: Settings > Celebrate. If the client blocks the message, the error shows in `/gsq diag` (`hall ... chatErr=`).

**"Complete" races do not open.** The final boss is not marked in Settings > Content.

**Invite confirmed does not build the raid.** `/gsq diag` lists which group/raid APIs exist. If converting to raid or moving subgroups is not possible, the addon skips it and tells you; do it by hand.

**Two squads with the same name at the same time.** Each client keeps the one it saw first; rename or reset one from Moderation.

**A player still sees an achievement I disabled.** The change has not reached them yet (bulk changes travel at 1 message per second). `/gsq diag` shows `catalog achdef= custom= grants= off=`: compare with yours.

## FAQ

**Can I hand the settings to an officer?** No: only rank 0 signs settings (and the achievement catalog). Officers moderate (approve, disband, reset) and relay data.

**What happens if a new season starts mid-wipe?** That wipe stays in the previous season.

**How long does a big guild take to catch up?** Minutes (500 profiles), on purpose, to respect the client's message limit.

**Can it be used to split loot or charge people?** No. It stores no economy data: free, MIT, no ads, no donations and no gold involved.
