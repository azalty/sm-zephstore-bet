#include <sdktools>
#include <sourcemod>
#include <halflife>
#define REQUIRE_PLUGIN
#include <colorvariables>
#include <myjailshop>
#include <store>

/*
this plugin needs:
- FixHintColorMessages.smx by Franc1sco
- colorvariables.inc
- myjailshop
- zephyrus store

Compiled using SM 1.8 - higher versions cannot compile due to Zeph store being outdated
*/

int betAmount[MAXPLAYERS+1];
int betUser[MAXPLAYERS+1];
int betTotalUsers;
int betTotalAmount;
bool betEnabled;
float betTime;

Handle betHinttextTimer[MAXPLAYERS+1];
Handle betSpamTimer[MAXPLAYERS+1];
Handle betRoundStartTimer;
Handle betTimer;

ConVar g_betDelay;
ConVar g_betTime;
ConVar g_betSpam;
ConVar g_betHintUpdate;

public Plugin myinfo = 
{
	name = "Zeph store betting",
	author = "azalty/rlevet",
	description = "Allows players to bet credits. The more you bet, the more chances you have of winning.",
	version = "1.0.0",
	url = "github.com/rlevet"
}

public void OnPluginStart()
{
	// Cvars
	g_betDelay = CreateConVar("zephstore_bet_delay", "5.0", "Delay after round start to advertise !bet and allow bets (in seconds, float) - to disable, enter 0.0");
	g_betTime = CreateConVar("zephstore_bet_time", "60.0", "Time they are allowed to bet (after zephstore_bet_delay - in seconds, float). If round ends before this time, betting will be canceled.");
	g_betSpam = CreateConVar("zephstore_bet_spam", "5.0", "Minimum time between two usages of !bet command for one player, to prevent flooding (in seconds, float) - to disable, enter 0.0");
	g_betHintUpdate = CreateConVar("zephstore_bet_hintupdate", "1.0", "Every how much seconds the hintbox (message at the center) updates (float, recommended to let as default)", _, true, 0.1, true, 2.0);
	
	// Console cmds
	RegConsoleCmd("sm_bet", Command_Bet);
	
	// Events
	HookEvent("round_start", OnRoundStart);
	
	// Translations
	LoadTranslations("zephstore.bet.phrases");
}

public void OnRoundStart(Handle event, const char[] name, bool dontBroadcast)
{
	betEnabled = false;
	betTotalUsers = 0;
	betTotalAmount = 0;
	betTime = 0.0;
	
	delete betRoundStartTimer;
	delete betTimer;
	
	if (GameRules_GetProp("m_bWarmupPeriod") == 0)
	{
		int playersConnected = MaxClients;
		for(int client = 1 ; client <= playersConnected ; client++)
		{
			if (IsClientInGame(client))
			{
				betUser[client] = 0;
				betAmount[client] = 0;
			}
		}
		
		if (g_betDelay.FloatValue > 0.0)
		{
			betRoundStartTimer = CreateTimer(5.0, betEnable);
		}
		betTimer = CreateTimer(g_betTime.FloatValue+g_betDelay.FloatValue, betChooseWinner);
	}
}

public void OnClientDisconnect(int client)
{
	betTotalAmount = betTotalAmount-betAmount[client]; // updates the timer in real time
	delete betHinttextTimer[client];
	if (g_betSpam.FloatValue > 0.0)
	{
		delete betSpamTimer[client];
	}
	betUser[client] = 0;
	betAmount[client] = 0;
}

public void OnMapEnd()
{
	// prevents handles and timers from existing after map change
	for(int client=1 ; client <= MaxClients ; client++)
	{
		if (IsClientInGame(client))
		{
			delete betHinttextTimer[client];
			delete betSpamTimer[client];
		}
	}
	delete betRoundStartTimer;
	delete betTimer;
}

public Action Command_Bet(int client, int args)
{
	if (client)
	{
		if (!(betEnabled)) // if bet disabled ()
		{
			CPrintToChat(client, "%t", "NoBet");
			return Plugin_Handled;
		}
		if (args != 1) // bad syntax (not !bet <something>)
		{
			CPrintToChat(client, "%t", "Usage", "CreditsName");
			return Plugin_Handled;
		}
		if (betSpamTimer[client]) // prevents players from spamming !bet command and flooding chat
		{
			CPrintToChat(client, "%t", "WaitABit");
			return Plugin_Handled;
		}
		
		int curJetons = Store_GetClientCredits(client);
		
		char cmdargs[64];
		GetCmdArg(1, cmdargs, sizeof(cmdargs));
		
		int myBetAmount = StringToInt(cmdargs);
		
		if (myBetAmount <= 0) // prevents players from betting negative or null values, or using a bad syntax ('!bet blabla' - for exemple)
		{
			CPrintToChat(client, "%t", "Usage", "CreditsName");
			return Plugin_Handled;
		}
		if (curJetons < (betAmount[client]+myBetAmount)) // prevents players from betting more than they have
		{
			CPrintToChat(client, "%t", "NotEnough", "CreditsName");
			return Plugin_Handled;
		}
		
		betAmount[client] = betAmount[client]+myBetAmount;
		if (!(betUser[client])) // register the client as a betUser if he isn't already one. This is used to calculate the winner.
		{
			betUser[client] = betTotalUsers+1;
			betTotalUsers++;
		}
		betTotalAmount = betTotalAmount+myBetAmount;
		
		float luck = (float(betAmount[client])/betTotalAmount)*100.0; // float with int, or int with float, else it will round
		float curtime = GetGameTime();
		int timeleft = RoundFloat((betTime+60-curtime)); // calculates timeleft for betting
		PrintHintText(client, "%t", "HintboxText", betAmount[client], luck, betTotalAmount, timeleft, "CreditsName");
		
		char name[32];
		GetClientName(client, name, sizeof(name));
		
		if (betAmount[client] == myBetAmount) // first bet
		{
			CPrintToChatAll("%T", "FirstBet", LANG_SERVER, name, myBetAmount, luck, betTotalAmount, "CreditsName");
		}
		else // second,third... bet (you can bet more!)
		{
			CPrintToChatAll("%T", "NextBet", LANG_SERVER, name, myBetAmount, betAmount[client], luck, betTotalAmount, "CreditsName");
		}
		
		if (!(betHinttextTimer[client])) // if hinttext is not showing, show it
		{
			betHinttextTimer[client] = CreateTimer(g_betHintUpdate.FloatValue, betHinttext, client, TIMER_REPEAT);
		}
		// we do not remove zeph credits here to prevent losing your credits when disconnecting or server crashes
		if (g_betSpam.FloatValue > 0.0)
		{
			betSpamTimer[client] = CreateTimer(g_betSpam.FloatValue, betSpam, client); // prevents players from spamming !bet command and flooding chat
		}
	}
	
	return Plugin_Handled;
}

