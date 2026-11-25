# Stage A training results, 25 November 2026

The training server used RS2ServerFix 0.7.5.0 with `AllowAnyMutator=True`. The test used one Steam client and the HTTP redirect. Raw client logs, which can contain a Steam session ticket, remain private and are not in this repository.

## v011 failure

The client downloaded and ran `RS2ClientFixes_v011.u`, then logged `event=link-idle reason=no-owner` after 60 seconds. No server report was observed in that trial. The build is frozen under its original package name.

## v012 results

`RS2ClientFixes_v012.u` SHA-256: `75F19428CCCF0BF5046BD04D385E1E8A5F89D17CBF89D11FEEE2C994955767DB`.

- The Steam client obtained the package through the redirect, joined, and logged `owner-set source=rpc`, `observer-started`, then `link-ready`. The server received a report with `owner_syncs=1`.
- A map change created a new link with `owner_syncs=2`; the client logged another `link-ready` without a second `observer-started`. The server received the new map's report.
- A temporary Bitdefender rule isolated Steam. The Steam UI showed disconnected. The client logged connection status `3` (`OSCS_NoNetworkConnection`) and login status `2` to `0` (`LS_LoggedIn` to `LS_NotLoggedIn`). The server received both loss counters.
- After the rule was removed, the client logged login status `0` to `2`. The server received `login_regained_here=1` and returned to `logged_in=1`. The last connection-status callback remained `3`; this field records the last callback, not a continuously polled online state.
- The operator confirmed that the game remained connected and WebAdmin remained ranked throughout the simulated outage.
- An Epic client on a separate game launch obtained v012 through the redirect and logged `owner-set source=rpc`, `observer-started platform=2 status_delegate=False login=255`, and `link-ready`. The server received `event=report platform=epic` with `owner_syncs=1` and summarized `epic=1`. The operator confirmed WebAdmin stayed ranked and there was no EAC join error.

The current native log did not expose Leech retry details under its logging configuration. This trial establishes Stage A telemetry delivery on Steam and Epic; it does not establish browser-count repair or behavior during a real Steam maintenance window.
