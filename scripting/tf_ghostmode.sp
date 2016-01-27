/**
 * Sourcemod Plugin Template
 */

#pragma semicolon 1

#include <sourcemod>
#include <tf2>
#include <tf2_stocks>
#include <sdktools>
#include <sdkhooks>

#pragma newdecls required

#define PLUGIN_VERSION          "0.5.0"     // Plugin version.

public Plugin myinfo = {
    name = "[TF2] Ghost Mode",
    author = "nosoop",
    description = "Implementation of Ghost Mode using Valve's ghost TFConds",
    version = PLUGIN_VERSION,
    url = "http://github.com/nosoop/SM-TFGhostMode"
}

#include "ghostmode/respawn_callback.sp"

char TF_CLASSNAMES[][] = {
	"", "scout", "sniper", "soldier", "demoman", "medic", "heavyweapons", "pyro", "spy", "engineer"
};


float m_flNextRespawnTime[MAXPLAYERS+1];
float m_vecDeathPos[MAXPLAYERS+1][3];
float m_vecDeathAng[MAXPLAYERS+1][3];

public void OnPluginStart() {
	HookEvent("player_death", OnPlayerDeath, EventHookMode_Post);
	
	// Listen for a few commands to properly remove ghost condition on.
	AddCommandListener(CmdListen_CancelGhostMode, "spectate");
	AddCommandListener(CmdListen_CancelGhostMode, "jointeam");
	
	// Listen to `joinclass` to prevent class switching in-spawn
	AddCommandListener(CmdListen_ChangeClass, "joinclass");
	
	for (int i = MaxClients; i > 0; --i) {
		if (IsClientInGame(i)) {
			OnClientPutInServer(i);
		}
	}
}

public void OnPluginEnd() {
	for (int i = MaxClients; i > 0; --i) {
		if (IsClientInGame(i)) {
			CancelGhostMode(i);
		}
	}
}

public void OnMapStart() {
	PrecacheScriptSound("Halloween.GhostBoo");
}

public void OnClientPutInServer(int client) {
	SDKHook(client, SDKHook_PostThink, OnGhostPostThink);
}

public void OnPlayerDeath(Event event, const char[] name, bool dontBroadcast) {
	int userid = event.GetInt("userid");
	int client = GetClientOfUserId(userid);
	
	GetClientAbsOrigin(client, m_vecDeathPos[client]);
	GetClientEyeAngles(client, m_vecDeathAng[client]);
	
	/*if (IsFakeClient(client)) {
		// just to prove that respawn times match those of non-ghosted players
		return;
	}*/
	
	if (event.GetInt("deathflags") & TF_DEATHFLAG_DEADRINGER) {
		DisplayGhostExplosion(client);
		return;
	}
	
	// Perform a callback on the next few frames until the respawn time is available
	RequestNextRespawnTimer(client, OnClientHasActiveRespawnTimer);
}

public void OnGhostPostThink(int client) {
	// very finicky
	if (TF2_IsPlayerInCondition(client, TFCond_HalloweenGhostMode)) {
		SetEntProp(GetPlayerResourceEntity(), Prop_Send, "m_bAlive", false, _, client);
	}
}

/**
 * Turns the player into a (dead) ghost with a respawn time.
 * TODO handle arena mode?
 */
public void OnClientHasActiveRespawnTimer(int client, float flNextRespawnTime, any data) {
	if (client == 0 || flNextRespawnTime < GetGameTime()) {
		// invalid userid or invalid respawn time
		return;
	}
	
	int userid = GetClientUserId(client);
	
	m_flNextRespawnTime[client] = flNextRespawnTime;
	
	float flSecondsToNextRespawn = flNextRespawnTime - GetGameTime();
	
	// TODO configure a sane limit
	static float flMaxTimerTime = 10.0;
	
	// off by two
	float flActiveTimerTime = flSecondsToNextRespawn > flMaxTimerTime + 2.0 ? flMaxTimerTime + 2.0 : flSecondsToNextRespawn;
	
	// Create timers for PrintCenterText
	for (float i = 0.0; i < flActiveTimerTime; i += 1.0) {
		DataPack pack;
		CreateDataTimer(flSecondsToNextRespawn - i, Timer_GhostRespawnTimer, pack, TIMER_FLAG_NO_MAPCHANGE);
		pack.WriteCell(userid);
		pack.WriteFloat(flNextRespawnTime);
	}
	
	TF2_RespawnPlayer(client);
	TeleportEntity(client, m_vecDeathPos[client], m_vecDeathAng[client], NULL_VECTOR);
	
	DisplayGhostExplosion(client);
	
	TF2_AddCondition(client, TFCond_HalloweenGhostMode);
}

