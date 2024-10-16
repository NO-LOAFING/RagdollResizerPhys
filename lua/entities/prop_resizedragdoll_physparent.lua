AddCSLuaFile()

ENT.Base 			= "base_gmodentity"
ENT.PrintName			= "Resized Ragdoll"

ENT.Spawnable			= false
ENT.AdminSpawnable		= false

ENT.AutomaticFrameAdvance	= true
ENT.RenderGroup			= false //let the engine set the rendergroup by itself

ENT.ClassOverride		= "prop_resizedragdoll_physparent"




function ENT:SetupDataTables()

	self:NetworkVar("Bool", 0, "Stretch")

	//TODO: move all the physobj scales here eventually and get rid of the current networking system; that'll take a little effort since we'll need handling for the values changing
	//i.e. in cases where clients got bad values or were slow to update them

end




function ENT:Initialize()

	if SERVER then

		if !self.PhysObjScales then MsgN("ERROR: Resized ragdoll " .. self:GetModel() .. " doesn't have a PhysObjScales table! Something went wrong!") self:Remove() return end

		if !self.PhysObjMeshes then //if someone wants to specify custom meshes for whatever reason, they can fill this table before initializing the resized ragdoll
			//Spawn a ragdoll with our model so we can grab its physics meshes
			local rag = ents.Create("prop_ragdoll")
			if !IsValid(rag) then MsgN("error: Resized ragdoll " .. self:GetModel() .. " couldn't spawn a normal ragdoll to get its physics meshes!") self:Remove() return end
			rag:SetModel(self:GetModel())
			rag:Spawn()

			//Get the default physics mesh from each of the ragdoll's physics objects
			local meshes = {}
			for i = 0, rag:GetPhysicsObjectCount() - 1 do
				local physobj = rag:GetPhysicsObjectNum(i)
				if physobj:IsValid() then
					local convexes = physobj:GetMeshConvexes()
					meshes[i] = {}
					for convexnum, convextab in pairs (convexes) do
						meshes[i][convexnum] = meshes[i][convexnum] or {}
						for _, v in pairs (convextab) do
							table.insert(meshes[i][convexnum], v.pos)
						end
					end
				end
			end
			self.PhysObjMeshes = meshes
			rag:Remove()
		end
		
		//Sanity check for self.PhysObjScales - if we're from a save/dupe, and our saved PhysObjScales table doesn't match up with the number of physobjs on the model (i.e. player installed 
		//an improved physics addon for that model, giving it more physobjs than it had when the save was made), then it'll try to get nonexistent scales and cause errors unless we fix it up.
		local tab = {}
		for i, _ in pairs (self.PhysObjMeshes) do
			if self.PhysObjScales[i] == nil then
				tab[i] = Vector(1,1,1)
			else
				tab[i] = self.PhysObjScales[i]
			end
		end
		self.PhysObjScales = tab

		//Have a dummy ent use FollowBone to expose all of the entity's bones. If we don't do this, a whole bunch of bones can return as invalid clientside, 
		//as well as return the wrong locations serverside.
		local lol = ents.Create("base_point")
		lol:SetPos(self:GetPos())
		lol:SetAngles(self:GetAngles())
		lol:FollowBone(self,0)
		lol:Spawn()
		lol:Remove() //We don't need the ent to stick around. All we needed was for it to use FollowBone once.

		self:SetAngles(Angle(0,0,0))
		//Don't set sequence yet, we need to get the physobj pos offsets from the default idle sequence


		//Get the model's info table and process it - we'll need it to set up the physobjs
		local modelinforaw = util.GetModelInfo(self:GetModel())
		if !modelinforaw or !modelinforaw.KeyValues then
			if !util.IsValidModel(self:GetModel()) then
				MsgN("RAGDOLL RESIZER: Removed resized ragdoll ", self:GetModel(), " because we can't get its model info due to an invalid model. (dupe/save using a model that's not installed?)")
			else
				MsgN("RAGDOLL RESIZER: Removed resized ragdoll ", self:GetModel(), " because we can't get its model info for an unknown reason.")
			end
			self:Remove()
			return 
		end
		self.ModelInfo = {}
		for _, tab in pairs (util.KeyValuesToTablePreserveOrder(modelinforaw.KeyValues)) do
			--[[MsgN(tab.Key)
			for _, tab2 in pairs (tab.Value) do
				MsgN( tab2.Key .. " = " .. tab2.Value )
			end
			MsgN("")]]

			if tab.Key == "solid" then
				self.ModelInfo.Solids = self.ModelInfo.Solids or {}

				local tabprocessed = {}
				for _, tab2 in pairs (tab.Value) do
					tabprocessed[tab2.Key] = tab2.Value
				end

				self.ModelInfo.Solids[tabprocessed["index"]] = tabprocessed
			end

			if tab.Key == "ragdollconstraint" then
				self.ModelInfo.Constraints = self.ModelInfo.Constraints or {}

				local tabprocessed = {}
				for _, tab2 in pairs (tab.Value) do
					tabprocessed[tab2.Key] = tab2.Value
				end

				self.ModelInfo.Constraints[tabprocessed["child"]] = tabprocessed
			end

			if tab.Key == "collisionrules" then
				self.ModelInfo.CollisionPairs = self.ModelInfo.CollisionPairs or {}

				for _, tab2 in pairs (tab.Value) do
					if tab2.Key == "collisionpair" then
						local pair = string.Explode( ",", tab2.Value, false)
						table.insert(self.ModelInfo.CollisionPairs, pair)
					elseif tab2.Key == "selfcollisions" then
						self.ModelInfo.SelfCollisions = tab2.Value
					end
				end
			end
		end
		//PrintTable(self.ModelInfo)


		//self:TranslateBoneToPhysBone() just doesn't work at all on some models (TODO: which model? need to write this down for further testing!), so we can't rely on it - make a table to use instead
		self.PhysObjPhysBoneIDs = {}
		for i = 0, table.Count(self.ModelInfo.Solids) - 1 do
			self.PhysObjPhysBoneIDs[string.lower(self.ModelInfo.Solids[i]["name"])] = i
		end

		//Generate physbone offsets - use the modelinfo table to determine which physobjs are parented to which, and then get their offset from their parent.
		//We need this because we need to multiply the position offset by the parent physbone's scale.

		for i = 0, table.Count(self.ModelInfo.Solids) - 1 do

			//MsgN("test: ", i , " translate bone to physbone ", self:TranslateBoneToPhysBone(i))

			if self.ModelInfo.Solids[i]["parent"] then
				//Physobj has a parent physobj, so get its offset from that
				local bonepos = self:GetBoneMatrix( self:TranslatePhysBoneToBone(i) ):GetTranslation()
				local parboneid = self:LookupBone(self.ModelInfo.Solids[i]["parent"])
				local parbonepos, parboneang = self:GetBoneMatrix( parboneid ):GetTranslation(), self:GetBoneMatrix( parboneid ):GetAngles()

				local offsetpos, _ = WorldToLocal(bonepos, Angle(0,0,0), parbonepos, parboneang)
				self.ModelInfo.Solids[i]["offsetpos"] = offsetpos * self.PhysObjScales[ self.PhysObjPhysBoneIDs[string.lower(self.ModelInfo.Solids[i]["parent"])] ]
			else
				//Physobj doesn't have a parent physobj, so get its offset from the model origin
				local bonepos = self:GetBoneMatrix( self:TranslatePhysBoneToBone(i) ):GetTranslation()

				local offsetpos, _ = WorldToLocal(bonepos, Angle(0,0,0), self:GetPos(), self:GetAngles())
				self.ModelInfo.Solids[i]["offsetpos"] = offsetpos
			end

		end

		//Now use the ragdoll sequence for physobj and constraint angles
		//TODO: This doesn't work right for at least one model that doesn't have a proper ragdoll seq for its default constraint angs (models/Humans/Charple01.mdl). Where does it get its angs from??
		local sequence = self:SelectWeightedSequence(ACT_DIERAGDOLL)
		if sequence != -1 then
			self:SetModel(self:GetModel()) //calling SetModel here prevents animation blending, instead we get the angs from the new animation immediately
			self:SetSequence(sequence)
			self:ResetSequence(sequence)
		end

		//Create the physics objects
		self.PhysObjs = {}
		self.PhysObjEnts = {}
		local PhysObjErrors = {}
		for i = 0, table.Count(self.ModelInfo.Solids) - 1 do

			local matr = self:GetBoneMatrix( self:TranslatePhysBoneToBone(i) )
			if matr then
				local physent = ents.Create("prop_resizedragdoll_physobj")

				if self.ModelInfo.Solids[i]["parent"] and self.ModelInfo.Solids[i]["parent"] != self.ModelInfo.Solids[i]["name"] then
					//Physobj has a parent physobj, so use its offset from that (TODO: What if a model is set up so that the parent physobj is created LATER than its
					//child for some reason? That would break everything since we wouldn't be able to get the parent's position!)
					local parphysobjid = self.PhysObjPhysBoneIDs[string.lower(self.ModelInfo.Solids[i]["parent"])]
					local parphysent = self.PhysObjEnts[parphysobjid]
					if !IsValid(parphysent) then
						PhysObjErrors[i] = i .. ": " .. self.ModelInfo.Solids[i]["name"] .. " couldn't be created because its parent (" .. self.ModelInfo.Solids[i]["parent"]  .. ") doesn't exist/failed to generate."
						continue
					end
					local ourpos, _ = LocalToWorld(self.ModelInfo.Solids[i]["offsetpos"], Angle(0,0,0), parphysent:GetPos(), parphysent:GetAngles())
					physent:SetPos(ourpos)

					//Store this stuff in the physent so it can use it itself
					physent.PhysParent = parphysent
					physent.PhysParentOffsetPos = self.ModelInfo.Solids[i]["offsetpos"]
				else
					//Physobj doesn't have a parent physobj, so use its offset from the model origin
					local ourpos, _ = LocalToWorld(self.ModelInfo.Solids[i]["offsetpos"], Angle(0,0,0), self:GetPos(), self:GetAngles())
					physent:SetPos(ourpos)
				end

				physent:SetAngles(matr:GetAngles())
				physent:SetModel("models/hunter/plates/plate.mdl")
				physent:DrawShadow(false)

				physent.RagdollParent = self
				physent.PhysBoneNum = i
				physent:Spawn()

				//multiply each of the vectors inside the mesh table by our scale
				local scaledmesh = {}
				for convexnum, convextab in pairs (self.PhysObjMeshes[i]) do
					scaledmesh[convexnum] = scaledmesh[convexnum] or {}
					for _, v in pairs (convextab) do
						table.insert(scaledmesh[convexnum], v * self.PhysObjScales[i] )
					end
				end
				physent:PhysicsInitMultiConvex(scaledmesh)
				--[[if !physent:GetPhysicsObject():IsValid() then  //the physobj can fail to generate if the mesh is really small, so if that happens use a backup mesh
					physent:PhysicsInitMultiConvex({{
						Vector(0.75, 0.75, 0.75), Vector(-0.75, 0.75, 0.75),
						Vector(0.75, -0.75, 0.75), Vector(-0.75, -0.75, 0.75),
						Vector(0.75, 0.75, -0.75), Vector(-0.75, 0.75, -0.75),
						Vector(0.75, -0.75, -0.75), Vector(-0.75, -0.75, -0.75),
						//Vector(1, 1, 1), Vector(-1, 1, 1),
						//Vector(1, -1, 1), Vector(-1, -1, 1),
						//Vector(1, 1, -1), Vector(-1, 1, -1),
						//Vector(1, -1, -1), Vector(-1, -1, -1),
					}})
					physent:SetCollisionGroup(COLLISION_GROUP_NONE)
				end]]
				physent:EnableCustomCollisions(true)
				physent:SetMoveType(MOVETYPE_VPHYSICS)
				physent:SetSolid(SOLID_VPHYSICS)
				local physobj = physent:GetPhysicsObject()
				if !physobj:IsValid() then
					//the backup mesh idea doesn't work very well, presumably because the mesh's center of gravity isn't in the right place, so just remove the entity
					PhysObjErrors[i] = i .. ": " .. self.ModelInfo.Solids[i]["name"] .. " failed to generate. This is usually because its collision mesh was too small or too thin for the engine to handle - you might have to increase its size a bit, or make the differences between the X, Y and Z scales less extreme."
					physent:Remove()
					continue
				end

				physobj:SetMass( self.ModelInfo.Solids[i]["mass"] * self.PhysObjScales[i].x * self.PhysObjScales[i].y * self.PhysObjScales[i].z )
				physobj:SetMaterial( self.ModelInfo.Solids[i]["surfaceprop"] or "" )				
				physobj:SetDamping( self.ModelInfo.Solids[i]["damping"], self.ModelInfo.Solids[i]["rotdamping"] )
				local inertia = self.ModelInfo.Solids[i]["inertia"]
				if inertia > 0 then physobj:SetInertia( physobj:GetInertia() * Vector(inertia,inertia,inertia) ) end

				physobj:Wake()

				self:DeleteOnRemove(physent)
				physent:DeleteOnRemove(self)
				self.PhysObjs[i] = physobj
				self.PhysObjEnts[i] = physent
			end

		end
		//Error handling for physobj creation
		if self.ErrorRecipient and table.Count(PhysObjErrors) > 0 then
			//Print detailed errors in the console explaining which physobjs failed to generate and why
			MsgN("RAGDOLL RESIZER:")
			MsgN(tostring(self) .. " (" .. string.GetFileFromFilename(self:GetModel()) .. ") :")
			for k, v in pairs (PhysObjErrors) do
				MsgN(v)
			end
			if table.Count(self.PhysObjEnts) == 0 then
				MsgN(tostring(self) .. " (" .. string.GetFileFromFilename(self:GetModel()) .. "didn't generate any physobjs, removing...")
				PhysObjErrors = {} //use an error count of 0 as a special case when networking (see below) to show a different message when no physobjs generate at all
			end
			MsgN("")

			//Tell the client that spawned the ragdoll to show a notification on the HUD letting the player about the error and directing them to the console
			net.Start( "ResizedRagdoll_FailedToGenerate_SendToCl" )
				net.WriteInt(table.Count(PhysObjErrors), 11)
			net.Send(self.ErrorRecipient)

			//If we couldn't generate s single physobj, then remove the entity
			if table.Count(self.PhysObjEnts) == 0 then
				self:Remove() 
				return 
			end
		end
		self.ErrorRecipient = nil //don't send the notification again if the player dupes/saves the ragdoll, once is enough


		//Apply ragdoll constraints
		if self.ModelInfo.Constraints then

			//self.ResizedRagdollConstraints = {}
			self.ConstraintSystem = ents.Create("phys_constraintsystem")
			self.ConstraintSystem:SetKeyValue( "additionaliterations", GetConVarNumber( "gmod_physiterations" ) )
			self.ConstraintSystem:SetName("constraintsystem_" .. self:EntIndex())
			self.ConstraintSystem:Spawn()
			self.ConstraintSystem:Activate()
			self:DeleteOnRemove(self.ConstraintSystem)
			SetPhysConstraintSystem(self.ConstraintSystem)

			for i, constrainttab in pairs (self.ModelInfo.Constraints) do

				local parentent = self.PhysObjEnts[ constrainttab["parent"] ]
				local childent = self.PhysObjEnts[ constrainttab["child"] ]
				local parentphys = self.PhysObjs[ constrainttab["parent"] ]
				local childphys = self.PhysObjs[ constrainttab["child"] ]
				if !IsValid(parentent) or !IsValid(childent) or !parentphys:IsValid() or !childphys:IsValid() then continue end
	
				local Constraint = ents.Create("phys_ragdollconstraint")
				Constraint:SetPos(childphys:GetPos())
				Constraint:SetAngles(parentphys:GetAngles())

				local mins = Vector( constrainttab["xmin"], constrainttab["ymin"], constrainttab["zmin"] )
				local maxs = Vector( constrainttab["xmax"], constrainttab["ymax"], constrainttab["zmax"] )
				local _, offsetang = WorldToLocal(childent:GetPos(), childent:GetAngles(), parentent:GetPos(), parentent:GetAngles())
				mins:Rotate(offsetang)
				maxs:Rotate(offsetang)
				Constraint:SetKeyValue( "xmin", math.min(mins.x,maxs.x) )
				Constraint:SetKeyValue( "xmax", math.max(mins.x,maxs.x) )
				Constraint:SetKeyValue( "ymin", math.min(mins.y,maxs.y) )
				Constraint:SetKeyValue( "ymax", math.max(mins.y,maxs.y) )
				Constraint:SetKeyValue( "zmin", math.min(mins.z,maxs.z) )
				Constraint:SetKeyValue( "zmax", math.max(mins.z,maxs.z) )

				//TODO: Find a better way to handle friction; these values don't rotate well and averaging them isn't much better. 
				//For now, I guess we'll just settle for ultra-floppy frictionless ragdolls.
				--[[local friction = Vector( constrainttab["xfriction"], constrainttab["yfriction"], constrainttab["zfriction"] )
				friction:Rotate(offsetang)
				Constraint:SetKeyValue( "xfriction", math.Clamp(friction.x, 0, friction.x) )
				Constraint:SetKeyValue( "yfriction", math.Clamp(friction.y, 0, friction.y) )
				Constraint:SetKeyValue( "zfriction", math.Clamp(friction.z, 0, friction.z) )]]
				--[[local avgfriction = ( constrainttab["xfriction"] + constrainttab["yfriction"] + constrainttab["zfriction"] ) / 3
				Constraint:SetKeyValue( "xfriction", avgfriction )
				Constraint:SetKeyValue( "yfriction", avgfriction )
				Constraint:SetKeyValue( "zfriction", avgfriction )]]

				Constraint:SetKeyValue( "spawnflags", 1 )  //nocollide
				Constraint:SetKeyValue( "constraintsystem", "constraintsystem_" .. self:EntIndex() ) 
				Constraint:SetPhysConstraintObjects( parentphys, childphys )
				Constraint:Spawn()
				Constraint:Activate()
				self:DeleteOnRemove(Constraint)
				//self.ResizedRagdollConstraints[i] = Constraint

			end

			SetPhysConstraintSystem(NULL)
		end


		//Apply collision rules by adding logic_collision_pairs for all physobj pairs we don't want to collide
		local RagdollCollisions = {}
		local function RagdollCollisionPair(phys1,phys2)
			if !IsValid(phys1) or !IsValid(phys2) or phys1 == phys2 then return end
			for _, tab in pairs (RagdollCollisions) do
				//If we've already made a collision pair between these two physobjs then stop here
				if (tab.Phys1 == phys1 and tab.Phys2 == phys2) or (tab.Phys2 == phys1 and tab.Phys1 == phys2) then return end
			end

			local Constraint = ents.Create("logic_collision_pair")
			Constraint:SetKeyValue( "startdisabled", 1 )
			Constraint:SetPhysConstraintObjects( phys1, phys2 )
			Constraint:Spawn()
			Constraint:Activate()
			self:DeleteOnRemove(Constraint)
			Constraint:Input( "DisableCollisions", nil, nil, nil )

			table.insert( RagdollCollisions, {["Phys1"] = phys1, ["Phys2"] = phys2} )
		end

		if self.ModelInfo.SelfCollisions and self.ModelInfo.SelfCollisions == 0 then
			//If selfcollisions == 0, then none of the physobjs should collide with each other
			for physnum1 = 0, table.Count(self.ModelInfo.Solids) - 1 do
				for physnum2 = 0, table.Count(self.ModelInfo.Solids) - 1 do
					RagdollCollisionPair(self.PhysObjs[physnum1], self.PhysObjs[physnum2])
				end
			end
		elseif self.ModelInfo.CollisionPairs then
			//If collisionpairs are present, then only those pairs should collide with each other
			for physnum1 = 0, table.Count(self.ModelInfo.Solids) - 1 do
				for physnum2 = 0, table.Count(self.ModelInfo.Solids) - 1 do
					local shouldcollide = false
					for _, colpair in pairs (self.ModelInfo.CollisionPairs) do
						if (colpair[1] == physnum1 and colpair[2] == physnum2) or (colpair[2] == physnum1 and colpair[1] == physnum2) then
							shouldcollide = true
						end
					end
					if !shouldcollide then RagdollCollisionPair(self.PhysObjs[physnum1], self.PhysObjs[physnum2]) end
				end
			end
		end


		//Run the PostInitializeFunction to move the physobjs into place
		if self.PostInitializeFunction then self.PostInitializeFunction() end
		self.DoneGeneratingPhysObjs = true
		return

	end


	self:SetLOD(0)
	self:SetupBones()
	self:InvalidateBoneCache()
	//self:DestroyShadow()

	self.LastBuildBonePositionsTime = 0
	self.SavedBoneMatrices = {}
	self:AddCallback("BuildBonePositions", self.BuildBonePositions)

