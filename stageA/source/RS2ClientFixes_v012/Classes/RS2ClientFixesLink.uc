// Per-player courier for one map.
//
// Server: the mutator spawns it owned by the player's controller. It is
// relevant only to that player, so only that client receives it.
// Client: it reads the session observer and sends bounded counters back.
// It is destroyed with the map, so it keeps no session state of its own.
//
// Owner does not replicate for this class: v0.1.1 waited 60 s on a live
// client and logged reason=no-owner. Engine CoverReplicator.uc documents the
// same problem (bSkipActorPropertyReplication) and sends the owner by RPC.
// This class does that too, and retries until the client's first report,
// because the client replaces its controller once just after joining.
class RS2ClientFixesLink extends ReplicationInfo;

const LOG_CLIENT = "[RS2ClientFixes] v0.1.2 side=client";
const LOG_SERVER = "[RS2ClientFixes] v0.1.2 side=server";
const PLATFORM_UNKNOWN = 0;
const PLATFORM_STEAM = 1;
const PLATFORM_EPIC = 2;
const MAX_COUNT = 1000000;
const MAX_OWNER_SYNCS = 30;

// Server only. Never replicated.
var RS2ClientFixes Monitor;
var int OwnerSyncs;
var bool bHasReport;
var float LastReportTime;
var int IgnoredReports;
var byte ReportedPlatform;
var byte ReportedLogin;
var byte ReportedLastStatus;
var int ReportedStatusEventsLife;
var int ReportedStatusEventsHere;
var int ReportedStatusDropsLife;
var int ReportedStatusDropsHere;
var int ReportedStatusGracefulLife;
var int ReportedStatusGracefulHere;
var int ReportedLoginLostLife;
var int ReportedLoginLostHere;
var int ReportedLoginRegainedLife;
var int ReportedLoginRegainedHere;

// Client only.
var bool bLocalOwnerLogged;
var int ClientWaits;
var bool bClientReady;
var bool bClientSent;
var int ClientSentSequence;
var float ClientSentTime;

simulated event PostBeginPlay()
{
    super.PostBeginPlay();

    if (WorldInfo.NetMode == NM_Client)
    {
        SetTimer(1.0, true, 'ClientPoll');
    }
}

// Server: called by the mutator right after spawning. Sends the owner now
// and every 2 s until the client's first report arrives, at most 30 times.
function StartOwnerSync()
{
    SendOwner();
    SetTimer(2.0, true, 'SendOwner');
}

function SendOwner()
{
    if (bHasReport || PlayerController(Owner) == None || OwnerSyncs >= MAX_OWNER_SYNCS)
    {
        ClearTimer('SendOwner');
        return;
    }
    ++OwnerSyncs;
    ClientSetOwner(PlayerController(Owner));
}

