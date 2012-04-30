# File: require.jl
# Author: Jannis Harder
# Description: Simple handling of file dependencies
# Provides: @require, @reload
#
# TODO: Maybe support remote workers without access to the srcdir

macro require(names)
    if isa(names, Expr)
        assert(names.head == :tuple)
        names = names.args
    else
        names = (names,)
    end
    :(require($names...))
end

macro reload()
    :(require(:reload))
end

let
    local loaded = false
    try
        require()
        loaded = true
    end
    if loaded
        trace("require already loaded")
        return
    end

    function trace(args...)
        #println(myid(), ": ", args...)
    end

    function trace_load(args...)
        #println(myid(), ": ", args...)
    end


    trace("loading require")

    global RequireModInfo
    type RequireModInfo
        file::String
        mtime::Int
        contents::String
    end

    fwd_deps = HashTable()
    rev_deps = HashTable()
    modinfo = HashTable()
    unloaded = Set()
    needed = Set()
    cached = Set()
    modstack = {nothing}
    modset = Set()
    require_path = [getcwd(),"~/.julia/"]

    registered_set = Set(myid())


    global require
    function require(names::String...)
        if isempty(names)
            return
        end
        if modstack[end] == nothing
            require_remote_sync()
            @sync begin
                at_each(require, :local, names...)
            end
        else
            require(:local, names...)
        end
    end

    function require(mode::Symbol, names::String...)
        if mode == :local
            if isempty(names)
                return
            end
            entry_point(() -> map(require_single, names))
        elseif mode == :reload
            reload()
        else
            error("require: unknown mode $mode")
        end
    end

    global require_remote_sync
    function require_remote_sync()
        trace("remote sync")
        if length(registered_set) < nprocs()
            for w in 1:nprocs()
                if !has(registered_set, w)
                    trace("syncing to remote $w")
                    load_modules = map(n -> "+$n", require_loaded_modules())
                    remote_call_fetch(w, () -> begin
                        include("require.jl")
                        require(:local, load_modules...)
                        end)
                    add(registered_set, w)
                end
            end
        end
    end

    function entry_point(action)
        if modstack[end] == nothing
            try
                action()
                sync()
            catch e
                bt = join(reverse(modstack[2:end]), " <- ")
                println("error while loading module $bt")
                show(e)
                println()
                recover()
                error("load error")
            end
        else
            action()
        end
    end

    function recover()
        trace("recovering")
        for n in modset
            add(unloaded, n)
        end
        modstack = {nothing}
        modset = Set()
        cached = Set()
        trace("recovered")
    end

    function sync()
        if modstack[end] == nothing
            trace("syncing")
            load_all()
            cached = Set()
            trace("synced")
        end
    end

    function reload()
        if has(fwd_deps, nothing)
            require(fwd_deps[nothing]...)
        end
    end

    function require_single(name)
        if name[1:min(end, 1)] == "+"
            name = name[2:end]
            trace("require $name without reloading")
            if !has(modinfo, name) || (has(unloaded, name) && !has(needed, name))
                require_single(name)
            end
            return
        end
        if name == "require"
            error("error: integer divide by zero, universe destroyed")
        end
        trace("require $name")
        if has(modset, name)
            error("require: recursive require detected")
        end
        check_recursive(name)
        if has(unloaded, name)
            trace("loading requested $name")
            load_single(name)
        end
        add_dep(modstack[end], name)
        trace("end require $name")
    end

    function check_recursive(name)
        if has(unloaded, name)
            trace("dependency $name will be reloaded")
            return
        end
        if refresh_modinfo(name)
            invalidate_rev_deps(name)
        else
            trace("checking dependencies of $name")
            if has(fwd_deps, name)
                for n in fwd_deps[name]
                    check_recursive(n)
                end
            end
        end
    end

    function invalidate_rev_deps(name)
        trace("invalidating $name")
        if name == nothing
            trace("nothing to do")
            return
        end
        add(unloaded, name)
        add(needed, name)
        if has(fwd_deps, name)
            for n in fwd_deps[name]
                del_dep(name, n)
            end
        end
        if has(rev_deps, name)
            for n in rev_deps[name]
                invalidate_rev_deps(n)
            end
        end
    end

    function first(a)
        v = start(a)
        if done(a, v)
            error("first: collection is empty")
        end
        return next(a, v)[1]
    end

    function add_dep(from, to)
        trace("recording dependency from $from to $to")
        if has(fwd_deps, from)
            add(fwd_deps[from], to)
        else
            fwd_deps[from] = Set{Any}(to)
        end
        if has(rev_deps, to)
            add(rev_deps[to], from)
        else
            rev_deps[to] = Set{Any}(from)
        end
    end

    function del_dep(from, to)
        trace("unrecording dependency from $from to $to")
        if has(fwd_deps, from)
            del(fwd_deps[from], to)
        end
        if has(rev_deps, to)
            del(rev_deps[to], from)
        end
    end

    function load_all()
        trace("loading needed")
        while !isempty(needed)
            name = first(needed)
            trace("loading $name from needed")
            load_single(name)
        end
    end

    function load_single(name)
        trace_load("loading $name")
        del(unloaded, name)
        del(needed, name)
        push(modstack, name)
        add(modset, name)
        include(modinfo[name].file)
        assert(pop(modstack) == name)
        del(modset, name)
        trace_load("done loading $name")
    end

    function refresh_modinfo(name)
        trace("checking for $name")
        if has(cached, name)
            value = has(unloaded, name)
            trace("check for $name cached as ", value ? "changed" : "unchanged")
            return value
        end
        (file, mtime) = find_file(name)
        if has(modinfo, name) ? modinfo[name].mtime < mtime : true
            trace("found newer data for $name in $file")
            h = open(file)
            modinfo[name] = RequireModInfo(file, mtime, readall(h))
            add(unloaded, name)
            close(h)
            return true
        else
            add(cached, name)
        end
        return false
    end

    function find_file(name)
        file = split(name, '/')[end]
        candidates = ["$name.jl", "$name/$file.jl"]
        for p in require_path
            for c in candidates
                f = "$p/$c"
                return (f, try modification_time(f) catch; continue end)
            end
        end
        error("require: could not find file to load for $name")
    end

    function modification_time(filename)
        return int(chomp(readall(output(`stat -L -c %Y $filename`))))
    end

    global require_resource
    function require_resource(name)
        if modstack[end] == nothing
            dir = require_path[1]
        else
            dir = join(split(modinfo[modstack[end]].file, '/')[1:end-1], '/')
        end
        return "$dir/$name"
    end

    global require_loaded_modules
    function require_loaded_modules()
        out = Array(String, 0)
        for (n, info) in modinfo
            if !has(unloaded, n)
                push(out, n)
            end
        end
        return out
    end
end