end

if CLIENT then

	function ENT:BuildBonePositions(bonecount)

		if !self or self == NULL then return end
		if !self.PhysBones then return end

		//This function is expensive, so make sure we aren't running it more often than we need to
		if self.LastBuildBonePositionsTime == CurTime() then
			for i = 0, bonecount - 1 do
				if self.SavedBoneMatrices[i] and self:GetBoneName(i) != "__INVALIDBONE__" then
					self:SetBoneMatrix(i, self.SavedBoneMatrices[i])
				end
			end
			return
		else
			self.LastBuildBonePositionsTime = CurTime()
		end


		//Create a table of bone offsets for bones to use if they're not following a physobj
		if !self.BoneOffsets then
			//Grab the bone matrices from a clientside model instead - if we use ourselves, any bone manips we already have will be applied to the 
			//matrices, making the altered bones the new default (and then the manips will be applied again on top of them, basically "doubling" the manips)
			if !self.csmodel then
				//NOTE: This used ClientsideModel before, but users reported this causing crashes with very specific models (lordaardvark dazv5 overwatch pack h ttps://mega.nz/file/1vBjUQ6D#Yj72iK7eKAkIrnbwTVp66CEgu01nQ6wLNMFXoG-fvIw). This is clearly a much deeper issue, since this same function with the same models also crashes in other contexts (like rendering spawnicons, which the model author knew about and included a workaround for), but until it's fixed a workaround like this is necessary.
				self.csmodel = ents.CreateClientProp()
				self.csmodel:SetModel(self:GetModel())
				//self.csmodel = ClientsideModel(self:GetModel(),RENDERGROUP_TRANSLUCENT)
				self.csmodel:SetPos(self:GetPos())
				self.csmodel:SetAngles(self:GetAngles())
				self.csmodel:SetMaterial("null")  //invisible texture, so players don't see the csmodel for a split second while we're generating the table
				self.csmodel:SetLOD(0)
			end
			self.csmodel:DrawModel()
			self.csmodel:SetupBones()
			self.csmodel:InvalidateBoneCache()
			if self.csmodel and self.csmodel:GetBoneMatrix(0) == nil and self.csmodel:GetBoneMatrix(bonecount - 1) == nil then return end //the csmodel might need a frame or so to start returning the matrices; on some models like office workers from Black Mesa Character Expansion (https://steamcommunity.com/sharedfiles/filedetails/?id=2082334251), this always returns nil for the root bone but still works for the others, so make sure we check more than one bone

			local boneoffsets = {}
			for i = 0, bonecount - 1 do
				local newentry = {
					posoffset = Vector(0,0,0),
					angoffset = Angle(0,0,0),
				}
				local parentboneid = self.csmodel:GetBoneParent(i)
				if parentboneid and parentboneid != -1 then
					local parentmatr = self.csmodel:GetBoneMatrix(parentboneid)
					local ourmatr = self.csmodel:GetBoneMatrix(i)
					if ourmatr == nil then return end
					newentry["posoffset"], newentry["angoffset"] = WorldToLocal(ourmatr:GetTranslation(), ourmatr:GetAngles(), parentmatr:GetTranslation(), parentmatr:GetAngles())
				elseif i == 0 then
					local ourmatr = self.csmodel:GetBoneMatrix(i)
					if ourmatr != nil then
						newentry["posoffset"], newentry["angoffset"] = WorldToLocal(ourmatr:GetTranslation(), ourmatr:GetAngles(), self:GetPos(), self:GetAngles())
					end
				end
				if !newentry["posoffset"] then
					newentry["posoffset"] = Vector(0,0,0)
					newentry["angoffset"] = Angle(0,0,0)
				end
				table.insert(boneoffsets, i, newentry)
			end
			self.BoneOffsets = boneoffsets

			local physboneoffsets = {}
			for i = 0, bonecount - 1 do
				if self.PhysBones[i] and self.PhysBones[i].parentid != -1 then
					local parentmatr = self.csmodel:GetBoneMatrix(self.PhysBones[i].parentid)
					local ourmatr = self.csmodel:GetBoneMatrix(i)
					if ourmatr != nil then
						//we don't need an angle offset for these ones
						local pos = WorldToLocal(ourmatr:GetTranslation(), ourmatr:GetAngles(), parentmatr:GetTranslation(), parentmatr:GetAngles())
						table.insert(physboneoffsets, i, pos)
					end
				end
			end
			self.PhysBoneOffsets = physboneoffsets

			//We'll remove the clientside model in our Think hook, because doing it here can cause a crash (multiple BuildBonePositions calls trying to remove it simultaneously, maybe?)
			self.csmodeltoremove = self.csmodel
			self.csmodel = nil
		end


		for i = 0, bonecount - 1 do

			local matr = nil
			//local dostretch = true //test

			local parentmatr = nil
			local parentboneid = self:GetBoneParent(i)
			if parentboneid and parentboneid != -1 then
				parentmatr = self:GetBoneMatrix(parentboneid)
			else
				parentmatr = Matrix()
				parentmatr:SetTranslation(self:GetPos())
				parentmatr:SetAngles(self:GetAngles())
			end
			if parentmatr then
				parentmatr:Translate(self.BoneOffsets[i]["posoffset"])
				parentmatr:Translate(self:GetManipulateBonePosition(i))
				parentmatr:Rotate(self.BoneOffsets[i]["angoffset"])
				parentmatr:Rotate(self:GetManipulateBoneAngles(i))
			end

			if self.PhysBones[i] and IsValid(self.PhysBones[i].entity) then
				//Follow the physics object entity, but use the position offset from our parent physobj if we have one so that the ragdoll never looks "stretched"
				matr = Matrix()
				local physparentmatr = nil
				if self.PhysBoneOffsets[i] then
					physparentmatr = self:GetBoneMatrix(self.PhysBones[i].parentid)
				end
				if physparentmatr and !self:GetStretch() then
					physparentmatr:Translate(self.PhysBoneOffsets[i])
					matr:SetTranslation(physparentmatr:GetTranslation())
				else
					matr:SetTranslation(self.PhysBones[i].entity:GetPos())
				end
				matr:SetAngles(self.PhysBones[i].entity:GetAngles())
				matr:Scale( self.PhysBones[i].scalevec )
			else
				//Follow our parent bone
				if parentmatr then matr = parentmatr end
			end


			if matr then
				if self:GetBoneName(i) != "__INVALIDBONE__" then
					self:SetBoneMatrix(i,matr)
					self.SavedBoneMatrices[i] = matr
				end

				//Note: Jigglebones currently don't work because their procedurally generated matrix is replaced with the one we're giving them here.
				//We can detect jigglebones and do things to them specifically with self:BoneHasFlag(i,BONE_ALWAYS_PROCEDURAL), but there doesn't seem to be an easy way
				//to keep everything working (bone parenting, etc.) while still allowing the bones to jiggle.
			end

		end

	end

