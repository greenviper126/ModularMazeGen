--!strict

--[==[
Creator: Viper
]==]



--TYPES-----------------------------------------------------------------------------------

type mazeSettings<N, V> = {
	cols:N,
	rows:N,
	height:N,
	width:N,
	cellSize:N,
	worldOffset:V,
	
	rndRemove:N,
	objectChance:N
} --used for options the player can provide and for default settings

type layout<T, V> = {
	pillars:T, --functions that you want to run per pillar, they are the intersection between a col and row
	cells:T, --functions that you want to run per cell
	cols:T, --functions that you want to run per col
	rows:T, --functions that you want to run per row
	once:T, --functions that you want to run once

	objects:V --objects refers to instances placed in the maze, like a table or drawer
} --used for layout data and storing it in memeory

type instMem = {[number]:{Instance}}

type objectMem = {[number]:{[number]:{[string]:Instance}}} --stores the instances based on the cell and direction they are at

type memory = layout<instMem, objectMem>&{
	positions:{Vector2}, --the positions the algorithm took to get there
	solution:{Vector2}, --cell positions to solve the maze, currently does not provide solution
	visited:{boolean}, --used by pathing algorithm to check if its been in a certain cell before

	openDirections:{[number]:{boolean}} --directions that have no walls are true
}

type self = {
	_settings:mazeSettings<number, Vector3> & { --combine settings table with extra data that doesnt need to be provided
		pillarOffset:Vector3, --used by segment functions
		widthOffset:Vector3, --used by segment functions
		totalLength:Vector3, --used by segment functions
	},

	_mazeParts:Folder, --were all instances are stored in workspace
	_memory:memory, --instances and variables used for creating and cleaning up maze
	_layout:instLayout, -- the provided layout data
	_id:number --number to distinguish between mazes
}


export type segment = (self:Maze, x:number, y:number, direction:number?) -> ({}, Instance) --function that places a part in the maze based on given information

export type instLayout = layout<{segment}, {segment}> --layout that needs to be provided to create the maze

export type Settings = mazeSettings<number?, Vector3?> --optional values to provide to the maze



--LOCAL_FUNCTIONS/VARIABLES------------------------------------------------------------------------

local MazeID = 1 --used for _id in self

local function flattenTable(inputTable:{}) --removes tables inside the provided table and moves there data to it
	local function recursiveFlatten(input:{}, output:{})
		for _, v in pairs(input) do
			if type(v) == "table" then
				recursiveFlatten(v, output)
			else
				table.insert(output, v)
			end
		end
	end

	local resultTable = {}
	recursiveFlatten(inputTable, resultTable)
	return resultTable
end

local function iter<T>(tbl:{T}, method:(func:T)->())
	for _, func in pairs(tbl) do --iterates through a table of functions
		method(func) --gives function as first parameter to provided function
	end
end



--MAZE_OBJECT-----------------------------------------------------------------------------

local Maze = {}
Maze.__index = Maze

Maze._default = { --default variables if not provided from settings
	cols = 10,
	rows = 10,
	height = 12,
	width = 3,
	cellSize = 15,
	worldOffset = Vector3.new(0,0,0),

	rndRemove = 0,--%
	objectChance = 0--%
}::mazeSettings<number, Vector3>



export type Maze = typeof(setmetatable({} :: self, Maze)) --creates Maze type for typechecking



--[==[
CONSTUCTOR

configures settings and creates folder to store the maze in workspace
]==]
function Maze.new(set:Settings?):Maze
	local set:Settings = set or {} --table doesnt need to be provided
	local self = setmetatable({}::self, Maze)
	
	self._id = MazeID --set _id
	MazeID += 1 --new number for next maze object
	
	self._settings = {
		cols = set.cols or Maze._default.cols,
		rows = set.rows or Maze._default.rows,
		height = set.height or Maze._default.height,
		width = set.width or Maze._default.width,
		cellSize = set.cellSize or Maze._default.cellSize,
		worldOffset = set.worldOffset or Maze._default.worldOffset,

		rndRemove = set.rndRemove or Maze._default.rndRemove,
		objectChance = set.objectChance or Maze._default.objectChance,
		
		widthOffset = Vector3.zero,
		pillarOffset = Vector3.zero,
		totalLength = Vector3.zero
	}
	
	--set to correct values
	self._settings.widthOffset = Vector3.new(-self._settings.width/2,0,-self._settings.width/2)
	self._settings.pillarOffset = Vector3.new(-self._settings.cellSize/2,0,-self._settings.cellSize/2)
	self._settings.totalLength = Vector3.new(self._settings.rows*self._settings.cellSize+self._settings.width, 0, self._settings.cols*self._settings.cellSize+self._settings.width)
	self._settings.worldOffset = self._settings.worldOffset + self._settings.pillarOffset + Vector3.new(0,1,0)
	
	self._mazeParts = Instance.new("Folder", workspace)
	self._mazeParts.Name = "Maze"..self._id
	
	return self
