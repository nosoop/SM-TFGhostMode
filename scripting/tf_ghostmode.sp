/**
 * Sourcemod Plugin Template
 */

#pragma semicolon 1

#include <sourcemod>
#include <tf2>
#include <tf2_stocks>
#include <sdktools>
#include <sdkhooks>

#define PLUGIN_VERSION          "0.1.0"     // Plugin version.

public Plugin:myinfo = {
    name = "[TF2] Ghost Mode",
    author = "nosoop",
    description = "Implementation of Ghost Mode using Valve's ghost TFConds",
    version = PLUGIN_VERSION,
    url = "http://github.com/nosoop"
}

new g_rgRespawnTimes[MAXPLAYERS+1];

public OnPluginStart() {
    HookEvent("player_spawn", EventHook_OnPlayerSpawn);
    
    // TODO Handle cases where players want to switch teams or go spectate or [...]
    
    // Late loads.
    for (new i = MaxClients; i > 0; --i) {
        if (IsClientInGame(i)) {
            OnClientPutInServer(i);
            
            if (TF2_IsPlayerInCondition(i, TFCond_HalloweenGhostMode)) {
                PreparePlayerRespawn(i);
            }
        }
    }
}

public OnMapStart() {
    // Precache ghost sounds.
    decl String:halloweenBoo[64];
    for (new i = 0; i < 7; i++) {
        Format(halloweenBoo, sizeof(halloweenBoo), "vo/halloween_boo%d.wav", i+1);
        PrecacheSound(halloweenBoo);
    }
}

public OnClientPutInServer(iClient) {
    SDKHook(iClient, SDKHook_SetTransmit, SDKHook_OnSetTransmit);
}

public Action:EventHook_OnPlayerSpawn(Handle:hEvent, const String:name[], bool:dontBroadcast) {
    new iClient = GetClientOfUserId(GetEventInt(hEvent, "userid"));
    
    // TODO make optional, random chance?
    TF2_AddCondition(iClient, TFCond_HalloweenInHell, 9999999999.0);
}

public TF2_OnConditionAdded(iClient, TFCond:condition) {
    if (condition == TFCond_HalloweenGhostMode) {
        // TODO hide HUD
        PreparePlayerRespawn(iClient);
    }
}

/**
 * Handles player respawns, attempting to accurately match the normal respawn time.
 */
PreparePlayerRespawn(iClient) {
    new TFTeam:iTeam = TFTeam:GetClientTeam(iClient);

    if (iTeam <= TFTeam_Spectator) {
        return;
    }
    
    new Float:fRespawnTime = GetPlayerRespawnTime(iTeam);
    CreateTimer(fRespawnTime, Timer_GhostRespawn, iClient, TIMER_FLAG_NO_MAPCHANGE);
    // PrintToChat(iClient, "Respawning in %.2f...", fRespawnTime);
    
    // Creates "respawning in" center chat notification.
    g_rgRespawnTimes[iClient] = RoundFloat(fRespawnTime);
    CreateTimer(FloatFraction(fRespawnTime), Timer_StartRespawnCountdown, iClient, TIMER_FLAG_NO_MAPCHANGE);
}

/**
 * Starts the timer notification.
 */
public Action:Timer_StartRespawnCountdown(Handle:hTimer, any:iClient) {
    g_rgRespawnTimes[iClient]--;
    CreateTimer(1.0, Timer_RespawnCountdown, iClient, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
}

/**
 * Shows respawn timer notification.  Updates every second while the player it is for is dead.
 */
public Action:Timer_RespawnCountdown(Handle:hTimer, any:iClient) {
    g_rgRespawnTimes[iClient] -= 1;
    if (g_rgRespawnTimes[iClient] > 0) {
        PrintCenterText(iClient, "Respawn in: %d seconds", g_rgRespawnTimes[iClient]);
    } else if (g_rgRespawnTimes[iClient] == 0) {
        PrintCenterText(iClient, "Prepare to respawn");
    } else {
        PrintCenterText(iClient, "");
    }
    
    if (g_rgRespawnTimes[iClient] < 0
            || !TF2_IsPlayerInCondition(iClient, TFCond_HalloweenGhostMode)
            || GameRules_GetRoundState() == RoundState_TeamWin) {
        KillTimer(hTimer);
    }
}

/**
 * Timer that respawns a player while they are in ghost mode.
 * (Respawn time is set in PreparePlayerRespawn(iClient).)
 */
public Action:Timer_GhostRespawn(Handle:hTimer, any:iClient) {
    if (GameRules_GetRoundState() != RoundState_TeamWin) {
        TF2_RespawnPlayer(iClient);
    }
}

/**
 * Allow ghosts to be seen only by dead players.
 */
public Action:SDKHook_OnSetTransmit(iClient, iObservingClient) {
    new bool:bObserverDeadOrGhost = TF2_IsPlayerInCondition(iObservingClient, TFCond_HalloweenGhostMode)
            || !IsPlayerAlive(iObservingClient);
    
    if (iClient != iObservingClient
            && TF2_IsPlayerInCondition(iClient, TFCond_HalloweenGhostMode)
            && !bObserverDeadOrGhost) {
        return Plugin_Handled;
    }
    return Plugin_Continue;
}

/**
 * Amount of time to add to compensate for the freezecam.  Used in GetPlayerRespawnTime(client).
 */
#define FREEZECAM_TIME          5.0

/**
 * Returns the amount of time until respawn, provided a client on the specified team died at the time this method is called.
 */
stock Float:GetPlayerRespawnTime(TFTeam:iTeam) {
    // TODO handle for arena, etc.
    if (iTeam <= TFTeam_Spectator) {
        ThrowError("Team must be a non-spectating team (input %d)", iTeam);
    }

    new Float:fMinRespawnTime = GameRules_GetPropFloat("m_TeamRespawnWaveTimes", _:iTeam);

    new Float:fRespawnTime = GameRules_GetPropFloat("m_flNextRespawnWave", _:iTeam) - GetGameTime();
    fRespawnTime += fMinRespawnTime;
    
    if (fRespawnTime < fMinRespawnTime + FREEZECAM_TIME) {
        fRespawnTime += fMinRespawnTime;
    }

    return fRespawnTime;
}
