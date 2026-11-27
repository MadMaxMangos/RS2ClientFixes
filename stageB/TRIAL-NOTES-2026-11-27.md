# v013 training and production pilot status — 27 November 2026

The healthy training trial **passed with notes**. One Steam and one Epic client received v013 through the redirect, reported to the server and stayed connected through a Steam-only forced `Init()`, a new round and a map change. The Steam client minted a new ticket and reported `init_ok=True`; the server acknowledged one request. Voice, HUD, scoreboard and recon were reported normal. WebAdmin stayed ranked, and `SessionHasStats` recorded `bIsStatsSessionOk=1`, `GPackagesPassedMD5Checks=1`, `GOfficialGameServerStatus=3`, `bSessionHasStats=1`.

The same frozen package was installed on five -=PR=- production servers. Startup, joining and ranked state passed the rollout checks. The server 1 pilot recorded the package-check marker active and stats flags 1/1/3/1. Server 2 reached 64 client links with 64 reports under load; no ignored reports or critical log markers were seen in the monitored window. No production `rs2cf relink`, `rs2cf force` or `rs2leech recover` request was made as part of the rollout.

The real Steam-outage scenario remains open: neither the training trial nor this startup pilot proved that a fresh ticket clears a Leech code-1 refusal or restores the backend's public player count. `Init()` succeeded in training while Leech was already online, so no subsequent Leech login was observed there. The next maintenance window needs separate client-log and external browser observations.

Package SHA-256: `C4F89112AEA0132952F17538934AD79E63E8A17DA0F9D46498A94F2B88C10E4C`. WebAdmin listing SHA-256: `9579CFF35C24BE28B3F0EBB4DFA979CB6D67723A0D40A956EC5BFCE6265E57D7`.
