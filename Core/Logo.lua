-- Guild Squads (MIT) - Core/Logo.lua
-- Pure data: curated icon textures, background colours and border styles for squad logos.
-- A logo travels as three small numbers: icon index, colour index, border index.
local _, ns = ...
ns = ns or {}

local Logo = {}
ns.Logo = Logo

local P = "Interface\\Icons\\"
Logo.ICONS = {
  P .. "INV_Sword_04", P .. "INV_Axe_01", P .. "INV_Mace_01", P .. "INV_Shield_06", P .. "INV_Helmet_01",
  P .. "INV_Staff_13", P .. "INV_Wand_07", P .. "INV_Weapon_Bow_07", P .. "INV_ThrowingAxe_01", P .. "INV_Banner_02",
  P .. "INV_Misc_Book_09", P .. "INV_Torch_Lit", P .. "INV_Misc_Head_Dragon_01", P .. "INV_Misc_Bone_HumanSkull_01", P .. "INV_Misc_Rune_01",
  P .. "Ability_Warrior_DefensiveStance", P .. "Ability_Warrior_Charge", P .. "Ability_Warrior_BattleShout", P .. "Ability_Marksmanship", P .. "Ability_Rogue_Eviscerate",
  P .. "Ability_Stealth", P .. "Ability_Gouge", P .. "Ability_Druid_CatForm", P .. "Ability_Racial_BearForm", P .. "Ability_Hunter_Pet_Wolf",
  P .. "Ability_Mount_JungleTiger", P .. "Spell_Holy_HolyBolt", P .. "Spell_Holy_PowerWordShield", P .. "Spell_Holy_SealOfMight", P .. "Spell_Holy_Resurrection",
  P .. "Spell_Fire_FlameBolt", P .. "Spell_Fire_Fire", P .. "Spell_Frost_FrostBolt02", P .. "Spell_Frost_IceStorm", P .. "Spell_Nature_Lightning",
  P .. "Spell_Nature_StarFall", P .. "Spell_Nature_HealingTouch", P .. "Spell_Nature_Tranquility", P .. "Spell_Shadow_ShadowBolt", P .. "Spell_Shadow_DeathCoil",
}
Logo.FALLBACK = P .. "INV_Misc_QuestionMark"

Logo.COLORS = {
  { 0.10, 0.10, 0.10 }, { 0.55, 0.08, 0.08 }, { 0.08, 0.25, 0.55 }, { 0.10, 0.40, 0.12 },
  { 0.45, 0.20, 0.55 }, { 0.70, 0.50, 0.05 }, { 0.05, 0.45, 0.45 }, { 0.75, 0.75, 0.75 },
}

-- border: 1 = thin light, 2 = thick yellow, 3 = none
Logo.BORDERS = {
  { size = 1, r = 0.9, g = 0.9, b = 0.9 },
  { size = 3, r = 1.0, g = 0.82, b = 0.0 },
  { size = 0, r = 0, g = 0, b = 0 },
}

local function clampIndex(i, n)
  i = tonumber(i) or 1
  i = math.floor(i)
  if i < 1 or i > n then return 1 end
  return i
end

function Logo.icon(i) return Logo.ICONS[clampIndex(i, #Logo.ICONS)] end
function Logo.color(i) return Logo.COLORS[clampIndex(i, #Logo.COLORS)] end
function Logo.border(i) return Logo.BORDERS[clampIndex(i, #Logo.BORDERS)] end
function Logo.cycle(i, n, step)
  i = clampIndex(i, n) + step
  if i < 1 then i = n elseif i > n then i = 1 end
  return i
end

return Logo