end



--[==[
Converts col and row data into table index.
]==]
function Maze._cord(self:Maze, x:number, y:number):number
	return (y*self._settings.rows)-self._settings.rows+x
end



--[==[
Should be set first, resets memory so a maze can be created.
]==]
function Maze._init(self:Maze, layout:instLayout)
	if self._memory then --clean table of instances if any
		for _, inst in pairs(flattenTable(self._memory)) do
			if typeof(inst) ~= "Instance" then continue end
			inst:Destroy()
		end
	end
	
	self._layout = layout --set layout data from provide table
	
	self._memory = {
		pillars = {},
		cells = {},
		cols = {},
		rows = {},
		once = {},
		
		objects = {},
		
		positions = {},
		solution = {},
		visited = {},
		openDirections = {}
	}
	
	--memory is based on maze size
	local function setvalue(cord:number)
		self._memory.pillars[cord] = {}
		
		if cord <= self._settings.rows*self._settings.cols+self._settings.rows then
			self._memory.rows[cord] = {}
		end
		if cord <= self._settings.rows*self._settings.cols+self._settings.cols then
			self._memory.cols[cord] = {}
		end
		
		if cord <= self._settings.rows*self._settings.cols then
			self._memory.cells[cord] = {}
			self._memory.visited[cord] = false
			self._memory.openDirections[cord] = {--N,E,S,W
				[1] = false,
				[2] = false,
				[3] = false,
				[4] = false,
			}
			self._memory.objects[cord] = {--N,E,S,W
				[1] = {},
				[2] = {},
				[3] = {},
				[4] = {},
			}
		end
	end
	
	--reset tables
	for cord=1, self:_cord(self._settings.rows+1, self._settings.cols+1) do
		setvalue(cord) --inserts all the needed tables and values for each cell into memory
	end
	self._memory.positions[1] = Vector2.new(1,1)--set first position
	self._memory.visited[1] = true--set first position to be visited
end



--[==[
OBJECT_HANDLING

Methods and functions for placing objects in the maze
]==]

--[[
Adds an object to cell with a specified direction

Must give a function that returns were to store it in memory and the instance you placed in the maze
]]
function Maze._addObject(self:Maze, x:number, y:number, direction:number, func:segment):boolean
	assert(typeof(direction) == "number" and direction >= 1 and direction <= 4, typeof(direction).." is an invalid direction.")
	
	local memType, object = func(self, x, y, direction)
	local cord = self:_cord(x, y)
	local cell = memType[cord]
	
	assert(cell, "Could not add object, index "..cord.." does not exist.")
	
	local newObject = object:Clone()
	cell[direction][object.Name] = newObject
	
	return true
end

--[[
Removes all objects with the same name in a cell with a specified direction
]]
function Maze._removeObject(self:Maze, cord:number, direction:number, object:string):boolean
	local cell = self._memory.objects[cord]

	assert(typeof(direction) == "number" and direction >= 1 and direction <= 4, typeof(direction).." is an invalid direction.")
	assert(cell, "Could not remove object, index "..cord.." does not exist: ", object)
	
	local direction = cell[direction]
	local object = direction[object]
	
	if object then
		object:Destroy()
		direction[object.Name] = nil
		
		return true
	else
		warn("Could not remove object, instance index does not exist, ", object)
		return false
	end
end

--[[
Removes all objects with the same name in the maze.
]]
function Maze._removeObjectInCells(self:Maze, object:string)
	for cord, tbl in pairs(self._memory.objects) do
		for i, direction in pairs(tbl) do
			self:_removeObject(cord, i, object)
		end
	end
end

--[[
Converts direction value to degrees

Used for placing objects
]]
function Maze.DirectionToAngle(direction:number):number
	if direction == 1 then
		return 180
	elseif direction == 2 then
		return 90
	elseif direction == 3 then
		return 0
	elseif direction == 4 then
		return -90
	end

	return 0
end



--[==[
GRID_HANDELING

Methods for creating the maze grid
]==]

