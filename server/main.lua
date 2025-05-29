RegisterNetEvent('Renewed-Banking:server:addAccountMember', function(account, member)
    local Player = GetPlayerObject(source)
    if not Player then
        print("ERROR: Could not get player object for source: " .. tostring(source))
        return
    end
    
    local playerCid = GetIdentifier(Player)
    if not playerCid then
        print("ERROR: Could not get player identifier")
        return
    end

    -- Validate inputs
    if not account or not member or account == "" or member == "" then
        Notify(source, {
            title = "Banking",
            message = "Invalid account or member ID provided",
            type = "error"
        })
        return
    end

    -- Clean up the member ID (remove spaces, make uppercase for QB frameworks)
    member = string.gsub(tostring(member), "%s+", "")
    if Framework == 'qb' or Framework == 'qbx' then
        member = string.upper(member)
    end

    print("DEBUG: Looking for CID: " .. tostring(member) .. " (Framework: " .. tostring(Framework) .. ")")

    -- Check if trying to add their own ID
    if member == playerCid then
        Notify(source, {
            title = "Banking",
            message = "You cannot add yourself to the account",
            type = "error"
        })
        return
    end

    -- Check if the account exists
    if not cachedAccounts or not cachedAccounts[account] then
        Notify(source, {
            title = "Banking",
            message = "Account does not exist",
            type = "error"
        })
        return
    end

    -- Check if the player is the account creator
    if playerCid ~= cachedAccounts[account].creator then 
        print("Illegal action by " .. tostring(GetPlayerName(source))) 
        Notify(source, {
            title = "Banking",
            message = "You are not authorized to add members to this account",
            type = "error"
        })
        return 
    end

    -- Check if the CID exists in the database and get player info
    local playerExists = false
    local Player2 = nil
    local playerName = "Unknown Player"
    
    -- First try to get online player
    Player2 = GetPlayerObjectFromID(member)
    if Player2 then
        playerExists = true
        local name = GetCharacterName(Player2)
        if name then
            playerName = tostring(name)
        end
        print("DEBUG: Found online player: " .. tostring(playerName))
    else
        print("DEBUG: Player not online, checking database...")
        -- Check if the CID exists in the database (for offline players)
        
        if Framework == 'qb' or Framework == 'qbx' then
            -- For QB frameworks, check players table
            local success, result = pcall(function()
                return MySQL.query.await('SELECT citizenid, charinfo FROM players WHERE citizenid = ?', {member})
            end)
            
            if success and result and #result > 0 then
                playerExists = true
                print("DEBUG: QB Query result count: " .. tostring(#result))
                
                -- Try to get character name
                if result[1] and result[1].charinfo and result[1].charinfo ~= '' then
                    local charSuccess, charinfo = pcall(json.decode, result[1].charinfo)
                    if charSuccess and charinfo and charinfo.firstname and charinfo.lastname then
                        playerName = tostring(charinfo.firstname) .. " " .. tostring(charinfo.lastname)
                    end
                end
                print("DEBUG: Found offline QB player: " .. tostring(playerName))
            else
                print("DEBUG: No QB player found with CID: " .. tostring(member))
            end
        elseif Framework == 'esx' then
            -- For ESX, check users table
            local success, result = pcall(function()
                return MySQL.query.await('SELECT identifier, firstname, lastname FROM users WHERE identifier = ?', {member})
            end)
            
            if success and result and #result > 0 then
                playerExists = true
                print("DEBUG: ESX Query result count: " .. tostring(#result))
                
                if result[1] and result[1].firstname and result[1].lastname then
                    playerName = tostring(result[1].firstname) .. " " .. tostring(result[1].lastname)
                end
                print("DEBUG: Found offline ESX player: " .. tostring(playerName))
            else
                print("DEBUG: No ESX player found with identifier: " .. tostring(member))
            end
        end
    end

    print("DEBUG: Player exists: " .. tostring(playerExists))

    -- If CID doesn't exist, stop here and show error
    if not playerExists then
        local errorMessage = "Citizen ID '" .. tostring(member) .. "' does not exist in the database"
        
        -- Try direct client event
        TriggerClientEvent("Renewed-Banking:client:sendNotification", source, {
            message = errorMessage,
            title = "Banking",
            type = "error"
        })
        
        -- Also try Notify function as backup
        Notify(source, {
            title = "Banking",
            message = errorMessage,
            type = "error"
        })
        
        print("ERROR: " .. errorMessage)
        return
    end

    -- Check if player is already a member
    if cachedAccounts[account] and cachedAccounts[account].auth and cachedAccounts[account].auth[member] then
        TriggerClientEvent("Renewed-Banking:client:sendNotification", source, {
            message = "Player is already a member of this account",
            title = "Banking",
            type = "error"
        })
        return
    end

    -- Initialize player cache if it doesn't exist (for offline players)
    if not cachedPlayers[member] then
        print("DEBUG: Initializing player cache for: " .. tostring(member))
        UpdatePlayerAccount(member)
    end

    -- Add the account to the player's account list
    if cachedPlayers[member] and cachedPlayers[member].accounts then
        table.insert(cachedPlayers[member].accounts, account)
    end

    -- Build the auth array for database update
    local auth = {}
    if cachedAccounts[account] and cachedAccounts[account].auth then
        for k in pairs(cachedAccounts[account].auth) do 
            table.insert(auth, k)
        end
    end
    table.insert(auth, member)
    
    -- Update the cached account auth
    if not cachedAccounts[account].auth then
        cachedAccounts[account].auth = {}
    end
    cachedAccounts[account].auth[member] = true
    
    -- Update the database
    local success, err = pcall(function()
        MySQL.update('UPDATE bank_accounts_new SET auth = ? WHERE id = ?', {json.encode(auth), account})
    end)
    
    if not success then
        print("ERROR: Database update failed: " .. tostring(err))
        TriggerClientEvent("Renewed-Banking:client:sendNotification", source, {
            message = "Database error occurred",
            title = "Banking",
            type = "error"
        })
        return
    end
    
    print("DEBUG: Successfully added " .. tostring(member) .. " to account " .. tostring(account))
    
    -- Success notification
    TriggerClientEvent("Renewed-Banking:client:sendNotification", source, {
        message = "Member " .. tostring(playerName) .. " (" .. tostring(member) .. ") added successfully",
        title = "Banking",
        type = "success"
    })
    
    -- Notify the added player if they're online
    if Player2 then
        local targetSource = nil
        if Player2.source then
            targetSource = Player2.source
        elseif Player2.PlayerId then
            targetSource = Player2.PlayerId
        elseif Player2.PlayerData and Player2.PlayerData.source then
            targetSource = Player2.PlayerData.source
        end
        
        if targetSource then
            TriggerClientEvent("Renewed-Banking:client:sendNotification", targetSource, {
                message = "You have been added to a shared account: " .. tostring(account),
                title = "Banking",
                type = "success"
            })
        end
    end
end)local cachedAccounts = {}
local cachedPlayers = {}

-- Ensure Framework is properly detected
local Framework = nil

CreateThread(function()
    Wait(1000) -- Wait a bit for resources to load
    if GetResourceState('es_extended') == 'started' then
        Framework = 'esx'
    elseif GetResourceState('qbx_core') == 'started' then
        Framework = 'qbx'
    elseif GetResourceState('qb-core') == 'started' then
        Framework = 'qb'
    else
        Framework = 'unknown'
    end
    print("FRAMEWORK DETECTED: " .. tostring(Framework))
end)

function UpdatePlayerAccount(cid)
    local p = promise.new()
    MySQL.query('SELECT * FROM player_transactions WHERE id = ?', {cid}, function(account)
        local query = '%' .. cid .. '%'
        MySQL.query("SELECT * FROM bank_accounts_new WHERE auth LIKE ? ", {query}, function(shared)
            cachedPlayers[cid] = {
                isFrozen = 0,
                transactions = #account > 0 and json.decode(account[1].transactions) or {},
                accounts = {}
            }

            if #shared >= 1 then
                for k=1, #shared do
                    cachedPlayers[cid].accounts[#cachedPlayers[cid].accounts+1] = shared[k].id
                end
            end
            p:resolve(true)
        end)
    end)
    return Citizen.Await(p)
end

-- Framework Events
AddEventHandler('QBCore:Server:PlayerLoaded', function(Player)
    local cid = Player.PlayerData.citizenid
    UpdatePlayerAccount(cid)
end)

AddEventHandler('onResourceStart', function(resourceName)
    Wait(250)
    if resourceName == GetCurrentResourceName() then
        for _, v in ipairs(GetPlayers()) do
            local Player = GetPlayerObject(v)
            if Player then
                local cid = GetIdentifier(Player)
                UpdatePlayerAccount(cid)
            end
        end
    end
end)

-- Initialize cached accounts and create missing job/gang accounts
CreateThread(function()
    Wait(500)
    if not LoadResourceFile("Renewed-Banking", 'web/public/build/bundle.js') or GetCurrentResourceName() ~= "Renewed-Banking" then
        error(locale("ui_not_built"))
        return StopResource("Renewed-Banking")
    end
    
    local accounts = MySQL.query.await('SELECT * FROM bank_accounts_new', {})
    if accounts then
        for _,v in pairs (accounts) do
            local job = v.id
            v.auth = json.decode(v.auth)
            cachedAccounts[job] = {
                id = job,
                type = locale("org"),
                name = GetSocietyLabel(job),
                frozen = v.isFrozen == 1,
                amount = v.amount,
                transactions = json.decode(v.transactions),
                auth = {},
                creator = v.creator
            }
            if #v.auth >= 1 then
                for k=1, #v.auth do
                    cachedAccounts[job].auth[v.auth[k]] = true
                end
            end
        end
    end
    
    local jobs, gangs = GetFrameworkGroups()
    local query = {}
    local function addCachedAccount(group)
        cachedAccounts[group] = {
            id = group,
            type = locale('org'),
            name = GetSocietyLabel(group),
            frozen = 0,
            amount = 0,
            transactions = {},
            auth = {},
            creator = nil
        }
        query[#query + 1] = {"INSERT INTO bank_accounts_new (id, amount, transactions, auth, isFrozen, creator) VALUES (?, ?, ?, ?, ?, NULL) ",
        { group, cachedAccounts[group].amount, json.encode(cachedAccounts[group].transactions), json.encode({}), cachedAccounts[group].frozen }}
    end
    
    for job in pairs(jobs) do
        if not cachedAccounts[job] then
            addCachedAccount(job)
        end
    end
    for gang in pairs(gangs) do
        if not cachedAccounts[gang] then
            addCachedAccount(gang)
        end
    end
    if #query >= 1 then
        MySQL.transaction.await(query)
    end
end)

-- Utility Functions
local function getBankData(source)
    local Player = GetPlayerObject(source)
    local bankData = {}
    local cid = GetIdentifier(Player)
    if not cachedPlayers[cid] then UpdatePlayerAccount(cid) end
    local funds = GetFunds(Player)
    
    bankData[#bankData+1] = {
        id = cid,
        type = locale("personal"),
        name = GetCharacterName(Player),
        frozen = cachedPlayers[cid].isFrozen,
        amount = funds.bank,
        cash = funds.cash,
        transactions = cachedPlayers[cid].transactions,
    }

    local jobs = GetJobs(Player)
    if #jobs > 0 then
        for k=1, #jobs do
            if cachedAccounts[jobs[k].name] and IsJobAuth(jobs[k].name, jobs[k].grade) then
                bankData[#bankData+1] = cachedAccounts[jobs[k].name]
            end
        end
    else
        local job = cachedAccounts[jobs.name]
        if job and IsJobAuth(jobs.name, jobs.grade) then
            bankData[#bankData+1] = job
        end
    end

    local gang = GetGang(Player)
    if gang and gang ~= 'none' then
        local gangData = cachedAccounts[gang]
        if gangData and IsGangAuth(Player, gang) then
            bankData[#bankData+1] = gangData
        end
    end

    local sharedAccounts = cachedPlayers[cid].accounts
    for k=1, #sharedAccounts do
        local sAccount = cachedAccounts[sharedAccounts[k]]
        bankData[#bankData+1] = sAccount
    end

    return bankData
end

local function genTransactionID()
    local template = 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'
    return string.gsub(template, '[xy]', function(c)
        local v = (c == 'x') and math.random(0, 0xf) or math.random(8, 0xb)
        return string.format('%x', v)
    end)
end

local function sanitizeMessage(message)
    if type(message) ~= "string" then
        message = tostring(message)
    end
    message = message:gsub("'", "''"):gsub("\\", "\\\\")
    return message
end

local Type = type
local function handleTransaction(account, title, amount, message, issuer, receiver, transType, transID)
    if not account or Type(account) ~= 'string' then return print(locale("err_trans_account", account)) end
    if not title or Type(title) ~= 'string' then return print(locale("err_trans_title", title)) end
    if not amount or Type(amount) ~= 'number' then return print(locale("err_trans_amount", amount)) end
    if not message or Type(message) ~= 'string' then return print(locale("err_trans_message", message)) end
    if not issuer or Type(issuer) ~= 'string' then return print(locale("err_trans_issuer", issuer)) end
    if not receiver or Type(receiver) ~= 'string' then return print(locale("err_trans_receiver", receiver)) end
    if not transType or Type(transType) ~= 'string' then return print(locale("err_trans_type", transType)) end
    if transID and Type(transID) ~= 'string' then return print(locale("err_trans_transID", transID)) end

    local transaction = {
        trans_id = transID or genTransactionID(),
        title = title,
        amount = amount,
        trans_type = transType,
        receiver = receiver,
        message = sanitizeMessage(message),
        issuer = issuer,
        time = os.time()
    }
    
    if cachedAccounts[account] then
        table.insert(cachedAccounts[account].transactions, 1, transaction)
        local transactions = json.encode(cachedAccounts[account].transactions)
        MySQL.prepare("INSERT INTO bank_accounts_new (id, transactions) VALUES (?, ?) ON DUPLICATE KEY UPDATE transactions = ?",{
            account, transactions, transactions
        })
    elseif cachedPlayers[account] then
        table.insert(cachedPlayers[account].transactions, 1, transaction)
        local transactions = json.encode(cachedPlayers[account].transactions)
        MySQL.prepare("INSERT INTO player_transactions (id, transactions) VALUES (?, ?) ON DUPLICATE KEY UPDATE transactions = ?", {
            account, transactions, transactions
        })
    else
        print(locale("invalid_account", account))
    end
    return transaction
end

local function updateBalance(account)
    MySQL.prepare("UPDATE bank_accounts_new SET amount = ? WHERE id = ?",{ cachedAccounts[account].amount, account })
end

local function getPlayerData(source, id)
    local Player = source and GetPlayerObject(source)
    if not Player then Player = GetPlayerObjectFromID(id) end
    if not Player then
        local msg = ("Cannot Find Account(%s)"):format(id)
        print(locale("invalid_account", id))
        if source then
            Notify(source, {title = locale("bank_name"), description = msg, type = "error"})
        end
    end
    return Player
end

-- Notification function using UI system
function Notify(src, settings)
    if not src or not settings then return end
    
    local notification = {
        message = settings.message or settings.description or "No message",
        title = settings.title or "Banking",
        type = settings.type or "info"
    }
    
    TriggerClientEvent("Renewed-Banking:client:sendNotification", src, notification)
end

-- Account Money Functions
function GetAccountMoney(account)
    if not cachedAccounts[account] then
        locale("invalid_account", account)
        return false
    end
    return cachedAccounts[account].amount
end

function AddAccountMoney(account, amount)
    if not cachedAccounts[account] then
        locale("invalid_account", account)
        return false
    end
    cachedAccounts[account].amount = cachedAccounts[account].amount + amount
    updateBalance(account)
    return true
end

function RemoveAccountMoney(account, amount)
    if not cachedAccounts[account] then
        print(locale("invalid_account", account))
        return false
    end
    if cachedAccounts[account].amount < amount then
        print(locale("broke_account", account, amount))
        return false
    end
    cachedAccounts[account].amount = cachedAccounts[account].amount - amount
    updateBalance(account)
    return true
end

local function getAccountTransactions(account)
    if cachedAccounts[account] then
        return cachedAccounts[account].transactions
    elseif cachedPlayers[account] then
        return cachedPlayers[account].transactions
    end
    print(locale("invalid_account", account))
    return false
end

-- Banking Action Callbacks
lib.callback.register('Renewed-Banking:server:deposit', function(source, data)
    local Player = GetPlayerObject(source)
    local amount = tonumber(data.amount)
    if not amount or amount < 1 then
        TriggerClientEvent("Renewed-Banking:client:sendNotification", source, {
            message = locale("invalid_amount", "deposit"),
            title = locale("bank_name"),
            type = "error"
        })
        return false
    end
    local name = GetCharacterName(Player)
    if not data.comment or data.comment == "" then data.comment = locale("comp_transaction", name, "deposited", amount) else sanitizeMessage(data.comment) end
    if RemoveMoney(Player, amount, 'cash', data.comment) then
        if cachedAccounts[data.fromAccount] then
            AddAccountMoney(data.fromAccount, amount)
        else
            AddMoney(Player, amount, 'bank', data.comment)
        end
        local Player2 = getPlayerData(source, data.fromAccount)
        Player2 = Player2 and GetCharacterName(Player2) or data.fromAccount
        handleTransaction(data.fromAccount, locale("personal_acc") .. data.fromAccount, amount, data.comment, name, Player2, "deposit")
        local bankData = getBankData(source)
        return bankData
    else
        TriggerClientEvent("Renewed-Banking:client:sendNotification", source, {
            message = locale("not_enough_money"),
            title = locale("bank_name"),
            type = "error"
        })
        return false
    end
end)

lib.callback.register('Renewed-Banking:server:withdraw', function(source, data)
    local Player = GetPlayerObject(source)
    local amount = tonumber(data.amount)
    if not amount or amount < 1 then
        TriggerClientEvent("Renewed-Banking:client:sendNotification", source, {
            message = locale("invalid_amount", "withdraw"),
            title = locale("bank_name"),
            type = "error"
        })
        return false
    end
    local name = GetCharacterName(Player)
    local funds = GetFunds(Player)
    if not data.comment or data.comment == "" then data.comment = locale("comp_transaction", name, "withdrawed", amount) else sanitizeMessage(data.comment) end

    local canWithdraw
    if cachedAccounts[data.fromAccount] then
        canWithdraw = RemoveAccountMoney(data.fromAccount, amount)
    else
        canWithdraw = funds.bank >= amount and RemoveMoney(Player, amount, 'bank', data.comment) or false
    end
    if canWithdraw then
        local Player2 = getPlayerData(source, data.fromAccount)
        Player2 = Player2 and GetCharacterName(Player2) or data.fromAccount
        AddMoney(Player, amount, 'cash', data.comment)
        handleTransaction(data.fromAccount,locale("personal_acc") .. data.fromAccount, amount, data.comment, Player2, name, "withdraw")
        local bankData = getBankData(source)
        return bankData
    else
        TriggerClientEvent("Renewed-Banking:client:sendNotification", source, {
            message = locale("not_enough_money"),
            title = locale("bank_name"),
            type = "error"
        })
        return false
    end
end)

lib.callback.register('Renewed-Banking:server:transfer', function(source, data)
    local Player = GetPlayerObject(source)
    local amount = tonumber(data.amount)
    if not amount or amount < 1 then
        TriggerClientEvent("Renewed-Banking:client:sendNotification", source, {
            message = locale("invalid_amount", "transfer"),
            title = locale("bank_name"),
            type = "error"
        })
        return false
    end
    local name = GetCharacterName(Player)
    if not data.comment or data.comment == "" then data.comment = locale("comp_transaction", name, "transfered", amount) else sanitizeMessage(data.comment) end
    
    if cachedAccounts[data.fromAccount] then
        if cachedAccounts[data.stateid] then
            local canTransfer = RemoveAccountMoney(data.fromAccount, amount)
            if canTransfer then
                AddAccountMoney(data.stateid, amount)
                local title = ("%s / %s"):format(cachedAccounts[data.fromAccount].name, data.fromAccount)
                local transaction = handleTransaction(data.fromAccount, title, amount, data.comment, cachedAccounts[data.fromAccount].name, cachedAccounts[data.stateid].name, "withdraw")
                handleTransaction(data.stateid, title, amount, data.comment, cachedAccounts[data.fromAccount].name, cachedAccounts[data.stateid].name, "deposit", transaction.trans_id)
            else
                TriggerClientEvent("Renewed-Banking:client:sendNotification", source, {
                    message = locale("not_enough_money"),
                    title = locale("bank_name"),
                    type = "error"
                })
                return false
            end
        else
            local Player2 = getPlayerData(source, data.stateid)
            if not Player2 then
                TriggerClientEvent("Renewed-Banking:client:sendNotification", source, {
                    message = locale("fail_transfer"),
                    title = locale("bank_name"),
                    type = "error"
                })
                return false
            end
            local canTransfer = RemoveAccountMoney(data.fromAccount, amount)
            if canTransfer then
                AddMoney(Player2, amount, 'bank', data.comment)
                local plyName = GetCharacterName(Player2)
                local transaction = handleTransaction(data.fromAccount, ("%s / %s"):format(cachedAccounts[data.fromAccount].name, data.fromAccount), amount, data.comment, cachedAccounts[data.fromAccount].name, plyName, "withdraw")
                handleTransaction(data.stateid, ("%s / %s"):format(cachedAccounts[data.fromAccount].name, data.fromAccount), amount, data.comment, cachedAccounts[data.fromAccount].name, plyName, "deposit", transaction.trans_id)
            else
                TriggerClientEvent("Renewed-Banking:client:sendNotification", source, {
                    message = locale("not_enough_money"),
                    title = locale("bank_name"),
                    type = "error"
                })
                return false
            end
        end
    else
        local funds = GetFunds(Player)
        if cachedAccounts[data.stateid] then
            if funds.bank >= amount and RemoveMoney(Player, amount, 'bank', data.comment) then
                AddAccountMoney(data.stateid, amount)
                local transaction = handleTransaction(data.fromAccount, locale("personal_acc") .. data.fromAccount, amount, data.comment, name, cachedAccounts[data.stateid].name, "withdraw")
                handleTransaction(data.stateid, locale("personal_acc") .. data.fromAccount, amount, data.comment, name, cachedAccounts[data.stateid].name, "deposit", transaction.trans_id)
            else
                TriggerClientEvent("Renewed-Banking:client:sendNotification", source, {
                    message = locale("not_enough_money"),
                    title = locale("bank_name"),
                    type = "error"
                })
                return false
            end
        else
            local Player2 = getPlayerData(source, data.stateid)
            if not Player2 then
                TriggerClientEvent("Renewed-Banking:client:sendNotification", source, {
                    message = locale("fail_transfer"),
                    title = locale("bank_name"),
                    type = "error"
                })
                return false
            end

            if funds.bank >= amount and RemoveMoney(Player, amount, 'bank', data.comment) then
                AddMoney(Player2, amount, 'bank', data.comment)
                local name2 = GetCharacterName(Player2)
                local transaction = handleTransaction(data.fromAccount, locale("personal_acc") .. data.fromAccount, amount, data.comment, name, name2, "withdraw")
                handleTransaction(data.stateid, locale("personal_acc") .. data.fromAccount, amount, data.comment, name, name2, "deposit", transaction.trans_id)
            else
                TriggerClientEvent("Renewed-Banking:client:sendNotification", source, {
                    message = locale("not_enough_money"),
                    title = locale("bank_name"),
                    type = "error"
                })
                return false
            end
        end
    end
    local bankData = getBankData(source)
    return bankData
end)

-- Account Management Events
RegisterNetEvent('Renewed-Banking:server:createNewAccount', function(accountid)
    local Player = GetPlayerObject(source)
    if cachedAccounts[accountid] then return Notify(source, {title = locale("bank_name"), description = locale("account_taken"), type = "error"}) end
    local cid = GetIdentifier(Player)
    cachedAccounts[accountid] = {
        id = accountid,
        type = locale("org"),
        name = accountid,
        frozen = 0,
        amount = 0,
        transactions = {},
        auth = { [cid] = true },
        creator = cid
    }
    cachedPlayers[cid].accounts[#cachedPlayers[cid].accounts+1] = accountid
    MySQL.insert("INSERT INTO bank_accounts_new (id, amount, transactions, auth, isFrozen, creator) VALUES (?, ?, ?, ?, ?, ?) ",{
        accountid, cachedAccounts[accountid].amount, json.encode(cachedAccounts[accountid].transactions), json.encode({cid}), cachedAccounts[accountid].frozen, cid
    })
end)

lib.callback.register('Renewed-Banking:server:getPlayerAccounts', function(source)
    print("=== GET PLAYER ACCOUNTS CALLBACK ===")
    print("Source: " .. tostring(source))
    
    local Player = GetPlayerObject(source)
    if not Player then
        print("ERROR: Could not get player object")
        return {}
    end
    
    local cid = GetIdentifier(Player)
    if not cid then
        print("ERROR: Could not get player identifier")
        return {}
    end
    
    print("Player CID: " .. tostring(cid))
    
    if not cachedPlayers[cid] then
        print("Player not in cache, updating...")
        UpdatePlayerAccount(cid)
    end
    
    if not cachedPlayers[cid] or not cachedPlayers[cid].accounts then
        print("No accounts found for player")
        return {}
    end
    
    local accounts = cachedPlayers[cid].accounts
    local data = {}
    
    print("Player has " .. tostring(#accounts) .. " shared accounts")
    
    if #accounts >= 1 then
        for k=1, #accounts do
            local accountId = accounts[k]
            print("Checking account: " .. tostring(accountId))
            
            if cachedAccounts[accountId] then
                local creator = cachedAccounts[accountId].creator
                print("  Account creator: " .. tostring(creator))
                print("  Player CID: " .. tostring(cid))
                
                if creator == cid then
                    table.insert(data, accountId)
                    print("  Added to list (player is creator)")
                else
                    print("  Skipped (player is not creator)")
                end
            else
                print("  Account not found in cache: " .. tostring(accountId))
            end
        end
    end
    
    print("Returning " .. tostring(#data) .. " accounts:")
    for i, account in ipairs(data) do
        print("  " .. i .. ": " .. tostring(account))
    end
    
    print("=== END GET PLAYER ACCOUNTS ===")
    return data
end)

-- Create a callback version for synchronous member management
lib.callback.register('Renewed-Banking:server:getMemberManagement', function(source, data)
    print("=== GET MEMBER MANAGEMENT CALLBACK ===")
    print("Source: " .. tostring(source))
    print("Data: " .. (data and json.encode(data) or "nil"))
    
    local Player = GetPlayerObject(source)
    if not Player then
        print("ERROR: Could not get player object")
        return {account = data.account, members = {}}
    end

    local account = data and data.account
    if not account then
        print("ERROR: No account specified")
        return {members = {}}
    end
    
    local retData = {
        account = account,
        members = {}
    }
    local cid = GetIdentifier(Player)

    print("Account: " .. tostring(account))
    print("Requesting player: " .. tostring(cid))

    -- Check if account exists
    if not cachedAccounts or not cachedAccounts[account] then
        print("ERROR: Account does not exist: " .. tostring(account))
        return retData
    end

    print("Account found!")
    print("Account creator: " .. tostring(cachedAccounts[account].creator))

    -- Check if player is authorized to view members
    if cid ~= cachedAccounts[account].creator then
        print("ERROR: Player not authorized to view members")
        return retData
    end

    print("Player authorized!")

    -- Process members
    if cachedAccounts[account].auth then
        print("Processing auth members...")
        for memberId, _ in pairs(cachedAccounts[account].auth) do
            print("Processing member: " .. tostring(memberId))
            
            -- Skip the account creator from the member list
            if memberId ~= cid then
                print("  Member is not creator, adding to list")
                local memberName = "Unknown Player"
                
                -- Try to get online player first
                local Player2 = GetPlayerObjectFromID(memberId)
                if Player2 then
                    memberName = GetCharacterName(Player2)
                    print("    Found online: " .. tostring(memberName))
                else
                    print("    Player offline, checking database...")
                    -- Get name from database for offline player
                    if Framework == 'qb' or Framework == 'qbx' then
                        local success, result = pcall(function()
                            return MySQL.query.await('SELECT charinfo FROM players WHERE citizenid = ?', {memberId})
                        end)
                        
                        if success and result and #result > 0 then
                            if result[1].charinfo and result[1].charinfo ~= '' then
                                local charSuccess, charinfo = pcall(json.decode, result[1].charinfo)
                                if charSuccess and charinfo and charinfo.firstname and charinfo.lastname then
                                    memberName = tostring(charinfo.firstname) .. " " .. tostring(charinfo.lastname)
                                end
                            end
                        end
                    elseif Framework == 'esx' then
                        local success, result = pcall(function()
                            return MySQL.query.await('SELECT firstname, lastname FROM users WHERE identifier = ?', {memberId})
                        end)
                        
                        if success and result and #result > 0 then
                            if result[1].firstname and result[1].lastname then
                                memberName = tostring(result[1].firstname) .. " " .. tostring(result[1].lastname)
                            end
                        end
                    end
                    print("    Found offline: " .. tostring(memberName))
                end
                
                retData.members[memberId] = memberName
                print("    Added member: " .. tostring(memberId) .. " = " .. tostring(memberName))
            else
                print("  Skipping creator: " .. tostring(memberId))
            end
        end
    else
        print("No auth table found for account")
    end

    print("=== FINAL RESULT ===")
    local memberCount = 0
    for id, name in pairs(retData.members) do
        memberCount = memberCount + 1
        print("  Member " .. memberCount .. ": " .. tostring(id) .. " = " .. tostring(name))
    end
    print("Total members returning: " .. memberCount)
    print("=== END GET MEMBER MANAGEMENT ===")

    return retData
end)

RegisterNetEvent("Renewed-Banking:server:viewMemberManagement", function(data)
    local Player = GetPlayerObject(source)
    local account = data.account
    local retData = {
        account = account,
        members = {}
    }
    local cid = GetIdentifier(Player)

    for k,_ in pairs(cachedAccounts[account].auth) do
        local Player2 = getPlayerData(source, k)
        if cid ~= GetIdentifier(Player2) then
            retData.members[k] = GetCharacterName(Player2)
        end
    end

    TriggerClientEvent("Renewed-Banking:client:viewMemberManagement", source, retData)
end)

RegisterNetEvent('Renewed-Banking:server:addAccountMember', function(account, member)
    local Player = GetPlayerObject(source)
    local playerCid = GetIdentifier(Player)

    -- Validate inputs
    if not account or not member then
        Notify(source, {
            title = locale("bank_name") or "Banking", 
            description = "Invalid account or member ID provided", 
            type = "error"
        })
        return
    end

    -- Clean up the member ID (remove spaces, make uppercase for QB frameworks)
    member = string.gsub(tostring(member), "%s+", "")
    if Framework == 'qb' or Framework == 'qbx' then
        member = string.upper(member)
    end

    print("DEBUG: Looking for CID: " .. tostring(member) .. " (Framework: " .. tostring(Framework) .. ")")

    -- Check if trying to add their own ID
    if member == playerCid then
        Notify(source, {
            title = locale("bank_name") or "Banking", 
            description = "You cannot add yourself to the account", 
            type = "error"
        })
        return
    end

    -- Check if the account exists
    if not cachedAccounts[account] then
        Notify(source, {
            title = locale("bank_name") or "Banking", 
            description = "Account does not exist", 
            type = "error"
        })
        return
    end

    -- Check if the player is the account creator
    if playerCid ~= cachedAccounts[account].creator then 
        print((locale and locale("illegal_action", GetPlayerName(source))) or ("Illegal action by " .. GetPlayerName(source))) 
        Notify(source, {
            title = locale("bank_name") or "Banking", 
            description = "You are not authorized to add members to this account", 
            type = "error"
        })
        return 
    end

    -- Check if the CID exists in the database and get player info
    local playerExists = false
    local Player2 = nil
    local playerName = "Unknown Player"
    
    -- First try to get online player
    Player2 = GetPlayerObjectFromID(member)
    if Player2 then
        playerExists = true
        playerName = GetCharacterName(Player2)
        print("DEBUG: Found online player: " .. tostring(playerName))
    else
        print("DEBUG: Player not online, checking database...")
        -- Check if the CID exists in the database (for offline players)
        local result = nil
        
        if Framework == 'qb' or Framework == 'qbx' then
            -- For QB frameworks, check players table
            result = MySQL.query.await('SELECT citizenid, charinfo FROM players WHERE citizenid = ?', {member})
            print("DEBUG: QB Query result count: " .. tostring(result and #result or 0))
            
            if result and #result > 0 then
                playerExists = true
                -- Try to get character name
                if result[1].charinfo and result[1].charinfo ~= '' then
                    local success, charinfo = pcall(json.decode, result[1].charinfo)
                    if success and charinfo and charinfo.firstname and charinfo.lastname then
                        playerName = tostring(charinfo.firstname) .. " " .. tostring(charinfo.lastname)
                    end
                end
                print("DEBUG: Found offline QB player: " .. tostring(playerName))
            end
        elseif Framework == 'esx' then
            -- For ESX, check users table
            result = MySQL.query.await('SELECT identifier, firstname, lastname FROM users WHERE identifier = ?', {member})
            print("DEBUG: ESX Query result count: " .. tostring(result and #result or 0))
            
            if result and #result > 0 then
                playerExists = true
                if result[1].firstname and result[1].lastname then
                    playerName = tostring(result[1].firstname) .. " " .. tostring(result[1].lastname)
                end
                print("DEBUG: Found offline ESX player: " .. tostring(playerName))
            end
        else
            print("DEBUG: Unknown framework: " .. tostring(Framework))
        end
    end

    print("DEBUG: Player exists: " .. tostring(playerExists))

    -- If CID doesn't exist at all
    if not playerExists then
        Notify(source, {
            title = locale("bank_name") or "Banking", 
            description = "Citizen ID '" .. tostring(member) .. "' does not exist in the database", 
            type = "error"
        })
        print("DEBUG: CID not found in database: " .. tostring(member))
        return
    end

    -- Check if player is already a member
    if cachedAccounts[account].auth and cachedAccounts[account].auth[member] then
        Notify(source, {
            title = locale("bank_name") or "Banking", 
            description = "Player is already a member of this account", 
            type = "error"
        })
        return
    end

    -- Initialize player cache if it doesn't exist (for offline players)
    if not cachedPlayers[member] then
        print("DEBUG: Initializing player cache for: " .. tostring(member))
        UpdatePlayerAccount(member)
    end

    -- Add the account to the player's account list
    if cachedPlayers[member] and cachedPlayers[member].accounts then
        cachedPlayers[member].accounts[#cachedPlayers[member].accounts+1] = account
    end

    -- Build the auth array for database update
    local auth = {}
    if cachedAccounts[account].auth then
        for k in pairs(cachedAccounts[account].auth) do 
            auth[#auth+1] = k 
        end
    end
    auth[#auth+1] = member
    
    -- Update the cached account auth
    if not cachedAccounts[account].auth then
        cachedAccounts[account].auth = {}
    end
    cachedAccounts[account].auth[member] = true
    
    -- Update the database
    MySQL.update('UPDATE bank_accounts_new SET auth = ? WHERE id = ?', {json.encode(auth), account})
    
    print("DEBUG: Successfully added " .. tostring(member) .. " to account " .. tostring(account))
    
    -- Notify success
    Notify(source, {
        title = locale("bank_name") or "Banking", 
        description = "Member " .. tostring(playerName) .. " (" .. tostring(member) .. ") added successfully", 
        type = "success"
    })
    
    -- Notify the added player if they're online
    if Player2 then
        local targetSource = Player2.source or Player2.PlayerId or (Player2.PlayerData and Player2.PlayerData.source)
        if targetSource then
            Notify(targetSource, {
                title = locale("bank_name") or "Banking", 
                description = "You have been added to a shared account: " .. tostring(account), 
                type = "success"
            })
        end
    end
end)

RegisterNetEvent('Renewed-Banking:server:removeAccountMember', function(data)
    local Player = GetPlayerObject(source)
    if not Player then
        print("ERROR: Could not get player object for removeAccountMember")
        return
    end

    local playerCid = GetIdentifier(Player)
    local account = data.account
    local memberToRemove = data.cid

    print("=== REMOVE MEMBER PROCESS ===")
    print("Account: " .. tostring(account))
    print("Member to remove: " .. tostring(memberToRemove))
    print("Requesting player: " .. tostring(playerCid))

    -- Check if account exists
    if not cachedAccounts[account] then
        print("ERROR: Account does not exist")
        Notify(source, {
            title = "Banking",
            message = "Account does not exist",
            type = "error"
        })
        return
    end

    -- Check if player is the account creator
    if playerCid ~= cachedAccounts[account].creator then 
        print("ERROR: Player not authorized - Creator: " .. tostring(cachedAccounts[account].creator))
        Notify(source, {
            title = "Banking",
            message = "You are not authorized to remove members from this account",
            type = "error"
        })
        return 
    end

    -- Check if member exists in auth list
    if not cachedAccounts[account].auth or not cachedAccounts[account].auth[memberToRemove] then
        print("ERROR: Member not found in account auth list")
        Notify(source, {
            title = "Banking",
            message = "Member not found in account",
            type = "error"
        })
        return
    end

    -- Build new auth array without the removed member
    local newAuth = {}
    for k in pairs(cachedAccounts[account].auth) do
        if k ~= memberToRemove then
            table.insert(newAuth, k)
        end
    end

    -- Remove from player's account list if they're in cache
    if cachedPlayers[memberToRemove] and cachedPlayers[memberToRemove].accounts then
        local newAccountList = {}
        for i, accountId in ipairs(cachedPlayers[memberToRemove].accounts) do
            if accountId ~= account then
                table.insert(newAccountList, accountId)
            end
        end
        cachedPlayers[memberToRemove].accounts = newAccountList
        print("Removed account from player's cached account list")
    end

    -- Update cached account auth
    cachedAccounts[account].auth[memberToRemove] = nil
    
    -- Update database
    local success, err = pcall(function()
        MySQL.update('UPDATE bank_accounts_new SET auth = ? WHERE id = ?', {json.encode(newAuth), account})
    end)
    
    if not success then
        print("ERROR: Database update failed: " .. tostring(err))
        Notify(source, {
            title = "Banking",
            message = "Database error occurred",
            type = "error"
        })
        return
    end

    print("SUCCESS: Member removed from account")
    print("New auth list: " .. json.encode(newAuth))

    Notify(source, {
        title = "Banking",
        message = "Member removed successfully",
        type = "success"
    })

    -- Notify the removed player if they're online
    local RemovedPlayer = GetPlayerObjectFromID(memberToRemove)
    if RemovedPlayer then
        local targetSource = RemovedPlayer.source or RemovedPlayer.PlayerId or (RemovedPlayer.PlayerData and RemovedPlayer.PlayerData.source)
        if targetSource then
            Notify(targetSource, {
                title = "Banking",
                message = "You have been removed from shared account: " .. tostring(account),
                type = "info"
            })
        end
    end
end)

RegisterNetEvent('Renewed-Banking:server:deleteAccount', function(data)
    local account = data.account
    local Player = GetPlayerObject(source)
    local cid = GetIdentifier(Player)

    cachedAccounts[account] = nil

    for k=1, #cachedPlayers[cid].accounts do
        if cachedPlayers[cid].accounts[k] == account then
            cachedPlayers[cid].accounts[k] = nil
        end
    end

    MySQL.update("DELETE FROM `bank_accounts_new` WHERE id=:id", { id = account })
end)

-- Account Name Change
local find = string.find
local sub = string.sub
local function split(str, delimiter)
    local result = {}
    local from = 1
    local delim_from, delim_to = find(str, delimiter, from)
    while delim_from do
        result[#result + 1] = sub(str, from, delim_from - 1)
        from = delim_to + 1
        delim_from, delim_to = find(str, delimiter, from)
    end
    result[#result + 1] = sub(str, from)
    return result
end

local function updateAccountName(account, newName, src)
    if not account or not newName then return false end
    if not cachedAccounts[account] then
        local getTranslation = locale("invalid_account", account)
        print(getTranslation)
        if src then Notify(src, {title = locale("bank_name"), description = split(getTranslation, '0')[2], type = "error"}) end
        return false
    end
    if cachedAccounts[newName] then
        local getTranslation = locale("existing_account", account)
        print(getTranslation)
        if src then Notify(src, {title = locale("bank_name"), description = split(getTranslation, '0')[2], type = "error"}) end
        return false
    end
    if src then
        local Player = GetPlayerObject(src)
        if GetIdentifier(Player) ~= cachedAccounts[account].creator then
            local getTranslation = locale("illegal_action", GetPlayerName(src))
            print(getTranslation)
            Notify(src, {title = locale("bank_name"), description = split(getTranslation, '0')[2], type = "error"})
            return false
        end
    end

    cachedAccounts[newName] = json.decode(json.encode(cachedAccounts[account]))
    cachedAccounts[newName].id = newName
    cachedAccounts[newName].name = newName
    cachedAccounts[account] = nil
    for _, id in ipairs(GetPlayers()) do
        local Player2 = GetPlayerObject(id)
        if not Player2 then goto Skip end
        local cid = GetIdentifier(Player2)
        if #cachedPlayers[cid].accounts >= 1 then
            for k=1, #cachedPlayers[cid].accounts do
                if cachedPlayers[cid].accounts[k] == account then
                    table.remove(cachedPlayers[cid].accounts, k)
                    cachedPlayers[cid].accounts[#cachedPlayers[cid].accounts+1] = newName
                end
            end
        end
        ::Skip::
    end
    MySQL.update('UPDATE bank_accounts_new SET id = ? WHERE id = ?',{newName, account})
    return true
end

RegisterNetEvent('Renewed-Banking:server:changeAccountName', function(account, newName)
    updateAccountName(account, newName, source)
end)

-- Job Account Management
function GetJobAccount(jobName)
    if type(jobName) ~= "string" or jobName == "" then
        error(("^5[%s]^7-^1[ERROR]^7 %s"):format(GetInvokingResource(), "Invalid job name: expected a non-empty string"))
    end
    return cachedAccounts[jobName] or nil
end

local function CreateJobAccount(job, initialBalance)
    local currentResourceName = GetInvokingResource()

    if type(job) ~= "table" then
        error(("^5[%s]^7-^1[ERROR]^7 %s"):format(currentResourceName, "Invalid parameter: expected a table (job)"))
    end

    if type(job.name) ~= "string" or job.name == "" then
        error(("^5[%s]^7-^1[ERROR]^7 %s"):format(currentResourceName, "Invalid job name: expected a non-empty string"))
    end

    if type(job.label) ~= "string" or job.label == "" then
        error(("^5[%s]^7-^1[ERROR]^7 %s"):format(currentResourceName, "Invalid job label: expected a non-empty string"))
    end
    
    if cachedAccounts[job.name] then
        return cachedAccounts[job.name]
    end

    cachedAccounts[job.name] = {
        id = job.name,
        type = locale("org"),
        name = job.label,
        frozen = 0,
        amount = tonumber(initialBalance) or 0,
        transactions = {},
        auth = {},
        creator = nil
    }

    local insertId = MySQL.insert.await("INSERT INTO bank_accounts_new (id, amount, transactions, auth, isFrozen, creator) VALUES (?, ?, ?, ?, ?, NULL)", {
        job.name,
        cachedAccounts[job.name].amount,
        json.encode(cachedAccounts[job.name].transactions),
        json.encode(cachedAccounts[job.name].auth),
        cachedAccounts[job.name].frozen
    })

    if not insertId then
        cachedAccounts[job.name] = nil
        error(("^5[%s]^7-^1[ERROR]^7 %s"):format(currentResourceName, "Database error"))
    end

    return cachedAccounts[job.name]
end

local function addAccountMember(account, member)
    if not account or not member then 
        print("addAccountMember: Missing account or member parameter")
        return false
    end

    member = string.gsub(member, "%s+", "")
    if Framework == 'qb' or Framework == 'qbx' then
        member = string.upper(member)
    end

    if not cachedAccounts[account] then 
        print(locale("invalid_account", account)) 
        return false
    end

    local playerExists = false
    local Player2 = nil
    
    Player2 = GetPlayerObjectFromID(member)
    if Player2 then
        playerExists = true
    else
        local result = nil
        if Framework == 'qb' or Framework == 'qbx' then
            result = MySQL.query.await('SELECT citizenid FROM players WHERE citizenid = ?', {member})
        elseif Framework == 'esx' then
            result = MySQL.query.await('SELECT identifier FROM users WHERE identifier = ?', {member})
        end
        
        if result and #result > 0 then
            playerExists = true
        end
    end

    if not playerExists then
        print("addAccountMember: Citizen ID does not exist in database: " .. tostring(member))
        return false
    end
    
    if cachedAccounts[account].auth[member] then
        print("addAccountMember: Player is already a member of account: " .. account)
        return false
    end

    if not cachedPlayers[member] then
        UpdatePlayerAccount(member)
    end

    if cachedPlayers[member] then
        cachedPlayers[member].accounts[#cachedPlayers[member].accounts+1] = account
    end

    local auth = {}
    for k, _ in pairs(cachedAccounts[account].auth) do 
        auth[#auth+1] = k 
    end
    auth[#auth+1] = member
    
    cachedAccounts[account].auth[member] = true
    
    MySQL.update('UPDATE bank_accounts_new SET auth = ? WHERE id = ?', {json.encode(auth), account})
    
    print("addAccountMember: Successfully added " .. member .. " to account " .. account)
    return true
end

local function removeAccountMember(account, member)
    local Player2 = getPlayerData(false, member)

    if not Player2 then return end
    if not cachedAccounts[account] then print(locale("invalid_account", account)) return end

    local targetCID = GetIdentifier(Player2)

    local tmp = {}
    for k in pairs(cachedAccounts[account].auth) do
        if targetCID ~= k then
            tmp[#tmp+1] = k
        end
    end

    if cachedPlayers[targetCID] then
        local newAccount = {}
        if #cachedPlayers[targetCID].accounts >= 1 then
            for k=1, #cachedPlayers[targetCID].accounts do
                if cachedPlayers[targetCID].accounts[k] ~= account then
                    newAccount[#newAccount+1] = cachedPlayers[targetCID].accounts[k]
                end
            end
        end
        cachedPlayers[targetCID].accounts = newAccount
    end

    cachedAccounts[account].auth[targetCID] = nil

    MySQL.update('UPDATE bank_accounts_new SET auth = ? WHERE id = ?',{json.encode(tmp), account})
end

-- Debug command to check account data
RegisterCommand('checkaccount', function(source, args)
    if source == 0 then -- Server console only
        local accountName = args[1]
        if not accountName then
            print("Usage: checkaccount <account_name>")
            return
        end
        
        print("=== ACCOUNT DEBUG: " .. accountName .. " ===")
        
        -- Check cached data
        if cachedAccounts[accountName] then
            print("CACHED DATA:")
            print("  ID: " .. tostring(cachedAccounts[accountName].id))
            print("  Name: " .. tostring(cachedAccounts[accountName].name))
            print("  Creator: " .. tostring(cachedAccounts[accountName].creator))
            print("  Amount: " .. tostring(cachedAccounts[accountName].amount))
            
            if cachedAccounts[accountName].auth then
                print("  Auth members:")
                for k, v in pairs(cachedAccounts[accountName].auth) do
                    print("    " .. tostring(k) .. " = " .. tostring(v))
                end
            else
                print("  Auth: nil")
            end
        else
            print("CACHED DATA: Account not found")
        end
        
        -- Check database data
        local result = MySQL.query.await('SELECT * FROM bank_accounts_new WHERE id = ?', {accountName})
        if result and #result > 0 then
            print("DATABASE DATA:")
            print("  ID: " .. tostring(result[1].id))
            print("  Amount: " .. tostring(result[1].amount))
            print("  Creator: " .. tostring(result[1].creator))
            print("  Auth (raw): " .. tostring(result[1].auth))
            
            local authData = json.decode(result[1].auth)
            if authData then
                print("  Auth (decoded):")
                for i, member in ipairs(authData) do
                    print("    " .. i .. ": " .. tostring(member))
                end
            else
                print("  Auth: Failed to decode")
            end
        else
            print("DATABASE DATA: Account not found")
        end
        
        print("=== END ACCOUNT DEBUG ===")
    end
end, true)

-- Cash Command
lib.addCommand('givecash', {
    help = 'Gives cash to a player',
    params = {
        {
            name = 'target',
            type = 'playerId',
            help = locale("cmd_plyr_id"),
        },
        {
            name = 'amount',
            type = 'number',
            help = locale("cmd_amount"),
        }
    }
}, function(source, args)
    local Player = GetPlayerObject(source)
    if not Player then return end

    local iPlayer = GetPlayerObject(args.target)
    if not iPlayer then return Notify(source, {title = locale("bank_name"), description = locale('unknown_player', args.target), type = "error"}) end

    if IsDead(Player) then return Notify(source, {title = locale("bank_name"), description = locale('dead'), type = "error"}) end
    if #(GetEntityCoords(GetPlayerPed(source)) - GetEntityCoords(GetPlayerPed(args.target))) > 10.0 then return Notify(source, {title = locale("bank_name"), description = locale('too_far_away'), type = "error"}) end
    if args.amount < 0 then return Notify(source, {title = locale("bank_name"), description = locale('invalid_amount', "give"), type = "error"}) end

    if RemoveMoney(Player, args.amount, 'cash') then
        AddMoney(iPlayer, args.amount, 'cash')
        local nameA = GetCharacterName(Player)
        local nameB = GetCharacterName(iPlayer)
        Notify(source, {title = locale("bank_name"), description = locale('give_cash', nameB, tostring(args.amount)), type = "success"})
        Notify(args.target, {title = locale("bank_name"), description = locale('received_cash', nameA, tostring(args.amount)), type = "success"})
    else
        Notify(source, {title = locale("bank_name"), description = locale('not_enough_money'), type = "error"})
    end
end)

-- Database Tables Creation
local createTables = {
    { query = "CREATE TABLE IF NOT EXISTS `bank_accounts_new` (`id` varchar(50) NOT NULL, `amount` int(11) DEFAULT 0, `transactions` longtext DEFAULT '[]', `auth` longtext DEFAULT '[]', `isFrozen` int(11) DEFAULT 0, `creator` varchar(50) DEFAULT NULL, PRIMARY KEY (`id`));", values = nil },
    { query = "CREATE TABLE IF NOT EXISTS `player_transactions` (`id` varchar(50) NOT NULL, `isFrozen` int(11) DEFAULT 0, `transactions` longtext DEFAULT '[]', PRIMARY KEY (`id`));", values = nil }
}

assert(MySQL.transaction.await(createTables), "Failed to create tables")

-- Main Events
RegisterNetEvent('Renewed-Banking:server:getBankData', function()
    local source = source
    local bankData = getBankData(source)
    TriggerClientEvent('Renewed-Banking:client:receiveBankData', source, bankData)
end)

-- Exports
exports("handleTransaction", handleTransaction)
exports('getAccountMoney', GetAccountMoney)
exports('addAccountMoney', AddAccountMoney)
exports('removeAccountMoney', RemoveAccountMoney)
exports("changeAccountName", updateAccountName)
exports('GetJobAccount', GetJobAccount)
exports("CreateJobAccount", CreateJobAccount)
exports("addAccountMember", addAccountMember)
exports("removeAccountMember", removeAccountMember)
exports("getAccountTransactions", getAccountTransactions)