end




//Networking crap - 
//Step 1: If we're the client and we don't have a physbones table, request it from the server.
//Step 2: If we're the server and we receive a request, send a physbones table.
//Step 3: If we're the client and we receive a physbones table, use it.

//ResizedRagdoll_PhysBonesTable_GetFromSv structure:
//	Entity: Entity that needs a PhysBones table

//ResizedRagdoll_PhysBonesTable_SendToCl structure:
//	Entity: Entity that needs a PhysBones table
//
//	Int(11): Number of table entries
//	FOR EACH ENTRY:
//		Int(11): Key for this entry (bone index)
//
//		Entity: Physobj entity
//		Vector: Physobj scale
//		Int(11): Parent physobj's bone index

//ResizedRagdoll_FailedToGenerate_SendToCl structure:
//	Int(11): Number of physobjs that failed to generate (or 0 if none generated)

if SERVER then 

	util.AddNetworkString("ResizedRagdoll_PhysBonesTable_GetFromSv")
	util.AddNetworkString("ResizedRagdoll_PhysBonesTable_SendToCl")
	util.AddNetworkString("ResizedRagdoll_FailedToGenerate_SendToCl")


	//If we received a request for a physbones table, then send it to the client
	net.Receive("ResizedRagdoll_PhysBonesTable_GetFromSv", function(_, ply)
		local ent = net.ReadEntity()
		if !IsValid(ent) then return end
		if !ent.DoneGeneratingPhysObjs then return end

		net.Start( "ResizedRagdoll_PhysBonesTable_SendToCl" )
			net.WriteEntity(ent)

			net.WriteInt(table.Count(ent.PhysObjEnts), 11)
			for k, ent2 in pairs (ent.PhysObjEnts) do
				net.WriteInt(ent:TranslatePhysBoneToBone(k), 11)

				net.WriteEntity(ent2)
				net.WriteVector(ent.PhysObjScales[k])

				local parentname = ent.ModelInfo.Solids[k]["parent"]
				local parentid = nil
				if parentname and parentname != ent.ModelInfo.Solids[k]["name"] then parentid = ent:LookupBone(parentname) end
				net.WriteInt(parentid or -1, 11)
				net.WriteInt(k, 11)
			end
		net.Send(ply)
	end)

