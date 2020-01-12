-- Mountain Defence

-- Teams
-- 1 - Player
-- 5 - Attackers and Cerberi GT's
-- 6 - Hadean GT's

-- Northwest - apcdepart
-- West - recyclerpath1

assert(load(assert(LoadFile("_requirefix.lua")),"_requirefix.lua"))();
local _FECore = require('_FECore');

local Routines = {};

local NORTH_PATH = "north_path";
local NORTH_WEST_PATH = "north_west_path";
local WEST_PATH = "west_path";
local SOUTH_PATH = "south_path";
local EAST_PATH = "east_path";

local UNITS = {
	Triton = "cvscout",
	Krul = "cvtank",
	Xypos = "evscout",
	Dominator = "cvhatank",
	ZeusSks = "evmislu",
	ZeusWorm = "evmislw",
	Xares = "evtank",
	Talon = "cvtalon02",
	Demon = "cvdcar",
	Drath = "cvwalk",
	Siren = "cvrbomb",
	Dread = "cvatank",
	Krahanos = "evwalk",
	HedouxLs = "evatankl",
	Locust = "evmort",
	Gorgon = "cvgorg",
	HedouxFbs = "evatanks",
}

local M = {
--Mission State
	RoutineState = {},
	RoutineWakeTime = {},
	RoutineActive = {},
	MissionOver = false,
	StrongerAttacks = false,
	AwayFromBase = false,
	PlayerBuildings = {},

-- Floats

-- Handles
	PortalNorth = nil,
	PortalNorthWest = nil,
	PortalWest = nil,
	PortalSouth = nil,
	PortalEast = nil,
	Recycler = nil,
	Jammer = nil,

-- Ints
	TPS = 10,
--Vectors

--End
	endme = 0
}

function LaunchAttacks(R, STATE, spawn, path, attackPlan)
	local plan = attackPlan[STATE + 1];

	-- Deactivate the routine if there is no more attacks
	-- We can only get into a negative state if there is a condition function
	if (plan == nil) then
		if (STATE > 0) then
			SetRoutineActive(R, false);
			return;
		else
			plan = attackPlan[-STATE - 1];
		end
	end

	-- Check for condtions
	if plan.Condition ~= nil then
		if plan.Condition() == false then
			if STATE < 0 then
				Wait(R, 5);
			else
				-- Failing a condition means we negate the state
				SetState(R, -1 - STATE, 5);
			end
			return
		else
			if STATE < 0 then
				-- Reset state back to positive in case of success
				SetState(R, -STATE - 1, 0);
			end
		end
	end

	-- Spawn attackers
	local distance = 10;
	local units = {};
	if plan.Attackers ~= nil then
		local attackers = {};
		if type(plan.Attackers) == "function" then
			attackers = plan.Attackers();
		else
			attackers = plan.Attackers;
		end
		for k, attacker in pairs(attackers) do
			units[k] = TeleportIn(attacker, 5, spawn, distance)
			SetEjectRatio(units[k], 0);
			distance = distance + 5;
		end
	end

	-- Order attackers to do things
	if plan.Orders ~= nil then
		plan.Orders(units);
	else
		for k, attacker in pairs(units) do
			Patrol(attacker, path, 1);
		end
	end

	-- Set the next state
	local nextState = STATE + 1;
	if plan.NextState ~= nil then
		if type(plan.NextState) == "function" then
			nextState = plan.NextState();
		else
			nextState = plan.NextState;
		end
	end

	-- Set a delay after attack
	local delay = 0;
	if plan.DelayAfterAttack ~= nil then
		if type(plan.DelayAfterAttack) == "function" then
			delay = plan.DelayAfterAttack();
		else
			delay = plan.DelayAfterAttack;
		end
	end

	SetState(R, nextState, delay);
end

function DefineRoutine(routineID, func, activeOnStart)
	if routineID == nil or Routines[routineID]~= nil then
		-- error("DefineRoutine: duplicate or invalid routineID: "..tostring(routineID));
		PrintConsoleMessage("DefineRoutine: duplicate or invalid routineID: "..tostring(routineID));
	else
		Routines[routineID] = func;
		M.RoutineState[routineID] = 0;
		M.RoutineWakeTime[routineID] = 0.0;
		M.RoutineActive[routineID] = activeOnStart;
	end
