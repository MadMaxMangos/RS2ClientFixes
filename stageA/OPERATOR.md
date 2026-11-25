# RS2ClientFixes Stage A: training trial

Stage A reports only. It never calls Steam `Init()`, a login or an authentication function. It answers two questions:

1. Does the package reach clients and run on them?
2. What can a joined client see about its own Steam connection while Steam drops and returns?

Use the training server only, with no other players.

## The package

`stageA\deploy\ROGame\BrewedPC\RS2ClientFixes_v012.u`

Check its SHA-256 against the `package_sha256` in the newest `evidence\stageA-*\result.json`. One file serves the server and the client. The mutator class runs only on a dedicated server. Clients run the per-player link and a session observer that lives on the game viewport, so it survives map changes on the same server.

`.upkg` flags: `AllowDownload=True`, `ClientOptional=False`, `ServerSideOnly=False`. A client that cannot obtain the package cannot join. That makes delivery failures obvious during the trial. Decide the production value after trial A2.

**Every compile writes a new package GUID**, so a rebuild of the same source under the same name is a *different* package. Once a `_vNNN` file has gone onto any server, client or the redirect, never rebuild under that name; bump the version. The build script archives any build it replaces into `stageA\superseded\`.

## Server setup (training)

1. Run RS2ServerFix 0.7.5.0 with `RS2PackageCheck.ini` containing `AllowAnyMutator=True`. RS2ClientFixes_v012 is not in the safelist, so without this the server unranks.
2. Put `RS2ClientFixes_v012.u` where the server's other mutator packages live (`ROGame\BrewedPCServer` on the training server, beside `PRSeedMutator.u`). The repository's `deploy\ROGame\BrewedPC` folder holds the source file for this copy and for the redirect; it is not the training server destination.
3. Put `stageA\deploy\ROGame\Config\ROMutator_RS2ClientFixes.ini` into the server's `ROGame\Config` (beside `ROMutator_PRSeed.ini`). This lists the mutator in WebAdmin as "RS2 Client Fixes (v012)". The file is server-only. Each release overwrites it and only its `ClassName` changes, so never keep two copies.
4. Add it to the server's mutator list: `?mutator=RS2ClientFixes_v012.RS2ClientFixes` (or append `,RS2ClientFixes_v012.RS2ClientFixes` to an existing mutator list).
5. Expected server log lines:
   - at map start: `[RS2ClientFixes] v0.1.2 side=server event=active mode=report-only`
   - per report: `[RS2ClientFixes] v0.1.2 side=server event=report player=<PlayerID> platform=<steam|epic|unknown> login=<n> last_status=<n> server_session=<n> status_events_life=<n> status_events_here=<n> status_drops_life=<n> status_drops_here=<n> status_graceful_life=<n> status_graceful_here=<n> login_lost_life=<n> login_lost_here=<n> login_regained_life=<n> login_regained_here=<n> observed_s_life=<n> observed_s_here=<n> since_change_s=<n> seq=<n> owner_syncs=<n> ignored=<n>`
   - within 60 s of any change: `[RS2ClientFixes] v0.1.2 side=server event=summary links=<n> reported=<n> steam=<n> epic=<n> drop_seen_life=<n> drop_seen_here=<n> logged_in=<n> ignored_reports=<n>`

If you see `event=inactive reason=not-dedicated-server`, the mutator loaded somewhere other than a dedicated server and did nothing. That is the intended behaviour.

## Optional trial A1: logic, with delivery taken out of the picture

1. Copy the same `RS2ClientFixes_v012.u` into the client's `ROGame\BrewedPC` (check the hash).
2. Launch the client normally and join training.
3. Expected client `Launch.log` lines, within a few seconds of joining:
   - `[RS2ClientFixes] v0.1.2 side=client event=owner-set source=rpc` and/or `event=owner-set source=local applied=True`. Either is enough. v0.1.1 failed here with `link-idle reason=no-owner`, because Owner does not replicate for this actor class.
   - `[RS2ClientFixes] v0.1.2 side=client event=observer-started platform=1 status_delegate=True login=<n>`
   - `[RS2ClientFixes] v0.1.2 side=client event=link-ready`

   If you see `link-idle` instead, note its `reason=`:
   - `no-owner`: neither owner path took effect;
   - `no-local-controller`;
   - `no-observer`: the viewport observer could not be created.

   On the server, the report's `owner_syncs=<n>` shows how many owner RPCs were needed before the first report (normally 1–3).
4. A server `event=report` line for your PlayerID should appear, followed by a summary within 60 s.
5. Change map. Expected:
   - client: `event=link-ready` again, and **no** second `observer-started`, because the observer is reused;
   - server: a fresh report.
6. Check that the server stays ranked: WebAdmin, the in-game browser, and `unsuppress DevSession` for `bSessionHasStats=1`. Check that EAC does not kick the client.

### Steam-loss observation after A1 or A2

While joined, block `steam.exe` outbound for 180 s. Use the test 1 PowerShell from the test-3 kit `OPERATOR.md`. Then watch the client log for:

- `[RS2ClientFixes] v0.1.2 side=client event=steam-status status=<n> events_life=<n> events_here=<n> drops_life=<n> drops_here=<n> graceful_life=<n> graceful_here=<n>` (Steam connection callbacks), and/or
- `[RS2ClientFixes] v0.1.2 side=client event=login-change from=<n> to=<n> lost_life=<n> lost_here=<n> regained_life=<n> regained_here=<n>` (Steam login status polled every 2 s).

The server should log a report with `status_drops_here` above 0 or `login_lost_here` above 0. The `_life` fields retain earlier server sessions; `_here` starts at zero on each new server address and continues across maps on that server. `server_session` increments on each address change. The address is never logged. `OSCS_NotConnected` increments `status_graceful_*`, not `status_drops_*`. Also note whether the native Leech retry loop (code 1) starts. Stage A cannot see that loop; only the native log shows it.

Each `drop_seen_*` summary field counts Steam players with a status loss or login loss over the lifetime or on this server, respectively, not individual events. Epic reports are excluded from both drop counts.

## Trial A2: delivery through the HTTP redirect (no Workshop)

In the training run, the Steam Workshop downloader logged that this unlisted package had no Workshop info, and the HTTP redirect delivered it. That warning alone does not mean delivery failed. The game server does not send the package file itself. A2 can be run first; A1 is optional if delivery needs to be isolated from the mutator logic.

1. Put `RS2ClientFixes_v012.u` on the training server's redirect. Use the same folder and compression convention your custom maps already use there.
2. On the Steam client:
   1. remove `RS2ClientFixes_v012.u` from `ROGame\BrewedPC`;
   2. remove any copy from `Documents\My Games\Rising Storm 2\ROGame\Cache`;
   3. join training.

   Expect a download line in `Launch.log`, then the same client lines as A1.
3. Repeat on the Epic client, clearing its `Rising Storm 2 EGS\ROGame\Cache` as well. Expect:
   - `[RS2ClientFixes] v0.1.2 side=client event=observer-started platform=2 status_delegate=False login=255`;
   - no `login-change` or `steam-status` lines, because Epic neither polls login status nor binds the connection-status delegate;
   - a server report with `platform=epic`.
4. If either client cannot fetch the file, `ClientOptional=False` stops that client joining. Note the error text; it decides the production value of that flag.

## Privacy

Stage A logs counters, enum values and the per-match PlayerID only. It logs no names, Steam IDs or tickets. Raw native logs from the outage step still contain `Login: token` lines; do not paste them.

Reported counters are client-supplied telemetry, not trusted proof.

## Rollback

1. Remove `RS2ClientFixes_v012.RS2ClientFixes` from the server mutator list.
2. Delete `RS2ClientFixes_v012.u` from the server's `BrewedPCServer`, any client `BrewedPC` copy, and the client `Cache`.
3. Restore the previous `ROMutator_RS2ClientFixes.ini` or remove it if originally absent.
4. Restore the `RS2PackageCheck.ini` state you started with.

## Known limits

- The observer keeps `RS2ClientFixes_v012` loaded for the whole client session. Each later release needs its own versioned package name and observer object name so clients can move between versions.
- A drop that happened before the client joined a server running this mutator is invisible to it.
- Test 3 (`rs2probeinit`, the `Init()` trial) has still not run. The probe installed on this client is the old passive rollback build (SHA-256 `85350E09…43A4B5`), which has no console command. Install the plain or restore variant from the test-3 kit first. Stage B depends on test 3.