end

if CLIENT then

	//If we received a physbones table from the server, then use it
	net.Receive("ResizedRagdoll_PhysBonesTable_SendToCl", function()
		local ent = net.ReadEntity()
		if !IsValid(ent) then return end
		if ent.PhysBones then return end

		//Store the physbones table - this table has a different format than anything used serverside, for ease of use with the BuildBonePositions callback
		local count = net.ReadInt(11)
		local tab = {}
		for i = 1, count do
			local key = net.ReadInt(11)

			tab[key] = {
				["entity"] = net.ReadEntity(),
				["scalevec"] = net.ReadVector(),
				["parentid"] = net.ReadInt(11),
				["physboneid"] = net.ReadInt(11),
			}
		end
		ent.PhysBones = tab

		//Create clientside physobjs so that clientside traces can hit them (these are managed by the physobj entities)
		local csrag = ClientsideRagdoll(ent:GetModel())
		for i, tab in pairs (ent.PhysBones) do
			//TODO: entity can turn out to be invalid in demo recordings; resetting the table and trying again just returns it as invalid /again/ the next time. repeatedly, so this doesn't work.
			//what causes this to happen in the first place? ent spawns inside a wall or something and doesn't get networked?
			--[[if !IsValid(tab.entity) then
				MsgN(ent:GetModel(), " bad ent, trying again")
				ent.PhysBones = nil
				return
			end]]
			local phys = csrag:GetPhysicsObjectNum(tab.physboneid)
			if IsValid(phys) and IsValid(tab.entity) then
				local convexes = phys:GetMeshConvexes()
				local mesh = {}
				for convexnum, convextab in pairs (convexes) do
					mesh[convexnum] = mesh[convexnum] or {}
					for _, v in pairs (convextab) do
						table.insert(mesh[convexnum], v.pos * tab.scalevec)
					end
				end
				tab.entity:PhysicsInitMultiConvex(mesh)

				local phys2 = tab.entity:GetPhysicsObject()
				if IsValid(phys2) then
					phys2:SetMaterial(phys:GetMaterial())

					phys2:SetPos(tab.entity:GetPos())
					phys2:SetAngles(tab.entity:GetAngles())
					phys2:EnableMotion(false)
					phys2:Sleep() //the clientside physobj likes to break things unless it's asleep

					tab.entity:SetRenderBounds( tab.entity:GetCollisionBounds() )
				end

				tab.entity.RagdollParent = ent
				tab.entity.PhysBoneNum = tab.physboneid
			end
		end
		csrag:Remove()
	end)


	//If we received an error message from the server telling us that physobjs failed to generate, then show a notification on the HUD
	net.Receive("ResizedRagdoll_FailedToGenerate_SendToCl", function()
		local message = ""
		local count = net.ReadInt(11)
		if count == 0 then
			message = "All physics objects failed to generate - check console for details"
		elseif count == 1 then
			message = "1 physics object failed to generate - check console for details"
		else
			message = count .. " physics objects failed to generate - check console for details"
		end

		GAMEMODE:AddNotify(message, NOTIFY_ERROR, 5)
		surface.PlaySound("buttons/button11.wav")
	end)


	function ENT:Think()

		//Bandaid fix for demo recording and playback - oh boy, this one's a doozy. This only applies to resized ragdolls spawned BEFORE recording a demo - they don't seem to have
		//any problems if spawned during a demo instead.
		//
		//This issue is two-pronged - first off, when demo recording begins, some clientside information is lost (why?). The prop_resizedragdoll_physparent loses its LOD and callback
		//set in Initialize, so we need to set both of those again, and all the prop_resizedragdoll_physobjs lose their clientside physics objects, so we need to recreate them in 
		//that entity's Think function.
		//These, or at least the callback, don't seem to be lost until a few frames into recording, so we have to manually check for them instead of engine.IsRecordingDemo() alone.
		//
		//Second, when the demo is played back, any clientside values set on the entity BEFORE the recording was started don't seem to exist, and serverside lua doesn't run at all - 
		//any changes made to clientside values by server activity like net messages are part of the demo recording, not done by serverside lua. This has a lot of bad implications
		//for addons not made with this behavior in mind, but here, it means that self.PhysBones wasn't recorded in the demo because it was set before recording began. We set it
		//back to nil here while we're recording so that the server sends us a new one, which WILL be recorded in the demo.
		if engine.IsRecordingDemo() and #self:GetCallbacks("BuildBonePositions") == 0 then
			self:SetLOD(0)
			self:AddCallback("BuildBonePositions", self.BuildBonePositions)
			self.PhysBones = nil
		end

		//If we don't have a physbones table then request it from the server
		if !self.PhysBones then
			net.Start( "ResizedRagdoll_PhysBonesTable_GetFromSv" )
				net.WriteEntity(self)
			net.SendToServer()

			self:NextThink(CurTime())
			return
		end

		if !self.RagdollBoundsFresh then self:GenerateRagdollBounds() end

		//Set the render bounds
		self:SetRenderBounds(self.RagdollBoundsMin, self.RagdollBoundsMax)
		self:MarkShadowAsDirty()

		//We can't remove the clientside model inside the BuildBonePositions callback, or else it'll cause a crash for some reason - do it here instead
		if self.csmodeltoremove then
			self.csmodeltoremove:Remove()
			self.csmodeltoremove = nil
		end

	end




	local ResizedRagdoll_IsSkyboxDrawing = false

	hook.Add("PreDrawSkyBox", "ResizedRagdoll_IsSkyboxDrawing_Pre", function()
		ResizedRagdoll_IsSkyboxDrawing = true
	end)

	hook.Add("PostDrawSkyBox", "ResizedRagdoll_IsSkyboxDrawing_Post", function()
		ResizedRagdoll_IsSkyboxDrawing = false
	end)

	function ENT:Draw(flag)

		//try to prevent this from being rendered additional times if it has a child with EF_BONEMERGE; TODO: i can't find any situation where this breaks anything, but it still feels like it could.
		if flag == 0 then
			return
		end

		//Don't draw in the 3D skybox if our renderbounds are clipping into it but we're not actually in there
		//(common problem for ents with big renderbounds on gm_flatgrass, where the 3D skybox area is right under the floor)
		if ResizedRagdoll_IsSkyboxDrawing and !self:GetNWBool("IsInSkybox") then return end
		//TODO: Fix opposite condition where ent renders in the world from inside the 3D skybox area (i.e. gm_construct) - we can't just do the opposite of this because
		//we still want the ent to render in the world if the player is also in the 3D skybox area with them, but we can't detect if the player is in that area clisntside

		if self.PhysBones then
			self:DrawModel()
		end

	end
	
	//function ENT:DrawTranslucent()
	//
	//	self:Draw()
	//
	//end

