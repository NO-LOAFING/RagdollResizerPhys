TOOL.Category = "Construction"
TOOL.Name = "Ragdoll Resizer"
TOOL.Command = nil
TOOL.ConfigName = "" 

TOOL.ClientConVar["drawhalo"] = "1"
TOOL.ClientConVar["frozen"] = "0"
TOOL.ClientConVar["debug"] = "0"  //console only, prints debug messages when a new entity is selected and the cpanel is populated
TOOL.ClientConVar["pose"] = "1"

TOOL.Information = {
	{name = "right0", stage = 0, icon = "gui/rmb.png"},
	{name = "info1", stage = 1, icon = "gui/info.png"},
	{name = "left1", stage = 1, icon = "gui/lmb.png"},
	{name = "right1", stage = 1, icon = "gui/rmb.png"},
}

if CLIENT then
	language.Add("tool.ragdollresizerphys.name", "Ragdoll Resizer")
	language.Add("tool.ragdollresizerphys.desc", "Change the size of ragdolls")
	//language.Add("tool.ragdollresizerphys.help", "Can resize entire ragdolls, or set the scale of individual parts.")

	language.Add("tool.ragdollresizerphys.right0", "Select a ragdoll to resize")
	language.Add("tool.ragdollresizerphys.info1", "Use the context menu to set the ragdoll's size")
	language.Add("tool.ragdollresizerphys.left1", "Apply changes and resize the ragdoll")
	language.Add("tool.ragdollresizerphys.right1", "Cancel and deselect the ragdoll, or select another ragdoll to resize")

	language.Add("undone_ResizedRagdollPhys", "Undone Resized Ragdoll")
end




function TOOL:LeftClick(trace)

	local oldrag = self:GetWeapon():GetNWEntity("RagdollResizer_CurEntity")
	if !IsValid(oldrag) or (oldrag:GetClass() != "prop_ragdoll" and oldrag:GetClass() != "prop_resizedragdoll_physparent") then return false end
	if CLIENT then return true end
	local ply = self:GetOwner()
	local spawnfrozen = self:GetClientNumber("frozen")


	local newrag = ents.Create("prop_resizedragdoll_physparent")

	newrag.ErrorRecipient = ply //if there's an error when creating the ragdoll, then it'll send a notification to this player

	if !self:GetWeapon().RagdollResizerScales then return end
	newrag.PhysObjScales = table.Copy(self:GetWeapon().RagdollResizerScales)

	newrag:SetModel(oldrag:GetModel())

	//set stretch mode
	newrag:SetStretch(self:GetWeapon():GetNWBool("RagdollResizer_Stretch"))


	//local lowestheight = oldrag:GetPos()
	//for i = 0, oldrag:GetPhysicsObjectCount() - 1 do
	//	local phys = oldrag:GetPhysicsObjectNum(i)
	//	if IsValid(phys) and phys:GetPos().z < lowestheight.z then lowestheight.z = phys:GetPos().z end
	//end
	//newrag:SetPos(lowestheight)
	newrag:SetPos(oldrag:GetPos())

	local oldragbonemanips = nil
	if oldrag:HasBoneManipulations() then
		oldragbonemanips = {}
	
		for i = 0, oldrag:GetBoneCount() do
			local t = {}
			
			local s = oldrag:GetManipulateBoneScale(i)
			local a = oldrag:GetManipulateBoneAngles(i)
			local p = oldrag:GetManipulateBonePosition(i)
			
			if s != Vector( 1, 1, 1 ) then t["s"] = s end
			if a != Angle( 0, 0, 0 ) then t["a"] = a end
			if p != Vector( 0, 0, 0 ) then t["p"] = p end
		
			if table.Count(t) > 0 then
				oldragbonemanips[i] = t
			end
		end
	end

	local oldragconsts = constraint.GetTable(oldrag)
	local pose = self:GetClientNumber("pose")

	//Do this stuff after the physics objects have been created
	newrag.PostInitializeFunction = function()
		//If enabled, move all physobjs to match the pose of the old ragdoll
		if pose == 1 then
			for i, physent in pairs (newrag.PhysObjEnts) do
				local oldphys = oldrag:GetPhysicsObjectNum(i)
				if oldphys:IsValid() then
					local phys = physent:GetPhysicsObject()
					phys:SetAngles(oldphys:GetAngles())
					phys:SetPos(oldphys:GetPos())
					physent:SetAngles(oldphys:GetAngles())
					physent:SetPos(oldphys:GetPos())
					phys:Wake()
					//Posed physobjs can have bad pos offsets sometimes, so keep correcting them
					physent.StopMovingOnceFrozen = 8 //do this even if stretchy, otherwise re-posing breaks entirely
				end
			end
			newrag:CorrectPhysObjLocations(true) //do this even if stretchy, otherwise re-posing breaks entirely
		end

		//Move all of the physobjs so that none of them are lower than the lowest point of the old ragdoll
		local lowestheight = nil
		for _, phys in pairs (newrag.PhysObjs) do
			if IsValid(phys) then
				if !lowestheight then
					lowestheight = phys:GetPos().z
				else
					if phys:GetPos().z < lowestheight then lowestheight = phys:GetPos().z end	
				end
			end
		end
		if lowestheight then
			local offset = oldrag:GetPos().z - lowestheight
			for i, phys in pairs (newrag.PhysObjs) do
				if IsValid(phys) then 
					phys:SetPos( phys:GetPos() + Vector(0,0,offset) )

					//If we're matching the pose of the old ragdoll, then freeze all physobjs that were also frozen on the old ragdoll
					local oldphys = oldrag:GetPhysicsObjectNum(i)
					if pose and oldphys:IsValid() then
						oldphys = !oldphys:IsMotionEnabled()
					end

					if spawnfrozen == 1 or oldphys then
						phys:EnableMotion(false)
						if ply then
							ply:AddFrozenPhysicsObject(nil, phys)  //the entity argument needs to be nil, or else it'll make a ton of halo effects and lag up the game
						end
					end
				end
			end
		end

		//Copy bonemanips - we can't do this until after the physobjs have been initialized or else it could mess up the bone positions
		if oldragbonemanips then duplicator.DoBoneManipulator(newrag, oldragbonemanips) end

		//Copy constraints - these also require the physobjs to exist for obvious reasons
		if oldragconsts then
			for k, const in pairs (oldragconsts) do
				if const.Entity then
					//If any of the values in the constraint table are oldrag, switch them over to newrag
					for key, val in pairs (const) do
						if val == oldrag then 
							const[key] = newrag 
						end
					end

					local entstab = {}

					//Also switch over any instances of oldrag to newrag inside the entity subtable
					for tabnum, tab in pairs (const.Entity) do
						if tab.Entity and tab.Entity == oldrag then 
							const.Entity[tabnum].Entity = newrag
							const.Entity[tabnum].Index = newrag:EntIndex()
						end
						entstab[const.Entity[tabnum].Index] = const.Entity[tabnum].Entity
					end

					//Now copy the constraint over to newrag
					duplicator.CreateConstraintFromTable(const, entstab)
				end
			end
		end
	end

	newrag:Spawn()  //Have newrag run its Initialize function and create its physobjs, and then run its PostInitializeFunction after that's done

	newrag:SetSkin(oldrag:GetSkin())
	//Copy bodygroups
	if oldrag:GetNumBodyGroups() then
		for i = 0, oldrag:GetNumBodyGroups() - 1 do
			newrag:SetBodygroup(i, oldrag:GetBodygroup(i)) 
		end
	end
	//Copy flexes
	if oldrag:HasFlexManipulatior() then
		newrag:SetFlexScale(oldrag:GetFlexScale())
		for i = 0, oldrag:GetFlexNum() - 1 do 
			newrag:SetFlexWeight(i, oldrag:GetFlexWeight(i)) 
		end
	end
	//Copy entity modifiers
	newrag.EntityMods = oldrag.EntityMods
	newrag.BoneMods = oldrag.BoneMods
	duplicator.ApplyEntityModifiers(ply, newrag)
	duplicator.ApplyBoneModifiers(ply, newrag)


	undo.Create("ResizedRagdollPhys")
		undo.SetPlayer(ply)
		undo.AddEntity(newrag)
	undo.Finish("Resized Ragdoll (" .. tostring(oldrag:GetModel()) .. ")")
	ply:AddCleanup("ragdolls", newrag)

	oldrag:Remove()
	return true	