--[[
Runs function for each cell
]]
function Maze._populateMain(self:Maze, func:segment)
	for y=1, self._settings.cols do
		for x=1, self._settings.rows do
			local tbl, part = func(self, x, y)
			table.insert(tbl[self:_cord(x, y)], part)
		end
	end
end

--[[
Runs function for end rows
]]
function Maze._populateEndRows(self:Maze, func:segment)
	for x=1, self._settings.rows do
		local tbl, part = func(self, x, self._settings.cols+1)
		table.insert(tbl[self:_cord(x, self._settings.cols+1)], part)
	end
end

--[[
Runs function for end cols
]]
function Maze._populateEndCols(self:Maze, func:segment)
	for y=1, self._settings.cols do
		local tbl, part = func(self, self._settings.rows+1, y)
		table.insert(tbl[self:_cord(self._settings.rows+1, y)], part)
	end
end

--[[
Runs function for end corner
]]
function Maze._populateEndCorner(self:Maze, func:segment)
	local tbl, part = func(self, self._settings.rows+1, self._settings.cols+1)
	table.insert(tbl[self:_cord(self._settings.rows+1, self._settings.cols+1)], part)
end

--[[
Similar to _populateMain but randomly places objects in each cell instead
]]
function Maze._rndPopulateCellWithObjects(self:Maze, func:segment)
	for y=1, self._settings.cols do
		for x=1, self._settings.rows do
			for i=1, 4 do--each direction
				--each object should have a random chance of spawning instead, but this works for now
				if math.random(0, 99) >= self._settings.objectChance then continue end
				if self:_isOpenCell(self:_cord(x, y), i) then continue end
				self:_addObject(x, y, i, func)
			end
		end
	end
end

--[[
Maze template is created based on given layout data and sent to populate methods accordingly
]]
function Maze._layoutPopulate(self:Maze)
	for _, segments in pairs(self._layout) do
		if segments == self._layout.once then
			iter(segments, function(func) 
				func(self, 0, 0)
			end)
		elseif segments == self._layout.cells then
			iter(segments, function(func) 
				self:_populateMain(func)
			end)
		elseif segments == self._layout.pillars then
			iter(segments, function(func) 
				self:_populateMain(func)
				self:_populateEndRows(func)
				self:_populateEndCols(func)
				self:_populateEndCorner(func)
			end)
		elseif segments == self._layout.rows then
			iter(segments, function(func) 
				self:_populateMain(func)
				self:_populateEndRows(func)
			end)
		elseif segments == self._layout.cols then
			iter(segments, function(func) 
				self:_populateMain(func)
				self:_populateEndCols(func)
			end)
		end
	end
end

--[[
Simliar to _layoutPopulate but for places objects

Should be ran last to get correct data
]]
function Maze._objectPopulate(self:Maze)
	iter(self._layout.objects, function(func)
		self:_rndPopulateCellWithObjects(func)
	end)
end




--[=[
PATHING_MODIFIERS

non esential methods for creating mazes
]=]

--[[
Default way to generate maze
]]
function Maze.Generate(self:Maze, layout:instLayout)
	self:_init(layout)
	self:_layoutPopulate()
	self:_createPath()
	self:_randomRemoveWalls()
	self:_objectPopulate()
	
	print("Maze "..self._id.." Complete.")
end

--[[
Creats entrance and exit for the maze
]]
function Maze.DefaultEntry(self:Maze)
	self:_removeCellInstance(self._memory.rows, 1)--staring corner
	self._memory.openDirections[1][3] = true--staring corner

	self:_removeCellInstance(self._memory.rows, self:_cord(self._settings.rows, self._settings.cols+1))--opposite corner
	self._memory.openDirections[self._settings.rows*self._settings.cols][1] = true--opposite corner
end

--[[
Removes walls randomly, should run after path algorithm

makes the maze look a bit more random
turns it into a non perfect maze meaning there is multiple solutions to solve it
]]
function Maze._randomRemoveWalls(self:Maze)
	local function rnd(x:number, y:number, directions:{number})
		for _, direction in pairs(directions) do
			if math.random(0, 99) >= self._settings.rndRemove then continue end
			self:_addDirection(x, y, direction) --removes wall and updates data
		end
	end
	
	for y=1, self._settings.cols do
		for x=1, self._settings.rows do
			local directions = self:_visitableCells(x, y, true)
			if #directions == 0 then continue end
			rnd(x, y, directions)
		end
	end
