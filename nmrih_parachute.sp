#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>

#define PARACHUTE_GRAVITY 0.2
#define NORMAL_GRAVITY 1.0

bool g_bParachuteUsed[MAXPLAYERS + 1];

public Plugin myinfo = {
    name = "NMRiH Parachute",
    author = "CULINFECTÉAVECCHEVEUXDEZOMBIE",
    description = "Allows players to slow fall with E key (no model, green glow)",
    version = "1.2b"
};

public void OnPluginStart()
{
    for (int i = 1; i <= MaxClients; i++) {
        if (IsClientInGame(i)) {
            SDKHook(i, SDKHook_PreThink, OnPreThink);
        }
    }
}

public void OnClientPutInServer(int client)
{
    SDKHook(client, SDKHook_PreThink, OnPreThink);
    g_bParachuteUsed[client] = false;
}

public void OnClientDisconnect(int client)
{
    g_bParachuteUsed[client] = false;
}

public Action OnPreThink(int client)
{
    if (!IsPlayerAlive(client)) return Plugin_Continue;

    int buttons = GetClientButtons(client);
    bool isInAir = !(GetEntityFlags(client) & FL_ONGROUND);
    float velocity[3];
    GetEntPropVector(client, Prop_Data, "m_vecVelocity", velocity);

    if (isInAir && velocity[2] < 0.0 && (buttons & IN_USE) && !g_bParachuteUsed[client])
    {
        SetEntityGravity(client, PARACHUTE_GRAVITY);
        g_bParachuteUsed[client] = true;
        CreateGlow(client);
    }

    if (!isInAir && g_bParachuteUsed[client])
    {
        SetEntityGravity(client, NORMAL_GRAVITY);
        g_bParachuteUsed[client] = false;
    }

    return Plugin_Continue;
}

void CreateGlow(int client)
{
    int color[4] = {0, 255, 0, 200}; // Zöld, áttetsző
    SetEntityRenderMode(client, RENDER_TRANSCOLOR);
    SetEntityRenderColor(client, color[0], color[1], color[2], color[3]);
    CreateTimer(1.0, Timer_RemoveGlow, client);
}

public Action Timer_RemoveGlow(Handle timer, any client)
{
    if (IsClientInGame(client) && IsPlayerAlive(client)) {
        SetEntityRenderColor(client, 255, 255, 255, 255); // visszaállítás
    }
    return Plugin_Stop;
}
