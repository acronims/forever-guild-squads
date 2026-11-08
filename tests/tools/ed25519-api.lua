-- ---- Guild Squads API (RFC 8032 Ed25519 on ccryptolib's field/group code) ----
do
  local fq, ed, sha512 = M.fq, M.edwards25519, M.sha512
  local IDENT = "\1" .. string.rep("\0", 31)
  -- L = 2^252 + 27742317777372353535851937790883648493, little-endian bytes
  local LBYTES = { 0xed, 0xd3, 0xf5, 0x5c, 0x1a, 0x63, 0x12, 0x58, 0xd6, 0x9c, 0xf7, 0xa2, 0xde, 0xf9, 0xde, 0x14,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0x10 }
  local function scalarCanonical(s) -- s < L ?
    for i = 32, 1, -1 do
      local a, b = s:byte(i), LBYTES[i]
      if a ~= b then return a < b end
    end
    return false
  end
  local function smallOrder(P) -- 8P == identity
    local Q = ed.double(ed.double(ed.double(P)))
    return ed.encode(Q) == IDENT
  end
  local function expand(sk)
    local h = sha512.digest(sk)
    return fq.decodeClamped(h:sub(1, 32)), h:sub(33, 64)
  end
  local E = {}
  E.sha512 = sha512.digest
  function E.publicKey(sk)
    assert(type(sk) == "string" and #sk == 32, "secret key length must be 32")
    local x = expand(sk)
    return ed.encode(ed.mulG(fq.bits(x)))
  end
  -- deterministic RFC 8032 5.1.6: r = H(prefix || M), R = rB, k = H(R || A || M), S = r + k*a mod L
  function E.sign(sk, pk, msg)
    assert(type(sk) == "string" and #sk == 32, "secret key length must be 32")
    assert(type(pk) == "string" and #pk == 32, "public key length must be 32")
    assert(type(msg) == "string", "message must be a string")
    local x, prefix = expand(sk)
    local r = fq.decodeWide(sha512.digest(prefix .. msg))
    local rStr = ed.encode(ed.mulG(fq.bits(r)))
    local k = fq.decodeWide(sha512.digest(rStr .. pk .. msg))
    return rStr .. fq.encode(fq.add(r, fq.mul(k, x)))
  end
  -- strict: |sig| = 64, S < L, A canonical and not small-order, R not small-order, [S]B == R + [k]A
  function E.verify(pk, msg, sig)
    if type(pk) ~= "string" or #pk ~= 32 or type(msg) ~= "string" or type(sig) ~= "string" or #sig ~= 64 then return false end
    local rStr, sStr = sig:sub(1, 32), sig:sub(33)
    if not scalarCanonical(sStr) then return false end
    local A = ed.decode(pk)
    if not A or ed.encode(A) ~= pk or smallOrder(A) then return false end
    local R = ed.decode(rStr)
    if not R or smallOrder(R) then return false end
    local k = fq.decodeWide(sha512.digest(rStr .. pk .. msg))
    local gs = ed.mulG(fq.bits(fq.decode(sStr)))
    local ye = ed.mul(A, fq.bits(k))
    return ed.encode(ed.sub(gs, ed.niels(ye))) == rStr
  end
  ns.Ed25519 = E
end
return ns.Ed25519