// Client. The same workaround as Engine CoverReplicator.ClientSetOwner. A
// reference that arrives before the client knows its controller is None;
// the server's retry covers that.
reliable client function ClientSetOwner(PlayerController PC)
{
    if (PC != None && PC.IsLocalPlayerController() && Owner != PC)
    {
        SetOwner(PC);
        `log(LOG_CLIENT @ "event=owner-set source=rpc",, 'Log');
    }
}

simulated function ClientPoll()
{
    local PlayerController PC;
    local RS2ClientFixesObserver Observer;

    PC = PlayerController(Owner);
    if (PC == None || !PC.IsLocalPlayerController())
    {
        // Only the owning player ever receives this actor, so the local
        // controller is its owner. This also covers the controller the
        // client replaces just after joining.
        PC = GetALocalPlayerController();
        if (PC != None)
        {
            SetOwner(PC);
            if (!bLocalOwnerLogged)
            {
                bLocalOwnerLogged = true;
                `log(LOG_CLIENT @ "event=owner-set source=local applied=" $ (PlayerController(Owner) == PC),, 'Log');
            }
        }
    }

    if (PC != None && PC.IsLocalPlayerController() && PlayerController(Owner) == PC)
    {
        Observer = class'RS2ClientFixesObserver'.static.Acquire();
    }

    if (Observer == None)
    {
        ++ClientWaits;
        if (ClientWaits == 60)
        {
            ClearTimer('ClientPoll');
            if (PC == None)
            {
                `log(LOG_CLIENT @ "event=link-idle reason=no-local-controller",, 'Log');
            }
            else if (PlayerController(Owner) != PC)
            {
                `log(LOG_CLIENT @ "event=link-idle reason=no-owner",, 'Log');
            }
            else
            {
                `log(LOG_CLIENT @ "event=link-idle reason=no-observer",, 'Log');
            }
        }
        return;
    }

    if (!Observer.ObserveServer(WorldInfo.GetAddressURL()))
    {
        return;
    }

    if (!bClientReady)
    {
        bClientReady = true;
        `log(LOG_CLIENT @ "event=link-ready",, 'Log');
    }

    // Report once per map, then on each change, at most every 5 seconds.
    if (bClientSent)
    {
        if (Observer.Sequence == ClientSentSequence)
        {
            return;
        }
        if (WorldInfo.TimeSeconds - ClientSentTime < 5.0)
        {
            return;
        }
    }

    bClientSent = true;
    ClientSentSequence = Observer.Sequence;
    ClientSentTime = WorldInfo.TimeSeconds;
    ServerReport(Observer.PlatformCode(), Observer.LoginStatus, Observer.LastConnectionStatus,
        Observer.ServerSession,
        Observer.StatusEvents, Observer.StatusEvents - Observer.BaseStatusEvents,
        Observer.StatusDrops, Observer.StatusDrops - Observer.BaseStatusDrops,
        Observer.StatusGraceful, Observer.StatusGraceful - Observer.BaseStatusGraceful,
        Observer.LoginLost, Observer.LoginLost - Observer.BaseLoginLost,
        Observer.LoginRegained, Observer.LoginRegained - Observer.BaseLoginRegained,
        int(Observer.ObservedSeconds), int(Observer.ObservedSeconds - Observer.ServerStartSeconds),
        int(Observer.ObservedSeconds - Observer.LastChangeSeconds), Observer.Sequence);
}

reliable server function ServerReport(byte Platform, byte Login, byte LastStatus,
    int ServerSession, int StatusEventsLife, int StatusEventsHere,
    int StatusDropsLife, int StatusDropsHere,
    int StatusGracefulLife, int StatusGracefulHere,
    int LoginLostLife, int LoginLostHere,
    int LoginRegainedLife, int LoginRegainedHere,
    int ObservedSecondsLife, int ObservedSecondsHere,
    int SinceChangeSeconds, int Sequence)
{
    local string PlatformText;

    if (WorldInfo.NetMode != NM_DedicatedServer || Monitor == None)
    {
        return;
    }

    // Any client can call this as often as it likes. Keep the log bounded.
    if (bHasReport && WorldInfo.TimeSeconds - LastReportTime < 4.0)
    {
        ++IgnoredReports;
        return;
    }

    bHasReport = true;
    LastReportTime = WorldInfo.TimeSeconds;

    ReportedPlatform = Platform;
    if (ReportedPlatform != PLATFORM_STEAM && ReportedPlatform != PLATFORM_EPIC)
    {
        ReportedPlatform = PLATFORM_UNKNOWN;
    }
    ReportedLogin = Login;
    ReportedLastStatus = LastStatus;
    ReportedStatusEventsLife = Clamp(StatusEventsLife, 0, MAX_COUNT);
    ReportedStatusEventsHere = Clamp(StatusEventsHere, 0, MAX_COUNT);
    ReportedStatusDropsLife = Clamp(StatusDropsLife, 0, MAX_COUNT);
    ReportedStatusDropsHere = Clamp(StatusDropsHere, 0, MAX_COUNT);
    ReportedStatusGracefulLife = Clamp(StatusGracefulLife, 0, MAX_COUNT);
    ReportedStatusGracefulHere = Clamp(StatusGracefulHere, 0, MAX_COUNT);
    ReportedLoginLostLife = Clamp(LoginLostLife, 0, MAX_COUNT);
    ReportedLoginLostHere = Clamp(LoginLostHere, 0, MAX_COUNT);
    ReportedLoginRegainedLife = Clamp(LoginRegainedLife, 0, MAX_COUNT);
    ReportedLoginRegainedHere = Clamp(LoginRegainedHere, 0, MAX_COUNT);

    PlatformText = "unknown";
    if (ReportedPlatform == PLATFORM_STEAM)
    {
        PlatformText = "steam";
    }
    else if (ReportedPlatform == PLATFORM_EPIC)
    {
        PlatformText = "epic";
    }

    `log(LOG_SERVER @ "event=report player=" $ class'RS2ClientFixes'.static.PlayerIdOf(Controller(Owner))
        $ " platform=" $ PlatformText
        $ " login=" $ ReportedLogin
        $ " last_status=" $ ReportedLastStatus
        $ " server_session=" $ Clamp(ServerSession, 0, MAX_COUNT)
        $ " status_events_life=" $ ReportedStatusEventsLife
        $ " status_events_here=" $ ReportedStatusEventsHere
        $ " status_drops_life=" $ ReportedStatusDropsLife
        $ " status_drops_here=" $ ReportedStatusDropsHere
        $ " status_graceful_life=" $ ReportedStatusGracefulLife
        $ " status_graceful_here=" $ ReportedStatusGracefulHere
        $ " login_lost_life=" $ ReportedLoginLostLife
        $ " login_lost_here=" $ ReportedLoginLostHere
        $ " login_regained_life=" $ ReportedLoginRegainedLife
        $ " login_regained_here=" $ ReportedLoginRegainedHere
        $ " observed_s_life=" $ Clamp(ObservedSecondsLife, 0, MAX_COUNT)
        $ " observed_s_here=" $ Clamp(ObservedSecondsHere, 0, MAX_COUNT)
        $ " since_change_s=" $ Clamp(SinceChangeSeconds, 0, MAX_COUNT)
        $ " seq=" $ Clamp(Sequence, 0, MAX_COUNT)
        $ " owner_syncs=" $ OwnerSyncs
        $ " ignored=" $ IgnoredReports,, 'Log');

    Monitor.NoteReport();
}

defaultproperties
{
    bAlwaysRelevant=false
    bOnlyRelevantToOwner=true
    NetUpdateFrequency=1
}
