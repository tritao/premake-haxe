--
-- haxe/haxe.lua
-- Define the Haxe language API's.
-- Copyright (c) 2024 Joao Matos, and the Premake project
--

	local p = premake
	local api = p.api

--
-- Register the Haxe extension
--

	p.HAXE = "Haxe"
	api.addAllowed("kind", p.HAXE)
	api.addAllowed("language", p.HAXE)

--
-- Register some Haxe specific properties
--

	api.register {
		name = "haxe_classpath",
		scope = "config",
		kind = "list:path",
		tokens = true,
	}

	api.register {
		name = "haxe_main",
		scope = "config",
		kind = "string",
	}

	api.register {
		name = "haxe_targets",
		scope = "config",
		kind = "keyed:string",
	}

	-- path to the haxe compiler
	api.register {
		name = "haxe_exe_path",
		scope = "project",
		kind = "path",
	}

	-- path to the haxe std library
	api.register {
		name = "haxe_std_path",
		scope = "project",
		kind = "path",
	}

	-- path to the hashlink sdk
	api.register {
		name = "hashlink_include_path",
		scope = "project",
		kind = "path",
	}

	filter { "kind:Haxe" }
		language "Haxe"

	filter {}

--
-- Decide when to load the full module
--

	return function (cfg)
		return (cfg.language == p.HAXE or cfg.kind == p.HAXE)
	end
