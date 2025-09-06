\
/**
 * 
 * Counts NMRiH zombie kills, shows a bottom-center HUD with Kills + Level,
 * and prepends chat messages with "[Lvl. X] Name: msg".
 * Persists kills to addons/sourcemod/data/nmrih_kill_levels.cfg (KeyValues).
 *
 * Author: ajandek
 * Compiles on SourceMod 1.10+ / 1.12.
 */

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>

#pragma semicolon 1
#pragma newdecls required

#define DATA_FILE   "nmrih_kill_levels.cfg"
#define SAVE_INTERVAL 10.0     // seconds - periodic save

// -----------------------------------------------------
// Globals
// -----------------------------------------------------
Handle g_hHudSync = INVALID_HANDLE;
Handle g_tHudRefresh = INVALID_HANDLE;
Handle g_tAutoSave = INVALID_HANDLE;

int g_iKills[MAXPLAYERS+1];     // persistent kills
bool g_bDirty[MAXPLAYERS+1];    // needs save?
float g_fLastAdd[MAXPLAYERS+1]; // last kill timestamp for double-count protection

/** Return cumulative kills needed to *reach* the next level from given current level.
 * We target ~100,000 kills to reach level 60.
 * Formula tuned: req(l) = ceil( 15 * (l+1) ^ 1.35 )
 */
int KillsReqForNextLevel(int level)
{
    if (level < 1) level = 1;
    if (level >= 60) return 0;

    float lf = float(level + 1);
    int req = RoundToCeil( 15.0 * Pow(lf, 1.35) );
    return req;
}

/** Convert total kills -> level in [1..60] */
int LevelFromKills(int kills)
{
    int lvl = 1;
    int cum = 0;

    for (int l = 1; l < 60; l++)
    {
        int need = KillsReqForNextLevel(l);
        if (kills >= cum + need)
        {
            cum += need;
            lvl = l + 1;
        }
        else
        {
            break;
        }
    }
    return lvl;
}

/** Utility: valid player? */
bool IsValidP(int client)
{
    return (client >= 1 && client <= MaxClients && IsClientInGame(client) && !IsFakeClient(client));
}

// -----------------------------------------------------
// Plugin info
// -----------------------------------------------------
public Plugin myinfo =
{
    name        = "NMRiH Levels + HUD",
    author      = "CULINFECTÉAVECCHEVEUXDEZOMBIE",
    description = "Counts zombie kills, shows bottom-center HUD and chat prefix with level. Saves to data KeyValues.",
    version     = "1.0.4",
    url         = ""
};


bool GetStableId(int client, char[] out, int outlen)
{
    if (!IsClientConnected(client)) return false;

    // Prefer SteamID64
    if (GetClientAuthId(client, AuthId_SteamID64, out, outlen, true))
        return true;

    // Fallback: Steam2
    if (GetClientAuthId(client, AuthId_Steam2, out, outlen, true))
        return true;

    // Fallback: Steam3
    if (GetClientAuthId(client, AuthId_Steam3, out, outlen, true))
        return true;

    // Last resort: old API
    GetClientAuthString(client, out, outlen);
    return out[0] != '\0';
}
// -----------------------------------------------------
// Lifecycle
// -----------------------------------------------------
public void OnPluginStart()
{
    // HUD
    g_hHudSync = CreateHudSynchronizer();

    // Events we use to count zombie kills
    HookEvent("npc_killed", Event_NPCKilled);
    HookEvent("zombie_killed_by_fire", Event_ZombieKilledByFire);
    HookEvent("zombie_head_split", Event_ZombieHeadSplit);

    // Chat prefix
    AddCommandListener(OnClientSay, "say");
    AddCommandListener(OnClientSay, "say_team");

    // Refresh HUD periodically
    if (g_tHudRefresh != INVALID_HANDLE) KillTimer(g_tHudRefresh);
    g_tHudRefresh = CreateTimer(0.5, Timer_RefreshHud, _, TIMER_REPEAT);

    // Auto-save
    if (g_tAutoSave != INVALID_HANDLE) KillTimer(g_tAutoSave);
    g_tAutoSave = CreateTimer(SAVE_INTERVAL, Timer_AutoSave, _, TIMER_REPEAT);

    // Commands
    RegConsoleCmd("sm_killlevels_save", Cmd_SaveNow, "Force-save kill levels to file.");

    // Preload data file so first load succeeds
    EnsureDataFile();
}

// Reset last-add timestamps at map start to avoid GetGameTime() wrap issues
public void OnMapStart()
{
    for (int i = 1; i <= MaxClients; i++)
    {
        g_fLastAdd[i] = 0.0;
    }
}


// Clear on map end
public void OnMapEnd()
{
    SaveAll();
}

public void OnPluginEnd()
{
    SaveAll();
}

// Client connect/disconnect
public void OnClientPostAdminCheck(int client)
{
    if (!IsValidP(client)) return;
    LoadOne(client);
}


public void OnClientPutInServer(int client)
{
    if (client >= 1 && client <= MaxClients)
    {
        g_fLastAdd[client] = 0.0;
    }
}

public void OnClientDisconnect(int client)
{
    if (!IsClientConnected(client)) return;
    SaveOne(client);
}

// -----------------------------------------------------
// Timers
// -----------------------------------------------------
public Action Timer_RefreshHud(Handle timer, any data)
{
    for (int i = 1; i <= MaxClients; i++)
    {
        if (!IsValidP(i)) continue;
        ShowMyHud(i);
    }
    return Plugin_Continue;
}