end




function TOOL:RightClick(trace)

	if CLIENT then return true end

	if IsValid(trace.Entity) and (trace.Entity:GetClass() == "prop_ragdoll" or trace.Entity:GetClass() == "prop_resizedragdoll_physparent") then
		if CLIENT then return true end
		local modelinforaw = util.GetModelInfo(trace.Entity:GetModel())
		if modelinforaw then
			self:GetWeapon():SetNWEntity("RagdollResizer_CurEntity",trace.Entity)
			local stretch = (trace.Entity.GetStretch and trace.Entity:GetStretch())
			self:GetWeapon():SetNWBool("RagdollResizer_Stretch", stretch)
		else
			if IsUselessModel(trace.Entity:GetModel()) then
				//util.GetModelInfo will silently fail on ragdolls with a bad modelname (http://wiki.garrysmod.com/page/util/GetModelInfo), meaning we won't be able to 
				//resize them (example model from bug report: https://steamcommunity.com/sharedfiles/filedetails/?id=747597416), so don't select the ragdoll and instead 
				//send the player a notification telling them what the problem is
				MsgN("RAGDOLL RESIZER:")
				MsgN("The ragdoll \"" .. trace.Entity:GetModel() .. "\" can't be resized because we can't get its model info due to a bad file name.")
				MsgN("")
				MsgN("")
				MsgN("WHY DID THIS HAPPEN?:")
				MsgN("")
				MsgN("The ragdoll resizer uses a function called util.GetModelInfo() to create the resized ragdoll entity. This function gives us all the info we need about the ragdoll's different physics objects and how they're all connected together, meaning we can't create the new ragdoll without it.")
				MsgN("The problem is, util.GetModelInfo() will FAIL if the model name contains any of the following:")
				MsgN("_gesture")
				MsgN("_anim")
				MsgN( "_gst")
				MsgN("_pst")
				MsgN("_shd")
				MsgN("_ss")
				MsgN("_posture")
				MsgN("_anm")
				MsgN("ghostanim")
				MsgN("_paths")
				MsgN("_shared")
				MsgN("anim_")
				MsgN("gestures_")
				MsgN("shared_ragdoll_")
				MsgN("Usually, model files with these names are \"useless models\" that only exist to store animations for other models, and don't need to be spawned by themselves. They're automatically filtered out of the spawn menu and search bar, so you normally won't run into them.")
				MsgN("Unfortunately, with the thousands and THOUSANDS of custom models people create for Gmod, someone's bound to make one that has one of these phrases in its name even though it's a totally normal, legitimate model. This means it'll get caught in the \"useless model\" filter anyway and util.GetModelInfo() won't work on it.")
				MsgN("")
				MsgN("")
				MsgN("HOW CAN I FIX IT?:")
				MsgN("")
				MsgN("If you created this model, then you'll have to change the name of the file so it doesn't contain any of the phrases above.")
				MsgN("If you downloaded this model off the workshop, then you'll probably have to ask the creator to fix it. They might not want to, because changing the file name will break any old saves or dupes that were already using the model. Alternatively, if you know what you're doing, you might be able to decompile the addon and change the file name yourself.")
				MsgN("")
				MsgN("")
			else
				//util.GetModelInfo failed for some other reason, throw a different error
				MsgN("RAGDOLL RESIZER:")
				MsgN("The ragdoll \"" .. trace.Entity:GetModel() .. "\" can't be resized because we can't get its model info for an unknown reason.")
			end
			net.Start( "ResizedRagdoll_FailedModelInfo_SendToCl" )
			net.Send(self:GetOwner())
		end
		return true
	else
		if IsValid(self:GetWeapon():GetNWEntity("RagdollResizer_CurEntity")) then
			if SERVER then
				self:GetWeapon():SetNWEntity("RagdollResizer_CurEntity",NULL)
			end
			return true
		end
	end