end

function Advance(routineID, delay)
	routineID = routineID or error("Advance(): invalid routineID.", 2);
	SetState(routineID, M.RoutineState[routineID] + 1, delay);
end

function SetState(routineID, state, delay)
	routineID = routineID or error("SetState(): invalid routineID.", 2);
	delay = delay or 0.0;
	PrintConsoleMessage("SetState() " .. " " .. routineID .. " " .. state .. " " .. delay);
	M.RoutineState[routineID] = state;
	M.RoutineWakeTime[routineID] = GetTime() + delay;
end

function Wait(routineID, delay)
	M.RoutineWakeTime[routineID] = GetTime() + delay;
end

function SetRoutineActive(routineID, active)
	M.RoutineActive[routineID] = active;
end

function Save()

	_FECore.Save();
	
	return M
end

function Load(...)
	
	_FECore.Load();
	
	if select('#', ...) > 0 then
		M = ...
	end
end

function InitialSetup()
	_FECore.InitialSetup();

	DefineRoutine("North Portal", PortalNorthAttackRoutine, true);
	DefineRoutine("North West Portal", PortalNorthWestAttackRoutine, true);
	DefineRoutine("West Portal", PortalWestAttackRoutine, true);
	DefineRoutine("East Portal", PortalEastAttackRoutine, true);
	DefineRoutine("South Portal", PortalSouthAttackRoutine, true);

	DefineRoutine("Main Mission Loop", MissionRoutine, true);
	DefineRoutine("Check Rec Alive", CheckRecAlive, true);
	DefineRoutine("Check Away From Base", CheckAwayFromBase, true);
	DefineRoutine("Heal Buildings", HealBuildings, true);

	local preloadODFs = {
		"teleportin"
	};
	for k,v in pairs(preloadODFs) do
		PreloadODF(v);
	end

	for k,v in pairs(UNITS) do
		PreloadODF(v);
	end

	M.TPS = EnableHighTPS();
	AllowRandomTracks(false);
end

function Start()

	_FECore.Start();

	DefaultAllies();
	-- Defenders and Attackers are allied at start
	Ally(5, 6);
	SetScrap(1, 40);

	-- Get portal handles
	M.PortalNorth = GetHandleOrDie('portalnorth');
	M.PortalNorthWest = GetHandleOrDie('portalnorthwest');
	M.PortalWest = GetHandleOrDie('portalwest');
	M.PortalEast = GetHandleOrDie('portaleast');
	M.PortalSouth = GetHandleOrDie('portalsouth');
	
	-- Player Handles
	M.Player = GetPlayerHandle();
	M.Recycler = GetHandleOrDie('unnamed_ivrecy');
	M.Jammer = GetHandleOrDie("riverjammer");

	-- Handle portals ourselves
	ClearPortalDest(M.PortalNorth, true);
	ClearPortalDest(M.PortalNorthWest, true);
	ClearPortalDest(M.PortalWest, true);
	ClearPortalDest(M.PortalEast, true);
	ClearPortalDest(M.PortalSouth, true);

	PrintConsoleMessage("Starting Mountain Defence Mission");

	--prevents script from accidentally creating new global variables.
	GLOBAL_lock(_G);
end

function Update()
	_FECore.Update();

	for routineID,r in pairs(Routines) do
		if M.RoutineActive[routineID] and M.RoutineWakeTime[routineID] <= GetTime() then
			r(routineID, M.RoutineState[routineID]);
		end
	end

	M.Player = GetPlayerHandle();
end

