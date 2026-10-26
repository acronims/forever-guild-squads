# Security

Guild Squads only talks to other clients of your own guild through the WoW addon channel. It never sends data outside the game.

**Report a vulnerability privately** through GitHub: *Security* tab → *Report a vulnerability*. Please do not open a public issue.
Useful details: version (`/gsq diag` first line), what an attacker needs (a guild member? an officer?), and steps to reproduce.

Known by design: records are validated by guild rank, not by cryptographic signatures, so a GM or officer running a modified client can forge relayed data (see [README, Known limitations](README.md#known-limitations)).

Supported version: the latest release on CurseForge.
