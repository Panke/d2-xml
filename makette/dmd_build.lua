function varsub(s, vt)
    local pat = "%$%([%w_]*%)"
    local i, j = string.find(s,pat)
    while i do
        local ns = ""
        local v = string.sub(s,i+2,j-1)
        if (i > 1) then
            ns = string.sub(s, 1,i-1)
        end
        ns = ns .. vt[v]
        s = ns .. string.sub(s,j+1)
        i, j = string.find(s,pat)
    end
    return s
end

function dvarsub(s, vt)
    local pat = "%$%([%w_]*%)"
    local i, j = string.find(s,pat)
    while i do
        local ns = ""
        local v = string.sub(s,i+2,j-1)
        print("dvar ", v)
        if (i > 1) then
            ns = string.sub(s, 1,i-1)
        end
        if not vt[v] then
            print("Not found : ", v)
        else
            ns = ns .. vt[v]
        end
        s = ns .. string.sub(s,j+1)
        i, j = string.find(s,pat)
    end
    return s
end

function vsub(s, val, r)
    s = string.gsub(s, "%$%(" .. val .. "%)", r)
    return s
end

function join(sep, ...)
    local s = ""
    for i = 1, select('#', ...) do
        local v = select(i, ...)
        if (i > 1) then s = s .. sep end
        s = s .. v
    end
    return s
end

