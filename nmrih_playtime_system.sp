/**
 * NMRiH Play Time HUD (Fixed)
 * - Uses MAXPLAYERS for array sizes
 * - Uses CreateHudSynchronizer() API
 */

#include <sourcemod>

#define PLUGIN_NAME        "NMRiH Play Time HUD"
#define PLUGIN_VERSION     "1.1"
#define DATA_FILENAME      "nmrih_playtime.cfg"

ConVar gCvarHudX;
ConVar gCvarHudY;
ConVar gCvarHudUpdate;
ConVar gCvarColor;

Handle g_hHudSync = INVALID_HANDLE;

char g_sDataPath[PLATFORM_MAX_PATH];

int  g_iSessionSeconds[MAXPLAYERS+1];
int  g_iSavedSeconds[MAXPLAYERS+1];
bool g_bLoaded[MAXPLAYERS+1];
char g_sAuthId[MAXPLAYERS+1][64];

Handle g_hTimerUpdate = INVALID_HANDLE;
Handle g_hTimerAutosave = INVALID_HANDLE;

public Plugin myinfo =
{
    name        = PLUGIN_NAME,
    author      = "CULINFECTÉAVECCHEVEUXDEZOMBIE",
    description = "Play time tracker with HUD and persistent save",
    version     = PLUGIN_VERSION,
    url         = ""
};

public void OnPluginStart()
{
    g_hHudSync = CreateHudSynchronizer();

    // Cvars: position, update rate, color (RGBA)
    gCvarHudX        = CreateConVar("pt_hud_x", "0.01", "HUD X (0.0 left - 1.0 right)");
    gCvarHudY        = CreateConVar("pt_hud_y", "0.25", "HUD Y (0.0 top - 1.0 bottom)");
    gCvarHudUpdate   = CreateConVar("pt_update_interval", "1.0", "HUD refresh & time add interval in seconds (>=0.2)");
    gCvarColor       = CreateConVar("pt_color", "144 238 144 255", "HUD color RGBA (e.g. '255 255 255 255')");

    // Data file path
    BuildPath(Path_SM, g_sDataPath, sizeof(g_sDataPath), "data/%s", DATA_FILENAME);

    float interval = gCvarHudUpdate.FloatValue;
    if (interval < 0.2) interval = 0.2;

    g_hTimerUpdate   = CreateTimer(interval, Timer_Update, _, TIMER_REPEAT);
    g_hTimerAutosave = CreateTimer(60.0, Timer_Autosave, _, TIMER_REPEAT);

    HookEvent("player_disconnect", Evt_Disconnect, EventHookMode_Post);

    PrintToServer("[%s] Loaded. Data file: %s", PLUGIN_NAME, g_sDataPath);
}

public void OnMapEnd()
{
    SaveAllPlayers();
}

public void OnClientDisconnect(int client)
{
    SavePlayer(client);
    ResetPlayer(client);
}

public void OnClientAuthorized(int client, const char[] auth)
{
    // Prefer SteamID64, fallback to Steam2, then IP as last resort
    if (!GetClientAuthId(client, AuthId_SteamID64, g_sAuthId[client], sizeof(g_sAuthId[client]), true))
    {
        if (!GetClientAuthId(client, AuthId_Steam2, g_sAuthId[client], sizeof(g_sAuthId[client]), true))
        {
            GetClientIP(client, g_sAuthId[client], sizeof(g_sAuthId[client]), true);
        }
    }
}

public void OnClientPutInServer(int client)
{
    if (IsFakeClient(client))
        return;

    LoadPlayer(client);
}

public Action Evt_Disconnect(Event event, const char[] name, bool dontBroadcast)
{
    int userid = event.GetInt("userid");
    int client = GetClientOfUserId(userid);
    if (client > 0)
    {
        SavePlayer(client);
        ResetPlayer(client);
    }
    return Plugin_Continue;
}

