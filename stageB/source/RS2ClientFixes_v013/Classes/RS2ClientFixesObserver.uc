// Session observer for a joined client.
//
// It lives on the game viewport, so it survives map changes on the same
// server; the per-map link actor cannot. It keeps no reference to any actor
// or world object, so it cannot hold a level in memory after travel.
//
// Stage B (v0.1.3): it can also re-run the Steam subsystem's Init(), which is
// the only path that mints a new Leech ticket (client 805E0D61: execInit ->
// native Init -> InitSteamworks -> the single Leech-ticket mint). It does so
// ONLY when the server asks (an operator command) and only:
//   - on a Steam build, never Epic;
//   - while Steam reports the local player logged in;
//   - after Steam's login was lost and then regained in this process (a
//     forced request, for trials, skips this test), at least 30 s after the
//     regain;
//   - at most twice per game process.
// The call runs from Tick, the same context as the main-menu test that
// passed (RS2CFInitTest_v002), with the same save and restore of the three
// interface references that Init() overwrites.
class RS2ClientFixesObserver extends Interaction within GameViewportClient;

const LOG_CLIENT = "[RS2ClientFixes] v0.1.3 side=client";
const OBSERVER_NAME = "RS2ClientFixesObserver_v013";
const UNKNOWN_STATUS = 255;
const MAX_RELINK_ATTEMPTS = 2;
const RELINK_SETTLE_SECONDS = 30.0;

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
var bool bLoginLossOpen;
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

// Stage B relink state, for the whole game process.
var int RelinkAttempts;
var int RegainedHandled;
var float RegainedAtSeconds;
var bool bRelinkQueued;
var bool bRelinkQueuedForce;
var int RelinkQueuedNonce;
var int RequestSequence;
var int QueuedRequestSequence;
// The latest relink outcome. The link that asked sends it to the server.
var int ResultSequence;
var int ResultNonce;
var int ResultRequestSequence;
var byte ResultCode;
var bool bResultInitOk;
var byte ResultLoginAfter;

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

    if (bRelinkQueued)
    {
        bRelinkQueued = false;
        RunRelink();
    }

    PollAge += FMin(DeltaTime, 2.0);
    if (PollAge < 2.0)
    {
        return;
    }
    PollAge = 0.0;
    PollLogin();
}

