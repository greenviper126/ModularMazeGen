--!strict

local ServerStorage = game:GetService("ServerStorage")
local CollectionService = game:GetService("CollectionService")

local MazeGen = require(ServerStorage.Maze.MazeGen)



local function setWallpbr(part:Part)
	part.Color = Color3.fromRGB(255, 255, 255)
	part.Material = Enum.Material.SmoothPlastic
	part.MaterialVariant = "BackRooms Wall"
end

local function setCeilingpbr(part:Part)
	part.Color = Color3.fromRGB(174, 171, 96)
	part.Material = Enum.Material.Rock
	part.MaterialVariant = "Office Ceiling Tiles"
end

local function setFloorpbr(part:Part)
	part.Color = Color3.fromRGB(174, 171, 96)
	part.Material = Enum.Material.Fabric
end



local DefaultMaze = {}
	
function DefaultMaze.Pillar(self:MazeGen.Maze, x:number, z:number)
	local part = Instance.new("Part")
	part.Anchored = true
	part.Size = Vector3.new(self._settings.width, self._settings.height, self._settings.width)
	part.Position = Vector3.new(x*self._settings.cellSize, self._settings.height/2, z*self._settings.cellSize) + self._settings.pillarOffset + self._settings.worldOffset
	part.Parent = self._mazeParts
	
	setWallpbr(part)
	
	return self._memory.pillars, part
end

function DefaultMaze.Ceiling(self:MazeGen.Maze, x:number, z:number)
	local posOffset = -self._settings.pillarOffset + self._settings.widthOffset + self._settings.worldOffset
	
	local part = Instance.new("Part")
	part.Anchored = true
	part.CastShadow = false
	part.Size = self._settings.totalLength + Vector3.new(0,1,0)
	part.Position = self._settings.totalLength/2 + Vector3.new(0,0.5+self._settings.height,0) + posOffset
	part.Parent = self._mazeParts
	
	local highlight = Instance.new("Highlight")
	highlight.Adornee = part
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.FillColor = Color3.fromRGB(212, 255, 133)
	highlight.FillTransparency = 0.6
	highlight.OutlineTransparency = 1
	highlight.Parent = part
	
	setCeilingpbr(part)

	return self._memory.once, part
end

function DefaultMaze.Floor(self:MazeGen.Maze, x:number, z:number)
	local posOffset = -self._settings.pillarOffset + self._settings.widthOffset + self._settings.worldOffset
	
	local part = Instance.new("Part")
	part.Anchored = true
	part.Size = self._settings.totalLength + Vector3.new(0,1,0)
	part.Position = self._settings.totalLength/2 + Vector3.new(0,-0.5,0) + posOffset
	part.Parent = self._mazeParts
	
	setFloorpbr(part)
	
	return self._memory.once, part
end

function DefaultMaze.Wall(self:MazeGen.Maze, x:number, z:number, r:number)
	local part = Instance.new("Part")
	part.Anchored = true
	part.Size = Vector3.new(self._settings.cellSize-self._settings.width, self._settings.height, self._settings.width)
	part.Position = Vector3.new(x*self._settings.cellSize, self._settings.height/2, z*self._settings.cellSize) + self._settings.worldOffset
	part.Rotation = Vector3.new(part.Rotation.X, r or 0, part.Rotation.Y)
	part.CFrame = part.CFrame * CFrame.new(Vector3.new(0, 0, self._settings.pillarOffset.Z))
	part.Parent = self._mazeParts
	
	setWallpbr(part)
	
	return part
end

function DefaultMaze.RowWall(self:MazeGen.Maze, x:number, z:number)
	return self._memory.rows, DefaultMaze.Wall(self, x, z, 0)
end

function DefaultMaze.ColWall(self:MazeGen.Maze, x:number, z:number)
	return self._memory.cols, DefaultMaze.Wall(self, x, z, 90)
end

--this is more of a test for objects, this should be moved to MazeGen module
function DefaultMaze.objects(folder:Instance):...MazeGen.segment
	local segments = {}
	
	for _, inst in pairs(folder:GetChildren()) do
		if not inst:IsA("Model") then continue end
		
		table.insert(segments, function(self:MazeGen.Maze, x:number, z:number, direction:number?)
			assert(typeof(direction) == "number", typeof(direction).." is not a number.")
			
			local model = inst:Clone()
			assert(model and model.PrimaryPart, "model has no primary, ", inst)
			model.Name = tostring(direction)
			CollectionService:AddTag(model.PrimaryPart, "Object")
			
			--at the moment objects only get placed correctly when the original model is facing the right direction, ill find a fix later
			
			local modelSize = model.PrimaryPart.Size
			local midPos = Vector3.new(x*self._settings.cellSize, modelSize.Y/2, z*self._settings.cellSize) + self._settings.worldOffset
			local rotation = Vector3.new(model.PrimaryPart.Rotation.X, self.DirectionToAngle(direction), model.PrimaryPart.Rotation.Y)
			local baseCord = CFrame.new(midPos) * CFrame.Angles(math.rad(rotation.X), math.rad(rotation.Y), math.rad(rotation.Z))
			local transformedCord = baseCord * CFrame.new(Vector3.new(0, 0, self._settings.pillarOffset.Z + modelSize.X/2))
			
			model:PivotTo(transformedCord)
			
			model.Parent = self._mazeParts
			
			local parts = workspace:GetPartBoundsInBox(model:GetPivot(), model.PrimaryPart.Size)
			for _, part in pairs(parts) do
				if not CollectionService:HasTag(part, "Object") then continue end
				if part == model.PrimaryPart then continue end
				
				model:Destroy()
			end
			
			
			return self._memory.objects, model
		end)
	end
	
	return table.unpack(segments)
end



--layout data that the MazeGen can use
DefaultMaze.layout = {
	once = {DefaultMaze.Floor, DefaultMaze.Ceiling},
	pillars = {DefaultMaze.Pillar},
	cells = {},
	rows = {DefaultMaze.RowWall},
	cols = {DefaultMaze.ColWall},
	objects = {DefaultMaze.objects(ServerStorage.Objects)}
}::MazeGen.instLayout

return DefaultMaze