public Action betEnable(Handle timer)
{
	betEnabled = true;
	betTime = GetGameTime()
	CPrintToChatAll("%T", "Advert", LANG_SERVER, "CreditsName")
	
	betRoundStartTimer = null;
}

public Action betSpam(Handle timer, int client)
{
	betSpamTimer[client] = null;
}

public Action betChooseWinner(Handle timer)
{
	betEnabled = false;
	
	if (!(betTotalUsers == 0))
	{
		if (betTotalUsers == 1)
		{
			int playersConnected = MaxClients;
			for(int client = 1 ; client <= playersConnected ; client++)
			{
				if (IsClientInGame(client) && (betUser[client] != 0))
				{
					betUser[client] = 0;
					betAmount[client] = 0;
					CPrintToChat(client, "%t", "WinnerAlone")
				}
			}
		}
		else
		{
			float winnernumber = GetURandomFloat(); // get a random float between 0-1
			int betUserToClient[MAXPLAYERS+1];
			
			int playersConnected = MaxClients;
			betTotalAmount = 0; // lets recalc and exclude people that disconnected to prevent creating currency
			for(int client = 1 ; client <= playersConnected ; client++)
			{
				if (IsClientInGame(client) && (betUser[client] != 0))
				{
					betUserToClient[betUser[client]] = client; // set the user to the client number
					
					int curjetons = Store_GetClientCredits(client);
					
					if (curjetons < betAmount[client])
					{
						//betTotalAmount = betTotalAmount-betAmount[client]; no longer needed
						betAmount[client] = 0;
						CPrintToChat(client, "%t", "Cheater", "CreditsName")
					}
					else
					{
						betTotalAmount = betTotalAmount+betAmount[client];
						int jetons = curjetons-betAmount[client];
						Store_SetClientCredits(client, jetons);
					}
					//betUser[client] = 0;
					//betAmount[client] = 0;
				}
			}
			bool winnerExists;
			for (int loopnumber = 1 ; loopnumber <= betTotalUsers ; loopnumber++)
			{
				int client = betUserToClient[loopnumber];
				
				if (client)
				{
					winnernumber = winnernumber-(float(betAmount[client])/betTotalAmount);
					if (winnernumber <= 0)
					{
						int jetons = Store_GetClientCredits(client)+betTotalAmount;
						Store_SetClientCredits(client, jetons);
						float luck = (float(betAmount[client])/betTotalAmount)*100.0;
						char name[32];
						GetClientName(client, name, sizeof(name));
						CPrintToChatAll("%T", "Winner", LANG_SERVER, name, betTotalAmount, luck, "CreditsName");
						winnerExists = true;
						break;
					}
				}
			}
			if (!(winnerExists))
			{
				for(int client = 1 ; client <= playersConnected ; client++)
				{
					if (IsClientInGame(client) && (betUser[client] != 0) && (betAmount[client] != 0))
					{
						int curjetons = Store_GetClientCredits(client);
						int jetons = curjetons+betAmount[client];
						Store_SetClientCredits(client, jetons);
						//betUser[client] = 0;
						//betAmount[client] = 0;
					}
				}
				CPrintToChatAll("%T", "WinnerDisconnected", LANG_SERVER)
			}
			
			
			//Store_SetClientCredits(client, nowjetons);
		}
	}
	betTimer = null;
}

public Action betHinttext(Handle timer, int client)
{
	if (!(client && (IsClientInGame(client))))
	{
		betHinttextTimer[client] = null;
		return Plugin_Stop;
	}
	if (!(betEnabled))
	{
		betHinttextTimer[client] = null;
		return Plugin_Stop;
	}
	
	float luck = (float(betAmount[client])/betTotalAmount)*100.0;
	float curtime = GetGameTime();
	int timeleft = RoundFloat((betTime+60-curtime));
	PrintHintText(client, "%t", "HintboxText", betAmount[client], luck, betTotalAmount, timeleft, "CreditsName");

	return Plugin_Continue;
}