public Action Timer_AutoSave(Handle timer, any data)
{
    SaveAll();
    return Plugin_Continue;
}

// -----------------------------------------------------
// HUD + Chat
// -----------------------------------------------------
void ShowMyHud(int client)
{
    int kills = g_iKills[client];
    int lvl = LevelFromKills(kills);

    // bottom-center white
    SetHudTextParams(-1.0, 0.94, 0.6, 125, 183, 227, 255, 0, 0.0, 0.0, 0.0);
    ShowSyncHudText(client, g_hHudSync, "Zombie kills: %d | Level %d", kills, lvl);
}

public Action OnClientSay(int client, const char[] command, int argc)
{
    if (!IsValidP(client)) return Plugin_Continue;

    char msg[256];
    GetCmdArgString(msg, sizeof(msg));
    StripQuotes(msg);

    // Let commands pass through (! or /)
    if (msg[0] == '!' || msg[0] == '/')
        return Plugin_Continue;

    // Empty? ignore
    if (msg[0] == '\0')
        return Plugin_Handled;

    char name[64];
    GetClientName(client, name, sizeof(name));

    int lvl = LevelFromKills(g_iKills[client]);
    PrintToChatAll("\x03[Level %d] \x01%s: %s", lvl, name, msg);
    return Plugin_Handled; // suppress default echo
}

// -----------------------------------------------------
// Kill counting via events
// -----------------------------------------------------

void CreditKill(int client)
{
    if (!IsValidP(client)) return;

    float now = GetGameTime();
    // If game time wrapped (map change), reset last timestamp
    if (now + 0.001 < g_fLastAdd[client])
    {
        g_fLastAdd[client] = 0.0;
    }
    // prevent double-counting bursts from multiple events for same kill
    if (now - g_fLastAdd[client] < 0.05)
        return;

    g_fLastAdd[client] = now;

       int prevLevel = LevelFromKills(g_iKills[client]);
    g_iKills[client]++;
    int newLevel = LevelFromKills(g_iKills[client]);
    if (newLevel > prevLevel)
    {
        char pname[64];
        GetClientName(client, pname, sizeof(pname));
        PrintToChatAll("\x04%s \x03has leveled up to \x04Level %d", pname, newLevel);
    }

    g_bDirty[client] = true;
}

public void Event_NPCKilled(Event event, const char[] name, bool dontBroadcast)
{
    int killer = event.GetInt("killeridx", 0);
    if (IsValidP(killer))
        CreditKill(killer);
}

public void Event_ZombieKilledByFire(Event event, const char[] name, bool dontBroadcast)
{
    int igniter = event.GetInt("igniter_id", 0);
    if (IsValidP(igniter))
        CreditKill(igniter);
}

public void Event_ZombieHeadSplit(Event event, const char[] name, bool dontBroadcast)
{
    int player = event.GetInt("player_id", 0);
    if (IsValidP(player))
        CreditKill(player);
}

// -----------------------------------------------------
// Persistence (KeyValues in addons/sourcemod/data/)
// -----------------------------------------------------
void EnsureDataFile()
{
    char path[PLATFORM_MAX_PATH];
    BuildPath(Path_SM, path, sizeof(path), "data/%s", DATA_FILE);

    if (!FileExists(path))
    {
        KeyValues kv = new KeyValues("Kills");
        kv.ExportToFile(path);
        delete kv;
    }
}

void LoadOne(int client)
{
    char path[PLATFORM_MAX_PATH];
    BuildPath(Path_SM, path, sizeof(path), "data/%s", DATA_FILE);

    char steam[64];
    if (!GetStableId(client, steam, sizeof(steam))) return;

    KeyValues kv = new KeyValues("Kills");
    if (kv.ImportFromFile(path))
    {
        g_iKills[client] = kv.GetNum(steam, 0);
    }
    delete kv;
    g_bDirty[client] = false;
}

void SaveOne(int client)
{
    if (!IsClientConnected(client)) return;
    if (!g_bDirty[client]) return;

    char path[PLATFORM_MAX_PATH];
    BuildPath(Path_SM, path, sizeof(path), "data/%s", DATA_FILE);

    char steam[64];
    if (!GetStableId(client, steam, sizeof(steam))) return;

    KeyValues kv = new KeyValues("Kills");
    kv.ImportFromFile(path);
    kv.SetNum(steam, g_iKills[client]);
    kv.ExportToFile(path);
    delete kv;

    g_bDirty[client] = false;
}

void SaveAll()
{
    char path[PLATFORM_MAX_PATH];
    BuildPath(Path_SM, path, sizeof(path), "data/%s", DATA_FILE);

    KeyValues kv = new KeyValues("Kills");
    kv.ImportFromFile(path);

    bool any = false;

    for (int i = 1; i <= MaxClients; i++)
    {
        if (!IsClientConnected(i)) continue;
        if (!g_bDirty[i]) continue;

        char steam[64];
        if (!GetStableId(i, steam, sizeof(steam))) continue;
        kv.SetNum(steam, g_iKills[i]);
        g_bDirty[i] = false;
        any = true;
    }

    if (any)
        kv.ExportToFile(path);

    delete kv;
}

// Admin command to force-save
public Action Cmd_SaveNow(int client, int args)
{
    SaveAll();
    ReplyToCommand(client, "[KillLVL] Saved.");
    return Plugin_Handled;
}