end



--[=[
PATHING_ALGORITHM
]=]

--[[
Finds cells from current position that the algorithm hasnt visited yet
]]
function Maze._visitableCells(self:Maze, x:number, y:number, noVisit:boolean?):{number}
	local cord = self:_cord(x, y)
	local directions = {} --all possible directions the algorithm can go to next
	
	--north
	if cord+self._settings.rows <= self._settings.rows*self._settings.cols and (noVisit or not self._memory.visited[cord+self._settings.rows]) then
		table.insert(directions, 1)
	end
	--east
	if cord%self._settings.rows ~= 1 and (noVisit or not self._memory.visited[cord-1]) then
		table.insert(directions, 2)
	end
	--south
	if cord-self._settings.rows > 0 and (noVisit or not self._memory.visited[cord-self._settings.rows]) then
		table.insert(directions, 3)
	end
	--west
	if cord%self._settings.rows ~= 0 and (noVisit or not self._memory.visited[cord+1]) then
		table.insert(directions, 4)
	end
	
	return directions
end

--[[
Updates open direction and visited data
]]
function Maze._openCell(self:Maze, cord1:number, cord2:number)
	local direction = cord1 - cord2
	local cell1 = self._memory.openDirections[cord1]
	local cell2 = self._memory.openDirections[cord2]
	
	if direction == -self._settings.rows then --north
		cell1[1] = true; cell2[3] = true
	elseif direction == 1 then --east
		cell1[2] = true; cell2[4] = true
	elseif direction == self._settings.rows then --south
		cell1[3] = true; cell2[1] = true
	elseif direction == -1 then --west
		cell1[4] = true; cell2[2] = true
	end
	self._memory.visited[cord2] = true
end

--[[
Checks if a wall is in the way

Used for objects
]]
function Maze._isOpenCell(self:Maze, cord:number, direction:number):boolean
	local cell = self._memory.openDirections[cord]
	return cell[direction] or false
end

--[[
Remove maze part at certain cord

Not meant for objects
]]
function Maze._removeCellInstance(self:Maze, tbl:{{Instance}}, cord:number)
	local cell = tbl[cord]
	assert(cell, "No instances could be found at table index: "..cord..", tbl: ", tbl)

	for _, part in pairs(cell) do
		if not part:IsA("Instance") then continue end
		part:Destroy()
	end
end

--[[
Remove wall and update data for algorithm
]]
function Maze._addDirection(self:Maze, x:number, y:number, direction:number)
	local cord = self:_cord(x, y)
	
	if direction == 1 then --north
		self:_openCell(cord, cord+self._settings.rows)
		self:_removeCellInstance(self._memory.rows, cord+self._settings.rows)
		table.insert(self._memory.positions,Vector2.new(x, y+1))
	elseif direction == 2 then --east
		self:_openCell(cord, cord-1)
		self:_removeCellInstance(self._memory.cols, cord)
		table.insert(self._memory.positions,Vector2.new(x-1, y))
	elseif direction == 3 then --south
		self:_openCell(cord, cord-self._settings.rows)
		self:_removeCellInstance(self._memory.rows, cord)
		table.insert(self._memory.positions,Vector2.new(x, y-1))
	elseif direction == 4 then --west
		self:_openCell(cord, cord+1)
		self:_removeCellInstance(self._memory.cols, cord+1)
		table.insert(self._memory.positions,Vector2.new(x+1, y))
	end
end

--[[
Creats path using recursive backtracking
]]
function Maze._createPath(self:Maze)
	local function recursiveBacktrack()
		local x = self._memory.positions[#self._memory.positions].X::number
		local y = self._memory.positions[#self._memory.positions].Y::number
		local directions = self:_visitableCells(x, y)
		local cord = self:_cord(x, y)
		
		if #directions > 0 then --found direction
			local nextCellDir = directions[math.random(1, #directions)]
			self:_addDirection(x, y, nextCellDir)
		else --no new directions
			table.remove(self._memory.positions) --backtrack
		end
	end
	
	repeat --regular function recusion is to slow
		recursiveBacktrack()
	until
	self._memory.positions == nil or table.maxn(self._memory.positions) == 0
end



--[==[
CLEANUP
]==]
function Maze.Destroy(self:Maze)
	for _, value in pairs(flattenTable(self._memory)) do
		if typeof(value) == "Instance" then
			value:Destroy() --remove all instances of the maze
		end
	end
	self = nil::any
end

return Maze
