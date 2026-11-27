// RS2ClientFixes. Stage A: report. Stage B (v0.1.3): operator-triggered
// Steam re-login for clients stuck after a Steam outage.
//
// One package serves both sides. A mutator exists only where the game is
// hosted, so this class decides the server side: it activates only on a
// dedicated server and gives each connected player a link actor. Clients
// download the same package; the link actor and the session observer run
// there.
//
// The server never calls Init() itself: a dedicated server's Leech login
// uses static credentials that a Steam outage cannot expire. Nothing happens
// to any client until an admin sends a command (WebAdmin console or in-game
// after AdminLogin):
//   rs2cf status             totals here; one line per player in the log
//   rs2cf relink             ask every Steam client whose Steam login was
//                            lost and regained to re-run Init()
//   rs2cf force <who>        ask one client, without the regain test (trials);
//                            <who> = self (in-game only), PlayerID or exact name
//   rs2cf restartmsg [<who>] chat line asking regained Steam players (or one
//                            player) to restart RS2 when convenient
// Use "ROMutate rs2cf ..." to see the reply in the WebAdmin console; plain
// "mutate rs2cf ..." also works and replies as a console message.
// The client refuses unless its own checks pass (see RS2ClientFixesObserver).
class RS2ClientFixes extends ROMutator
    dependson(OnlineSubsystem);

const LOG_PREFIX = "[RS2ClientFixes] v0.1.3 side=server";
const RESTART_TEXT = "Steam had an outage earlier. If the server browser or your rank looks wrong, please restart Rising Storm 2 when this round ends.";

var bool bServerActive;
var bool bSummaryDirty;
var int RelinkNonce;
var int RelinkSent;
var int RelinkResults;
var int RelinkInitCalls;
var int RelinkInitOk;
var float LastRefusedLog;