function NotifyGameSessionEnded()
{
    super.NotifyGameSessionEnded();
    if (bRelinkQueued)
    {
        `log(LOG_CLIENT @ "event=relink-dropped reason=session-ended nonce=" $ RelinkQueuedNonce,, 'Log');
        bRelinkQueued = false;
        RelinkQueuedNonce = 0;
        QueuedRequestSequence = 0;
    }
}

function byte CurrentLogin()
{
    local Engine ClientEngine;
    local OnlineSubsystem OnlineSub;
    local LocalPlayer Player;

    ClientEngine = class'Engine'.static.GetEngine();
    OnlineSub = class'GameEngine'.static.GetOnlineSubsystem();
    if (ClientEngine == None || OnlineSub == None || OnlineSub.PlayerInterface == None
        || ClientEngine.GamePlayers.Length < 1)
    {
        return UNKNOWN_STATUS;
    }

    Player = ClientEngine.GamePlayers[0];
    if (Player == None || Player.ControllerId < 0 || Player.ControllerId > 255)
    {
        return UNKNOWN_STATUS;
    }
    return OnlineSub.PlayerInterface.GetLoginStatus(byte(Player.ControllerId));
}

function PollLogin()
{
    local byte Current;

    // The Epic build's Steam user path is unverified, and Epic players are
    // never refresh candidates. Report their login status as unknown.
    if (bEpicBuild)
    {
        return;
    }

    Current = CurrentLogin();
    if (Current == UNKNOWN_STATUS || Current == LoginStatus)
    {
        return;
    }

    if (LoginStatus == LS_LoggedIn)
    {
        ++LoginLost;
        bLoginLossOpen = true;
    }
    else if (Current == LS_LoggedIn && bLoginLossOpen)
    {
        // Stricter than Stage A: startup login is not a regain without an observed loss.
        ++LoginRegained;
        RegainedAtSeconds = ObservedSeconds;
        bLoginLossOpen = false;
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

// Returns RELINK_OK when a relink may run now, otherwise the refusal code.
function byte RelinkRefusal(bool bForce)
{
    local Engine ClientEngine;

    if (bEpicBuild)
    {
        return class'RS2ClientFixesLink'.const.RELINK_EPIC;
    }
    if (RelinkAttempts >= MAX_RELINK_ATTEMPTS)
    {
        return class'RS2ClientFixesLink'.const.RELINK_CAP;
    }
    ClientEngine = class'Engine'.static.GetEngine();
    if (ClientEngine == None || ClientEngine.GameViewport != Outer || ClientEngine.GamePlayers.Length != 1)
    {
        return class'RS2ClientFixesLink'.const.RELINK_VIEWPORT;
    }
    if (OnlineSubsystemSteamworks(class'GameEngine'.static.GetOnlineSubsystem()) == None)
    {
        return class'RS2ClientFixesLink'.const.RELINK_NOT_STEAM;
    }
    // Init() mints only while Steam reports the player logged on.
    if (CurrentLogin() != LS_LoggedIn)
    {
        return class'RS2ClientFixesLink'.const.RELINK_NOT_LOGGED_IN;
    }
    if (!bForce)
    {
        if (LoginRegained <= RegainedHandled)
        {
            return class'RS2ClientFixesLink'.const.RELINK_NO_REGAIN;
        }
        if (ObservedSeconds - RegainedAtSeconds < RELINK_SETTLE_SECONDS)
        {
            return class'RS2ClientFixesLink'.const.RELINK_SETTLING;
        }
    }
    return class'RS2ClientFixesLink'.const.RELINK_OK;
}

// Called by the link when the server asks. A refusal is answered at once; an
// accepted request runs on the next Tick. False means the link must answer busy.
function bool QueueRelink(int Nonce, bool bForce)
{
    local byte Code;

    if (bRelinkQueued)
    {
        `log(LOG_CLIENT @ "event=relink-dropped reason=already-queued nonce=" $ Nonce,, 'Log');
        return false;
    }

    ++RequestSequence;
    Code = RelinkRefusal(bForce);
    if (Code != class'RS2ClientFixesLink'.const.RELINK_OK)
    {
        StoreResult(Nonce, RequestSequence, Code, false, CurrentLogin());
        `log(LOG_CLIENT @ "event=relink-refused nonce=" $ Nonce $ " force=" $ bForce
            $ " reason=" $ class'RS2ClientFixesLink'.static.RelinkText(Code)
            $ " attempts=" $ RelinkAttempts $ " regained_life=" $ LoginRegained
            $ " regained_handled=" $ RegainedHandled,, 'Log');
        return true;
    }

    bRelinkQueued = true;
    bRelinkQueuedForce = bForce;
    RelinkQueuedNonce = Nonce;
    QueuedRequestSequence = RequestSequence;
    `log(LOG_CLIENT @ "event=relink-queued nonce=" $ Nonce $ " force=" $ bForce,, 'Log');
    return true;
}

function RunRelink()
{
    local byte Code;
    local int RequestNonce, RequestSerial;
    local bool bRequestForce;
    local OnlineSubsystemSteamworks Steam;
    local bool bInitSucceeded;
    local OnlineGameInterface SavedGame;
    local OnlineGameInterfaceImpl SavedImpl;
    local TWWorkshopSteamWorks SavedWorkshop;
    local byte LoginAfter;

    RequestNonce = RelinkQueuedNonce;
    RequestSerial = QueuedRequestSequence;
    bRequestForce = bRelinkQueuedForce;
    // State can change between the request and this tick. Check again.
    Code = RelinkRefusal(bRequestForce);
    if (Code != class'RS2ClientFixesLink'.const.RELINK_OK)
    {
        StoreResult(RequestNonce, RequestSerial, Code, false, CurrentLogin());
        `log(LOG_CLIENT @ "event=relink-refused nonce=" $ RequestNonce
            $ " stage=run reason=" $ class'RS2ClientFixesLink'.static.RelinkText(Code),, 'Log');
        return;
    }

    Steam = OnlineSubsystemSteamworks(class'GameEngine'.static.GetOnlineSubsystem());
    SavedGame = Steam.GameInterface;
    SavedImpl = Steam.GameInterfaceImpl;
    SavedWorkshop = Steam.WorkshopInterface;

    // Consume the attempt and the regain before Init emits native callbacks.
    ++RelinkAttempts;
    RegainedHandled = LoginRegained;
    `log(LOG_CLIENT @ "event=relink-begin nonce=" $ RequestNonce $ " force=" $ bRequestForce
        $ " attempt=" $ RelinkAttempts $ " regained_life=" $ LoginRegained,, 'Log');
    bInitSucceeded = Steam.Init();
    Steam.GameInterface = SavedGame;
    Steam.GameInterfaceImpl = SavedImpl;
    Steam.WorkshopInterface = SavedWorkshop;

    LoginAfter = CurrentLogin();
    StoreResult(RequestNonce, RequestSerial, class'RS2ClientFixesLink'.const.RELINK_OK, bInitSucceeded, LoginAfter);
    `log(LOG_CLIENT @ "event=relink-returned nonce=" $ RequestNonce $ " init_ok=" $ bInitSucceeded
        $ " login_after=" $ LoginAfter $ " references_restored=true",, 'Log');
}

function StoreResult(int Nonce, int RequestSerial, byte Code, bool bInitOk, byte LoginAfter)
{
    ++ResultSequence;
    ResultNonce = Nonce;
    ResultRequestSequence = RequestSerial;
    ResultCode = Code;
    bResultInitOk = bInitOk;
    ResultLoginAfter = LoginAfter;
}

defaultproperties
{
}