function addDirSourceList(dirSource, result,vt)
    local ext = dirSource["ext"]
    local path = varsub(dirSource["path"],vt)
    local list = dirSource["list"]
    for i,v in ipairs( list ) do
        local srcpath = join(dirSeparator, path, v) .. ext
        result[#result + 1] = srcpath
    end
end

function getModuleName(depfile)
    local f = io.open(depfile,"r")
    local fline = f:read()
    f:close()
    local moduleName = string.match(fline,"([%w%.]*)%s.*")
    return moduleName
end

function joinlist(sep, list)
    local s = ""
    for i,v in ipairs(list) do
        if (i > 1) then
            s = s .. sep
        end
    s = s .. v
    end
    return s
end

function doTargetLink(vt)
    local ts = vt["build_tools"]
    local linker = ts["linker"]
    local objs = vt["build_objs"]
    local targ = vt["build_target"]
    local b = vt["build_data"]

    vt["output"] = targ["output"]

    -- gcc -o $(output) $(lib-paths) $(inputs) $(libs)
    local spaths = ""
    for i,v in ipairs(objs) do
        if (i > 1) then
            spaths = spaths .. " "
        end
        spaths = spaths .. v
    end
    vt["inputs"] = spaths


    local libcmd = linker["lib"]
    local libs = ""
    for i,v in ipairs(linker["default_libs"]) do
        if (i > 1) then
            libs = libs .. " "
        end
        libs = libs .. vsub( libcmd, 'val', v)
    end
    print(libs)
    vt["libs"] = libs

    local libpath=linker["lib_path"]
    local paths = linker["search_paths"]
    spaths = ""
    for i,v in ipairs(paths) do
        if (i>1) then
            spaths = spaths .. " "
        end
        spaths = spaths .. vsub( libpath, 'val', v)
    end
    print("spaths : " , spaths)
    vt["lib_paths"] = spaths;
    local syntax = linker["syntax"]
    print("syntax ", syntax)
    --gcc -o $(output) $(lib_paths) $(inputs) $(libs)

    local cmd = dvarsub(syntax,vt)
    print(cmd)
    local result = os.execute(cmd)
    print( "result = ", result)
end

function doTargetExe(vt)

    local srclist = {}
    local objlist = {}

    local ts = vt['build_tools']
    local targ = vt['build_target']
    local b = vt['build_data']

    print("Do target : ", targ.id, " buildName: ", b.id, " toolset: ", ts.id)

    local compiler = ts["compiler"]
    local import_path_table = {}

    for i, v in ipairs( targ["sources"] ) do
        local src = sources[v]

        print("srcname: ", v)
        for j, ds in ipairs( src ) do
            local stype = ds["type"]
            print("type: ", stype)


            if (stype == "dir") then
                local fileset = {}
                addDirSourceList( ds, fileset, vt)
                fileset.package = ds["package"];
                if (fileset.package) then
                    print("Package ", fileset.package)
                end
                srclist[#srclist+1] = fileset;
            elseif (stype == "import") then
                local temp = varsub(ds["path"],vt)
                import_path_table[temp] = true
            end
        end
    end
 -- dmd $(output) $(import_paths) $(flags) $(inputs)

    local objdir = varsub(targ["obj"],vt)
    local output_file = compiler["output_file"]
    local deps_file = compiler["deps_file"]
    local syntax = compiler["syntax"]


    mkdirRecurse(objdir)

    local combine = targ["combine"]

    if not combine then
        combine = "single"
    end

    print("Combine = ", combine)

    local import_path = compiler["import_path"]

    depfile = join(dirSeparator, objdir,"_dep.txt")
    local tempobj = join(dirSeparator, objdir,"_temp.o")

    import_path_list = ""
    for k,v in pairs(import_path_table) do
        if #import_path_list > 0 then
            import_path_list = import_path_list .. " "
        end
        import_path_list = import_path_list .. vsub( import_path,'val', k)
    end
    print("Import path list ", import_path_list)

    if combine ~= "all" then
        print("test")
        vt['flags'] = join(" ",b["flags"], compiler["no_link"], vsub(deps_file, 'val', depfile))
        vt['output'] = vsub(output_file,'val',tempobj)
    end

    print("Build objs to ", objdir)

     vt['import_paths'] = import_path_list

    if combine=="single" then
         for iset, fileset in ipairs( srclist ) do
            local packageName = fileset.package
            print("package ", packageName)
            for i,v in fileset do
                vt['inputs'] = v
                cmd = varsub(syntax,vt)
                print( "cmd ", cmd)
                local result = os.execute(cmd)
                print( "result = ", result)
                local moduleName = ""
                if packageName then
                    moduleName = packageName .. "." .. getBaseName(v)
                else
                    moduleName = getModuleName(depfile)
                end
                local modulePath = string.gsub(moduleName, "%.",dirSeparator) .. ".o"
                print( "module ", modulePath)
                modulePath = join(dirSeparator,objdir,modulePath)
                moveFile(tempobj, modulePath)
                objlist[#objlist+1] = modulePath
            end
        end
        vt['build_objs'] = objlist
        doTargetLink(vt)
    elseif combine=="package" then
        print("# = ", #srclist)
        for iset, fileset in ipairs( srclist ) do
            local packageName = fileset.package
            print("package ", packageName, #fileset)
            vt['inputs'] = joinlist(" ",fileset)
            print(vt['inputs'])
            cmd = varsub(syntax,vt)
            print( "cmd ", cmd)
            local result = os.execute(cmd)
            print( "result = ", result)
            local moduleName = ""
            if packageName then
                moduleName = packageName
            else
                moduleName = getModuleName(depfile)
            end
            local modulePath = string.gsub(moduleName, "%.",dirSeparator) .. ".o"
            print( "module ", modulePath)
            modulePath = join(dirSeparator,objdir,modulePath)
            moveFile(tempobj, modulePath)
            objlist[#objlist+1] = modulePath
        end
        vt['build_objs'] = objlist
        doTargetLink(vt)
    else -- all
        print("# = ", #srclist)
        all = {}
        for iset, fileset in ipairs( srclist ) do
            for i,v in ipairs(fileset) do
                all[#all + 1] = v
            end
        end
        vt['flags'] = join(" ",b["flags"], vsub(deps_file, 'val', depfile))
        vt['inputs'] = joinlist(" ",all)
        vt['output'] = vsub(output_file,'val',targ["output"])
        cmd = varsub(syntax,vt)
        print(cmd)
        local result = os.execute(cmd)
        print( "result = ", result)
    end
    --]]
end


function doTarget()
    local targ = targets[target]
    local tt = targ["type"]
    local b = builds[build]
    local ts = toolsets[toolset]
    local vt = {}
    setmetatable(vt,{__index = _G})
    vt['build_target'] = targ
    vt['build_tools'] = toolsets[toolset]
    vt['build_data'] = builds[build]

    if (tt == "exe") then
        doTargetExe(vt)
    end
end

doTarget()
