-- Interface mobile : les noms des raccourcis, dans Échap > Raccourcis (une manette peut
-- ouvrir une roue avec l'un de ses boutons).
BINDING_HEADER_WOLKARAMOBILE = "Interface mobile"
for i = 1, 4 do
    _G["BINDING_NAME_CLICK WolkaraMobileToggle" .. i .. ":LeftButton"] = i == 1 and "Ouvrir ou fermer la roue" or ("Ouvrir ou fermer la roue " .. i)
end