function InitMutator(string Options, out string ErrorMessage)
{
    super.InitMutator(Options, ErrorMessage);

    if (WorldInfo.NetMode != NM_DedicatedServer)
    {
        `log(LOG_PREFIX @ "event=inactive reason=not-dedicated-server netmode=" $ int(WorldInfo.NetMode),, 'Log');
        return;
    }

    bServerActive = true;
    // Per-map base keeps a previous map's request nonce unlikely to recur.
    RelinkNonce = Rand(1000000000) + 1;
    SetTimer(60.0, true, 'LogSummary');
    `log(LOG_PREFIX @ "event=active mode=report+operator-relink",, 'Log');
}

// GenericPlayerInitialization calls this for new logins and for players
// arriving by seamless travel, so each map gets a fresh link per player.
function NotifyLogin(Controller NewPlayer)
{
    super.NotifyLogin(NewPlayer);

    if (bServerActive)
    {
        AttachLink(PlayerController(NewPlayer));
    }
}

function NotifyLogout(Controller Exiting)
{
    local RS2ClientFixesLink Link;

    if (bServerActive && Exiting != None)
    {
        foreach DynamicActors(class'RS2ClientFixesLink', Link)
        {
            if (Link.Owner == Exiting)
            {
                Link.Destroy();
                bSummaryDirty = true;
            }
        }
    }

    super.NotifyLogout(Exiting);
}

function AttachLink(PlayerController PC)
{
    local RS2ClientFixesLink Link;

    // Remote human players only. WebAdmin controllers and bots have no
    // network connection.
    if (PC == None || NetConnection(PC.Player) == None)
    {
        return;
    }

    foreach DynamicActors(class'RS2ClientFixesLink', Link)
    {
        if (Link.Owner == PC)
        {
            return;
        }
    }

    Link = Spawn(class'RS2ClientFixesLink', PC);
    if (Link == None)
    {
        `log(LOG_PREFIX @ "event=link-failed player=" $ PlayerIdOf(PC),, 'Log');
        return;
    }

    Link.Monitor = self;
    Link.StartOwnerSync();
    bSummaryDirty = true;
}

static function int PlayerIdOf(Controller C)
{
    if (C == None || C.PlayerReplicationInfo == None)
    {
        return -1;
    }
    return C.PlayerReplicationInfo.PlayerID;
}

function NoteReport()
{
    bSummaryDirty = true;
}

function NoteRelinkResult(bool bInitCalled, bool bInitOk)
{
    ++RelinkResults;
    if (bInitCalled)
    {
        ++RelinkInitCalls;
    }
    if (bInitOk)
    {
        ++RelinkInitOk;
    }
    bSummaryDirty = true;
}

// --- Operator commands ----------------------------------------------------

function Mutate(string MutateString, PlayerController Sender)
{
    local string Result;

    if (bServerActive && HandleCommand(MutateString, Sender, Result) && Sender != None && Result != "")
    {
        Sender.ClientMessage(Result);
    }
    super.Mutate(MutateString, Sender);
}

function ROMutate(string MutateString, PlayerController Sender, out string ResultMsg)
{
    local string Result;

    super.ROMutate(MutateString, Sender, ResultMsg);
    if (bServerActive && HandleCommand(MutateString, Sender, Result))
    {
        ResultMsg = Result;
    }
}

// WebAdmin users are Admin controllers; in-game players need AdminLogin.
function bool IsOperator(PlayerController Sender)
{
    return Sender != None && WorldInfo.Game != None && WorldInfo.Game.AccessControl != None
        && WorldInfo.Game.AccessControl.IsAdmin(Sender);
}

// Returns true if the string was an rs2cf command (handled or refused).
function bool HandleCommand(string MutateString, PlayerController Sender, out string Result)
{
    local array<string> Words;
    local string Cmd, Who;
    local int i;

    ParseStringIntoArray(MutateString, Words, " ", true);
    if (Words.Length == 0 || !(Words[0] ~= "rs2cf"))
    {
        return false;
    }

    if (!IsOperator(Sender))
    {
        Result = "rs2cf: admin only";
        // Any player can send mutate. Keep the log bounded.
        if (LastRefusedLog == 0.0 || WorldInfo.TimeSeconds - LastRefusedLog > 10.0)
        {
            LastRefusedLog = WorldInfo.TimeSeconds;
            `log(LOG_PREFIX @ "event=command-refused reason=not-admin player=" $ PlayerIdOf(Sender),, 'Log');
        }
        return true;
    }

    Cmd = "status";
    if (Words.Length > 1)
    {
        Cmd = Locs(Words[1]);
    }
    for (i = 2; i < Words.Length; ++i)
    {
        Who = (Who == "") ? Words[i] : (Who @ Words[i]);
    }

    if (Cmd == "status")
    {
        Result = StatusText(true);
    }
    else if (Cmd == "relink")
    {
        Result = RelinkRegained();
    }
    else if (Cmd == "force")
    {
        Result = RelinkForced(Sender, Who);
    }
    else if (Cmd == "restartmsg")
    {
        Result = RestartMessage(Sender, Who);
    }
    else
    {
        Result = "rs2cf commands: status | relink | force <PlayerID|name|self (in-game)> | restartmsg [<PlayerID|name|self (in-game)>]";
    }

    `log(LOG_PREFIX @ "event=command cmd=" $ Cmd $ " by=" $ PlayerIdOf(Sender) $ " result=\"" $ Result $ "\"",, 'Log');
    return true;
}

static function bool IsRegainedSteam(RS2ClientFixesLink Link)
{
    return Link.bHasReport
        && Link.ReportedPlatform == class'RS2ClientFixesLink'.const.PLATFORM_STEAM
        && Link.ReportedLoginLostLife > 0
        && Link.ReportedLoginRegainedLife > 0;
}

function string RelinkRegained()
{
    local RS2ClientFixesLink Link;
    local int Candidates, Sent, Throttled, Outstanding, NotLoggedIn;

    foreach DynamicActors(class'RS2ClientFixesLink', Link)
    {
        if (!IsRegainedSteam(Link))
        {
            continue;
        }
        ++Candidates;
        // The client checks this too, with fresher state; skip the obvious.
        if (Link.ReportedLogin != LS_LoggedIn)
        {
            ++NotLoggedIn;
            continue;
        }
        if (Link.HasOutstandingRelink())
        {
            ++Outstanding;
            continue;
        }
        if (Link.RequestRelink(++RelinkNonce, false))
        {
            ++Sent;
        }
        else
        {
            ++Throttled;
        }
    }
    RelinkSent += Sent;
    bSummaryDirty = true;
    return "rs2cf relink: regained_steam=" $ Candidates $ " sent=" $ Sent
        $ " not_logged_in=" $ NotLoggedIn $ " outstanding=" $ Outstanding $ " throttled=" $ Throttled
        $ " (results: rs2cf status)";
}

function RS2ClientFixesLink FindTarget(PlayerController Sender, string Who)
{
    local RS2ClientFixesLink Link;
    local PlayerController PC;
    local bool bById;
    local int Id;

    if (Who == "")
    {
        return None;
    }
    bById = (string(int(Who)) == Who);
    Id = int(Who);

    foreach DynamicActors(class'RS2ClientFixesLink', Link)
    {
        PC = PlayerController(Link.Owner);
        if (PC == None || PC.PlayerReplicationInfo == None)
        {
            continue;
        }
        if ((Who ~= "self" && PC == Sender)
            || (bById && PC.PlayerReplicationInfo.PlayerID == Id)
            || (!bById && PC.PlayerReplicationInfo.PlayerName ~= Who))
        {
            return Link;
        }
    }
    return None;
}

function string RelinkForced(PlayerController Sender, string Who)
{
    local RS2ClientFixesLink Link;

    Link = FindTarget(Sender, Who);
    if (Link == None)
    {
        return "rs2cf force: no connected player matches '" $ Who $ "' (use PlayerID or exact name in WebAdmin; self in-game only)";
    }
    if (!Link.bHasReport)
    {
        return "rs2cf force: player " $ PlayerIdOf(Controller(Link.Owner)) $ " has not reported yet; try again after link-ready";
    }
    if (Link.HasOutstandingRelink())
    {
        return "rs2cf force: outstanding request for player " $ PlayerIdOf(Controller(Link.Owner)) $ "; wait for result or retry when request is over 60 s old";
    }
    if (!Link.RequestRelink(++RelinkNonce, true))
    {
        return "rs2cf force: throttled for player " $ PlayerIdOf(Controller(Link.Owner)) $ ", try again in 15 s";
    }
    ++RelinkSent;
    bSummaryDirty = true;
    return "rs2cf force: sent to player " $ PlayerIdOf(Controller(Link.Owner)) $ " (result: rs2cf status)";
}

function string RestartMessage(PlayerController Sender, string Who)
{
    local RS2ClientFixesLink Link;
    local int Sent;

    if (Who != "")
    {
        Link = FindTarget(Sender, Who);
        if (Link == None)
        {
            return "rs2cf restartmsg: no connected player matches '" $ Who $ "' (use PlayerID or exact name in WebAdmin; self in-game only)";
        }
        WorldInfo.Game.BroadcastHandler.BroadcastText(None, PlayerController(Link.Owner), RESTART_TEXT);
        return "rs2cf restartmsg: sent to player " $ PlayerIdOf(Controller(Link.Owner));
    }

    foreach DynamicActors(class'RS2ClientFixesLink', Link)
    {
        if (IsRegainedSteam(Link) && PlayerController(Link.Owner) != None)
        {
            WorldInfo.Game.BroadcastHandler.BroadcastText(None, PlayerController(Link.Owner), RESTART_TEXT);
            ++Sent;
        }
    }
    return "rs2cf restartmsg: sent to " $ Sent $ " regained Steam players";
}

function string StatusText(bool bLogPlayers)
{
    local RS2ClientFixesLink Link;
    local int Links, Reported, Steam, Epic, Regained, RegainedLoggedIn, Pending, Unanswered;
    local string ResultText;

    foreach DynamicActors(class'RS2ClientFixesLink', Link)
    {
        ++Links;
        if (Link.RelinkRequests > 0 && !Link.bRelinkResult)
        {
            if (WorldInfo.TimeSeconds - Link.RelinkRequestTime > class'RS2ClientFixesLink'.const.RELINK_TIMEOUT_SECONDS)
            {
                ++Unanswered;
            }
            else
            {
                ++Pending;
            }
        }
        if (Link.bHasReport)
        {
            ++Reported;
            if (Link.ReportedPlatform == class'RS2ClientFixesLink'.const.PLATFORM_STEAM)
            {
                ++Steam;
            }
            else if (Link.ReportedPlatform == class'RS2ClientFixesLink'.const.PLATFORM_EPIC)
            {
                ++Epic;
            }
            if (IsRegainedSteam(Link))
            {
                ++Regained;
                if (Link.ReportedLogin == LS_LoggedIn)
                {
                    ++RegainedLoggedIn;
                }
            }
        }
        if (bLogPlayers)
        {
            ResultText = "none";
            if (Link.RelinkRequests > 0)
            {
                if (Link.bRelinkResult)
                {
                    ResultText = class'RS2ClientFixesLink'.static.RelinkText(Link.RelinkResultCode);
                }
                else if (WorldInfo.TimeSeconds - Link.RelinkRequestTime > class'RS2ClientFixesLink'.const.RELINK_TIMEOUT_SECONDS)
                {
                    ResultText = "unanswered";
                }
                else
                {
                    ResultText = "pending";
                }
            }
            `log(LOG_PREFIX @ "event=status-player player=" $ PlayerIdOf(Controller(Link.Owner))
                $ " reported=" $ Link.bHasReport
                $ " platform=" $ Link.ReportedPlatform
                $ " login=" $ Link.ReportedLogin
                $ " login_lost_life=" $ Link.ReportedLoginLostLife
                $ " login_regained_life=" $ Link.ReportedLoginRegainedLife
                $ " relink_requests=" $ Link.RelinkRequests
                $ " relink_answered=" $ Link.bRelinkResult
                $ " relink_age_s=" $ ((Link.RelinkRequests > 0 && !Link.bRelinkResult) ? int(WorldInfo.TimeSeconds - Link.RelinkRequestTime) : -1)
                $ " relink_result=" $ ResultText
                $ " init_ok=" $ Link.bRelinkInitOk
                $ " attempts=" $ Link.RelinkAttemptsReported,, 'Log');
        }
    }

    return "rs2cf v0.1.3: links=" $ Links $ " reported=" $ Reported $ " steam=" $ Steam $ " epic=" $ Epic
        $ " regained_steam=" $ Regained $ " regained_logged_in=" $ RegainedLoggedIn
        $ " | relink sent=" $ RelinkSent $ " answered=" $ RelinkResults $ " init_called=" $ RelinkInitCalls
        $ " init_ok=" $ RelinkInitOk $ " pending=" $ Pending $ " unanswered_gt60s=" $ Unanswered $ " (this map)";
}