end

//networking for util.GetModelInfo fail notification
if SERVER then
	util.AddNetworkString("ResizedRagdoll_FailedModelInfo_SendToCl")
else
	net.Receive("ResizedRagdoll_FailedModelInfo_SendToCl", function()
		GAMEMODE:AddNotify("Can't resize this model - check the console for details", NOTIFY_ERROR, 5)
		surface.PlaySound("buttons/button11.wav")
	end)
end




TOOL.CurEntity = NULL

function TOOL:Think()

	local debug = self:GetClientNumber("debug")  //if this is enabled then print debug messages related to entity selection and cpanel population
	local function DebugMsg(msg)
		if debug == 1 then MsgN("RAGDOLL RESIZER DEBUG: " .. msg) end
	end

	local ent = self:GetWeapon():GetNWEntity("RagdollResizer_CurEntity")

	if CLIENT then

		local panel = controlpanel.Get("ragdollresizerphys")
		if !panel or !panel.physobjlist then return end


		//Store a reference to our toolgun in the panel table so it can access and change our values
		if !panel.ToolgunObj or panel.ToolgunObj != self:GetWeapon() then panel.ToolgunObj = self:GetWeapon() end


		//Update the "ghost ragdoll" entity used to preview the scale changes. 

		if self.CurEntity != ent:EntIndex() then
			//If the selected entity has changed, then clear the ghost ragdoll so the function creates a new one
			self:RemoveGhostRagdoll()

			DebugMsg("TOOL:Think(): Selected entity index changed from " .. tostring(self.CurEntity) .. " to " .. tostring(ent:EntIndex()) .. " (" .. tostring(ent) .. ")")

			//Update the clientside RagdollResizerScales table
			if IsValid(ent) then
				//Create a new table
				self:GetWeapon().RagdollResizerScales = {}
				if ent.PhysBones then
					for k, v in pairs (ent.PhysBones) do
						self:GetWeapon().RagdollResizerScales[k] = v.scalevec
					end
				else
					for i = 0, GetPhysBoneCountAlternate(ent) - 1 do
						self:GetWeapon().RagdollResizerScales[ent:TranslatePhysBoneToBone(i)] = Vector(1,1,1)
					end
				end
			else
				//Remove the table
				self:GetWeapon().RagdollResizerScales = nil
			end
		end

		if IsValid(ent) then
			if !IsValid(self.GhostRagdoll) then
				DebugMsg("TOOL:Think(): Creating a new preview model (" .. tostring(ent:GetModel()) .. ")!")

				//Create the ghost ragdoll
				local model = ent:GetModel()
				util.PrecacheModel(model)
				self.GhostRagdoll = ents.CreateClientProp(model)
				if self.GhostRagdoll then
					self.GhostRagdoll:SetModel(model)
					self.GhostRagdoll:SetSkin(ent:GetSkin())
					self.GhostRagdoll:SetPos(ent:GetPos())
					self.GhostRagdoll:Spawn()
					self.GhostRagdoll:SetMoveType(MOVETYPE_NONE)
					self.GhostRagdoll:SetNotSolid(true)
					self.GhostRagdoll:SetRenderMode(RENDERMODE_TRANSALPHA)
					self.GhostRagdoll:SetColor(Color(255, 255, 255, 178)) //hl2 fastzombie model is invisible if alpha is any lower than 178, haven't run into this issue on any other models but better safe than sorry

					//Copy bodygroups
					if ent:GetNumBodyGroups() then
						for i = 0, ent:GetNumBodyGroups() - 1 do
							self.GhostRagdoll:SetBodygroup(i, ent:GetBodygroup(i))
						end
					end

					//there is no reason for the ghost ragdoll to not render
					self.GhostRagdoll:SetRenderBoundsWS(Vector(-99999999,-99999999,-99999999), Vector(99999999,99999999,99999999))

					self.GhostRagdoll:SetLOD(0)
					self.GhostRagdoll:SetupBones()
					self.GhostRagdoll:InvalidateBoneCache()

					self.GhostRagdoll.LastBuildBonePositionsTime = 0
					self.GhostRagdoll.SavedBoneMatrices = {}

					self.GhostRagdoll:AddCallback( "BuildBonePositions", function()

						local RagdollResizerScales = self:GetWeapon().RagdollResizerScales
						local pose = self:GetClientNumber("pose")
						local self = self.GhostRagdoll

						if !self or self == NULL then return end
						if !RagdollResizerScales then return end
						if !ent or ent == NULL then return end


						//This function is expensive, so make sure we aren't running it more often than we need to
						if self.LastBuildBonePositionsTime == CurTime() then
							for i = 0, self:GetBoneCount() - 1 do
								if self.SavedBoneMatrices[i] and self:GetBoneName(i) != "__INVALIDBONE__" then
									self:SetBoneMatrix(i, self.SavedBoneMatrices[i])
								end
							end
							return
						else
							self.LastBuildBonePositionsTime = CurTime()
						end


						if !self.BoneOffsets then
							//Grab the bone offsets from ourselves - since we don't have any bonemanips we don't have to worry about it retrieving the wrong values
							self:DrawModel()

							local boneoffsets = {}
							for i = 0, self:GetBoneCount() - 1 do
								boneoffsets[i] = {}

								local ourmatr = self:GetBoneMatrix(i)
								if ourmatr then
									local parentboneid = self:GetBoneParent(i)
									if parentboneid and parentboneid != -1 then
										local parentmatr = self:GetBoneMatrix(parentboneid)
										boneoffsets[i]["posoffset"], boneoffsets[i]["angoffset"] = WorldToLocal(ourmatr:GetTranslation(), ourmatr:GetAngles(), parentmatr:GetTranslation(), parentmatr:GetAngles())
									else
										boneoffsets[i]["posoffset"], boneoffsets[i]["angoffset"] = WorldToLocal(ourmatr:GetTranslation(), ourmatr:GetAngles(), self:GetPos(), self:GetAngles())
									end
								else
									boneoffsets[i]["posoffset"], boneoffsets[i]["angoffset"] = Vector(0,0,0), Angle(0,0,0)
								end
							end

							self.BoneOffsets = boneoffsets

							//Get the physbone offsets - since the physobjs don't exist clientside yet, we need to figure out what their child physbones are by using GetModelInfo
							local modelinforaw = util.GetModelInfo(self:GetModel()) //this can silently fail if the ragdoll has a bad modelname (http://wiki.garrysmod.com/page/util/GetModelInfo) but we should've caught that already

							local solids = {}
							for _, tab in pairs (util.KeyValuesToTablePreserveOrder(modelinforaw.KeyValues)) do
								if tab.Key == "solid" then
									local tabprocessed = {}
									for _, tab2 in pairs (tab.Value) do
										tabprocessed[tab2.Key] = tab2.Value
									end

									solids[tabprocessed["index"]] = tabprocessed
								end
							end
							self.PhysBoneParents = {}
							for i = 0, table.Count(solids) - 1 do
								if solids[i]["parent"] and solids[i]["parent"] != solids[i]["name"] then
									self.PhysBoneParents[ self:LookupBone(solids[i]["name"]) ] = self:LookupBone( solids[i]["parent"] )
								end
							end

							self.PhysBoneOffsets = {}
							for i = 0, self:GetBoneCount() - 1 do
								local ourmatr = self:GetBoneMatrix(i)
								if RagdollResizerScales[i] and self.PhysBoneParents[i] then
									if ourmatr then
										local parentmatr = self:GetBoneMatrix(self.PhysBoneParents[i])
										//we don't need an angle offset for these ones
										local pos = WorldToLocal(ourmatr:GetTranslation(), ourmatr:GetAngles(), parentmatr:GetTranslation(), parentmatr:GetAngles())
										self.PhysBoneOffsets[i] = pos
									end
								end
							end

							//Now use the ragdoll sequence for angles
							local sequence = self:SelectWeightedSequence(ACT_DIERAGDOLL)
							if sequence != -1 then
								local mdl = self:GetModel()	  //just calling SetModel(self:GetModel()) here doesn't prevent animation blending unlike when we do the same
								self:SetModel("models/error.mdl") //thing in prop_resizedragdoll_physparent; instead we have to switch to another model and then switch back
								self:SetModel(mdl)
								self:SetSequence(sequence)
								self:ResetSequence(sequence)

								self:SetupBones() //give the bones a nudge, otherwise we won't get the correct angles below
							end

							self.PhysBoneAngles = {}
							for i = 0, self:GetBoneCount() - 1 do
								local ourmatr = self:GetBoneMatrix(i)
								if ourmatr then
									//instead, save the exact angle of the bone itself, since we can't grab it from a physobj here and the matrix will distort the angle if scaled unevenly
									self.PhysBoneAngles[i] = ourmatr:GetAngles()
								end
							end

						end

						//SetupBones above seems to run this hook again, so prevent it from returning errors
						if !self.PhysBoneAngles then return end

						local lowestheight = nil
						for i = 0, self:GetBoneCount() - 1 do

							local matr = nil

							local parentmatr = nil
							local parentboneid = self:GetBoneParent(i)  //TODO: some people are getting a bug where this returns a string??
							if parentboneid and parentboneid != -1 then
								parentmatr = self:GetBoneMatrix(parentboneid)
							else
								parentmatr = Matrix()
								parentmatr:SetTranslation(self:GetPos())
								parentmatr:SetAngles(self:GetAngles())
							end
							if parentmatr then
								parentmatr:Translate(self.BoneOffsets[i]["posoffset"])
								parentmatr:Rotate(self.BoneOffsets[i]["angoffset"])
							end

							if RagdollResizerScales[i] then
								matr = Matrix()
								local physparentmatr = nil
								if self.PhysBoneOffsets[i] then
									physparentmatr = self:GetBoneMatrix(self.PhysBoneParents[i])
								end
								if physparentmatr and self.PhysBoneOffsets[i] then
									physparentmatr:Translate(self.PhysBoneOffsets[i])
									matr:SetTranslation(physparentmatr:GetTranslation())
								else
									matr:SetTranslation(parentmatr:GetTranslation())
								end
								if pose == 1 then
									local angmatr = ent:GetBoneMatrix(i)
									if angmatr then
										if !physparentmatr then
											matr:SetTranslation(angmatr:GetTranslation())
										end
										matr:SetAngles(angmatr:GetAngles())
									end
								else
									if self.PhysBoneAngles[i] then matr:SetAngles(self.PhysBoneAngles[i]) end
								end
								matr:Scale(RagdollResizerScales[i])
							else
								//Follow our parent bone
								if parentmatr then matr = parentmatr end
							end


							if matr then
								if self:GetBoneName(i) != "__INVALIDBONE__" then
									self:SetBoneMatrix(i,matr)
									self.SavedBoneMatrices[i] = matr

									if RagdollResizerScales[i] then
										if !lowestheight then
											lowestheight = matr:GetTranslation().z
										else
											if matr:GetTranslation().z < lowestheight then lowestheight = matr:GetTranslation().z end
										end
									end
								end
							end

						end

						//Do this lowestheight thing to emulate how the resized ragdoll spawn function tries to spawn it sort of flush against the ground.
						//TODO: This is inaccurate when pose == 1 and physobjs without parents have a different scale than the old ragdoll, why?
						if !lowestheight then return end
						local offset = self:GetPos().z - lowestheight
						for i = 0, self:GetBoneCount() - 1 do
							matr = self:GetBoneMatrix(i)
							if matr then
								matr:SetTranslation(matr:GetTranslation() + Vector(0,0,offset))
								if self:GetBoneName(i) != "__INVALIDBONE__" then
									self:SetBoneMatrix(i,matr)
									self.SavedBoneMatrices[i] = matr
								end
							end
						end
					end)

					//The holster function doesn't run clientside if we die (at least in singleplayer?), so have the toolgun get rid of the ghost ragdoll
					//upon being removed itself.
					self:GetWeapon():CallOnRemove("RemoveRagdollResizerGhost", function()
						self:RemoveGhostRagdoll()
					end)
				end
			else
				//Update the ghost ragdoll
				self.GhostRagdoll:SetupBones()
				self.GhostRagdoll:InvalidateBoneCache()

				//local lowestheight = ent:GetPos()
				//for i = 0, ent:GetBoneCount() - 1 do
				//	local pos = ent:GetBonePosition(i)
				//	if pos and pos.z < lowestheight.z then lowestheight.z = pos.z end
				//end
				//self.GhostRagdoll:SetPos(lowestheight)
				self.GhostRagdoll:SetPos(ent:GetPos())
			end
		else

			//Clear the ghost ragdoll
			self:RemoveGhostRagdoll()

		end


		//If the selected entity has changed, update the controlpanel
		if self.CurEntity != ent:EntIndex() then
			DebugMsg("TOOL:Think(): Populating controls with " .. tostring(ent) .. "...")

			self.CurEntity = ent:EntIndex()
			panel.SelectedEntity = ent  //the function called by moving a slider needs to be able to access the entity somehow
			//panel.physobjlist.PopulateList(self.GhostRagdoll)
			panel.physobjlist.PopulateList(ent, debug)
		end

	else

		//If the selected entity has changed, update the serverside RagdollResizerScales table
		if self.CurEntity != ent:EntIndex() then
			self.CurEntity = ent:EntIndex()

			if IsValid(ent) then
				//Create a new table
				if ent.PhysObjScales then 
					self:GetWeapon().RagdollResizerScales = table.Copy(ent.PhysObjScales)
				else
					self:GetWeapon().RagdollResizerScales = {}
					for i = 0, ent:GetPhysicsObjectCount() - 1 do
						self:GetWeapon().RagdollResizerScales[i] = Vector(1,1,1)
					end
				end
			else
				//Remove the table
				self:GetWeapon().RagdollResizerScales = nil
			end
		end

	end

