# RS2ClientFixes

RS2ClientFixes is an UnrealScript mutator for Rising Storm 2: Vietnam. The current `v011` package is **Stage A telemetry for a training trial**. It records a joined client's Steam connection and login-status changes and reports counters to the dedicated server. Epic clients report their platform without Steam status polling. Client-supplied counters are observations, not trusted proof.

Stage A does not repair Steam authentication, Leech sessions, or server-browser player counts. It does not call `Init()` or change login credentials. The package compiled successfully, but has **not yet been tested in game**.

## Files

| Path | Purpose |
| --- | --- |
| [`stageA/source/RS2ClientFixes_v011/Classes/`](stageA/source/RS2ClientFixes_v011/Classes/) | Three UnrealScript classes and package flags. |
| [`stageA/deploy/ROGame/BrewedPC/RS2ClientFixes_v011.u`](stageA/deploy/ROGame/BrewedPC/RS2ClientFixes_v011.u) | Frozen compiled package for the training trial. |
| [`stageA/deploy/ROGame/Config/ROMutator_RS2ClientFixes.ini`](stageA/deploy/ROGame/Config/ROMutator_RS2ClientFixes.ini) | Server-side WebAdmin listing. |
| [`stageA/OPERATOR.md`](stageA/OPERATOR.md) | Training setup, delivery checks, expected logs, and rollback. |

## Training setup

Follow the [operator guide](stageA/OPERATOR.md). Install the `.u` on the training server and place the `.ini` in its `ROGame/Config` directory. Add `RS2ClientFixes_v011.RS2ClientFixes` to the server's mutator list. The same `.u` runs its client-side observer after a client joins. The package flags are `AllowDownload=True`, `ClientOptional=False`, and `ServerSideOnly=False`.

The package is not on the current safelist. The training plan uses RS2ServerFix 0.7.5.0 with `AllowAnyMutator=True` and checks ranked status, EAC acceptance, Steam and Epic delivery, and the resulting logs. This repository does not contain RS2ServerFix or the game SDK.

## Build and version identity

The committed `v011` package was built with an isolated RS2 SDK and `VNEditor.exe make`. Its SHA-256 is:

```text
D10AE6CAB7CFFDDDB61CD3E7F4E336E324C3E24F0ADB78A6F50EC1298F4F2A80
```

UE3 assigns a new package GUID on compilation. Once a package has been served to clients, do not rebuild under the same `_vNNN` name. For the next build, increment the source package folder and `.upkg` name, the observer object name, the log version, the compiled `.u` name, the WebAdmin `ClassName`, and the operator guide together. Keep the game and SDK binaries out of this repository.

## License

The project is licensed under [GPL-3.0](LICENSE). Rising Storm 2: Vietnam and its SDK belong to their respective owners; they are not included here.
