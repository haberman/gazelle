-- usage: lua luac.lua [file.lua]* [-L [module.lua]*]
--
-- creates a precompiled chunk that preloads all modules listed after
-- -L and then runs all programs listed before -L.
--
-- assumptions:
--	file xxx.lua contains module xxx
--	'/' is the directory separator (could have used package.config)
--	int and size_t take 4 bytes (could have read sizes from header)
--	does not honor package.path
--
-- Luiz Henrique de Figueiredo <lhf@tecgraf.puc-rio.br>
-- Tue Aug  5 22:57:33 BRT 2008
-- This code is hereby placed in the public domain.

local MARK="////////"
local NAME="luac"

local OUTPUT=NAME..".out"
NAME="=("..NAME..")"

local n=#arg
local m=n
local b

for i=1,n do
	if arg[i]=="-L" then m=i-1 break end
end
if m+2<=n then b="local t=package.preload;\n" else b="local t;\n" end

for i=m+2,n do
        local nopath = string.gsub(arg[i],"^.-([^/]+)%.lua$","t['%1']=function()end;\n")
        local onepath = string.gsub(arg[i],"^.-([^/]+/[^/]+)%.lua$","t['%1']=function()end;\n")
        if onepath:find("bootstrap") then
          b=b..onepath
        else
          b=b..nopath
        end
	arg[i]=string.sub(string.dump(assert(loadfile(arg[i]))),13)
end
b=b.."t='"..MARK.."';\n"

for i=1,m do
	b=b.."(function()end)();\n"
	arg[i]=string.sub(string.dump(assert(loadfile(arg[i]))),13)
end
--print(b)

b=string.dump(assert(loadstring(b,NAME)))
local x,y=string.find(b,MARK)
b=string.sub(b,1,x-6).."\0"..string.sub(b,y+2,y+5)

f=assert(io.open(OUTPUT,"wb"))
assert(f:write(b))
for i=m+2,n do
	assert(f:write(arg[i]))
end
for i=1,m do
	assert(f:write(arg[i]))
end
assert(f:write(string.rep("\0",12)))
assert(f:close())
