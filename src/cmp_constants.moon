M = {} -- Module
M.INT_SIZE = 4
M.VAL_SIZE = 8

-- Anything that successfully AND's with
-- almost all 0s into 0 is true
M.TYPE_TAG_BOOL = 1
M.TYPE_TAG_INT = 3
return M