end

function ENT:GenerateRagdollBounds()

	if !(self.PhysObjEnts or self.PhysBones) then return end

	local pos = self:GetPos()
	local mins, maxs = pos, pos
	if !self.PhysObjEnts and self.PhysBones then  //the table structure's a bit different on the server and on the client, so just use whichever one we've got
		for _, v in pairs (self.PhysBones) do
			if IsValid(v.entity) and IsValid(v.entity:GetPhysicsObject()) then
				local phys = v.entity:GetPhysicsObject()

				local physpos, physang = phys:GetPos(), phys:GetAngles()
				local pmins, pmaxs = phys:GetAABB()
				local vects = {
					pmins, Vector(pmaxs.x, pmins.y, pmins.z),
					Vector(pmins.x, pmaxs.y, pmins.z), Vector(pmaxs.x, pmaxs.y, pmins.z),
					Vector(pmins.x, pmins.y, pmaxs.z), Vector(pmaxs.x, pmins.y, pmaxs.z),
					Vector(pmins.x, pmaxs.y, pmaxs.z), pmaxs,
				}
				for i = 1, #vects do
					local wspos = LocalToWorld(vects[i], Angle(0,0,0), physpos, physang)
					vects[i] = wspos
				end
				mins = Vector( math.min(vects[1].x, vects[2].x, vects[3].x, vects[4].x, 
						vects[5].x, vects[6].x, vects[7].x, vects[8].x, mins.x),
						math.min(vects[1].y, vects[2].y, vects[3].y, vects[4].y, 
						vects[5].y, vects[6].y, vects[7].y, vects[8].y, mins.y),
						math.min(vects[1].z, vects[2].z, vects[3].z, vects[4].z, 
						vects[5].z, vects[6].z, vects[7].z, vects[8].z, mins.z) )
				maxs = Vector( math.max(vects[1].x, vects[2].x, vects[3].x, vects[4].x, 
						vects[5].x, vects[6].x, vects[7].x, vects[8].x, maxs.x),
						math.max(vects[1].y, vects[2].y, vects[3].y, vects[4].y, 
						vects[5].y, vects[6].y, vects[7].y, vects[8].y, maxs.y),
						math.max(vects[1].z, vects[2].z, vects[3].z, vects[4].z, 
						vects[5].z, vects[6].z, vects[7].z, vects[8].z, maxs.z) )
			end
		end
	else
		for _, phys in pairs (self.PhysObjs) do
			if IsValid(phys) then
				local physpos, physang = phys:GetPos(), phys:GetAngles()
				local pmins, pmaxs = phys:GetAABB()
				local vects = {
					pmins, Vector(pmaxs.x, pmins.y, pmins.z),
					Vector(pmins.x, pmaxs.y, pmins.z), Vector(pmaxs.x, pmaxs.y, pmins.z),
					Vector(pmins.x, pmins.y, pmaxs.z), Vector(pmaxs.x, pmins.y, pmaxs.z),
					Vector(pmins.x, pmaxs.y, pmaxs.z), pmaxs,
				}
				for i = 1, #vects do
					local wspos = LocalToWorld(vects[i], Angle(0,0,0), physpos, physang)
					vects[i] = wspos
				end
				mins = Vector( math.min(vects[1].x, vects[2].x, vects[3].x, vects[4].x, 
						vects[5].x, vects[6].x, vects[7].x, vects[8].x, mins.x),
						math.min(vects[1].y, vects[2].y, vects[3].y, vects[4].y, 
						vects[5].y, vects[6].y, vects[7].y, vects[8].y, mins.y),
						math.min(vects[1].z, vects[2].z, vects[3].z, vects[4].z, 
						vects[5].z, vects[6].z, vects[7].z, vects[8].z, mins.z) )
				maxs = Vector( math.max(vects[1].x, vects[2].x, vects[3].x, vects[4].x, 
						vects[5].x, vects[6].x, vects[7].x, vects[8].x, maxs.x),
						math.max(vects[1].y, vects[2].y, vects[3].y, vects[4].y, 
						vects[5].y, vects[6].y, vects[7].y, vects[8].y, maxs.y),
						math.max(vects[1].z, vects[2].z, vects[3].z, vects[4].z, 
						vects[5].z, vects[6].z, vects[7].z, vects[8].z, maxs.z) )
			end
		end
	end

	self.RagdollBoundsMin = mins - pos
	self.RagdollBoundsMax = maxs - pos
	self.RagdollBoundsFresh = true

