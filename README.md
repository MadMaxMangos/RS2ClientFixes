# RS2ClientFixes

RS2ClientFixes is an UnrealScript mutator for Rising Storm 2: Vietnam. The current `v012` package is **Stage A telemetry for a training trial**. It records a joined client's Steam connection and login-status changes and reports counters to the dedicated server. Epic clients are designed to report their platform without Steam status polling. Client-supplied counters are observations, not trusted proof.

Stage A does not repair Steam authentication, Leech sessions, or server-browser player counts. It does not call `Init()` or change login credentials. `v012` passed training checks for Steam and Epic redirect delivery, owner handoff, server reporting, Steam map travel, and a simulated Steam loss and return. A real maintenance outage remains untested. See the [trial notes](stageA/TRIAL-NOTES-2026-11-25.md).

## Files

| Path | Purpose |
| --- | --- |
| [`stageA/source/RS2ClientFixes_v012/Classes/`](stageA/source/RS2ClientFixes_v012/Classes/) | Current UnrealScript classes and package flags. |
| [`stageA/deploy/ROGame/BrewedPC/RS2ClientFixes_v012.u`](stageA/deploy/ROGame/BrewedPC/RS2ClientFixes_v012.u) | Frozen compiled package for the current training trial. |
| [`stageA/deploy/ROGame/Config/ROMutator_RS2ClientFixes.ini`](stageA/deploy/ROGame/Config/ROMutator_RS2ClientFixes.ini) | Server-side WebAdmin listing. |
| [`stageA/OPERATOR.md`](stageA/OPERATOR.md) | Training setup, delivery checks, expected logs, and rollback. |

## Training setup

Follow the [operator guide](stageA/OPERATOR.md). On the training server, install the `.u` beside its other mutator packages in `ROGame/BrewedPCServer` and place the `.ini` in `ROGame/Config`. Add `RS2ClientFixes_v012.RS2ClientFixes` to the server's mutator list. The same `.u` reaches clients through the HTTP redirect. The package flags are `AllowDownload=True`, `ClientOptional=False`, and `ServerSideOnly=False`.

The package is not on the current safelist. The training plan uses RS2ServerFix 0.7.5.0 with `AllowAnyMutator=True` and checks ranked status, EAC acceptance, Steam and Epic delivery, and the resulting logs. This repository does not contain RS2ServerFix or the game SDK.

## Build and version identity

The committed `v012` package was built with an isolated RS2 SDK and `VNEditor.exe make`. Its SHA-256 is:

```text
75F19428CCCF0BF5046BD04D385E1E8A5F89D17CBF89D11FEEE2C994955767DB
```

UE3 assigns a new package GUID on compilation. Once a package has been served to clients, do not rebuild under the same `_vNNN` name. For the next build, increment the source package folder and `.upkg` name, the observer object name, the log version, the compiled `.u` name, the WebAdmin `ClassName`, and the operator guide together. Keep the game and SDK binaries out of this repository.

The archived `v011` source and package are retained for comparison. Its client link failed to receive its owner in the first live trial and never reported. Do not deploy `v011` for telemetry.

## License

The project is licensed under [GPL-3.0](LICENSE). Rising Storm 2: Vietnam and its SDK belong to their respective owners; they are not included here.