end

function TOOL:GetStage()

	local ent = self:GetWeapon():GetNWEntity("RagdollResizer_CurEntity")

	if IsValid(ent) then
		return 1
	else
		return 0
	end

end

if CLIENT then

	function TOOL:RemoveGhostRagdoll()

		if IsValid(self.GhostRagdoll) then
			self.GhostRagdoll:Remove()
			self.GhostRagdoll = nil
			if IsValid(self:GetWeapon()) then self:GetWeapon():RemoveCallOnRemove("RemoveRagdollResizerGhost") end
		end

	end

	function TOOL:Holster()

		self:RemoveGhostRagdoll()

	end

	//This is where things get stupid! Since ent:GetModelPhysBoneCount() doesn't work (always returns 0), we need to get the number of physbones 
	//ourselves somehow, so we'll do it through this dumb method that probably won't even work if the last physbone is connected to bone 0 for some reason.
	function GetPhysBoneCountAlternate(ent)

		local physbonecount = -1

		//Since we can't retrieve the number of physbones, we'll just use the number of bones instead, which we know is higher. The physbones that 
		//don't exist will return either 0 or -1 when translated back to bones, so ignore those ones.
		for i = 0, ent:GetBoneCount() - 1 do
			local num = ent:TranslatePhysBoneToBone(i)
			if num > 0 then physbonecount = i end
		end

		return physbonecount + 1

	end

