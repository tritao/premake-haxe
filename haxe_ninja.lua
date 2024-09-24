local p = premake
local haxe = p.modules.haxe

if os.locate("premake-ninja/ninja.lua") then

    require("ninja")

end

local ninja = p.modules.ninja

if ninja then

    --
    -- Patch the ninja action...
    --

    local action = p.action.get('ninja')
    if action == nil then
        error( "Failed to locate prerequisite action 'ninja'" )
    end

    table.insert(action.valid_kinds, p.HAXE)

    -- hlc target needs to run haxe to generate `hlc.json` which contains the information
    -- about the generated tree C files.

    function haxe.setup_hlc_project(base_prj)

        local hlc_json = ninja.get_hlc_json(base_prj, base_prj.haxe_targets.hlc)
        if not hlc_json then
            error("expected valid hlc.json data")
        end

        local out = path.getdirectory(base_prj.haxe_targets.hlc)
        out = path.join("%{cfg.buildtarget.directory}", out)

        local target_files = {}
        for _,file in ipairs(hlc_json.files) do
            file = path.join(out, file)
            table.insert(target_files, file)
        end

        language "C"
        files(target_files)
        dependson { base_prj.name }
        includedirs { out }
        if base_prj.hashlink_include_path then
            includedirs {base_prj.hashlink_include_path }
        end
    end

    local function readFile(file)
        local f = assert(io.open(file, "rb"))
        local content = f:read("*all")
        f:close()
        return content
    end

    function ninja.get_hlc_json(cfg, out)
        local haxe = cfg.haxe_exe_path or "haxe"

        local flags = ninja.get_haxe_global_args(cfg, false)
        flags = table.concat(flags, " ")

        local tmpdir = path.getdirectory(os.tmpname())
        tmpdir = path.join(tmpdir, "hlc_json")
        if os.isdir(tmpdir) then
            os.rmdir(tmpdir)
        end

        if not cfg.haxe_main then
            error("expected a valid Haxe main class")
        end

        local main_c = path.getname(out)
        local args = ninja.get_haxe_args(cfg, "hl", path.join(tmpdir, main_c), false)

        local invocation = string.format("%s %s %s ", haxe, flags, args)
        verbosef(string.format("invoking Haxe to get hlc.json data: %s", invocation))

        result, errorCode = os.outputof(invocation)
        if errorCode ~= 0 then
            error("invoking the Haxe compiler to get hlc.json dependency data failed")
        end

        local hlc_json_path = path.join(tmpdir, "hlc.json")
        if not os.isfile(hlc_json_path) then
            error(string.format("expected hlc.json file at `%s`", hlc_json_path))
        end
       
        local hlc_json = json.decode(readFile(hlc_json_path))
        return hlc_json
    end

    function ninja.get_haxe_global_args(cfg, relative)
        local flags = {}
        if cfg.haxe_std_path then
            local std_path = cfg.haxe_std_path
            if relative then
                std_path = p.project.getrelative(cfg.workspace, std_path)
            end
            table.insert(flags, "--std-path " .. std_path)
        end
        return flags
    end

    -- the following environment variables need to be set:

    --  HAXE_STD_PATH - specifies path to the haxe std library (used by haxe itself)
    --  HAXELIB_PATH - specifies path for haxelib libraries (used by haxelib)
    --  HAXEPATH - specifies path to haxe installation (used by haxelib)

    -- since ninja does not support passing environment variables to subprocesses,
    -- (https://github.com/ninja-build/ninja/issues/1002), set them via haxe compiler
    -- arguments.

    function ninja.haxe_compilation_rules(cfg, toolset)
        local haxe = cfg.haxe_exe_path or "haxe"
        haxe = p.project.getrelative(cfg.workspace, haxe)
        p.outln("HAXE_EXE = " .. haxe)
        p.outln("")
        
        local flags = ninja.get_haxe_global_args(cfg, true)
        flags = table.concat(flags, " ")
        p.outln("FLAGS = " .. flags)

        p.outln("rule haxe")
		p.outln("  command = " .. "$HAXE_EXE" .. " $FLAGS")
		p.outln("  description = haxe $out")
        p.outln("")
    end

    local function get_input_files(cfg)
        local prj = cfg.project
        local files = {}
        p.tree.traverse(p.project.getsourcetree(prj), {
        onleaf = function(node, depth)
            local filecfg = p.fileconfig.getconfig(node, cfg)
            if not filecfg or filecfg.flags.ExcludeFromBuild then
                return
            end
            local rule = p.global.getRuleForFile(node.name, prj.rules)
            local filepath = p.project.getrelative(cfg.workspace, node.abspath)
    
            if p.fileconfig.hasCustomBuildRule(filecfg) then
                custom_command_build(prj, cfg, filecfg, filepath, file_dependencies)
            elseif rule then
                local environ = table.shallowcopy(filecfg.environ)
    
                if rule.propertydefinition then
                    p.rule.prepareEnvironment(rule, environ, cfg)
                    p.rule.prepareEnvironment(rule, environ, filecfg)
                end
                local rulecfg = p.context.extent(rule, environ)
                custom_command_build(prj, cfg, rulecfg, filepath, file_dependencies)
            else
                table.insert(files, filepath)
            end
        end,
        }, false, 1)
    
        return files
    end

    function get_source_files(cfg)
        local prj = cfg.project or cfg
        local classpath = cfg.haxe_classpath or {}
        local files = {}
        if prj._ then
            p.tree.traverse(p.project.getsourcetree(prj), {
            onleaf = function(node, depth)
                local filecfg = p.fileconfig.getconfig(node, cfg)
                if filecfg and filecfg.flags.ExcludeFromBuild then
                    return
                end

                local rule = p.global.getRuleForFile(node.name, prj.rules)    
                if p.fileconfig.hasCustomBuildRule(filecfg) then
                    return
                elseif rule then
                    return
                else
                    local filepath = node.abspath
                    table.insert(files, filepath)
                end
            end,
            }, false, 1)
        else
            files = table.shallowcopy(prj.files)
        end

        for i=1,#files do
            for _,classpath in ipairs(classpath) do
                local abs = path.getabsolute(path.join(cfg.basedir, classpath))
                local filepath = files[i]
                local path = path.getrelative(abs, filepath)
                if string.len(path) < string.len(filepath) then
                    files[i] = path
                end
            end
        end

        return files
    end

    function ninja.get_haxe_args(cfg, target, out, relative)
        args={}

        for _,define in ipairs(cfg.defines) do
            table.insert(args, "-D " .. define)
        end

        if cfg.haxe_classpath then
            for _,classpath in ipairs(cfg.haxe_classpath) do
                if relative then 
                    classpath = p.project.getrelative(cfg.workspace, classpath)
                end
                table.insert(args, "-p " .. classpath)
            end
        end

        local main_class = cfg.haxe_main
        if main_class then
            table.insert(args, "-m " .. main_class)
        end

        if cfg.buildoptions then
            for _,opt in ipairs(cfg.buildoptions) do
                table.insert(args, opt)
            end
        end

        table.insert(args, string.format("--%s %s", target, out))

        local files = get_source_files(cfg)
        for _,file in ipairs(files) do
            table.insert(args, file)
        end

        return table.concat(args, " ")
    end

    function ninja.haxe_target_rules(cfg, toolset)
        local outputs = {}

        local sorted_targets = {}

        for k, v in pairs(cfg.haxe_targets) do
            table.insert(sorted_targets, { key = k, value = v })
        end
        table.sort(sorted_targets, function(a, b) return a.key > b.key end)

		for _,entry in pairs(sorted_targets) do
            local target = entry.key
            local out = entry.value

            if target == "hlc" then
                target = "hl"
            end

            local targetdir = p.project.getrelative(cfg.workspace, cfg.buildtarget.directory)
            local output = targetdir .. "/" .. out
            table.insert(outputs, output)

            local extra_outputs = {}
            local command_rule = "haxe"
            local objfiles = {}
            local files = get_input_files(cfg)    
            local deps = table.join(final_dependency, extrafiles, prelink_dependency)
            ninja.add_build(cfg, output, extra_outputs, command_rule, files, {}, deps, {})

            out = path.join(cfg.buildtarget.directory, out)
            out = p.project.getrelative(cfg.workspace, out)
    
            local args = ninja.get_haxe_args(cfg, target, out, true)
            p.outln("    FLAGS = $FLAGS "  .. args)
        end
        return outputs
    end

    ninja.register_handler(p.HAXE, ninja.haxe_compilation_rules, ninja.haxe_target_rules)
end
