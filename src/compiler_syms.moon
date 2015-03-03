M = {}

M.Variable = newtype {
    init: (@name) =>
        @isConstant = false
        @isValue = false
    makeConstant: (value) =>
        @isConstant = true
        @constantValue = value
    makeValue: (value) =>
        @isConstant = true
        @value = value
}

M.Param = newtype {
    init: (@name) =>
        @var = M.Variable(@name)
}

return M