end

if SERVER then

	function ENT:Think()

		if !self.DoneGeneratingPhysObjs then return end
		self:SetPos( self.PhysObjEnts[0]:GetPos() )

		if !self.RagdollBoundsFresh then self:GenerateRagdollBounds() end
		self:SetCollisionBounds(self.RagdollBoundsMin, self.RagdollBoundsMax) //if we don't do this, the ragdoll stops rendering if its collision bounds end up entirely inside the world, like HL2 citizen heads are prone to doing https://steamcommunity.com/sharedfiles/filedetails/?id=904420753

		if self:IsFlagSet(FL_DISSOLVING) and !self.DoneDissolveFloat then
			self.DoneDissolveFloat = true
			for _, ent in pairs (self.PhysObjEnts) do
				local phys = ent:GetPhysicsObject()
				if IsValid(phys) then
					phys:EnableGravity(false)
					phys:EnableDrag(true)
					phys:SetDragCoefficient(100) //rough estimate, can't actually find any valve code for this, but results in combine ball deaths that look approximately the same
				end
			end
		end

		//Detect whether we're in the 3D skybox, and network that to clients to use in the Draw function because they can't detect it themselves
		//(sky_camera ent is serverside only and ent:IsEFlagSet(EFL_IN_SKYBOX) always returns false)
		local skycamera = ents.FindByClass("sky_camera")
		if istable(skycamera) then skycamera = skycamera[1] end
		if IsValid(skycamera) then
			local inskybox = self:TestPVS(skycamera)
			if self:GetNWBool("IsInSkybox") != inskybox then
				self:SetNWBool("IsInSkybox", inskybox)
			end
		end

		self:NextThink(CurTime())

	end

	//Make sure the physobjs are the correct distance from each other, so the ragdoll doesn't "stretch" and/or end up with physobjs in different places than they visually appear to be
	function ENT:CorrectPhysObjLocations(doanyway)
		if !self.DoneGeneratingPhysObjs and !doanyway then return end

		for k, physent in pairs (self.PhysObjEnts) do
			local physobj = physent:GetPhysicsObject()
			if physent.PhysParent then
				local ourpos, _ = LocalToWorld(physent.PhysParentOffsetPos, Angle(0,0,0), physent.PhysParent:GetPos(), physent.PhysParent:GetAngles())
				local vel = physobj:GetVelocity()

				local mins, maxs = physobj:GetAABB()
				local size = maxs - mins
				local mult = 0.1

				//Give frozen physobjs a lot more leeway so they can stay in one spot
				if !doanyway and !physobj:IsMotionEnabled() and (!physent.StopMovingOnceFrozen or physent.StopMovingOnceFrozen == 0) then mult = 0.75 end
				
				if math.abs(physobj:GetPos():Distance(ourpos)) > ((size.x + size.y + size.z) / 3) * mult then
					physobj:SetPos(ourpos, true)
					physobj:SetVelocityInstantaneous(vel) //if we don't restore the velocity after moving the physobj then the ragdoll gets all floaty
				end

			end
		end

	end

