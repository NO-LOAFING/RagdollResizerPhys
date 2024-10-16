AddCSLuaFile()

//add a property that only appears if the util.TraceLine detour is busted, to warn the player they've got a conflicting addon
properties.Add("ragdollresizer_error", {
	MenuLabel = "A CONFLICTING ADDON IS CAUSING ERRORS WITH THE RAGDOLL RESIZER - CLICK FOR DETAILS",
	Order = -1000,
	PrependSpacer = true,
	AppendSpacer = true, //unfortunately doesnt work
	MenuIcon = "icon16/exclamation.png", //"vgui/notices/error", //using a bigger icon doesnt actually make the property taller unfortunately
	
	Filter = function(self, ent, ply)

		if !IsValid(ent) then return false end
		if ent:GetClass() != "prop_resizedragdoll_physobj" then return false end //this is where the magic happens - the property only appears if we've right clicked on a prop_resizedragdoll_physobj, but that shouldn't be possible, because our util.TraceLine detour is supposed to redirect it to the parent entity. That means the property only shows up if the detour isn't working!
		if !gamemode.Call("CanProperty", ply, "ragdollresizer_error", ent) then return false end

		return true

	end,

	Action = function(self, ent)

		//local window = g_ContextMenu:Add("DFrame")
		local window = vgui.Create("DFrame")
		window:SetWidth(450)
		window:SetHeight(210)
		window:Center()
		//window:SetSizable(true)
		//window:SetTitle("woe to you! a the ragdoll resizer has gone a-splode!")
		window:SetTitle("Ragdoll Resizer Error")
		window:SetBackgroundBlur(true)
		window:SetDrawOnTop(true)

		local text = vgui.Create("RichText", window)
		text:Dock(FILL)
		text:SetVerticalScrollbarEnabled(true)
		//text:SetPaintBackgroundEnabled(true) //these don't work, why?
		//text:SetFGColor(Color(0,0,0,255)) //^
		//text:SetBGColor(Color(255,255,255,255)) //^
		//text:AppendText("Oh, no! Everything has gone horpfully wrong!\n\nIt sure does look like one of those other addons you have installed is interfering with the Ragdoll Resizer's absolute hack fraudery! I'd explain more, but what we really need here is more placeholder text to bulken this window out!\n\nAnyway, the G-Mod is currently under the impression that this nifty ol' resized ragdoll isn't a ragdoll at all, but a series of cubes, which it is. This won't do! As such, all one of us here at the Ragdoll Resizer team(TM) have replaced Garry's perfectly good util.TraceLine hook with our own cobbled-together garbage that, when introduced into the game, will intercept the traceresults table and sneakily redirect the trace.Entity to point to the ragdoll resizer's 'parent' entity (the one what actually has the character model) instead! Those dimwits at the other tools won't know what hit them! They'll totally think they're clicking on a normal dang ragdoll!\n\n")
		//text:AppendText("Or so that was the plan! It seems that someone else has got their foot in the door, and plopped their own detour in the place of util.TraceLine, and now it's all busted! Our override isn't working at all! They're probably trying to do some sort of portals, or that gravity hull thing, or one of many other flavors of technical wizardry that involve making a separate area well outside the usual game world, and redirecting all the traces so that we're none the wiser! Whatever method they're using, it's totally screwing up our thing here. \n\nGo click on this button here to spew out an error in the console, then dump the whole stack trace it gives you into the garbage bin of the steam workshop comments! In fact, if you can tell what addon is doing it, save me the trouble and link it the comment too! I'll add it to the list eventually!")
		text:AppendText("It looks like the Ragdoll Resizer's util.TraceLine detour has stopped working. This means that the Toolgun and many other things WON'T WORK on resized ragdolls until it's fixed!\n\nThis is almost always caused by another addon messing with the same function, usually a \"portal\"-style mod, or a mod that makes a separate area outside of the normal game world, which need to make traces go through their portals.\n\nTo fix this, disable any conflicting addons, and then restart the map; if it's not obvious which addon is causing the conflict, then you might have to try this a few times. Also consider checking the Ragdoll Resizer's Steam Workshop page - all known conflicting addons are listed in the description, and if you discover a new one, then leave a comment about it so that I can add it to the list!")

		//test: deliberately cause util.TraceLine error to dump a stack trace in console and get the addon what broke it
		//this returns a useful error for doors, but not gravity hull designator. don't bother doing this.
		//util.TraceLine()

		//Fix: If the window is created while the context menu is closed (by clicking the property and immediately letting go of C, especially if lagging)
		//then it'll be unclickable and get stuck on the screen, so we have to manually enable mouse input here to stop that from happening
		//window:SetMouseInputEnabled(true)
		//text:SetMouseInputEnabled(true)

		window:MakePopup()
		window:DoModal()

	end
})

//also add a property to make the ragdoll stretchy, using the same style as the one from the ragdoll stretch tool for cohesion's sake (https://steamcommunity.com/sharedfiles/filedetails/?id=529986984)
properties.Add( "ragdollresizer_stretch", {
	MenuLabel = "#Make stretchy", //sic
	Order = 1200,
	MenuIcon = "icon16/tag.png",
	
	Filter = function(self, ent, ply) 

		if !IsValid(ent) then return false end
		if !(ent:GetClass() == "prop_ragdoll" and ent.ClassOverride == "prop_resizedragdoll_physparent") then return false end
		if !gamemode.Call("CanProperty", ply, "ragdollresizer_stretch", ent) then return false end

		return true 

	end,
	
	Action = function(self, ent)

		self:MsgStart()
			net.WriteEntity(ent)
		self:MsgEnd()
		
	end,
	
	Receive = function(self, length, ply)
	
		local ent = net.ReadEntity()
		
		if !IsValid(ent) then return false end
		if !properties.CanBeTargeted(ent, ply) then return false end
		if !IsValid(ply) then return false end
		if !(ent:GetClass() == "prop_ragdoll" and ent.ClassOverride == "prop_resizedragdoll_physparent") then return false end
		if !self:Filter(ent, ply) then return false end

		ent:SetStretch(!ent:GetStretch()) //toggle the stretch instead of always enabling it like the stretch tool addon. since we want the property to match visually, this won't look right when disabling, but whatever.
		
	end,

	//doesn't work on a non-toggle
	--[[Checked = function(self, ent, tr)

		if !IsValid(ent) or !ent.GetStretch then return false end

		return ent:GetStretch()

	end]]

} )