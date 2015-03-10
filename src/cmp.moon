import FunctionBuilder 
    from require "cmp_func_builder"
import LangContext 
    from require "cmp_context"
import parse
    from require "parser"

-- Ensure we have smart-dumping:
require "cmp_dump_func"

-- Various compiler passes:
import Scope, Variable, Constant
    from require "cmp_sym_resolve"

-- No imports:
require "cmp_stack_alloc"

import compileFuncBody
    from require "cmp_compile"

args = {
    :FunctionBuilder, :LangContext
    :parse
    :Scope, :Variable, :Constant
    :compileFuncBody
}
for k, v in pairs require("cmp_constants")
    args[k] = v

return args
