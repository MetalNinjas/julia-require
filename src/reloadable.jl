# File: require.jl
# Author: Jannis Harder
# Description: Allows types to be reloaded
# Provides: @reloadable

macro reloadable(typ)
    assert(typ.head == :type)
    name = typ.args[1]
    if isa(name, Expr)
        name = name.args[1]
    end
    hidden_name = symbol(strcat("#", name, "#", hash(string(typ))))
    already_defined = false
    try
        eval(hidden_name)
        already_defined = true
    end
    if !already_defined
        typ_hidden = expr_replace_sym(typ, name, hidden_name)
        quote
            global $hidden_name
            $typ_hidden
            global $name = $hidden_name
        end
    else
        quote
            global $name = $hidden_name
        end
    end
end

expr_replace_sym(exp::Symbol, a::Symbol, b::Symbol) = exp == a ? b : exp

function expr_replace_sym(exp::Expr, a::Symbol, b::Symbol)
    expr(exp.head, map(x -> expr_replace_sym(x, a, b), exp.args))
end
expr_replace_sym(exp::Any, a::Symbol, b::Symbol) = exp
