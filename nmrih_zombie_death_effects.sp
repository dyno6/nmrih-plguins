// nmrih_death_effect_inject.sp
// Inject DMG_BURN and/or DMG_DISSOLVE into lethal hits so zombies burn and/or dissolve on normal kills.
// 
//
// Requires: SourceMod + SDKHooks + sdktools
//
// CVARs:
//  sm_deatheffect_enable 1             // Enable/disable
//  sm_deatheffect_only_player 1        // Only when the attacker is a player
//  sm_deatheffect_class_prefix ""      // Optional filter, e.g. "npc_", "npc_nmrih_"; empty = no filter
//  sm_deatheffect_mode 3               // 1=Burn, 2=Dissolve, 3=Burn+Dissolve 
//  sm_deatheffect_debug 0              // Verbose logs
//
// Admin cmd:
//  sm_deatheffect_info                  // Print aimed entity info (class, HP)
//
#pragma semicolon 1

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>

public Plugin myinfo =
{
    name        = "NMRiH Zombie Death Effect",
    author      = "CULINFECTÉAVECCHEVEUXDEZOMBIE",
    description = "Inject DMG_BURN / DMG_DISSOLVE into lethal hits so zombies burn/dissolve on normal kills.",
    version     = "1.1.0",
    url         = ""
};

ConVar gCvar_Enable;
ConVar gCvar_OnlyPlayer;
ConVar gCvar_ClassPrefix;
ConVar gCvar_Mode;
ConVar gCvar_Debug;

// Safe defines (avoid redefinition warning if already in includes)
#if !defined DMG_BURN
    #define DMG_BURN (1 << 3)        // 0x0008
#endif
#if !defined DMG_DISSOLVE
    #define DMG_DISSOLVE (1 << 19)   // 0x80000
#endif

public void OnPluginStart()
{
    gCvar_Enable      = CreateConVar("sm_deatheffect_enable", "1", "Enable plugin (0/1)", FCVAR_PLUGIN, true, 0.0, true, 1.0);
    gCvar_OnlyPlayer  = CreateConVar("sm_deatheffect_only_player", "1", "Only when attacker is a player? (0/1)", FCVAR_PLUGIN, true, 0.0, true, 1.0);
    gCvar_ClassPrefix = CreateConVar("sm_deatheffect_class_prefix", "", "Optional classname prefix to restrict (e.g. npc_, npc_nmrih_). Empty = no filter.", FCVAR_PLUGIN);
    gCvar_Mode        = CreateConVar("sm_deatheffect_mode", "3", "1=Burn, 2=Dissolve, 3=Burn + Dissolve (Cyclop-like).", FCVAR_PLUGIN, true, 1.0, true, 3.0);
    gCvar_Debug       = CreateConVar("sm_deatheffect_debug", "0", "Verbose debug logs (0/1)", FCVAR_PLUGIN, true, 0.0, true, 1.0);

    // Hook existing entities after short delay, and hook created entities as they appear
    CreateTimer(0.5, Timer_HookExisting);
    RegAdminCmd("sm_deatheffect_info", Cmd_Info, ADMFLAG_GENERIC, "Print aimed entity info.");
}

public void OnMapStart()
{
    CreateTimer(0.5, Timer_HookExisting);
}

public Action Timer_HookExisting(Handle timer)
{
    int ent = -1;
    while ((ent = FindEntityByClassname(ent, "*")) != -1)
    {
        if (ent <= MaxClients) continue;
        if (!IsValidEntity(ent)) continue;
        SDKHook(ent, SDKHook_OnTakeDamage, Hook_OnTakeDamage);
    }
    if (gCvar_Debug.BoolValue)
    {
        PrintToServer("[DEATHEFFECT] Hooked existing non-player entities.");
    }
    return Plugin_Stop;
}

public void OnEntityCreated(int ent, const char[] classname)
{
    if (ent <= MaxClients) return;
    CreateTimer(0.02, Timer_DeferredHook, EntIndexToEntRef(ent));
}

