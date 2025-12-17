local bit = bit32
local band, bor, bxor, bnot = bit.band, bit.bor, bit.bxor, bit.bnot
local lshift, rshift, rol = bit.lshift, bit.rshift, bit.lrotate

local H0 = {0x67452301,0xEFCDAB89,0x98BADCFE,0x10325476,0xC3D2E1F0}
local K  = {0x5A827999,0x6ED9EBA1,0x8F1BBCDC,0xCA62C1D6}

local function to_hex(s) local t={} for i=1,#s do t[#t+1]=("%02x"):format(s:byte(i)) end return table.concat(t) end
local function from_hex(h) local t={} for i=1,#h,2 do t[#t+1]=string.char(tonumber(h:sub(i,i+1),16)) end return table.concat(t) end

local function preprocess(m)
  local ml=#m*8; m=m.."\128"; m=m..string.rep("\0",(56-#m%64)%64)
  local t={} for i=7,0,-1 do t[#t+1]=string.char(band(rshift(ml,i*8),0xff)) end
  return m..table.concat(t)
end

local function block_u32s(b)
  local w={} for i=1,64,4 do local a,b2,c,d=b:byte(i,i+3)
    w[#w+1]=bor(lshift(a,24),lshift(b2,16),lshift(c,8),d) end return w
end

local function sha1_raw(m)
  local h0,h1,h2,h3,h4=table.unpack(H0)
  m=preprocess(m)
  for i=1,#m,64 do
    local w=block_u32s(m:sub(i,i+63))
    for t=17,80 do w[t]=rol(bxor(bxor(bxor(w[t-3],w[t-8]),w[t-14]),w[t-16]),1) end
    local a,b,c,d,e=h0,h1,h2,h3,h4
    for t=1,80 do
      local r = (t<=20) and 1 or (t<=40) and 2 or (t<=60) and 3 or 4
      local f = (r==1) and bor(band(b,c),band(bnot(b),d))
             or (r==2 or r==4) and bxor(b,bxor(c,d))
             or bor(bor(band(b,c),band(b,d)),band(c,d))
      local temp=(rol(a,5)+f+e+K[r]+w[t])%2^32
      e,d,c,b,a=d,c,rol(b,30),a,temp
    end
    h0=(h0+a)%2^32; h1=(h1+b)%2^32; h2=(h2+c)%2^32; h3=(h3+d)%2^32; h4=(h4+e)%2^32
  end
  local function be(x) return string.char(band(rshift(x,24),255),band(rshift(x,16),255),band(rshift(x,8),255),band(x,255)) end
  return table.concat{be(h0),be(h1),be(h2),be(h3),be(h4)}
end

local function sha1(s) return to_hex(sha1_raw(s)) end

local function hmac_sha1_raw(key,msg)
  if #key>64 then key=sha1_raw(key) end
  if #key<64 then key=key..string.rep("\0",64-#key) end
  local o=key:gsub(".",function(c)return string.char(bit.bxor(c:byte(),0x5c)) end)
  local i=key:gsub(".",function(c)return string.char(bit.bxor(c:byte(),0x36)) end)
  return sha1_raw(o..sha1_raw(i..msg))
end
local function hmac_sha1(key,msg) return to_hex(hmac_sha1_raw(key,msg)) end

return { sha1_raw=sha1_raw, sha1=sha1, hmac_sha1_raw=hmac_sha1_raw, hmac_sha1=hmac_sha1, to_hex=to_hex, from_hex=from_hex }
