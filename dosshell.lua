local w, h = term.getSize()
local currentPath = "/"   -- absolute path with leading "/"
local selectedList = "dirs"
local selDir, selFile = 1, 1
local dirs, files = {}, {}
local mouseX, mouseY = 1, 1
local lastClickTime, lastClickButton = 0, 0
local showMenu = false
local errorMsg = ""          -- current error message
local errorMsgExpire = 0     -- time (ms) when message expires

-- Display error message for 3 seconds
local function setError(msg)
    errorMsg = msg
    errorMsgExpire = os.epoch("utc") + 3000
end

-- Safe refresh of lists
local function refresh()
    local ok, all = pcall(fs.list, currentPath)
    if not ok then
        currentPath = "/"
        ok, all = pcall(fs.list, currentPath)
        if not ok then
            setError("Directory access error")
            dirs, files = { ".." }, {}
            return
        end
    end
    dirs, files = { ".." }, {}
    table.sort(all)
    for _, name in ipairs(all) do
        local fullPath = fs.combine(currentPath, name)
        if fs.isDir(fullPath) then
            table.insert(dirs, name)
        else
            table.insert(files, name)
        end
    end
    if selDir > #dirs then selDir = #dirs end
    if selDir < 1 then selDir = 1 end
    if selFile > #files then selFile = #files end
    if selFile < 1 then selFile = 1 end
end

-- Input dialog
local function inputDialog(prompt)
    term.setCursorPos(1, h)
    term.setBackgroundColor(colors.blue)
    term.setTextColor(colors.white)
    term.clearLine()
    term.write(prompt .. ": ")
    local result = read()
    return result
end

-- Confirm dialog (yes/no)
local function confirmDialog(msg)
    term.setCursorPos(1, h)
    term.setBackgroundColor(colors.blue)
    term.setTextColor(colors.white)
    term.clearLine()
    term.write(msg .. " (y/N): ")
    local result = read():lower()
    return result == "y" or result == "yes"
end

-- Safe command execution with optional working directory
local function safeRun(command, description, workingDir)
    local ok, err
    local oldDir = nil
    if workingDir then
        oldDir = shell.dir()
        shell.setDir(workingDir)
    end
    ok, err = pcall(shell.run, command)
    if not ok then
        setError(string.format("Error while %s: %s", description or "running", err))
    end
    if oldDir then
        shell.setDir(oldDir)
    end
    return ok
end

-- Execute action (open folder / run file)
local function executeAction()
    if selectedList == "dirs" then
        local target = dirs[selDir]
        if target == ".." then
            if currentPath == "/" then
                currentPath = "/"
            else
                currentPath = fs.getDir(currentPath)
                if currentPath == "" then currentPath = "/" end
            end
        else
            currentPath = fs.combine(currentPath, target)
        end
        selDir, selFile = 1, 1
        refresh()
    else
        if #files > 0 then
            local fullPath = fs.combine(currentPath, files[selFile])
            term.setBackgroundColor(colors.black); term.setTextColor(colors.white)
            term.clear(); term.setCursorPos(1, 1)
            local ok = safeRun(fullPath, "running file")
            if not ok then
                print("\n" .. errorMsg)
            else
                print("\nPress any key to return...")
            end
            os.pullEvent("key")
            refresh()
        end
    end
end