end




function TOOL:DrawHUD()

	local ent = self.GhostRagdoll

	if IsValid(ent) then
		//Draw a halo around the ghost ragdoll - render it through everything so that it doesn't get hidden inside the ragdoll (i.e. if we've set the scale really low)
		if self:GetClientNumber( "drawhalo" ) == 1 then
			local animcolor = 189 + math.cos( RealTime() * 4 ) * 17

			halo.Add( {ent}, Color(255, 255, animcolor, 255), 2.3, 2.3, 1, true, true )

		end

		//Draw the name and position of the selected bone
		local bone = self:GetWeapon():GetNWInt("RagdollResizer_PhysObjIndex")
		if bone and bone > -1 then
			bone = ent:TranslatePhysBoneToBone(bone)
			local matr = ent:GetBoneMatrix(bone)
			local _pos = nil
			if matr then 
				_pos = matr:GetTranslation() 
			else
				_pos = ent:GetBonePosition(bone) 
			end

			if !_pos then return end
			local _pos = _pos:ToScreen()
			local textpos = {x = _pos.x+5,y = _pos.y-5}

			draw.RoundedBox(0,_pos.x - 2,_pos.y - 2,4,4,Color(0,0,0,255))
			draw.RoundedBox(0,_pos.x - 1,_pos.y - 1,2,2,Color(255,255,255,255))
			draw.SimpleTextOutlined(ent:GetBoneName(bone),"Default",textpos.x,textpos.y,Color(255,255,255,255),TEXT_ALIGN_LEFT,TEXT_ALIGN_BOTTOM,1,Color(0,0,0,255))
		end
	end

end




