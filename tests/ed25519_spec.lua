-- v1.2 AF1: Ed25519 (RFC 8032) vendored from ccryptolib in Core/Ed25519.lua. Spec: docs/SPEC-v1.2-p2p.md, annex F.
-- Vectors of RFC 8032 section 7.1, interoperability with node's crypto (ED25519_NODE, built by tests/run.js) and
-- the strict verify: S >= L, small-order R or A and non-canonical A are refused.
local E = NS.Ed25519

local function unhex(h) return (h:gsub("..", function(x) return string.char(tonumber(x, 16)) end)) end
local function hex(s) return (s:gsub(".", function(c) return string.format("%02x", c:byte()) end)) end

local RFC = {
  { "9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60",
    "d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a", "",
    "e5564300c360ac729086e2cc806e828a84877f1eb8e5d974d873e065224901555fb8821590a33bacc61e39701cf9b46bd25bf5f0595bbe24655141438e7a100b" },
  { "4ccd089b28ff96da9db6c346ec114e0f5b8a319f35aba624da8cf6ed4fb8a6fb",
    "3d4017c3e843895a92b70aa74d1b7ebc9c982ccf2ec4968cc0cd55f12af4660c", "72",
    "92a009a9f0d4cab8720e820b5f642540a2b27b5416503f8fb3762223ebdb69da085ac1e43e15996e458f3613d0f11d8c387b2eaeb4302aeeb00d291612bb0c00" },
  { "c5aa8df43f9f837bedb7442f31dcb7b166d38535076f094b85ce3a2e0b4458f7",
    "fc51cd8e6218a1a38da47ed00230f0580816ed13ba3303ac5deb911548908025", "af82",
    "6291d657deec24024827e69c3abe01a30ce548a284743a445e3680d7db5ac3ac18ff9b538d16f290ae67f760984dc6594a7c15e9716ed28dc027beceea1ec40a" },
}

-- little-endian 32-byte add (S + L) without overflow: S < L < 2^253
local L = unhex("edd3f55c1a631258d69cf7a2def9de1400000000000000000000000000000010")
local function addLE(a, b)
  local out, c = {}, 0
  for i = 1, 32 do
    local v = a:byte(i) + b:byte(i) + c
    out[i] = string.char(v % 256)
    c = (v - v % 256) / 256
  end
  return table.concat(out)
end

test("ed25519: RFC 8032 7.1 TEST 1-3 (public key, deterministic signature, verify)", function()
  ok(E ~= nil, "Core/Ed25519.lua loaded (NS.Ed25519)")
  ok(hex(E.sha512("abc")) == "ddaf35a193617abacc417349ae20413112e6fa4e89a97ea20a9eeee64b55d39a2192992a274fc1a836ba3c23a3feebbd454d4423643ce80e2a9ac94fa54ca49f", "sha512('abc')")
  for i, v in ipairs(RFC) do
    local sk, pk, m, sig = unhex(v[1]), unhex(v[2]), unhex(v[3]), unhex(v[4])
    ok(E.publicKey(sk) == pk, "TEST " .. i .. " public key")
    ok(E.sign(sk, pk, m) == sig, "TEST " .. i .. " signature")
    ok(E.verify(pk, m, sig) == true, "TEST " .. i .. " verifies")
    ok(E.verify(pk, m .. "x", sig) == false, "TEST " .. i .. " other message refused")
    local bad = sig:sub(1, 10) .. string.char((sig:byte(11) + 1) % 256) .. sig:sub(12)
    ok(E.verify(pk, m, bad) == false, "TEST " .. i .. " flipped byte refused")
  end
end)