end




duplicator.RegisterEntityClass( "prop_resizedragdoll_physparent", function( ply, data )
	local ent = ents.Create("prop_resizedragdoll_physparent")

	local OldBoneManip = data.BoneManip  //don't apply bone manips until after we've initialized the entity, otherwise it'll mess up the physbone offsets
	data.BoneManip = nil
	duplicator.DoGeneric(ent, data)

	//in multiplayer, physobj scale is clamped between 0.20 and 50; don't let them bypass this by loading an unclamped dupe from singleplayer
	if !game.SinglePlayer() then
		for num, scalevec in pairs (data.PhysObjScales) do
			data.PhysObjScales[num] = Vector( math.Clamp(scalevec.x, 0.20, 50), math.Clamp(scalevec.y, 0.20, 50), math.Clamp(scalevec.z, 0.20, 50) )
		end
	end
	ent.PhysObjScales = data.PhysObjScales
	//don't copy any of these values, they should be recreated from scratch when ent:Initialize() runs
	ent.PhysObjMeshes = nil //old versions of the addon carried this over, but that just meant that if the model was ever updated, the meshes would be out of date, especially since they potentially wouldn't match up with the new modelinfo
	ent.ModelInfo = nil
	ent.PhysObjPhysBoneIDs = nil
	ent.PhysObjs = nil
	ent.PhysObjEnts = nil
	ent.ConstraintSystem = nil
	//ent.ResizedRagdollConstraints = nil
	ent.DoneGeneratingPhysObjs = nil
	ent.PostInitializeFunction = nil
	ent.RagdollBoundsFresh = nil
	ent.RagdollBoundsMin = nil
	ent.RagdollBoundsMax = nil

	ent.PostInitializeFunction = function()
		if ( data.ColGroup ) then ent:SetCollisionGroup( data.ColGroup ) end
		duplicator.DoGenericPhysics(ent, ply, data)
		duplicator.DoBoneManipulator(ent, OldBoneManip)  //now it's safe to apply the bone manips
	end
	ent:Spawn()  //initialize the entity and have it create its physobjs

	return ent
end, "Data" )









































//FUNCTION REDIRECTS:
//Whenever something interacts with a resized ragdoll's parent ent or physobj ents, we need to trick the game into thinking it's just one entity with multiple physics objects, like a 
//regular ragdoll. This is mostly accomplished through a whole bunch of metatable stuff.

local meta = FindMetaTable("Entity")

//Physobj retrieval functions
local old_GetPhysicsObject = meta.GetPhysicsObject
if old_GetPhysicsObject then
	function meta.GetPhysicsObject(ent, ...)
		if isentity(ent) and IsValid(ent) and (ent:GetClass() == "prop_ragdoll" and ent.ClassOverride == "prop_resizedragdoll_physparent") and ent.PhysObjs then
			local physobj = ent.PhysObjs[0]
			//MsgN("overridden GetPhysicsObject: " .. tostring(physobj))
			if physobj then return physobj else return NULL end
		else
			return old_GetPhysicsObject(ent, ...)
		end
	end
end

local old_GetPhysicsObjectNum = meta.GetPhysicsObjectNum
if old_GetPhysicsObjectNum then
	function meta.GetPhysicsObjectNum(ent, num, ...)
		if isentity(ent) and IsValid(ent) and (ent:GetClass() == "prop_ragdoll" and ent.ClassOverride == "prop_resizedragdoll_physparent") and ent.PhysObjs then
			local physobj = ent.PhysObjs[num]
			//MsgN("overridden GetPhysicsObjectNum(" .. num .. "): " .. tostring(physobj))
			if physobj then return physobj else return ent.PhysObjs[0] end  //i really don't like this method, but some default gmod functions will error if we don't return a valid physobj here, and the ent probably shouldn't exist anyway if physobj 0 didn't generate
		else
			return old_GetPhysicsObjectNum(ent, num, ...)
		end
	end
end

local old_GetPhysicsObjectCount = meta.GetPhysicsObjectCount
if old_GetPhysicsObjectCount then
	function meta.GetPhysicsObjectCount(ent, ...)
		if isentity(ent) and IsValid(ent) and (ent:GetClass() == "prop_ragdoll" and ent.ClassOverride == "prop_resizedragdoll_physparent") and ent.PhysObjScales then
			//MsgN("overridden GetPhysicsObjectCount: " .. tostring(table.Count(ent.PhysObjScales)))
			return table.Count(ent.PhysObjScales)
		else
			return old_GetPhysicsObjectCount(ent, ...)
		end
	end
end




//GetMoveType - if we don't do this then most constraint tools won't work on us
local old_GetMoveType = meta.GetMoveType
if old_GetMoveType then
	function meta.GetMoveType(ent, ...)
		if isentity(ent) and IsValid(ent) and (ent:GetClass() == "prop_ragdoll" and ent.ClassOverride == "prop_resizedragdoll_physparent") then
			return MOVETYPE_VPHYSICS
		else
			return old_GetMoveType(ent, ...)
		end
	end
end

//SetCollisionGroup - necessary for the nocollide tool to work
local old_SetCollisionGroup = meta.SetCollisionGroup
if old_SetCollisionGroup then
	function meta.SetCollisionGroup(ent, group, ...)
		old_SetCollisionGroup(ent, group, ...)

		if isentity(ent) and IsValid(ent) and (ent:GetClass() == "prop_ragdoll" and ent.ClassOverride == "prop_resizedragdoll_physparent") then
			if ent.PhysObjEnts then
				for _, physobjent in pairs (ent.PhysObjEnts) do
					if IsValid(physobjent) then old_SetCollisionGroup(physobjent, group, ...) end
				end
			end
		end
	end
end

//GetClass - i should be ashamed of a solution this hacky; trick anything that interacts with us into thinking we're a prop_ragdoll 
//(we can still check if a prop_ragdoll is real or a prop_resizedragdoll_physparent by checking for ent.ClassOverride)
local old_GetClass = meta.GetClass
if old_GetClass then
	function meta.GetClass(ent, ...)
		local class = old_GetClass(ent, ...)

		if class == "prop_resizedragdoll_physparent" then
			return "prop_ragdoll"
		else
			return class
		end
	end
end

//TODO: unfinished; this will actually take a lot more work than i thought since we'll have to tell the clientside BuildBonePositions, the serverside CorrectPhysObjLocations,
//and maybe some other stuff that the bone is no longer parented; if we do this, don't forget to add EnableConstraints too!
//nothing actually uses this so it's super low priority
--[[//RemoveInternalConstraint
local old_RemoveInternalConstraint = meta.RemoveInternalConstraint
if old_RemoveInternalConstraint then
	function meta.RemoveInternalConstraint(ent, num, ...)
		if ent.ResizedRagdollConstraints then
			if num > 0 then
				local const = ent.ResizedRagdollConstraints[num]
				if IsValid(const) then
					const:Fire("Break")
				end
			else
				for i, const in pairs (ent.ResizedRagdollConstraints) do
					MsgN("heads")
					const:Fire("Break")
				end
			end
		end
		return old_RemoveInternalConstraint(ent, num, ...)
	end
end]]




