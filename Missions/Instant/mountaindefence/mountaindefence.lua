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
	Locust = "evmort"
}

local M = {
--Mission State
	RoutineState = {},
	RoutineWakeTime = {},
	RoutineActive = {},
	MissionOver = false,

-- Floats

-- Handles
	PortalNorth = nil,
	PortalNorthWest = nil,
	PortalWest = nil,
	PortalSouth = nil,
	PortalEast = nil,
	Recycler = nil,

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
		error("DefineRoutine: duplicate or invalid routineID: "..tostring(routineID));
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
	PrintConsoleMessage("SetState() " .. " " .. routineID .. " " .. state .. " " .. delay);
	routineID = routineID or error("SetState(): invalid routineID.", 2);
	delay = delay or 0.0;
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

	-- DefineRoutine(1, PortalNorthAttackRoutine, true);
	DefineRoutine(2, PortalNorthWestAttackRoutine, true);
	-- DefineRoutine(3, PortalWestAttackRoutine, true);
	-- DefineRoutine(4, PortalEastAttackRoutine, true);
	-- DefineRoutine(5, PortalSouthAttackRoutine, true);

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

	_FECore.Start()

	DefaultAllies()
	-- Defenders and Attackers are allied at start
	Ally(5, 6);
	SetScrap(1, 40)

	-- Get portal handles
	M.PortalNorth = GetHandleOrDie('portalnorth');
	M.PortalNorthWest = GetHandleOrDie('portalnorthwest');
	M.PortalWest = GetHandleOrDie('portalwest');
	M.PortalEast = GetHandleOrDie('portaleast');
	M.PortalSouth = GetHandleOrDie('portalsouth');
	
	-- Player Handles
	M.Player = GetPlayerHandle();
	M.Recycler = GetHandleOrDie('unnamed_ivrecy');

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
		NextState = 1,
		Attackers = {
			UNITS.Xypos,
			UNITS.Xypos
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
		NextState = 1,
		Attackers = {
			UNITS.Siren,
			UNITS.Siren
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
		NextState = 1,
		Attackers = {
			UNITS.Xares,
			UNITS.Xypos
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
		NextState = 1,
		Attackers = {
			UNITS.Locust,
			UNITS.ZeusWorm
		}
	}
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
		NextState = 2,
		Attackers = {
			UNITS.Talon,
			UNITS.Talon
		}
	}
}
function PortalSouthAttackRoutine(R, STATE)
	LaunchAttacks(R, STATE, M.PortalSouth, SOUTH_PATH, SouthAttacks);
end