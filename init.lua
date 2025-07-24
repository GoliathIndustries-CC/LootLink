local required = {
    ["cryptoNet"] = function()
        shell.run("wget https://raw.githubusercontent.com/SiliconSloth/CryptoNet/refs/heads/master/cryptoNet.lua lib/cryptoNet.lua")
    end
}

for mod, getter in pairs(required) do
    local status = pcall(require, mod)
    if not status then
        getter()
    end
end