public Action Timer_GhostRespawnTimer(Handle timer, DataPack data) {
	data.Reset();
	int client = GetClientOfUserId(data.ReadCell());
	
	if (client > 0 && IsClientInGame(client) && TF2_IsPlayerInCondition(client, TFCond_HalloweenGhostMode)) {
		float flExpectedRespawnTime = data.ReadFloat();
		if (m_flNextRespawnTime[client] != flExpectedRespawnTime) {
			// wrong respawn time, don't use
			// TODO store all of these in the player's own arraylist?
			return Plugin_Handled;
		}
		
		// TODO timer is showing every other number sometimes
		int nSecondsToRespawn = RoundToFloor(m_flNextRespawnTime[client] - GetGameTime());
		
		if (nSecondsToRespawn > 0) {
			if (nSecondsToRespawn == 1) {
				// TODO localize to #game_respawntime_in_sec
				PrintCenterText(client, "Respawn in: 1 second");
			} else {
				// TODO localize to #game_respawntime_in_secs
				PrintCenterText(client, "Respawn in: %d seconds", nSecondsToRespawn);
			}
		} else { 
			// clear center text
			PrintCenterText(client, "");
			if (nSecondsToRespawn == 0) {
				int white[] = {255, 255, 255, 255};
				ScreenFadeIn(client, 512, 512, white);
			} else {
				// time to respawn (-1)
				DisplayGhostExplosion(int client);
				TF2_RespawnPlayer(client);
			}
		}
	}
	return Plugin_Handled;
}

/**
 * Spawns the "ghost appearation" particle effect on a player
 */
void DisplayGhostExplosion(int client) {
	float vecEyePos[3];
	GetClientEyePosition(client, vecEyePos);
	vecEyePos[2] -= 32.0;
	TF2_GenericBombExplode(vecEyePos, _, _, "ghost_appearation");
}

/**
 * Hooks the `changeclass` command to prevent switching classes and respawning in the spawn room while being a ghost.
 */
public Action CmdListen_ChangeClass(int client, const char[] name, int argc) {
	if (TF2_IsPlayerInCondition(client, TFCond_HalloweenGhostMode) && m_flNextRespawnTime[client] > GetGameTime()) {
		// No way to check for respawn rooms without hooks so we'll just handle all of them
		char buffer[256];
		GetCmdArgString(buffer, sizeof(buffer));
		
		if (strlen(buffer) > 0) {
			TFClassType desiredClass = view_as<TFClassType>(GetRandomInt(1, sizeof(TF_CLASSNAMES) - 1));
			for (int i = 0; i < sizeof(TF_CLASSNAMES); i++) {
				if (StrEqual(buffer, TF_CLASSNAMES[i])) {
					desiredClass = view_as<TFClassType>(i);
				}
			}
			// TODO use localized #game_respawn_as
			SetEntProp(client, Prop_Send, "m_iDesiredPlayerClass", desiredClass);
		}
		return Plugin_Handled;
	}
	return Plugin_Continue;
}

/* Cancel Ghost Mode for a player */

public Action CmdListen_CancelGhostMode(int client, const char[] name, int argc) {
    CancelGhostMode(client);
    return Plugin_Continue;
}

void CancelGhostMode(int client) {
    if (TF2_IsPlayerInCondition(client, TFCond_HalloweenGhostMode)) {
        TF2_RemoveCondition(client, TFCond_HalloweenGhostMode);
        ForcePlayerSuicide(client);
    }
}

/**
 * Stock to make the screen fade in.
 * Adapted from Fun Commands
 */
stock bool ScreenFadeIn(int client, int nDuration, int nHoldtime=-1, int rgba[4] = {0, 0, 0, 255}, bool bReliable=true) {
    Handle userMessage = StartMessageOne("Fade", client, (bReliable?USERMSG_RELIABLE:0));
    
    if (userMessage == INVALID_HANDLE) {
        return false;
    }
    
    BfWriteShort(userMessage, nDuration);
    BfWriteShort(userMessage, nHoldtime);
    BfWriteShort(userMessage, 0x0002);
    BfWriteByte(userMessage, rgba[0]);
    BfWriteByte(userMessage, rgba[1]);
    BfWriteByte(userMessage, rgba[2]);
    BfWriteByte(userMessage, rgba[3]);
    EndMessage();
    
    return true;
}

/**
 * Takes a `tf_generic_bomb` entity, sets it up and detonates it.
 * Adapted from https://forums.alliedmods.net/showthread.php?t=272874
 */
stock void TF2_GenericBombExplode(float vecOrigin[3], float flDamage = 0.0, float flRadius = 0.0,
		const char[] strParticle = "", const char[] strSound = "") {
	int iBomb = CreateEntityByName("tf_generic_bomb");
	DispatchKeyValueVector(iBomb, "origin", vecOrigin);
	DispatchKeyValueFloat(iBomb, "damage", flDamage);
	DispatchKeyValueFloat(iBomb, "radius", flRadius);
	DispatchKeyValue(iBomb, "health", "1");
	
	if (strlen(strParticle) > 0) {
		DispatchKeyValue(iBomb, "explode_particle", strParticle);
	}
	
	if (strlen(strSound) > 0) {
		DispatchKeyValue(iBomb, "sound", strSound);
	}
	
	DispatchSpawn(iBomb);

	AcceptEntityInput(iBomb, "Detonate");
	AcceptEntityInput(iBomb, "Kill");
}  