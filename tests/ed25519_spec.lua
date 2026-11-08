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
