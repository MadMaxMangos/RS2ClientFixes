// Session observer for a joined client.
//
// It lives on the game viewport, so it survives map changes on the same
// server; the per-map link actor cannot. It keeps no reference to any actor
// or world object, so it cannot hold a level in memory after travel. It only
// reads Steam's state. It never calls a login, Init or authentication
// function.
class RS2ClientFixesObserver extends Interaction within GameViewportClient;

const LOG_CLIENT = "[RS2ClientFixes] v0.1.1 side=client";
const OBSERVER_NAME = "RS2ClientFixesObserver_v011";
const UNKNOWN_STATUS = 255;

var bool bInserted;
var bool bDelegateBound;
var bool bEpicBuild;
var byte LoginStatus;
var byte LastConnectionStatus;
var int StatusEvents;
var int StatusDrops;
var int StatusGraceful;
var int LoginLost;
var int LoginRegained;
var string ServerIdentity;
var int ServerSession;
var int BaseStatusEvents;
var int BaseStatusDrops;
var int BaseStatusGraceful;
var int BaseLoginLost;
var int BaseLoginRegained;
var float ServerStartSeconds;
var int Sequence;
var float ObservedSeconds;
var float LastChangeSeconds;
var float PollAge;

static function RS2ClientFixesObserver Acquire()
{
    local Engine ClientEngine;
    local GameViewportClient HostViewport;
    local Object Existing;
    local RS2ClientFixesObserver Observer;

    ClientEngine = class'Engine'.static.GetEngine();
    if (ClientEngine == None || ClientEngine.GameViewport == None)
    {
        return None;
    }
    HostViewport = ClientEngine.GameViewport;

    Existing = FindObject(PathName(HostViewport) $ "." $ OBSERVER_NAME, class'Object');
    if (Existing != None)
    {
        Observer = RS2ClientFixesObserver(Existing);
        // Never adopt a differently typed object, or one that failed to insert.
        if (Observer == None || !Observer.bInserted)
        {
            return None;
        }
        return Observer;
    }

    Observer = new(HostViewport, OBSERVER_NAME) class'RS2ClientFixesObserver';
    if (Observer == None)
    {
        return None;
    }
    if (HostViewport.InsertInteraction(Observer) < 0)
    {
        `log(LOG_CLIENT @ "event=observer-failed reason=insertion",, 'Log');
        return None;
    }

    Observer.bInserted = true;
    Observer.Begin();
    return Observer;
}

function Begin()
{
    local OnlineSubsystem OnlineSub;

    bEpicBuild = class'WorldInfo'.static.IsEOSBuild();
    LoginStatus = UNKNOWN_STATUS;
    LastConnectionStatus = UNKNOWN_STATUS;

    OnlineSub = class'GameEngine'.static.GetOnlineSubsystem();
    if (!bEpicBuild && OnlineSub != None && OnlineSub.SystemInterface != None)
    {
        OnlineSub.SystemInterface.AddConnectionStatusChangeDelegate(OnSteamConnectionStatus);
        bDelegateBound = true;
    }

    PollLogin();

    `log(LOG_CLIENT @ "event=observer-started platform=" $ PlatformCode()
        $ " status_delegate=" $ bDelegateBound $ " login=" $ LoginStatus,, 'Log');
}

function byte PlatformCode()
{
    if (bEpicBuild)
    {
        return class'RS2ClientFixesLink'.const.PLATFORM_EPIC;
    }
    return class'RS2ClientFixesLink'.const.PLATFORM_STEAM;
}

// Store only the address text, never the world or its actors. The link calls
// this on every poll, including the first poll after a map change.
function bool ObserveServer(string CurrentIdentity)
{
    if (CurrentIdentity == "")
    {
        return false;
    }
    if (ServerIdentity != CurrentIdentity)
    {
        ServerIdentity = CurrentIdentity;
        ++ServerSession;
        BaseStatusEvents = StatusEvents;
        BaseStatusDrops = StatusDrops;
        BaseStatusGraceful = StatusGraceful;
        BaseLoginLost = LoginLost;
        BaseLoginRegained = LoginRegained;
        ServerStartSeconds = ObservedSeconds;
        NoteChange();
    }
    return true;
}

event Tick(float DeltaTime)
{
    if (!bInserted || DeltaTime <= 0.0)
    {
        return;
    }

    // Approximate session clock. Not a precise outage timer.
    ObservedSeconds += FMin(DeltaTime, 600.0);
    PollAge += FMin(DeltaTime, 2.0);
    if (PollAge < 2.0)
    {
        return;
    }
    PollAge = 0.0;
    PollLogin();
}

function PollLogin()
{
    local Engine ClientEngine;
    local OnlineSubsystem OnlineSub;
    local LocalPlayer Player;
    local byte Current;

    // The Epic build's Steam user path is unverified, and Epic players are
    // never refresh candidates. Report their login status as unknown.
    if (bEpicBuild)
    {
        return;
    }

    ClientEngine = class'Engine'.static.GetEngine();
    OnlineSub = class'GameEngine'.static.GetOnlineSubsystem();
    if (ClientEngine == None || OnlineSub == None || OnlineSub.PlayerInterface == None
        || ClientEngine.GamePlayers.Length < 1)
    {
        return;
    }

    Player = ClientEngine.GamePlayers[0];
    if (Player == None || Player.ControllerId < 0 || Player.ControllerId > 255)
    {
        return;
    }

    Current = OnlineSub.PlayerInterface.GetLoginStatus(byte(Player.ControllerId));
    if (Current == LoginStatus)
    {
        return;
    }

    if (LoginStatus == LS_LoggedIn)
    {
        ++LoginLost;
    }
    else if (Current == LS_LoggedIn && LoginStatus != UNKNOWN_STATUS)
    {
        ++LoginRegained;
    }

    `log(LOG_CLIENT @ "event=login-change from=" $ LoginStatus $ " to=" $ Current
        $ " lost_life=" $ LoginLost $ " lost_here=" $ (LoginLost - BaseLoginLost)
        $ " regained_life=" $ LoginRegained
        $ " regained_here=" $ (LoginRegained - BaseLoginRegained),, 'Log');
    LoginStatus = Current;
    NoteChange();
}

// Steam's disconnect and reconnect callbacks reach script here. A start-up
// broadcast of OSCS_Connected is counted as an event, not as a drop.
function OnSteamConnectionStatus(EOnlineServerConnectionStatus NewConnectionStatus)
{
    if (bEpicBuild)
    {
        return;
    }
    ++StatusEvents;
    if (NewConnectionStatus == OSCS_NotConnected)
    {
        ++StatusGraceful;
    }
    else if (NewConnectionStatus != OSCS_Connected)
    {
        ++StatusDrops;
    }
    LastConnectionStatus = NewConnectionStatus;

    `log(LOG_CLIENT @ "event=steam-status status=" $ LastConnectionStatus
        $ " events_life=" $ StatusEvents
        $ " events_here=" $ (StatusEvents - BaseStatusEvents)
        $ " drops_life=" $ StatusDrops $ " drops_here=" $ (StatusDrops - BaseStatusDrops)
        $ " graceful_life=" $ StatusGraceful
        $ " graceful_here=" $ (StatusGraceful - BaseStatusGraceful),, 'Log');
    NoteChange();
}

function NoteChange()
{
    ++Sequence;
    LastChangeSeconds = ObservedSeconds;
}

defaultproperties
{
}