if SERVER then

	util.AddNetworkString("ResizedRagdoll_UpdateToolScale_SendToSv")
	net.Receive("ResizedRagdoll_UpdateToolScale_SendToSv", function()
		local physobjid = net.ReadInt(11)

		local toolgun = net.ReadEntity()


		if physobjid == -10 then

			if !net:ReadBool() then
				local scale = net.ReadVector()
				if toolgun.RagdollResizerScales then
					for k, _ in pairs (toolgun.RagdollResizerScales) do
						toolgun.RagdollResizerScales[k] = scale
					end
				end
			end

		else

			//Set a NWVar on the toolgun so that the DrawHUD function can show the selected physobj
			toolgun:SetNWInt("RagdollResizer_PhysObjIndex",physobjid)

			if !net:ReadBool() and physobjid != -1 then
				local scale = net.ReadVector()
				if toolgun.RagdollResizerScales then toolgun.RagdollResizerScales[physobjid] = scale end
			end

		end
	end)

	util.AddNetworkString("ResizedRagdoll_UpdateToolStretch_SendToSv")
	net.Receive("ResizedRagdoll_UpdateToolStretch_SendToSv", function()
		local stretch = net.ReadBool()
		local toolgun = net.ReadEntity()

		toolgun:SetNWBool("RagdollResizer_Stretch", stretch)
	end)

