--
-- haxe/haxe.lua
-- Define the Haxe action(s).
-- Copyright (c) 2024 Joao Matos, and the Premake project
--

	local p = premake

	p.modules.haxe = {}

	local m = p.modules.haxe

	m._VERSION = p._VERSION
	m.elements = {}

	local api = p.api

	-- remove this if you want to embed the module
	dofile "_preload.lua"

--
-- Patch the project table to provide knowledge of Haxe projects
--
	function p.project.ishaxe(prj)
		return prj.language == p.HAXE
	end

--
-- Patch the path table to provide knowledge of Haxe file extensions
--
	function path.ishaxefile(fname)
		return path.hasextension(fname, { ".hx" })
	end

--
-- Patch actions
--

	include("haxe_ninja.lua")

	return m
