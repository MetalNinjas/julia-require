julia-require
=============

Macros to make loading (and reloading) files in Julia easier. Instead of loading files with `load()` you can use the `@require` macro which automatically resolves all dependencies and loads files only once even for multiple requires:

```julia
@require "ml/cv", "nlopt"
```

This will first look for the file `./ml/cv.jl` and if the file is not found for `./ml/cv/cv.jl` then `./nlopt.jl` is loaded (and `./nlopt/nlopt.jl` respectively). This allows convenient growth of modules, as they can be simply put into a subdirectory when additional compartmentalization is needed without the need to change all the includes. The search path is currently hard-coded as the current working directory and`~/.julia` (where the `require.jl` will be installed.

The module also supports automatic reloading of all changed file. This is quite handy when working with the interactive shell, simply type

```julia
julia> @reload
```

to get up to date. If types are defined in one of your changed files you will see some errors about redifinition of types (the new code is still loaded but if the type changed that change is not considered). You can circumvent this by using the reloadable module and write

```julia
@require "reloadable" # Considering reloadable.jl is in your cwd

@reloadable type Data
  ...
end
```

which makes the type reloadable (once it was loaded without reloadable this cannot be changed by reloading, julia has to be restarted then). Be warned though, that this is a total hack, there is no guarantee that this will continue to work or that you choose a typename which leads to an internal hash collision.


Installation
------------

As julia has no package management system yet, if it would this code probably wouldn't exist ;), there is no good way to install the require.jl into the system so that it is loaded with every julia session. As a preliminary solution this library comes with an alias shell script that automatically loads the require file after boot and passes all other command line options.