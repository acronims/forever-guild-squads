-- prints generated packing code for each format, using ccryptolib's own generator (load patched to return source)
local src = io.open(arg[1]):read("*a")
src = src:gsub("return load%(out%)%(%)", "return out")
src = src:gsub("if not string.pack or pcall%(string.dump, string.pack%) then", "if true then")
local packing = assert(loadstring(src))()
local P = {"<I3I3I3I3I3I3I3I3I3I3I2", ">I16", ">I4I4I4I4I4I4I4I4I4I4I4I4I4I4I4I4"}
local U = {"<I3I3I2I3I3I2I3I3I2I3I3I2", "<I3I3I3I3I3I3I3I3I3I3I2", "<I3I3I3I3I3I3I3I3I3I3I3", "<I3I3I3I3I3I3I3I3I3I3I1", ">I4I4I4I4I4I4I4I4I4I4I4I4I4I4I4I4I4I4I4I4I4I4I4I4I4I4I4I4I4I4I4I4"}
io.write("local PK, UK = {}, {}\n")
for _, f in ipairs(P) do local s = packing.compilePack(f); io.write(("PK[%q] = (function() %s end)()\n"):format(f, s)) end
for _, f in ipairs(U) do local s = packing.compileUnpack(f); io.write(("UK[%q] = (function() %s end)()\n"):format(f, s)) end
io.write("return { compilePack = function(f) return assert(PK[f], f), f end, compileUnpack = function(f) return assert(UK[f], f), f end }\n")