else

	local function UpdateResizedRagdollScale(physobjid,newscale)

		local panel = controlpanel.Get("ragdollresizerphys")
		if !panel or !panel.ToolgunObj then return end

		local ent = panel.SelectedEntity
		if !IsValid(ent) then return end

		if !newscale then newscale = Vector(panel.slider_x:GetValue(), panel.slider_y:GetValue(), panel.slider_z:GetValue()) end


		if physobjid == -10 then

			//ID is -10, which means the user used the all slider and we're changing the size of all the physobjs

			if !IsValid(ent) then return end
			ent:SetupBones()
			ent:InvalidateBoneCache()

			//First, apply the new scale clientside
			if !panel.UpdatingSliders and IsValid(ent) and panel.ToolgunObj.RagdollResizerScales then
				for id = 0, GetPhysBoneCountAlternate(ent) - 1 do
					panel.ToolgunObj.RagdollResizerScales[ent:TranslatePhysBoneToBone(id)] = newscale
				end
			end

			//Then, send it to the server to update the serverside RagdollResizerScales table
			net.Start( "ResizedRagdoll_UpdateToolScale_SendToSv" )
				net.WriteInt(-10, 11)
				net.WriteEntity(panel.ToolgunObj)

				net.WriteBool(panel.UpdatingSliders)
				if !panel.UpdatingSliders then
					net.WriteVector(newscale)
				end
			net.SendToServer()

		else

			//ID is a regular physobj id, which means the user used an XYZ slider and we're changing the size of one physobj

			//First, apply the new scale clientside
			if !panel.UpdatingSliders and IsValid(ent) and panel.ToolgunObj.RagdollResizerScales and physobjid != -1 then
				panel.ToolgunObj.RagdollResizerScales[ent:TranslatePhysBoneToBone(physobjid)] = newscale
			end

			//Then, send it to the server to update the serverside RagdollResizerScales table
			net.Start( "ResizedRagdoll_UpdateToolScale_SendToSv" )
				net.WriteInt(physobjid, 11)
				net.WriteEntity(panel.ToolgunObj)

				net.WriteBool(panel.UpdatingSliders)
				if !panel.UpdatingSliders then
					net.WriteVector(newscale)
				end
			net.SendToServer()

		end

	end

	local function UpdateStretch(stretch)

		local panel = controlpanel.Get("ragdollresizerphys")
		if !panel or !panel.ToolgunObj then return end

		net.Start( "ResizedRagdoll_UpdateToolStretch_SendToSv" )
			net.WriteBool(stretch)
			net.WriteEntity(panel.ToolgunObj)
		net.SendToServer()

	end




	function TOOL.BuildCPanel(panel)

		//panel:AddControl("Header", {Description = "#tool.ragdollresizerphys.help"})
		panel:AddControl("Header", {Description = "#tool.ragdollresizerphys.desc"})




		panel.slider_all = panel:NumSlider("Ragdoll Scale", nil, 0.20, 50, 2)
		panel.slider_all.SetValue = function(self, val)
			//only clamp the value in multiplayer - let players go nuts with the size in singleplayer since the only person they can ruin things for is themselves
			if !game.SinglePlayer() then
				val = math.Clamp(tonumber(val) or 0, self:GetMin(), self:GetMax())
			else
				val = tonumber(val)
			end
			//the rest of this is the default slider setvalue function
			if ( val == nil ) then return end
			if ( self:GetValue() == val ) then return end
			self.Scratch:SetValue( val )
			self:ValueChanged( self:GetValue() )
		end
		panel.slider_all.OnValueChanged = function()
			if panel.UpdatingSliders then return end
			local val = panel.slider_all:GetValue()
			UpdateResizedRagdollScale(-10, Vector(val,val,val))  //-10 is a fake physobjid that tells the function we want to resize all the physobjs
			panel.slider_x:SetValue(val)
			panel.slider_y:SetValue(val)
			panel.slider_z:SetValue(val)
			panel.slider_xyz:SetValue(val)
		end
		panel.slider_all:SetHeight(20)
		panel.slider_all:SetDefaultValue(1.00)

		panel.slider_all_help = panel:ControlHelp("Changes the scale of the whole ragdoll.")

		panel:ControlHelp("")




		panel.physobjlist = panel:AddControl("ListBox", {
			Label = "Physics Object", 
			Height = 300,
		})

		panel.physobjlist.selectedobj = -1
		panel.physobjlist.PopulateList = function(ent, debug)

			local function DebugMsg(msg)
				if debug == 1 then MsgN("RAGDOLL RESIZER DEBUG: " .. msg) end
			end

			panel.physobjlist:Clear()
			panel.physobjlist.selectedobj = -1

			DebugMsg("panel.physobjlist.PopulateList(): Checking if our selected entity (" .. tostring(ent) .. ") is valid...")

			if IsValid(ent) then

				DebugMsg("panel.physobjlist.PopulateList(): Selected entity (" .. tostring(ent) .. ") IS valid! Populating the controls!")

				//Show the controls
				panel.physobjlist:SetHeight(300)
				panel.slider_all:SetHeight(20)
				panel.slider_all_help:SetText("Changes the scale of the whole ragdoll.")
				panel.UpdatingSliders = true
				local slider_all_value = nil
				if panel.ToolgunObj.RagdollResizerScales then
					for k, v in pairs (panel.ToolgunObj.RagdollResizerScales) do
						if slider_all_value == nil then
							slider_all_value = v.x //ehh
						end
					end
				end
				if slider_all_value == nil then
					slider_all_value = 1
				end
				panel.slider_all:SetValue(slider_all_value)
				panel.check_stretch:SetHeight(15)
				if ent.GetStretch then
					panel.check_stretch:SetChecked(ent:GetStretch())
				else
					panel.check_stretch:SetChecked(false)
				end
				panel.UpdatingSliders = false
				if panel.slidercontainer:GetExpanded() == false then panel.slidercontainer:Toggle() end

				ent:SetupBones()
				ent:InvalidateBoneCache()

				local physbonecount = GetPhysBoneCountAlternate(ent)
				if physbonecount != 0 then

					DebugMsg("panel.physobjlist.PopulateList(): Selected entity (" .. tostring(ent) .. ") has " .. tostring(physbonecount) .. " physobjs that we can find, populating list")

					for id = 0, physbonecount - 1 do
						local bonename = ent:GetBoneName( ent:TranslatePhysBoneToBone(id) )
						if bonename != "__INVALIDBONE__" then
							local line = panel.physobjlist:AddLine( bonename )
							line.OnSelect = function() 
								panel.physobjlist.selectedobj = id
								panel.UpdateSliders(ent, id)
							end
							if id == 0 then line:SetSelected(true) line.OnSelect() end
						end
					end

				else

					DebugMsg("panel.physobjlist.PopulateList(): Selected entity (" .. tostring(ent) .. ") has no physobjs that we can find, keeping list empty")

				end

			else

				DebugMsg("panel.physobjlist.PopulateList(): Selected entity (" .. tostring(ent) .. ") IS NOT valid! Emptying the controls!")

				//Hide the controls
				panel.physobjlist:SetHeight(0)
				panel.slider_all:SetHeight(0)
				panel.slider_all_help:SetText("")
				panel.check_stretch:SetHeight(0)
				if panel.slidercontainer:GetExpanded() == true then panel.slidercontainer:Toggle() end
				panel.slidercontainer:GetParent():SetTall(panel.slidercontainer:GetTall())

				//Add a placeholder line (is this still necessary? i know that dtrees can break if you leave them empty, but maybe not this?)
				local line = panel.physobjlist:AddLine("(select a ragdoll)")

			end

		end
		panel.physobjlist.OnRowSelected = function() end  //get rid of the default OnRowSelected function created by the AddControl function




		panel.slidercontainer = vgui.Create("DForm", panel)
		panel.slidercontainer.Paint = function()
			surface.SetDrawColor(Color(0,0,0,70))
    			surface.DrawRect(0, 0, panel.slidercontainer:GetWide(), panel.slidercontainer:GetTall())
		end
		panel.slidercontainer.Header:SetTall(0)
		panel:AddPanel(panel.slidercontainer)


		panel.UpdatingSliders = false
		panel.UpdateSliders = function(ent, objid)
			//Don't let the options accidentally update anything while we're changing their values like this
			panel.UpdatingSliders = true

			if IsValid(ent) and objid != -1 then
				local scale = panel.ToolgunObj.RagdollResizerScales[ent:TranslatePhysBoneToBone(objid)]

				if scale then
					//if the keyboard focus is on a slider's text field when we update the slider's value, then the text value won't update correctly,
					//so make sure to take the focus off of the text fields first
					panel.slider_x.TextArea:KillFocus()
					panel.slider_y.TextArea:KillFocus()
					panel.slider_z.TextArea:KillFocus()
					panel.slider_xyz.TextArea:KillFocus()

					panel.slider_x:SetValue(scale.x)
					panel.slider_y:SetValue(scale.y)
					panel.slider_z:SetValue(scale.z)
					panel.slider_xyz:SetValue(scale.x)  //ehh

					//taking the focus off of the text areas isn't enough, we also need to update their text manually because vgui.GetKeyboardFocus()
					//erroneously tells them that they've still got focus and shouldn't be updating themselves
					panel.slider_x.TextArea:SetText( panel.slider_x.Scratch:GetTextValue() )
					panel.slider_y.TextArea:SetText( panel.slider_y.Scratch:GetTextValue() )
					panel.slider_z.TextArea:SetText( panel.slider_z.Scratch:GetTextValue() )
					panel.slider_xyz.TextArea:SetText( panel.slider_xyz.Scratch:GetTextValue() )
				end
			end
			UpdateResizedRagdollScale(objid)  //Make sure the NWvars update even if none of the sliders were changed

			panel.UpdatingSliders = false
		end


		panel.slider_x = panel.slidercontainer:NumSlider("Scale X", nil, 0.20, 50, 2)
		panel.slider_x.SetValue = function(self, val)
			//only clamp the value in multiplayer - let players go nuts with the size in singleplayer since the only person they can ruin things for is themselves
			if !game.SinglePlayer() then
				val = math.Clamp(tonumber(val) or 0, self:GetMin(), self:GetMax())
			else
				val = tonumber(val)
			end
			//the rest of this is the default slider setvalue function
			if ( val == nil ) then return end
			if ( self:GetValue() == val ) then return end
			self.Scratch:SetValue( val )
			self:ValueChanged( self:GetValue() )
		end
		panel.slider_x.OnValueChanged = function() UpdateResizedRagdollScale(panel.physobjlist.selectedobj) end
		panel.slider_x:SetHeight(9)
		panel.slider_x:SetDefaultValue(1.00)

		panel.slider_y = panel.slidercontainer:NumSlider("Scale Y", nil, 0.20, 50, 2)
		panel.slider_y.SetValue = function(self, val)
			//only clamp the value in multiplayer - let players go nuts with the size in singleplayer since the only person they can ruin things for is themselves
			if !game.SinglePlayer() then
				val = math.Clamp(tonumber(val) or 0, self:GetMin(), self:GetMax())
			else
				val = tonumber(val)
			end
			//the rest of this is the default slider setvalue function
			if ( val == nil ) then return end
			if ( self:GetValue() == val ) then return end
			self.Scratch:SetValue( val )
			self:ValueChanged( self:GetValue() )
		end
		panel.slider_y.OnValueChanged = function() UpdateResizedRagdollScale(panel.physobjlist.selectedobj) end
		panel.slider_y:SetHeight(9)
		panel.slider_y:SetDefaultValue(1.00)

		panel.slider_z = panel.slidercontainer:NumSlider("Scale Z", nil, 0.20, 50, 2)
		panel.slider_z.SetValue = function(self, val)
			//only clamp the value in multiplayer - let players go nuts with the size in singleplayer since the only person they can ruin things for is themselves
			if !game.SinglePlayer() then
				val = math.Clamp(tonumber(val) or 0, self:GetMin(), self:GetMax())
			else
				val = tonumber(val)
			end
			//the rest of this is the default slider setvalue function
			if ( val == nil ) then return end
			if ( self:GetValue() == val ) then return end
			self.Scratch:SetValue( val )
			self:ValueChanged( self:GetValue() )
		end
		panel.slider_z.OnValueChanged = function() UpdateResizedRagdollScale(panel.physobjlist.selectedobj) end
		panel.slider_z:SetHeight(9)
		panel.slider_z:SetDefaultValue(1.00)

		panel.slider_xyz = panel.slidercontainer:NumSlider("Scale XYZ", nil, 0.20, 50, 2)
		panel.slider_xyz.SetValue = function(self, val)
			//only clamp the value in multiplayer - let players go nuts with the size in singleplayer since the only person they can ruin things for is themselves
			if !game.SinglePlayer() then
				val = math.Clamp(tonumber(val) or 0, self:GetMin(), self:GetMax())
			else
				val = tonumber(val)
			end
			//the rest of this is the default slider setvalue function
			if ( val == nil ) then return end
			if ( self:GetValue() == val ) then return end
			self.Scratch:SetValue( val )
			self:ValueChanged( self:GetValue() )
		end
		panel.slider_xyz.OnValueChanged = function()
			if panel.UpdatingSliders then return end
			local val = panel.slider_xyz:GetValue()
			panel.slider_x:SetValue(val)
			panel.slider_y:SetValue(val)
			panel.slider_z:SetValue(val)
			UpdateResizedRagdollScale(panel.physobjlist.selectedobj)
		end
		panel.slider_xyz:SetHeight(9)
		panel.slider_xyz:SetDefaultValue(1.00)

		//probably don't need this any more now that players can reset the scale by middle clicking, but they're probably used to the button being here and might not even know about middle clicking
		local button = vgui.Create("DButton", panel.slidercontainer)
			button:SetText("Reset Scale")
			panel.slidercontainer:AddItem(button)
			panel.slidercontainer:InvalidateLayout()
		button:SetHeight(15)
		button.DoClick = function() 
			panel.slider_x:SetValue(1.00)
			panel.slider_y:SetValue(1.00)
			panel.slider_z:SetValue(1.00)
			panel.slider_xyz:SetValue(1.00)
			UpdateResizedRagdollScale(panel.physobjlist.selectedobj)
		end


		panel.slidercontainer:ControlHelp("")
		panel.slidercontainer:ControlHelp("Changes the X, Y, and Z scale of the selected physics object.")


		panel.slidercontainer:Toggle()  //options should be hidden by default since no entity is selected




		panel.check_stretch = panel:CheckBox("Make ragdoll stretchy", nil)
		panel.check_stretch.OnChange = function(self, check) 
			if !panel.UpdatingSliders then UpdateStretch(check) end
		end




		panel:AddControl("Label", {Text = ""})

		panel:AddControl("Checkbox", {Label = "Restore pose after resizing", Command = "ragdollresizerphys_pose"})

		panel:AddControl("Checkbox", {Label = "Resized ragdolls start frozen", Command = "ragdollresizerphys_frozen"})

		panel.eyeslider = panel:NumSlider("Eye Scale", nil, 0.20, 50, 2)
		panel.eyeslider.SetValue = function(self, val)
			//val = math.Clamp(tonumber(val) or 0, self:GetMin(), self:GetMax())
			val = tonumber(val)  //don't clamp the value, let players type in whatever they want 
			//the rest of this is the default slider setvalue function
			if ( val == nil ) then return end
			if ( self:GetValue() == val ) then return end
			self.Scratch:SetValue( val )
			self:ValueChanged( self:GetValue() )
		end
		panel.eyeslider.OnValueChanged = function()
			local val = panel.eyeslider:GetValue()
			if !val then return end
			val = -0.60 + ( (val * 4) * 0.15 )
			RunConsoleCommand("r_eyesize", tostring(val))
		end
		panel.eyeslider:SetValue( 1 + ( (GetConVar("r_eyesize"):GetFloat() / 0.15) * 0.25 ) )
		//panel.eyeslider:SetHeight(9)
		panel.eyeslider:SetDefaultValue(1.00)

		//probably don't need this any more now that players can reset the scale by middle clicking, but they're probably used to the button being here and might not even know about middle clicking
		--[[local button = vgui.Create("DButton", panel)
			button:SetText( "Reset Eye Scale" )
			panel:AddItem(button)
			panel:InvalidateLayout()
		button:SetHeight(15)
		button.DoClick = function() 
			panel.eyeslider:SetValue(1.00)
		end]]
		panel:ControlHelp("This is a global setting that sets the eye size of every single model. This is the same as the one in the Eye Poser tool, except it does some math to try and match the scale values used by resized ragdolls.")

		panel:AddControl("Checkbox", {Label = "Draw selection halo", Command = "ragdollresizerphys_drawhalo"})

	end

end