function MissionRoutine(R, STATE)
	if STATE == 0 then
		AddObjective("Defend the Recycler until further orders");
		Advance(R);
	elseif STATE == 1 then
		Advance(R, 800);
	elseif STATE == 2 then
		if IsAround(M.Jammer) then
			ClearObjectives();
			AddObjective("There is an Excluder Jammer to the south in the river system. Destroying it will turn the Hadean defences to our side.");
			SetObjectiveOn(M.Jammer);
		end
		Advance(R);
	elseif STATE == 3 then
		if IsAround(M.Jammer) == false then
			ClearObjectives();
			AddObjective("The Hadean defences are now under our control. Defend the Recycler until further orders.");
			M.StrongerAttacks = true;
			Ally(1,6);
			UnAlly(5,6);
			Advance(R);
		end
		Wait(R, 5);
	elseif STATE == 4 then
		Wait(R, 450);
	end
end

function CheckRecAlive(R, STATE)
	if IsAround(M.Recycler) == false then
		FailMission(5, "MountainFailRec.txt");
	end
end

function CheckAwayFromBase(R, STATE)
	if Distance3DSquared(M.Recycler, M.Player) > 600 then
		if M.AwayFromBase ~= true then
			PrintConsoleMessage("Player away from base");
			M.AwayFromBase = true;
			M.PlayerBuildings = {};
			for k, v in pairs(GetAllGameObjectHandles()) do
				if (IsBuilding(v) or GetCfg(v) == "ibgtow") and GetTeamNum(v) == 0 then
					M.PlayerBuildings[k] = v;
				end
			end
		end
	else
		if M.AwayFromBase == true then
			PrintConsoleMessage("Player close to base");
			M.AwayFromBase = false;
		end
	end
	Wait(R, 10);
end

function HealBuildings(R, STATE)
	if M.AwayFromBase == true then
		for k, v in pairs(M.PlayerBuildings) do
			AddHealth(v, 200);
		end
	end
	Wait(R, 5);
end

local NorthAttacks = {
	{
		DelayAfterAttack = 120,
		NextState = 1,
		Attackers = {
			UNITS.Xypos,
			UNITS.Xypos
		}
	},
	{
		DelayAfterAttack = 70,
		NextState = function()
			if M.StrongerAttacks then
				return 2;
			end
			return 1;
		end,
		Attackers = {
			UNITS.Xypos,
			UNITS.Xypos
		}
	},

	-- Stronger Attacks
	{
		DelayAfterAttack = 40,
		Attackers = {
			UNITS.Xares,
			UNITS.Xypos,
		}
	},
	{
		DelayAfterAttack = 60,
		NextState = 2,
		Attackers = {
			UNITS.Xares,
			UNITS.Xares,
			UNITS.Locust
		}
	}
}
function PortalNorthAttackRoutine(R, STATE)
	LaunchAttacks(R, STATE, M.PortalNorth, NORTH_PATH, NorthAttacks);
end

local NorthWestAttacks = {
	{
		DelayAfterAttack = 500
	},
	{
		DelayAfterAttack = 80,
		Attackers = {
			UNITS.Dominator,
			UNITS.Krul
		}
	},
	{
		DelayAfterAttack = 80,
		Attackers = {
			UNITS.Drath,
		},
	},
	{
		DelayAfterAttack = 60,
		NextState = function()
			if M.StrongerAttacks == true then
				return 4;
			end
			return 1;
		end,
		Attackers = {
			UNITS.Siren,
			UNITS.Triton
		}
	},
	
	-- Stronger Attacks
	{
		DelayAfterAttack = 90,
		Attackers = {
			UNITS.Krul,
			UNITS.Krul,
			UNITS.Dominator,
		}
	},
	{
		DelayAfterAttack = 80,
		Attackers = {
			UNITS.Drath,
			UNITS.Triton,
			UNITS.Krul
		}
	},
	{
		DelayAfterAttack = 60,
		Attackers = {
			UNITS.Demon,
		}
	},
	{
		DelayAfterAttack = 60,
		NextState = 4,
		Attackers = {
			UNITS.Gorgon
		}
	}
}
function PortalNorthWestAttackRoutine(R, STATE)
	LaunchAttacks(R, STATE, M.PortalNorthWest, NORTH_WEST_PATH, NorthWestAttacks);
end

