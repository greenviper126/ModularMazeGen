--!strict

local ServerStorage = game:GetService("ServerStorage")

local MazeGen = require(ServerStorage.Maze:WaitForChild("MazeGen"))
local DefaultLayout = require(ServerStorage.Maze:WaitForChild("DefaultLayout"))

local mazeSettings = {
	cols = 50,
	rows = 50,
	rndRemove = 10,
	objectChance = 5,
	worldOffset = Vector3.new(0,0,10)
}::MazeGen.Settings

local newMaze = MazeGen.new(mazeSettings)
newMaze:Generate(DefaultLayout.layout)
newMaze:DefaultEntry()--create entrance and exit
