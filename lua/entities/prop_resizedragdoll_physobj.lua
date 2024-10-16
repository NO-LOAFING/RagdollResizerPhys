AddCSLuaFile()

ENT.Base 			= "base_gmodentity"
ENT.PrintName			= "Resized Ragdoll Physobj"
ENT.Author			= ""

ENT.Spawnable			= false
ENT.AdminSpawnable		= false

//ENT.AutomaticFrameAdvance	= true
ENT.RenderGroup			= RENDERGROUP_TRANSLUCENT
ENT.PhysicsSounds		= true

//for killfeed notices
if CLIENT then
	language.Add("prop_resizedragdoll_physobj", "Ragdoll")
	killicon.AddAlias("prop_resizedragdoll_physobj", "prop_physics")
end




if CLIENT then

	function ENT:BabysitClientsidePhysobj(phys)

		phys:EnableMotion(false) //not sure if it's necessary to do this again after spawning it, but keep its motion disabled just in case
		phys:Sleep() //the clientside physobj likes to break things unless it's asleep
		phys:SetPos(self:GetPos())
		phys:SetAngles(self:GetAngles())

	end

	function ENT:PhysicsUpdate()

		local phys = self:GetPhysicsObject()
		if !IsValid(phys) then return end
		if !phys:IsAsleep() then self:BabysitClientsidePhysobj(phys) end

		//A physobj moved, so tell the parent to recompute the ragdoll bounds
		self.RagdollParent.RagdollBoundsFresh = nil

	end

	function ENT:CalcAbsolutePosition()

		local phys = self:GetPhysicsObject()
		if !IsValid(phys) then return end
		self:BabysitClientsidePhysobj(phys)

		//A physobj moved, so tell the parent to recompute the ragdoll bounds
		self.RagdollParent.RagdollBoundsFresh = nil

	end

	//We don't want to draw the physobj ents, but we can't use SetNoDraw or it'll cause visual jittering when moving the ragdoll
	//debug: comment these out to make the SetColor bit below in PhysicsUpdate work
	function ENT:Draw()
	end
	function ENT:DrawTranslucent()
	end

end




if SERVER then

	function ENT:PhysicsUpdate(phys)

		//debug: show where the physobj is and if it's held by the physgun
		--[[if phys:IsValid() and phys:HasGameFlag(FVPHYSICS_PLAYER_HELD) then
			self:SetColor(Color(255,0,0,255))
		else
			self:SetColor(Color(0,255,0,255))
		end]]

		//If the ragdoll is being carried by the physgun or was just frozen, then run a "stretch prevention" function to make sure all the physobjs are in the right spot
		if phys:IsValid() and self.RagdollParent and self.RagdollParent.DoneGeneratingPhysObjs then
			if phys:HasGameFlag(FVPHYSICS_PLAYER_HELD) then
				if !self.RagdollParent:GetStretch() then //don't do this if stretchy
					self.ShouldCorrectPhysObj = true
				else
					self.StopMovingOnceFrozen = 0 //clobber any remaining correction we have queued up if we're stretchy, otherwise we'll get unstretched if we spawned recently
				end
			else
				if !phys:IsMotionEnabled() then
					if self.StopMovingOnceFrozen and self.StopMovingOnceFrozen > 0 then
						self.StopMovingOnceFrozen = self.StopMovingOnceFrozen - 1
						self.ShouldCorrectPhysObj = true
					else
						self.ShouldCorrectPhysObj = false
					end
				else
					self.ShouldCorrectPhysObj = false
				end
			end

			//One physobj should be constantly checking if we need to run the function (we can't do this in the ragdoll's think hook because it's not fast enough)
			if self.PhysBoneNum == 0 then
				for k, ent in pairs (self.RagdollParent.PhysObjEnts) do
					if ent.ShouldCorrectPhysObj then self.RagdollParent:CorrectPhysObjLocations() return end
				end
			end
		end

		//A physobj moved, so tell the parent to recompute the ragdoll bounds
		self.RagdollParent.RagdollBoundsFresh = nil

	end

	hook.Add("OnPhysgunFreeze", "ResizedRagdoll_OnPhysObjFreeze", function(weapon, phys, ent, ply)
		if ent:GetClass() == "prop_resizedragdoll_physobj" and (!ent.RagdollParent or !ent.RagdollParent:GetStretch()) then //don't do this if stretchy
			ent.StopMovingOnceFrozen = 8 //when a physobj is frozen by the physgun, let CorrectPhysObjLocations settle its location for a few iterations
		end				     //before becoming less strict about its location (see the code for the function) so it doesn't freeze in a bad spot
	end)

end




//Don't duplicate this, the parent entity recreates the physobj ents from scratch when it spawns
duplicator.RegisterEntityClass( "prop_resizedragdoll_physobj", function( ply, data )
end, "Data" )