-- Handle File menu actions (also used by hotkeys)
local function handleFileAction(actionIdx)
    if actionIdx == 1 then -- Open
        executeAction()
    elseif actionIdx == 2 then -- Run (manual command)
        local cmd = inputDialog("Command")
        if cmd and cmd ~= "" then
            term.setBackgroundColor(colors.black); term.setTextColor(colors.white)
            term.clear(); term.setCursorPos(1, 1)
            if not safeRun(cmd, "executing command", currentPath) then
                print("\n" .. errorMsg)
            else
                print("\nPress any key to return...")
            end
            os.pullEvent("key")
        end
    elseif actionIdx == 3 then -- Move
        local name = (selectedList == "dirs") and dirs[selDir] or files[selFile]
        if not name then setError("Nothing selected"); refresh(); return end
        local src = fs.combine(currentPath, name)
        local dest = inputDialog("Move to")
        if dest and dest ~= "" then
            -- resolve destination absolute path
            if dest:sub(1,1) == "/" then
                dest = dest
            else
                dest = fs.combine(currentPath, dest)
            end
            local ok, err = pcall(fs.move, src, dest)
            if not ok then setError("Move: " .. err) end
        end
    elseif actionIdx == 4 then -- Copy
        local name = (selectedList == "dirs") and dirs[selDir] or files[selFile]
        if not name then setError("Nothing selected"); refresh(); return end
        local src = fs.combine(currentPath, name)
        local dest = inputDialog("Copy to")
        if dest and dest ~= "" then
            if dest:sub(1,1) == "/" then
                dest = dest
            else
                dest = fs.combine(currentPath, dest)
            end
            local ok, err = pcall(fs.copy, src, dest)
            if not ok then setError("Copy: " .. err) end
        end
    elseif actionIdx == 5 then -- Delete
        local name = (selectedList == "dirs") and dirs[selDir] or files[selFile]
        if not name then setError("Nothing selected"); refresh(); return end
        if name == ".." then setError("Cannot delete '..'"); return end
        if confirmDialog("Delete " .. name .. "?") then
            local path = fs.combine(currentPath, name)
            local ok, err = pcall(fs.delete, path)
            if not ok then setError("Delete: " .. err) end
        end
    elseif actionIdx == 6 then -- Rename
        local name = (selectedList == "dirs") and dirs[selDir] or files[selFile]
        if not name then setError("Nothing selected"); refresh(); return end
        local src = fs.combine(currentPath, name)
        local newName = inputDialog("New name")
        if newName and newName ~= "" then
            local dest = fs.combine(currentPath, newName)
            local ok, err = pcall(fs.move, src, dest)
            if not ok then setError("Rename: " .. err) end
        end
    elseif actionIdx == 7 then -- Create Dir
        local folder = inputDialog("Folder name")
        if folder and folder ~= "" then
            local path = fs.combine(currentPath, folder)
            local ok, err = pcall(fs.makeDir, path)
            if not ok then setError("Create folder: " .. err) end
        end
    end
    showMenu = false
    refresh()
end