public Action Timer_DeferredHook(Handle timer, any entRef)
{
    int ent = EntRefToEntIndex(entRef);
    if (ent > MaxClients && IsValidEntity(ent))
    {
        SDKHook(ent, SDKHook_OnTakeDamage, Hook_OnTakeDamage);
        if (gCvar_Debug.BoolValue)
        {
            char cn[64];
            GetEntityClassname(ent, cn, sizeof(cn));
            PrintToServer("[DEATHEFFECT] Hooked %d (%s)", ent, cn);
        }
    }
    return Plugin_Stop;
}

static bool IsValidClient(int client)
{
    return (1 <= client <= MaxClients) && IsClientInGame(client);
}

public Action Hook_OnTakeDamage(int victim, int &attacker, int &inflictor, float &damage, int &damagetype, int &weapon, float damageForce[3], float damagePosition[3], int damagecustom)
{
    if (!gCvar_Enable.BoolValue) return Plugin_Continue;
    if (victim <= MaxClients) return Plugin_Continue; // do not affect players
    if (!IsValidEntity(victim)) return Plugin_Continue;
    if (damage <= 0.0) return Plugin_Continue;

    // Only if player attacker?
    if (gCvar_OnlyPlayer.BoolValue && !IsValidClient(attacker))
        return Plugin_Continue;

    // Optional prefix filter
    static char prefix[32];
    gCvar_ClassPrefix.GetString(prefix, sizeof(prefix));
    if (prefix[0] != '\0')
    {
        char cn[64];
        GetEntityClassname(victim, cn, sizeof(cn));
        if (StrContains(cn, prefix, false) != 0) // not starting with prefix
            return Plugin_Continue;
    }

    // Predict lethality
    if (!HasEntProp(victim, Prop_Data, "m_iHealth"))
        return Plugin_Continue;

    int hp = GetEntProp(victim, Prop_Data, "m_iHealth");
    if (hp <= 0) return Plugin_Continue;

    int after = hp - RoundToCeil(damage);
    if (after > 0) return Plugin_Continue; // not lethal

    // Apply desired flags
    int mode = gCvar_Mode.IntValue; // 1=burn, 2=dissolve, 3=both
    int addFlags = 0;
    if (mode == 1) addFlags = DMG_BURN;
    else if (mode == 2) addFlags = DMG_DISSOLVE;
    else /* 3 or anything else */ addFlags = (DMG_BURN | DMG_DISSOLVE);

    int newType = damagetype | addFlags;

    if (newType != damagetype)
    {
        if (gCvar_Debug.BoolValue)
        {
            char vcn[64], wname[64];
            GetEntityClassname(victim, vcn, sizeof(vcn));
            if (weapon > 0 && IsValidEntity(weapon)) GetEntityClassname(weapon, wname, sizeof(wname)); else wname[0] = '\0';
            PrintToServer("[DEATHEFFECT] Inject flags 0x%X (mode=%d): vic=%d(%s) hp=%d dmg=%.1f atk=%d weap=%d(%s) old=0x%X new=0x%X",
                          addFlags, mode, victim, vcn, hp, damage, attacker, weapon, wname, damagetype, newType);
        }
        damagetype = newType;
        return Plugin_Changed;
    }

    return Plugin_Continue;
}

// Admin helper
public Action Cmd_Info(int client, int args)
{
    if (!IsValidClient(client)) return Plugin_Handled;
    int ent = GetClientAimTarget(client, false);
    if (ent <= 0 || !IsValidEntity(ent))
    {
        ReplyToCommand(client, "[DEATHEFFECT] No valid target.");
        return Plugin_Handled;
    }
    char cn[64];
    GetEntityClassname(ent, cn, sizeof(cn));
    int hp = HasEntProp(ent, Prop_Data, "m_iHealth") ? GetEntProp(ent, Prop_Data, "m_iHealth") : -1;
    ReplyToCommand(client, "[DEATHEFFECT] Aim target ent=%d class=%s hp=%d", ent, cn, hp);
    return Plugin_Handled;
}
