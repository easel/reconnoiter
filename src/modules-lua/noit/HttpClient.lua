local HttpClient = {};
HttpClient.__index = HttpClient;

function HttpClient:new(hooks)
    local obj = { }
    obj.e = noit.socket()
    setmetatable(obj, HttpClient)
    obj.hooks = hooks or { }
    return obj
end

function HttpClient:connect(target, port, ssl)
    if ssl == nil then ssl = false end
    self.target = target
    self.port = port
    local rv, err = self.e:connect(self.target, self.port)
    if self.hooks.connected ~= nil then self.hooks.connected() end
    if ssl == false then return rv, err end
    if rv ~= 0 then
        return rv, err
    end
    return self.e:ssl_upgrade_socket(self.hooks.certfile and self.hooks.certfile(),
                                     self.hooks.keyfile and self.hooks.keyfile(),
                                     self.hooks.cachain and self.hooks.cachain(),
                                     self.hooks.ciphers and self.hooks.ciphers())
end

function HttpClient:ssl_ctx()
   return self.e:ssl_ctx()
end

function HttpClient:do_request(method, uri, headers, payload)
    self.raw_bytes = 0
    self.content_bytes = 0
    self.e:write(method .. " " .. uri .. " " .. "HTTP/1.1\r\n")
    if payload ~= nil and string.len(payload) > 0 then
      headers["Content-Length"] = string.len(payload)
    end
    headers["Accept-Encoding"] = "gzip, deflate";
    if headers["User-Agent"] == nil then
        headers["User-Agent"] = "Reconnoiter/0.9"
    end
    for header, value in pairs(headers) do
      self.e:write(header .. ": " .. value .. "\r\n")
    end
    self.e:write("\r\n")
    if payload ~= nil and string.len(payload) > 0 then
      self.e:write(payload)
    end
end

function HttpClient:get_headers()
    local lasthdr
    local str = self.e:read("\n");
    if str == nil then error("no response") end
    self.protocol, self.code = string.match(str, "^HTTP/(%d.%d)%s+(%d+)%s+")
    if self.protocol == nil then error("malformed HTTP response") end
    self.headers = {}
    while true do
        local str = self.e:read("\n")
        if str == nil or str == "\r\n" or str == "\n" then break end
        str = string.gsub(str, '%s+$', '')
        local hdr, val = string.match(str, "^([-_%a%d]+):%s+(.+)$")
        if hdr == nil then
            if lasthdr == nil then error ("malformed header line") end
            hdr = lasthdr
            val = string.match(str, "^%s+(.+)")
            if val == nil then error("malformed header line") end
            self.headers[hdr] = self.headers[hdr] .. " " .. val
        else
            hdr = string.lower(hdr)
            self.headers[hdr] = val
            lasthdr = hdr
        end
    end
    if self.hooks.headers ~= nil then self.hooks.headers(self.headers) end
end

function ce_passthru(str) 
    return str
end

function te_close(self, content_enc_func)
    local len = 32678
    local str
    repeat
        local str = self.e:read(len)
        if str ~= nil then
            self.raw_bytes = self.raw_bytes + string.len(str)
        end
    until str == nil or string.len(str) ~= len
    local decoded = content_enc_func(str)
    if decoded ~= nil then
        self.content_bytes = self.content_bytes + string.len(decoded)
    end
    if self.hooks.consume ~= nil then self.hooks.consume(decoded) end
end

function te_length(self, content_enc_func)
    local len = tonumber(self.headers["content-length"])
    repeat
        local str = self.e:read(len)
        if str ~= nil then
            self.raw_bytes = self.raw_bytes + string.len(str)
            len = len - string.len(str)
        end
        local decoded = content_enc_func(str)
        self.content_bytes = self.content_bytes + string.len(decoded)
        if self.hooks.consume ~= nil then self.hooks.consume(decoded) end
    until str == nil or len == 0
end

function te_chunked(self, content_enc_func)
    while true do
        local str = self.e:read("\n")
        if str == nil then error("bad chunk transfer") end
        local hexlen = string.match(str, "^([0-9a-fA-F]+)")
        if hexlen == nil then error("bad chunk length: " .. str) end
        local len = tonumber(hexlen, 16)
        if len == 0 then break end
        str = self.e:read(len)
        if string.len(str or "") ~= len then error("short chunked read") end
        self.raw_bytes = self.raw_bytes + string.len(str)
        local decoded = content_enc_func(str)
        self.content_bytes = self.content_bytes + string.len(decoded)
        if self.hooks.consume ~= nil then self.hooks.consume(decoded) end
        -- each chunk ('cept a 0 size one) is followed by a \r\n
        str = self.e:read("\n")
        if str ~= "\r\n" and str ~= "\n" then error("short chunked boundary read") end
    end
    -- read trailers
    while true do
        local str = self.e:read("\n")
        if str == nil then error("bad chunk trailers") end
        if str == "\r\n" or str == "\n" then break end
    end
end

function HttpClient:get_body()
    local cefunc = ce_passthru
    local ce = self.headers["content-encoding"]
    if ce ~= nil then
        if ce == "gzip" then
            cefunc = noit.gunzip()
        elseif ce == "deflate" then
            cefunc = noit.gunzip()
        else
            error("unknown content-encoding: " .. ce)
        end
    end
    local te = self.headers["transfer-encoding"]
    local cl = self.headers["content-length"]
    if te ~= nil and te == "chunked" then
        return te_chunked(self, cefunc)
    elseif cl ~= nil and tonumber(cl) ~= nil then
        return te_length(self, cefunc)
    end
    return te_close(self, cefunc)
end

function HttpClient:get_response()
    self:get_headers()
    return self:get_body()
end

return HttpClient