-- Draw interface
local function draw()
    term.setBackgroundColor(colors.white)
    term.clear()
    
    -- Blue header
    term.setCursorPos(1, 1)
    term.setPaletteColor(colors.blue, 0x1e1d8f)
    term.setBackgroundColor(colors.blue)
    term.setTextColor(colors.white)
    term.clearLine()
    local title = "   MC-DOS Shell "
    term.setCursorPos(math.floor((w - #title) / 2), 1)
    term.write(title)
    
    -- Top menu
    term.setCursorPos(1, 2)
    term.setBackgroundColor(colors.white)
    term.setTextColor(colors.black)
    term.clearLine()
    term.write(" File  Options  View  Tree  Help")
    
    -- Path (convert UNIX style to DOS)
    local displayPath = " C:\\"
    if currentPath == "/" then
        displayPath = displayPath .. ""
    else
        displayPath = displayPath .. currentPath:sub(2):gsub("/", "\\")
    end
    term.setCursorPos(1, 3)
    term.write(displayPath)
    
    term.setBackgroundColor(colors.lightGray)
    term.setTextColor(colors.black)
    term.setCursorPos(1, 5)
    term.clearLine()
    term.setCursorPos(3, 5); term.write("Directory Tree")
    local split = math.floor(w/2)
    term.setCursorPos(split + 3, 5); term.write("Files")

    -- Borders
    term.setBackgroundColor(colors.gray)
    for i = 6, h-1 do
        term.setCursorPos(1, i); term.write(" ")
        term.setCursorPos(split, i); term.write(" ")
        term.setCursorPos(w, i); term.write(" ")
    end

    -- Directories
    for i, name in ipairs(dirs) do
        if i > h-8 then break end
        term.setCursorPos(2, i + 5)
        if selectedList == "dirs" and i == selDir then
            term.setBackgroundColor(colors.gray); term.setTextColor(colors.white)
        else
            term.setBackgroundColor(colors.white); term.setTextColor(colors.black)
        end
        local text = "-[+] " .. name
        term.write(string.sub(text .. string.rep(" ", split), 1, split - 2))
    end

    -- Files
    for i, name in ipairs(files) do
        if i > h-8 then break end
        term.setCursorPos(split + 1, i + 5)
        if selectedList == "files" and i == selFile then
            term.setBackgroundColor(colors.gray); term.setTextColor(colors.white)
        else
            term.setBackgroundColor(colors.white); term.setTextColor(colors.black)
        end
        local text = " " .. name
        term.write(string.sub(text .. string.rep(" ", w), 1, w - split - 1))
    end

    if showMenu then
        local items = {"Open - Enter", "Run - F5", "Move - F7", "Copy - F8", "Delete - Del", "Rename - F9", "Create Dir - N"}
        local menuWidth = 14
        local startX = 2
        local startY = 3
        local count = #items

        term.setBackgroundColor(colors.lightGray)
        
        -- Shadow
        for i = 1, count do
            term.setCursorPos(startX + menuWidth, startY + i)
            term.write(" ")
        end
        term.setCursorPos(startX + 2, startY + count)
        term.write(string.rep(" ", 12))

        -- Menu
        term.setBackgroundColor(colors.white)
        term.setTextColor(colors.black)
        for i, item in ipairs(items) do
            term.setCursorPos(startX, startY + i - 1)
            local line = " " .. item
            term.write(line .. string.rep(" ", menuWidth - #line))
        end
    end

    -- Bottom line: hints + error message
    term.setCursorPos(1, h)
    term.setBackgroundColor(colors.lightGray); term.setTextColor(colors.black)
    term.clearLine()
    local hints = " F1=Menu F3=Exit Tab=Switch Enter=Open/Run"
    term.write(hints)
    if errorMsg ~= "" and os.epoch("utc") < errorMsgExpire then
        term.setCursorPos(#hints + 2, h)
        term.setBackgroundColor(colors.red); term.setTextColor(colors.white)
        term.write(" " .. errorMsg .. " ")
    elseif errorMsg ~= "" then
        errorMsg = "" -- clear expired message
    end

    -- Mouse cursor (always drawn last)
    term.setCursorPos(mouseX, mouseY)
    term.setBackgroundColor(colors.black); term.setTextColor(colors.yellow); term.write("+")
end

-- Initialization and main loop
refresh()
local updateTimer = os.startTimer(0.05)

while true do
    draw()
    local event, p1, p2, p3 = os.pullEvent()
    
    if event == "mouse_move" or event == "mouse_click" or event == "mouse_drag" then
        mouseX, mouseY = p2, p3
        if event == "mouse_click" then
            if mouseY == 2 and mouseX >= 1 and mouseX <= 6 then
                showMenu = not showMenu
            elseif showMenu and mouseX >= 1 and mouseX <= 12 and mouseY > 2 and mouseY <= 9 then
                handleFileAction(mouseY - 2)
            else
                showMenu = false
                local split = math.floor(w/2)
                local clickedRow = mouseY - 5
                if mouseY >= 6 and mouseY <= h-2 then
                    if p2 < split then
                        selectedList = "dirs"
                        if clickedRow >= 1 and clickedRow <= #dirs then selDir = clickedRow end
                    else
                        selectedList = "files"
                        if clickedRow >= 1 and clickedRow <= #files then selFile = clickedRow end
                    end
                    if (os.epoch("utc") - lastClickTime < 500) then executeAction() end
                    lastClickTime = os.epoch("utc"); lastClickButton = p1
                end
            end
        end
    elseif event == "timer" and p1 == updateTimer then
        updateTimer = os.startTimer(0.05)
    elseif event == "key" then
        if p1 == keys.f1 then          -- Menu
            showMenu = not showMenu
        elseif p1 == keys.f3 then      -- Exit
            break
        elseif p1 == keys.f5 then      -- Run
            handleFileAction(2)
        elseif p1 == keys.f7 then      -- Move
            handleFileAction(3)
        elseif p1 == keys.f8 then      -- Copy
            handleFileAction(4)
        elseif p1 == keys.f9 then      -- Rename
            handleFileAction(6)
        elseif p1 == keys.n then       -- Create Dir
            handleFileAction(7)
        elseif p1 == keys.delete then  -- Delete
            handleFileAction(5)
        elseif p1 == keys.tab then
            selectedList = (selectedList == "dirs") and "files" or "dirs"
        elseif p1 == keys.up then
            if selectedList == "dirs" then
                if selDir > 1 then selDir = selDir - 1 end
            else
                if selFile > 1 then selFile = selFile - 1 end
            end
        elseif p1 == keys.down then
            if selectedList == "dirs" then
                if selDir < #dirs then selDir = selDir + 1 end
            else
                if selFile < #files then selFile = selFile + 1 end
            end
        elseif p1 == keys.enter then
            executeAction()
        end
    end
end

term.setBackgroundColor(colors.black); term.clear(); term.setCursorPos(1, 1)