local WestAttacks = {
	{
		DelayAfterAttack = 60
	},
	{
		DelayAfterAttack = function ()
			if (GetTime() > 360) then
				return 40;
			end
			return 300;
		end,
		Attackers = {
			UNITS.Xypos,
		}
	},
	{
		DelayAfterAttack = 40,
		Attackers = {
			UNITS.HedouxLs,
			UNITS.Xypos,
		}
	},
	{
		DelayAfterAttack = 20,
		NextState = function()
			if M.StrongerAttacks == true then
				return 5;
			end
			return 1;
		end,
		Attackers = {
			UNITS.Xares,
			UNITS.Xypos
		}
	},

	-- Stronger Attacks
	{
		DelayAfterAttack = 40,
		Attackers = {
			UNITS.Locust,
			UNITS.Locust,
		}
	},
	{
		DelayAfterAttack = 100,
		Attackers = {
			UNITS.Xares,
			UNITS.Xares,
			UNITS.HedouxFbs,
		}
	},
	{
		DelayAfterAttack = 40,
		NextState = 5,
		Attackers = {
			UNITS.Krahanos
		}
	}
}
function PortalWestAttackRoutine(R, STATE)
	LaunchAttacks(R, STATE, M.PortalWest, WEST_PATH, WestAttacks);
end

local EastAttacks = {
	{
		DelayAfterAttack = 100,
	},
	{
		DelayAfterAttack = 60,
		Attackers = {
			UNITS.Xypos
		}
	},
	{
		DelayAfterAttack = 50,
		Attackers = {
			UNITS.Xares
		}
	},
	{
		DelayAfterAttack = 40,
		NextState = function()
			if M.StrongerAttacks == true then
				return 4;
			end
			return 2;
		end,
		Attackers = {
			UNITS.Locust,
			UNITS.ZeusWorm
		}
	},

	-- Stonger Attacks
	{
		DelayAfterAttack = 70,
		Attackers = {
			UNITS.ZeusWorm,
			UNITS.ZeusSks,
			UNITS.Xypos
		}
	},
	{
		DelayAfterAttack = 60,
		NextState = 4,
		Attackers = {
			UNITS.HedouxFbs,
			UNITS.HedouxFbs,
			UNITS.Xares,
			UNITS.Locust
		}
	},
}
function PortalEastAttackRoutine(R, STATE)
	LaunchAttacks(R, STATE, M.PortalEast, EAST_PATH, EastAttacks);
end

local SouthAttacks = {
	{
		DelayAfterAttack = 20,
		Attackers = {
			UNITS.Triton,
		}
	},
	{
		DelayAfterAttack = 200
	},
	{
		DelayAfterAttack = 20,
		Attackers = {
			UNITS.Triton,
		}
	},
	{
		DelayAfterAttack = 70,
		Attackers = {
			UNITS.Triton,
			UNITS.Krul
		}
	},
	{
		DelayAfterAttack = function() 
			if GetTime() > 500 then
				return 200;
			end
			return 100;
		end,
		Attackers = {
			UNITS.Siren,
			UNITS.Triton
		}
	},
	{
		DelayAfterAttack = 20,
		NextState = function()
			if M.StrongerAttacks == true then
				return 7;
			end
			return 2;
		end,
		Attackers = {
			UNITS.Talon,
			UNITS.Talon
		}
	},

	-- Stronger Attacks
	{
		DelayAfterAttack = 80,
		Attackers = {
			UNITS.Krul,
			UNITS.Krul,
			UNITS.Triton,
			UNITS.Triton,
			UNITS.Siren,
		}
	},
	{
		DelayAfterAttack = 80,
		Attackers = {
			UNITS.Krul,
			UNITS.Krul,
			UNITS.Krul,
			UNITS.Krul,
			UNITS.Krul,
			UNITS.Dread
		}
	},
	{
		DelayAfterAttack = 60,
		Attackers = {
			UNITS.Talon,
			UNITS.Talon,
			UNITS.Talon,
		}
	},
	{
		DelayAfterAttack = 80,
		NextState = 7,
		Attackers = {
			UNITS.Demon,
		}
	}
}
function PortalSouthAttackRoutine(R, STATE)
	LaunchAttacks(R, STATE, M.PortalSouth, SOUTH_PATH, SouthAttacks);
end