test("ed25519: interoperates with node crypto (OpenSSL) both ways", function()
  ok(ED25519_NODE and #ED25519_NODE >= 2, "fixtures from tests/run.js")
  for i, line in ipairs(ED25519_NODE) do
    local h = {}
    for part in (line .. ":"):gmatch("([^:]*):") do h[#h + 1] = unhex(part) end
    local sk, pk, m, sig = h[1], h[2], h[3], h[4]
    ok(E.verify(pk, m, sig) == true, "node signature " .. i .. " verifies in Lua")
    ok(E.publicKey(sk) == pk, "node key " .. i .. ": same public key in Lua")
    -- Ed25519 is deterministic: an identical signature is the one node verifies
    ok(E.sign(sk, pk, m) == sig, "Lua signature " .. i .. " is byte-identical to node's")
  end
end)

test("ed25519: strict verify refuses malleable and small-order inputs", function()
  local v = RFC[1]
  local pk, m, sig = unhex(v[2]), unhex(v[3]), unhex(v[4])
  local R, S = sig:sub(1, 32), sig:sub(33)
  ok(E.verify(pk, m, R .. addLE(S, L)) == false, "S + L (malleable twin) refused")
  ok(E.verify(pk, m, R .. string.rep("\255", 32)) == false, "S >= 2^255 refused")
  local ID = "\1" .. string.rep("\0", 31)                                  -- identity, order 1
  local ORD2 = unhex("ecffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff7f") -- (0, -1), order 2
  local ORD8 = unhex("c7176a703d4dd84fba3c0b760d10670f2a2053fa2c39ccc64ec7fd7792ac037a") -- order 8
  local ZERO = string.rep("\0", 32)
  for name, P in pairs({ identity = ID, order2 = ORD2, order8 = ORD8 }) do
    ok(E.verify(P, m, sig) == false, "small-order A (" .. name .. ") refused")
    ok(E.verify(pk, m, P .. S) == false, "small-order R (" .. name .. ") refused")
    -- the classic forgery: A small order, R = identity, S = 0 verifies for any message under a lax check
    ok(E.verify(P, "any message", ID .. ZERO) == false, "forgery with small-order A (" .. name .. ") refused")
  end
  -- y = p + 1 encodes the identity non-canonically
  local NONCANON = unhex("eeffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff7f")
  ok(E.verify(NONCANON, m, sig) == false, "non-canonical A refused")
  ok(E.verify(pk, m, sig:sub(1, 63)) == false and E.verify(pk:sub(1, 31), m, sig) == false, "bad lengths refused")
  ok(E.verify(nil, m, sig) == false and E.verify(pk, nil, sig) == false, "non-string arguments refused")
end)

-- fix/perf (runtime review M5): the CI only ran the byte-table fallback of Core/Ed25519.lua (Fengari has no `bit`);
-- WoW has LuaBitOp's `bit`, whose results are SIGNED 32-bit. A fresh copy of the module is loaded with a `bit` shim
-- (signed like LuaBitOp, and unsigned like bit32) and must pass the RFC 8032 vectors and give the same multi-block
-- sha512; every call must get integers in [0, 2^32). The shim uses Lua 5.3 operators inside a string (the test VM is
-- Fengari, 5.3; the Lua 5.1 syntax gate never sees them). GSQ_BIT_SABOTAGE=1 breaks the shim (the test must go red).
local function bitShim(signed, stats)
  -- Fengari integers are 32-bit: map [0, 2^32) to int32 first (what LuaBitOp does), operate, then give the result
  -- signed (LuaBitOp) or back in [0, 2^32) (bit32)
  local mk = load([[
    local signed, sabotage = ...
    local T32 = 4294967296.0
    local function i32(x) if x >= 2147483648.0 then x = x - T32 end return math.tointeger(x) end
    local function norm(r)
      if sabotage then r = r ~ 1 end
      r = r + 0.0
      if not signed and r < 0 then r = r + T32 end
      return r
    end
    return function(a, b) return norm(i32(a) & i32(b)) end,
           function(a, b) return norm(i32(a) | i32(b)) end,
           function(a, b) return norm(i32(a) ~ i32(b)) end
  ]])
  local sab = rawget(_G, "GSQ_BIT_SABOTAGE") and true or false
  local band, bor, bxor = mk(signed, sab)
  local function chk(f)
    return function(a, b)
      stats.calls = stats.calls + 1
      if not (type(a) == "number" and type(b) == "number" and a >= 0 and a < 4294967296 and a == math.floor(a)
        and b >= 0 and b < 4294967296 and b == math.floor(b)) then stats.bad = stats.bad + 1 end
      return f(a, b)
    end
  end
  return { band = chk(band), bor = chk(bor), bxor = chk(bxor) }
end

test("ed25519 M5: the WoW `bit` path (signed and unsigned results) passes RFC 8032 7.1 and matches the sha512", function()
  local long = string.rep("guild squads 1.2 ", 40)   -- 680 B: 6 blocks of sha512
  for _, signed in ipairs({ true, false }) do
    local stats, had = { calls = 0, bad = 0 }, rawget(_G, "bit")
    bit = bitShim(signed, stats)
    local fns = {}
    local okL, errL = pcall(loadmod, "Core/Ed25519.lua", fns)
    bit = had
    ok(okL, "loaded with the shim: " .. tostring(errL))
    local E2 = fns.Ed25519
    local tag = signed and "signed" or "unsigned"
    ok(E2 ~= nil and E2 ~= E, tag .. ": a fresh copy")
    eq(hex(E2.sha512(long)), hex(E.sha512(long)), tag .. ": multi-block sha512 = the fallback's")
    for i, v in ipairs(RFC) do
      local sk, pk, m, sig = unhex(v[1]), unhex(v[2]), unhex(v[3]), unhex(v[4])
      ok(E2.publicKey(sk) == pk, tag .. " TEST " .. i .. " public key")
      ok(E2.sign(sk, pk, m) == sig, tag .. " TEST " .. i .. " signature")
      ok(E2.verify(pk, m, sig) == true, tag .. " TEST " .. i .. " verifies")
    end
    ok(stats.calls > 1000, tag .. ": the bit path was used (" .. stats.calls .. " calls)")
    eq(stats.bad, 0, tag .. ": every call got integers in [0, 2^32)")
  end
end)