public Action Timer_Update(Handle timer)
{
    float x = gCvarHudX.FloatValue;
    float y = gCvarHudY.FloatValue;
    float interval = gCvarHudUpdate.FloatValue;
    if (interval < 0.2) interval = 0.2;

    int r, g, b, a;
    ParseColorRGBA(gCvarColor, r, g, b, a);

    for (int client = 1; client <= MaxClients; client++)
    {
        if (!IsClientInGame(client) || IsFakeClient(client))
            continue;

        if (!g_bLoaded[client])
            LoadPlayer(client);

        // Increment time (approximate by interval)
        g_iSessionSeconds[client] += RoundToNearest(interval);

        int total = g_iSavedSeconds[client] + g_iSessionSeconds[client];
        int hours = total / 3600;
        int minutes = (total % 3600) / 60;

        SetHudTextParams(x, y, interval + 0.2, r, g, b, a, 0, 0.0, 0.0, 0.0);
        ShowSyncHudText(client, g_hHudSync, "[Play Time: %d h %d min]", hours, minutes);
    }

    return Plugin_Continue;
}

public Action Timer_Autosave(Handle timer)
{
    SaveAllPlayers();
    return Plugin_Continue;
}

// --------- Data handling ---------

void LoadPlayer(int client)
{
    if (IsFakeClient(client) || !IsClientInGame(client))
        return;

    if (g_bLoaded[client])
        return;

    if (g_sAuthId[client][0] == '\0')
    {
        OnClientAuthorized(client, "");
        if (g_sAuthId[client][0] == '\0')
            return;
    }

    KeyValues kv = new KeyValues("nmrih_playtime");
    FileToKeyValues(kv, g_sDataPath);

    if (kv.JumpToKey(g_sAuthId[client], false))
    {
        g_iSavedSeconds[client] = kv.GetNum("seconds", 0);
    }
    else
    {
        g_iSavedSeconds[client] = 0;
    }

    delete kv;

    g_iSessionSeconds[client] = 0;
    g_bLoaded[client] = true;
}

void SavePlayer(int client)
{
    if (!g_bLoaded[client])
        return;

    int total = g_iSavedSeconds[client] + g_iSessionSeconds[client];

    KeyValues kv = new KeyValues("nmrih_playtime");
    FileToKeyValues(kv, g_sDataPath);

    kv.JumpToKey(g_sAuthId[client], true);
    kv.SetNum("seconds", total);

    kv.Rewind();
    KeyValuesToFile(kv, g_sDataPath);
    delete kv;

    g_iSavedSeconds[client]   = total;
    g_iSessionSeconds[client] = 0;
}

void SaveAllPlayers()
{
    KeyValues kv = new KeyValues("nmrih_playtime");
    FileToKeyValues(kv, g_sDataPath);

    for (int client = 1; client <= MaxClients; client++)
    {
        if (!g_bLoaded[client] || IsFakeClient(client))
            continue;

        if (g_sAuthId[client][0] == '\0')
            continue;

        int total = g_iSavedSeconds[client] + g_iSessionSeconds[client];

        kv.JumpToKey(g_sAuthId[client], true);
        kv.SetNum("seconds", total);
        kv.Rewind();
    }

    KeyValuesToFile(kv, g_sDataPath);
    delete kv;
}

void ResetPlayer(int client)
{
    g_iSessionSeconds[client] = 0;
    g_iSavedSeconds[client] = 0;
    g_bLoaded[client] = false;
    g_sAuthId[client][0] = '\0';
}

void ParseColorRGBA(ConVar cvar, int &r, int &g, int &b, int &a)
{
    char buf[64];
    cvar.GetString(buf, sizeof(buf));

    char parts[4][8];
    int count = ExplodeString(buf, " ", parts, 4, 8);

    int vals[4] = {255,255,255,255};
    for (int i = 0; i < count && i < 4; i++)
    {
        vals[i] = StringToInt(parts[i]);
    }

    r = vals[0]; g = vals[1]; b = vals[2]; a = vals[3];
}
