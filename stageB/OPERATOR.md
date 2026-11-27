# RS2ClientFixes v013 operator guide

This is the frozen v013 package used in the 27 November 2026 training trial and five-server pilot. Its `.u` SHA-256 is `C4F89112AEA0132952F17538934AD79E63E8A17DA0F9D46498A94F2B88C10E4C`; the listing SHA-256 is `9579CFF35C24BE28B3F0EBB4DFA979CB6D67723A0D40A956EC5BFCE6265E57D7`.

## Install

1. With the server stopped, preserve the existing mutator package, listing and launch command for rollback.
2. Copy `deploy/ROGame/BrewedPC/RS2ClientFixes_v013.u` to the server's `ROGame/BrewedPCServer`. Copy `deploy/ROGame/Config/ROMutator_RS2ClientFixes.ini` to its `ROGame/Config`.
3. Add `RS2ClientFixes_v013.RS2ClientFixes` to the **existing** `?mutator=` list. Keep the other mutators. Serve the same `.u` on the server's HTTP redirect so clients can join.
4. Start the server. Confirm `[RS2ClientFixes] v0.1.3 side=server event=active mode=report+operator-relink`, a client `event=link-ready`, and a server report. Check WebAdmin and the in-game browser for the expected ranked state and counts.

The current -=PR=- pilot uses RS2ServerFix 0.7.5.0 with `RS2PackageCheck.ini` containing `AllowAnyMutator=True`, because v013 is not on the legacy safelist. That configuration is separate from this package. The package remains inert with respect to login until an admin issues a command.

## WebAdmin commands

Use `ROMutate` in the management console to see the reply:

| Command | Effect |
| --- | --- |
| `ROMutate rs2cf status` | Summarizes current-map links, Steam/Epic reports, relink requests and outcomes; logs one `status-player` line per reported player. |
| `ROMutate rs2cf relink` | Requests a refresh only for Steam clients that reported a logout followed by a login regain. The client waits at least 30 seconds after regain and enforces its own checks. |
| `ROMutate rs2cf force <PlayerID>` | Requests a refresh for one reported client without the regain requirement; intended for controlled trials. Epic clients refuse it. |
| `ROMutate rs2cf restartmsg [<PlayerID>]` | Sends a restart suggestion to eligible Steam clients or one selected player. |

An in-game admin can also use `mutate rs2cf ...` after `AdminLogin`; `self` is supported for a targeted in-game command. `force` and `relink` do not directly change server-side Leech registration. A response that a request was sent is not proof the client ran `Init()`; check `rs2cf status` and the `relink-result` log. A reported `init_ok=True` is not proof of public browser repair.

The client accepts at most two `Init()` calls per game process. The server throttles requests for the same player and does not send a new one while an earlier request is pending. Status counters reset on map load. Do not repeatedly issue commands while a request is outstanding.

## Outage observation

Record the server's browser count from an independent client before the outage, after Steam returns, and at 1, 2, 3 and 5 minutes after a deliberate `relink`. Keep the game client connected during the observation. Compare `rs2cf status`, client Leech login results and the external browser count; backend projection can lag. A map change and a full client restart are separate observations, because both can change client registration. Do not mix `rs2leech recover` into the same measurement window.

The healthy training trial proved an operator-forced new ticket during a match without a visible gameplay or ranked-state regression. It did **not** prove that a real code-1 refusal clears, that connected players re-register, or that public counts recover. Raw client logs can contain `Login: token`; share only a redacted report.

## Rollback

Remove `RS2ClientFixes_v013.RS2ClientFixes` from the launch mutator list, stop the server, and restore its previous listing and mutator files. Remove the v013 package from the redirect when no server uses it. Restore any separately changed RS2ServerFix files or configuration from that server's own baseline. Then restart and verify normal joining and ranked state. Do not hot-swap a loaded `.u` or DLL.