//Traces - any trace that hits a physobj should be redirected to hit the parent entity instead
//timer.Simple(1, function() //attempted fix for other util.TraceLine detours breaking this one. makes Doors work but makes Seamless Portals worse because of how their implementation works.

local old_TraceLine = util.TraceLine
if old_TraceLine then
	function util.TraceLine(tracetab, ...)
		local trace = old_TraceLine(tracetab, ...)

		//If we've hit a resized ragdoll physobj, then redirect the trace so it thinks it's hit the parent instead
		if trace and isentity(trace.Entity) and IsValid(trace.Entity) and trace.Entity:GetClass() == "prop_resizedragdoll_physobj" then
			if trace.Entity.PhysBoneNum and trace.PhysicsBone then trace.PhysicsBone = trace.Entity.PhysBoneNum end
			if IsValid(trace.Entity.RagdollParent) then trace.Entity = trace.Entity.RagdollParent end
		end

		return trace
	end
end

//12-15-23 - also detour TraceHull because the toolgun has been updated to use this instead of TraceLine (keep TraceLine around for other stuff like properties)
local old_TraceHull = util.TraceHull
if old_TraceHull then
	function util.TraceHull(tracetab, ...)
		local trace = old_TraceHull(tracetab, ...)

		//If we've hit a resized ragdoll physobj, then redirect the trace so it thinks it's hit the parent instead
		if trace and isentity(trace.Entity) and IsValid(trace.Entity) and trace.Entity:GetClass() == "prop_resizedragdoll_physobj" then
			if trace.Entity.PhysBoneNum and trace.PhysicsBone then trace.PhysicsBone = trace.Entity.PhysBoneNum end
			if IsValid(trace.Entity.RagdollParent) then trace.Entity = trace.Entity.RagdollParent end
		end

		return trace
	end
end

//end)




//Physgun halo effects - using the hooks instead won't work for these, unfortunately, it either won't render the halo at all, or still render the halo around the physobj ent
local old_DrawPhysgunBeam = GAMEMODE.DrawPhysgunBeam
if old_DrawPhysgunBeam then
	function GAMEMODE.DrawPhysgunBeam(self, ply, weapon, bOn, target, boneid, pos, ...)
		if isentity(target) and IsValid(target) and target:GetClass() == "prop_resizedragdoll_physobj" then
			if IsValid(target.RagdollParent) then target = target.RagdollParent end
		end
		return old_DrawPhysgunBeam(self, ply, weapon, bOn, target, boneid, pos, ...)
	end
end

local old_PlayerFrozeObject = GAMEMODE.PlayerFrozeObject
if old_PlayerFrozeObject then
	function GAMEMODE.PlayerFrozeObject(self, ply, entity, physobject, ...)
		if isentity(entity) and IsValid(entity) and entity:GetClass() == "prop_resizedragdoll_physobj" then
			if IsValid(entity.RagdollParent) then entity = entity.RagdollParent end
		end
		return old_PlayerFrozeObject(self, ply, entity, physobject, ...)
	end
end

local old_PlayerUnfrozeObject = GAMEMODE.PlayerUnfrozeObject
if old_PlayerUnfrozeObject then
	function GAMEMODE.PlayerUnfrozeObject(self, ply, entity, physobject, ...)
		if isentity(entity) and IsValid(entity) and entity:GetClass() == "prop_resizedragdoll_physobj" then
			if IsValid(entity.RagdollParent) then entity = entity.RagdollParent end
		end
		return old_PlayerUnfrozeObject(self, ply, entity, physobject, ...)
	end
end




//Serverside eye posing fix - since BuildBonePositions only runs clientside, the server still thinks the bones and attachments are floating there above the entity in a reference pose. 
//This means when the Eye Poser tool uses ent:GetAttachment( eyeattachment ) serverside, it gets the wrong pos/ang for the eye attachment and sets the eye target to a pos relative to 
//the wrong spot, resulting in the ragdoll looking in the wrong direction. Here we'll override ent:GetAttachment() to make it return the "actual" pos/ang for the eye attachment.
if SERVER then
	local old_GetAttachment = meta.GetAttachment
	if old_GetAttachment then
		function meta.GetAttachment(ent, attachmentId, ...)
			if isentity(ent) and IsValid(ent) and (ent:GetClass() == "prop_ragdoll" and ent.ClassOverride == "prop_resizedragdoll_physparent") then
				local eyeattachment = ent:LookupAttachment("eyes")
				if eyeattachment != 0 and attachmentId == eyeattachment then
					//First, retrieve the bone that the eye attachment is attached to. Gmod doesn't have a function for this, so we'll just have to search for a head
                                        //bone by looking at the bones' names, and assume the eye attachment is attached to that one.
                                        //(this method is terrible and will probably break with weird custom models, but there's no alternative)
					local function FindHeadBoneName()
						//First try some common names
						local result = ent:LookupBone("bip_head") or ent:LookupBone("ValveBiped.BipO1_Head1") or ent:LookupBone("ValveBiped.head") or nil
						if result then return result end
						//Common names didn't return anything, so search for the word "head" in all the bone names
						for i = 0, ent:GetBoneCount() - 1 do
							if string.find(string.lower(ent:GetBoneName(i)), "head", 1, true) then return i end
						end
					end

					local headbone = FindHeadBoneName()
					if headbone then
						//We're going to be using the head bone's physobj later to figure out where the attachment is actually supposed to be, so just in case the
						//head bone is actually just a child of the bone that owns the physobj (like fingers are to a hand bone), use that bone instead.
						local _physbone = ent:TranslateBoneToPhysBone(headbone)
						if _physbone and _physbone != -1 then _physbone = ent:TranslatePhysBoneToBone(_physbone) end
						if _physbone and _physbone != -1 and _physbone != headbone then headbone = _physbone end

						//Second, get the attachment's pos/ang offset from the head bone.
						local _headbone_ref = {}
						local _matr = ent:GetBoneMatrix(headbone)
						if _matr then
							_headbone_ref.Pos = _matr:GetTranslation()
							_headbone_ref.Ang = _matr:GetAngles()
						else
							_headbone_ref.Pos, _headbone_ref.Ang = ent:GetBonePosition(headbone)
						end
						local _attach_ref = old_GetAttachment(ent, attachmentId, ...) or {Ang = Angle(0,0,0), Pos = Vector(0,0,0)}
						local attach_offset_pos, attach_offset_ang = WorldToLocal(_attach_ref.Pos, _attach_ref.Ang, _headbone_ref.Pos, _headbone_ref.Ang)

						//Lastly, get the position of the head physobj and apply the offset(s) to it to get the "real" location of the eye attachment.
						local physnum = ent:TranslateBoneToPhysBone(headbone)
						local physent = ent.PhysObjs[physnum]
						if physent then  //sadly this won't work if the head physobj failed to generate (TODO?: add handling to use some parent physobj instead?)
							local physpos, physang = physent:GetPos(), physent:GetAngles()
							physpos, physang = LocalToWorld(attach_offset_pos * ent.PhysObjScales[physnum], attach_offset_ang, physpos, physang)

							return {Ang = physang, Pos = physpos}
						end
					end
				end
			end

			return old_GetAttachment(ent, attachmentId, ...)
		end
	end
end