# RS2ClientFixes

RS2ClientFixes is a versioned UnrealScript mutator for Rising Storm 2: Vietnam dedicated servers and their joining clients. The current package, **v013 (0.1.3)**, combines client Steam-status reporting with an **operator-triggered** request to refresh a Steam client's online-subsystem login. The same `.u` file runs on both sides; Epic clients report their platform and refuse Steam refresh requests.

The server does not trigger a refresh automatically. A WebAdmin or in-game admin can use `ROMutate rs2cf status` to inspect the current map, `ROMutate rs2cf relink` to ask eligible Steam clients to refresh after a detected logout and regain, or `ROMutate rs2cf force <PlayerID>` to target one reported client during a controlled trial. `ROMutate rs2cf restartmsg` sends a restart suggestion. Client-side checks limit requests to logged-in Steam clients, require a settled regain for `relink`, and cap `Init()` at two calls per game process. The client reports the result to the server. See the [v013 operator guide](stageB/OPERATOR.md) for exact command behavior.

**Current status (27 November 2026):** v013 passed a healthy, ranked training trial with one Steam and one Epic client, including a single forced Steam `Init()` during a match, a new round, a map change, recon, redirect delivery, and ranked stats. It is now deployed on five -=PR=- servers. Startup, client joining, ranked status and reporting were observed there. **A real Steam-maintenance outage and recovery from Leech code 1 have not yet been proven.** A successful `Init()` result means a new ticket was minted; it does not by itself prove Leech accepted that ticket or that the public browser count recovered. See the [training result](stageB/TRIAL-NOTES-2026-11-27.md).

## Current files

| Path | Purpose |
| --- | --- |
| [`stageB/source/RS2ClientFixes_v013/Classes/`](stageB/source/RS2ClientFixes_v013/Classes/) | v013 UnrealScript source and package flags. |
| [`stageB/deploy/ROGame/BrewedPC/RS2ClientFixes_v013.u`](stageB/deploy/ROGame/BrewedPC/RS2ClientFixes_v013.u) | Frozen v013 package, SHA-256 `C4F89112AEA0132952F17538934AD79E63E8A17DA0F9D46498A94F2B88C10E4C`. |
| [`stageB/deploy/ROGame/Config/ROMutator_RS2ClientFixes.ini`](stageB/deploy/ROGame/Config/ROMutator_RS2ClientFixes.ini) | WebAdmin listing for v013. |
| [`stageB/OPERATOR.md`](stageB/OPERATOR.md) | Install, commands, status checks and rollback. |

The older [v012 Stage A guide](stageA/OPERATOR.md) and [trial notes](stageA/TRIAL-NOTES-2026-11-25.md) are retained as history. v012 reports only; it has no relink command. Do not deploy v011: its first client link did not receive its owner.

## Installation and build identity

Install the `.u` with the server's other mutators in `ROGame/BrewedPCServer`, install the listing in `ROGame/Config`, and add `RS2ClientFixes_v013.RS2ClientFixes` to the existing mutator list. Clients receive the identical `.u` from the HTTP redirect. The package flags are `AllowDownload=True`, `ClientOptional=False`, and `ServerSideOnly=False`; a client that cannot download it cannot join.

This unlisted package requires a server setup that keeps ranked package checks passing. The current -=PR=- pilot uses RS2ServerFix 0.7.5.0 with `AllowAnyMutator=True`. RS2ClientFixes does not include that DLL, the game SDK, or server executable. The bypass is a separate, explicit server-side setting.

UE3 assigns a new package GUID at compilation. **Never rebuild under a `_vNNN` name once its package has reached a server, client or redirect.** Change the source folder, `.upkg`, observer object name, log version, compiled `.u`, listing `ClassName` and operator guide together for the next version. v013 is frozen; any code change needs v014 or later.

## Evidence and limits

Client counters are self-reported telemetry and can be falsified by a modified client. Server `links` and `reported` measure mutator link/report delivery, not the Leech backend's public player count. The client cannot read Leech's online status from UnrealScript; check its native log and an independent browser observer when evaluating an outage. Raw client `Launch.log` can contain Steam credentials and must be reviewed before sharing.

This is an independent community project, not an official Tripwire Interactive release.

## License

The project is licensed under [GPL-3.0](LICENSE). Rising Storm 2: Vietnam and its SDK belong to their respective owners; they are not included here.
