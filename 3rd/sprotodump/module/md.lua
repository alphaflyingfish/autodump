local util = require "util"

-- 使用时需要修改成对应的URL地址
local SPROTO_URL = "https://github.com/alphaflyingfish/autodump" 

local header = [[
generated by sprotodump DO NOT EDIT!!
]]



-- 用来生成每个目录下面的协议列表
local function field(...)
    return table.concat({...}, "|")
end

local function list(t)
    return table.concat(t, "\n")
end

local sum_mt = {}
sum_mt.__index = sum_mt
local function new_sum_stream()
    return setmetatable({
            field("kind", "sum"),
            field(":------:", ":------:"),
        }, sum_mt)
end

function sum_mt:append(kind, sum)
    table.insert(self, field(kind, tostring(sum)))
end


local module_mt = {}
module_mt.__index = module_mt
local function new_module_stream()
    return setmetatable({
        field("module", "range", "info", "protocol sum", "type sum"),
        field(":------:", ":------:", ":------:", ":------:", ":------:"),
    }, module_mt)
end

local empty = "`nil`"
function module_mt:append(namespace, range, info, path, p_sum, t_sum)
    namespace = namespace or empty
    range = range or empty
    info = info or empty
    local name = string.format("[%s](%s/%s)", namespace, SPROTO_URL, path)
    table.insert(self, field(name, range, info, tostring(p_sum), tostring(t_sum)))
end



local protocol_mt = {}
protocol_mt.__index = protocol_mt
local function new_protocol_stream()
    return setmetatable({
        field("protocol", "tag", "request", "response"),
        field(":------:", ":------:", ":------:", ":------:"),
    }, protocol_mt)
end

local function gen_link(meta)
    return SPROTO_URL.."/"..meta.file.."#L"..(meta.line)
end

function protocol_mt:append(v)
    local request = v.request
    local response = v.response
    local meta = v.meta
    local name =  v.name
    local tag = v.tag or ""
    
    name = string.format("[%s](%s)", name, gen_link(meta))
    request = request and request[1] and string.format("[%s](%s)", request._request, gen_link(request[1].meta)) or empty
    response = response and response[1] and string.format("[%s](%s)", response._response, gen_link(response[1].meta)) or empty
    table.insert(self, field(name, tag, request, response))
end

local function comment(line)
    local line = line or ""
    local s = string.match(line, "^%s*#(.*)$")
    return s
end

local function range(s)
    return string.match(s, "[%[%(]%s*%d+%s*,%s*%d+%s*[%]%)]")
end

local function space(s)
    return string.match(s, "^%s*$")
end

local function sproto(s)
    return string.match(s, "^(.+)%.sproto$")
end


local function decode_comment(sproto_filename)
    local name = util.file_basename(sproto_filename)
    local h = io.open(sproto_filename, "r")
    local l = h:lines()

    local range_min = 0
    local range_s = false
    local info_s  = false
    for line in l do
        local s = comment(line)
        if s then
            if not range_s then
                range_s = range(s)
                if range_s then
                    range_min = tonumber(string.match(range_s, "(%d+)%s*,"))
                end
            else
                info_s = s
            end
        end

        if range_s and info_s then
            break
        end
    end

    h:close()
    return name, range_s, info_s, range_min
end


local function shape_trunk_and_build(trunk, build)
    for k,v in pairs(build.protocol) do
        local t = build.type[v.request]
        if t then
            t._request = v.request
            v.request = t
        end
        t = build.type[v.response]
        if t then
            t._response = v.response
            v.response = t
        end
    end

    local trunk_ret = {}
    for i,v in ipairs(trunk) do
        local filename = v.info.filename
        assert(v and trunk_ret[filename]==nil)
        trunk_ret[filename] = v
    end
    return trunk_ret, build
end



local function sum_module(module)
    local protocol = module.protocol
    local type = module.type
    local protocol_sum = 0
    local type_sum = 0

    if protocol then
        for k,v in pairs(protocol) do
            protocol_sum = protocol_sum + 1
        end
    end

    if type then
        for k,v in pairs(type) do
            type_sum = type_sum + 1
        end
    end

    return protocol_sum, type_sum
end


local function decode_module(sproto_files, trunk)
    local module_stream = new_module_stream()
    local ret = {}

    for i,f in ipairs(sproto_files) do
        local name, range_s, info_s, range_min = decode_comment(f)
        local protocol_sum, type_sum = sum_module(trunk[f])
        table.insert(ret, {
                name, range_s, info_s, range_min, f, protocol_sum, type_sum,
            })
    end

    table.sort(ret, function (a, b) return a[4] < b[4] end)
    for i,v in ipairs(ret) do
        module_stream:append(v[1], v[2], v[3], v[5], v[6], v[7])
    end
    return list(module_stream)
end


local function decode_list(p)
    local protocol_stream = new_protocol_stream()
    local ret = {}

    for k,v in pairs(p) do
        table.insert(ret, v)
    end

    table.sort(ret, function (a, b) return a.tag < b.tag end)
    for i,v in ipairs(ret) do
        protocol_stream:append(v)
    end

    return list(protocol_stream)
end


local function decode_sum(build)
    local stream = new_sum_stream()
    local protocol_sum, type_sum = sum_module(build)
    stream:append("protocol", protocol_sum)
    stream:append("type", type_sum)
    return list(stream)
end



local function main(trunk, build, param)
    local sproto_files = param.sproto_file
    trunk, build = shape_trunk_and_build(trunk, build)
    local p = build.protocol
    local outfile = param.outfile or "sproto_list.md"

    local stream = {"# sproto list", header, }
    table.insert(stream, "\n## sum")
    table.insert(stream, decode_sum(build))
    table.insert(stream, "\n## module")
    table.insert(stream, decode_module(sproto_files, trunk))
    table.insert(stream, "\n## list")
    table.insert(stream, decode_list(p))
    local s = list(stream)

    util.write_file(outfile, s, "w")
end

return main