function LogSummary()
{
    local RS2ClientFixesLink Link;
    local int Links, Reported, Steam, Epic, DropSeenLife, DropSeenHere, LoggedIn, Ignored;

    if (!bSummaryDirty)
    {
        return;
    }
    bSummaryDirty = false;

    foreach DynamicActors(class'RS2ClientFixesLink', Link)
    {
        ++Links;
        Ignored += Link.IgnoredReports + Link.IgnoredRelinkResults;
        if (!Link.bHasReport)
        {
            continue;
        }
        ++Reported;
        if (Link.ReportedPlatform == class'RS2ClientFixesLink'.const.PLATFORM_STEAM)
        {
            ++Steam;
            if (Link.ReportedStatusDropsLife > 0 || Link.ReportedLoginLostLife > 0)
            {
                ++DropSeenLife;
            }
            if (Link.ReportedStatusDropsHere > 0 || Link.ReportedLoginLostHere > 0)
            {
                ++DropSeenHere;
            }
        }
        else if (Link.ReportedPlatform == class'RS2ClientFixesLink'.const.PLATFORM_EPIC)
        {
            ++Epic;
        }
        if (Link.ReportedLogin == LS_LoggedIn)
        {
            ++LoggedIn;
        }
    }

    `log(LOG_PREFIX @ "event=summary links=" $ Links $ " reported=" $ Reported
        $ " steam=" $ Steam $ " epic=" $ Epic
        $ " drop_seen_life=" $ DropSeenLife $ " drop_seen_here=" $ DropSeenHere
        $ " logged_in=" $ LoggedIn $ " ignored_reports=" $ Ignored
        $ " relink_sent=" $ RelinkSent $ " relink_answered=" $ RelinkResults
        $ " relink_init_called=" $ RelinkInitCalls $ " relink_init_ok=" $ RelinkInitOk,, 'Log');
}

defaultproperties
{
}
