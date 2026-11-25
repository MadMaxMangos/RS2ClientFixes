// RS2ClientFixes, Stage A: report only.
//
// One package serves both sides. A mutator exists only where the game is
// hosted, so this class decides the server side: it activates only on a
// dedicated server and gives each connected player a link actor. Clients
// download the same package; the link actor and the session observer run
// there. Nothing in Stage A calls a Steam login, Init or authentication
// function. It measures what a client can see during a Steam outage.
class RS2ClientFixes extends ROMutator
    dependson(OnlineSubsystem);

const LOG_PREFIX = "[RS2ClientFixes] v0.1.2 side=server";

var bool bServerActive;
var bool bSummaryDirty;

function InitMutator(string Options, out string ErrorMessage)
{
    super.InitMutator(Options, ErrorMessage);

    if (WorldInfo.NetMode != NM_DedicatedServer)
    {
        `log(LOG_PREFIX @ "event=inactive reason=not-dedicated-server netmode=" $ int(WorldInfo.NetMode),, 'Log');
        return;
    }

    bServerActive = true;
    SetTimer(60.0, true, 'LogSummary');
    `log(LOG_PREFIX @ "event=active mode=report-only",, 'Log');
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
        Ignored += Link.IgnoredReports;
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
        $ " logged_in=" $ LoggedIn $ " ignored_reports=" $ Ignored,, 'Log');
}

defaultproperties
{
}
