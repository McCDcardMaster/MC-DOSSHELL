local w, h = term.getSize()
local currentPath = "/"          -- current working directory (right panel)
local selectedPane = "tree"      -- "tree" or "files"
local treeNodes = {}             -- list of visible tree lines (for drawing/selection)
local treeOffset = 1             -- scroll offset for tree
local filesOffset = 1            -- scroll offset for files
local selTreeIndex = 1           -- selected line in treeNodes
local selFile = 1
local files = {}
local mouseX, mouseY = 1, 1
local lastClickTime, lastClickButton = 0, 0
local lastClickNode = nil
local showMenu = false
local errorMsg = ""
local errorMsgExpire = 0

-- Scrollbar drag state
local dragScrollbar = nil        -- "tree" or "files"
local dragStartMouseY = 0
local dragStartOffset = 0

-- Tree node definition
local Node = {}
function Node:new(name, path, parent)
    local obj = {
        name = name,
        path = path,
        parent = parent,
        expanded = false,
        loaded = false,
        children = {}
    }
    setmetatable(obj, self)
    self.__index = self
    return obj
end

function Node:loadChildren()
    if self.loaded then return end
    self.loaded = true
    self.children = {}
    local ok, list = pcall(fs.list, self.path)
    if not ok then return end
    table.sort(list)
    for _, name in ipairs(list) do
        local full = fs.combine(self.path, name)
        if fs.isDir(full) and name ~= "." and name ~= ".." then
            table.insert(self.children, Node:new(name, full, self))
        end
    end
end

function Node:expand()
    if not self.expanded then
        self:loadChildren()
        self.expanded = true
    end
end

function Node:collapse()
    self.expanded = false
end

function Node:toggle()
    if self.expanded then
        self:collapse()
    else
        self:expand()
    end
end

-- Rebuild the whole tree from root
local rootNode
function rebuildTree()
    rootNode = Node:new("/", "/", nil)
    rootNode:expand()   -- expand root initially
end

-- Build flat list of visible nodes (depth-first) with indentation info
local function buildVisibleNodes(node, depth, result)
    if not node then return end
    table.insert(result, { node = node, depth = depth })
    if node.expanded then
        for _, child in ipairs(node.children) do
            buildVisibleNodes(child, depth + 1, result)
        end
    end
end

-- Обновляет список видимых узлов дерева (без изменения смещения/выделения)
local function updateTreeStructure()
    treeNodes = {}
    buildVisibleNodes(rootNode, 0, treeNodes)
    if #treeNodes == 0 then
        treeNodes = {{ node = rootNode, depth = 0 }}
    end
    if selTreeIndex > #treeNodes then selTreeIndex = #treeNodes end
    if selTreeIndex < 1 then selTreeIndex = 1 end
end

-- Только подгоняет смещение в допустимые пределы (НЕ двигает выделение)
local function clampTreeOffset()
    local maxLines = h - 8
    local maxTreeOffset = math.max(1, #treeNodes - maxLines + 1)
    if treeOffset < 1 then treeOffset = 1 end
    if treeOffset > maxTreeOffset then treeOffset = maxTreeOffset end
end

-- Принудительно показывает выделенный элемент в дереве
local function ensureTreeSelectionVisible()
    local maxLines = h - 8
    if selTreeIndex < treeOffset then treeOffset = selTreeIndex end
    if selTreeIndex >= treeOffset + maxLines then treeOffset = selTreeIndex - maxLines + 1 end
    clampTreeOffset()
end

-- Аналогично для файлов
local function updateFilesStructure()
    local ok, all = pcall(fs.list, currentPath)
    if not ok then
        setError("Can't read directory")
        currentPath = "/"
        ok, all = pcall(fs.list, currentPath)
        if not ok then all = {} end
    end
    files = {}
    table.sort(all)
    for _, name in ipairs(all) do
        local full = fs.combine(currentPath, name)
        if not fs.isDir(full) then
            table.insert(files, name)
        end
    end
    if selFile > #files then selFile = #files end
    if selFile < 1 then selFile = 1 end
end

local function clampFilesOffset()
    local maxLines = h - 8
    local maxFilesOffset = math.max(1, #files - maxLines + 1)
    if filesOffset < 1 then filesOffset = 1 end
    if filesOffset > maxFilesOffset then filesOffset = maxFilesOffset end
end

local function ensureFilesSelectionVisible()
    local maxLines = h - 8
    if selFile < filesOffset then filesOffset = selFile end
    if selFile >= filesOffset + maxLines then filesOffset = selFile - maxLines + 1 end
    clampFilesOffset()
end

-- Полное обновление (структура + выделение + смещение)
local function fullRefresh()
    rebuildTree()
    updateTreeStructure()
    clampTreeOffset()
    updateFilesStructure()
    clampFilesOffset()
    -- Сразу показываем текущее выделение
    ensureTreeSelectionVisible()
    ensureFilesSelectionVisible()
end

-- Navigate to a directory node
local function navigateToNode(node)
    if not node then return end
    currentPath = node.path
    updateFilesStructure()
    updateTreeStructure()
    -- find index of this node in treeNodes
    for i, entry in ipairs(treeNodes) do
        if entry.node == node then
            selTreeIndex = i
            break
        end
    end
    ensureTreeSelectionVisible()
    clampFilesOffset()
    selectedPane = "files"
end

-- Error display
local function setError(msg)
    errorMsg = msg
    errorMsgExpire = os.epoch("utc") + 3000
end

-- Input dialog
local function inputDialog(prompt)
    term.setCursorPos(1, h)
    term.setBackgroundColor(colors.blue)
    term.setTextColor(colors.white)
    term.clearLine()
    term.write(prompt .. ": ")
    return read()
end

local function confirmDialog(msg)
    term.setCursorPos(1, h)
    term.setBackgroundColor(colors.blue)
    term.setTextColor(colors.white)
    term.clearLine()
    term.write(msg .. " (y/N): ")
    return read():lower() == "y"
end

-- Safe command execution
local function safeRun(command, description, workingDir)
    local oldDir = nil
    if workingDir then
        oldDir = shell.dir()
        shell.setDir(workingDir)
    end
    local ok, err = pcall(shell.run, command)
    if not ok then
        setError(string.format("Error while %s: %s", description or "running", err))
    end
    if oldDir then shell.setDir(oldDir) end
    return ok
end

-- File operations (used by menu)
local function getSelectedPath()
    if selectedPane == "tree" then
        local entry = treeNodes[selTreeIndex]
        if entry then return entry.node.path end
    else
        if #files > 0 then
            return fs.combine(currentPath, files[selFile])
        end
    end
    return nil
end

local function getSelectedName()
    if selectedPane == "tree" then
        local entry = treeNodes[selTreeIndex]
        if entry then return entry.node.name end
    else
        if #files > 0 then return files[selFile] end
    end
    return nil
end

local function handleFileAction(actionIdx)
    if actionIdx == 1 then -- Open (navigate or run)
        if selectedPane == "tree" then
            local entry = treeNodes[selTreeIndex]
            if entry then navigateToNode(entry.node) end
        else
            if #files > 0 then
                local full = fs.combine(currentPath, files[selFile])
                term.setBackgroundColor(colors.black); term.setTextColor(colors.white)
                term.clear(); term.setCursorPos(1, 1)
                local ok = safeRun(full, "running file")
                if not ok then print("\n" .. errorMsg) else print("\nPress any key...") end
                os.pullEvent("key")
                updateFilesStructure()
                clampFilesOffset()
            end
        end
    elseif actionIdx == 2 then -- Run command
        local cmd = inputDialog("Command")
        if cmd and cmd ~= "" then
            term.clear(); term.setCursorPos(1,1)
            if not safeRun(cmd, "executing command", currentPath) then
                print("\n" .. errorMsg)
            else
                print("\nPress any key...")
            end
            os.pullEvent("key")
            updateFilesStructure()
            clampFilesOffset()
        end
    elseif actionIdx == 3 then -- Move
        local name = getSelectedName()
        if not name then setError("Nothing selected"); fullRefresh(); return end
        local src = getSelectedPath()
        local dest = inputDialog("Move to")
        if dest and dest ~= "" then
            if dest:sub(1,1) ~= "/" then dest = fs.combine(currentPath, dest) end
            local ok, err = pcall(fs.move, src, dest)
            if not ok then setError("Move: " .. err) end
        end
    elseif actionIdx == 4 then -- Copy
        local name = getSelectedName()
        if not name then setError("Nothing selected"); fullRefresh(); return end
        local src = getSelectedPath()
        local dest = inputDialog("Copy to")
        if dest and dest ~= "" then
            if dest:sub(1,1) ~= "/" then dest = fs.combine(currentPath, dest) end
            local ok, err = pcall(fs.copy, src, dest)
            if not ok then setError("Copy: " .. err) end
        end
    elseif actionIdx == 5 then -- Delete
        local name = getSelectedName()
        if not name then setError("Nothing selected"); fullRefresh(); return end
        if name == "/" or name == ".." then setError("Cannot delete system entry"); return end
        if confirmDialog("Delete " .. name .. "?") then
            local path = getSelectedPath()
            local ok, err = pcall(fs.delete, path)
            if not ok then setError("Delete: " .. err) end
        end
    elseif actionIdx == 6 then -- Rename
        local name = getSelectedName()
        if not name then setError("Nothing selected"); fullRefresh(); return end
        local src = getSelectedPath()
        local newName = inputDialog("New name")
        if newName and newName ~= "" then
            local dest = fs.combine(fs.getDir(src), newName)
            local ok, err = pcall(fs.move, src, dest)
            if not ok then setError("Rename: " .. err) end
        end
    elseif actionIdx == 7 then -- Create Dir
        local folder = inputDialog("Folder name")
        if folder and folder ~= "" then
            local path = fs.combine(currentPath, folder)
            local ok, err = pcall(fs.makeDir, path)
            if not ok then setError("Create dir: " .. err) end
        end
    end
    showMenu = false
    fullRefresh()  -- rebuild everything after changes
end

-- Draw a vertical scrollbar
local function drawScrollbar(x, yStart, yEnd, total, visible, offset)
    if total <= visible then return end
    local trackHeight = yEnd - yStart + 1
    local thumbHeight = math.max(1, math.floor(visible * trackHeight / total))
    local maxOffset = total - visible
    local thumbPos = 0
    if maxOffset > 0 then
        thumbPos = math.floor((offset - 1) / maxOffset * (trackHeight - thumbHeight))
    end
    for y = yStart, yEnd do
        term.setCursorPos(x, y)
        if y >= yStart + thumbPos and y < yStart + thumbPos + thumbHeight then
            term.setBackgroundColor(colors.gray)
            term.setTextColor(colors.black)
            term.write(" ")
        else
            term.setBackgroundColor(colors.lightGray)
            term.setTextColor(colors.black)
            term.write(" ")
        end
    end
end

-- Draw the interface
local function draw()
    term.setBackgroundColor(colors.white)
    term.clear()

    -- Header
    term.setCursorPos(1,1)
    term.setPaletteColor(colors.blue, 0x1e1d8f)
    term.setBackgroundColor(colors.blue)
    term.setTextColor(colors.white)
    term.clearLine()
    local title = "   MC-DOS Shell "
    term.setCursorPos(math.floor((w - #title) / 2), 1)
    term.write(title)

    -- Menu bar
    term.setCursorPos(1,2)
    term.setBackgroundColor(colors.white)
    term.setTextColor(colors.black)
    term.clearLine()
    term.write(" File  Options  View  Tree  Help")

    -- Current path (DOS style)
    local displayPath = " C:\\"
    if currentPath ~= "/" then
        displayPath = displayPath .. currentPath:sub(2):gsub("/", "\\")
    end
    term.setCursorPos(1,3)
    term.write(displayPath)

    -- Column headers
    term.setBackgroundColor(colors.lightGray)
    term.setTextColor(colors.black)
    term.setCursorPos(1,5)
    term.clearLine()
    term.setCursorPos(3,5); term.write("Directory Tree")
    local split = math.floor(w/2)
    term.setCursorPos(split + 3,5); term.write("Files")

    -- Vertical separators
    term.setBackgroundColor(colors.gray)
    for y = 6, h-1 do
        term.setCursorPos(1, y); term.write(" ")
        term.setCursorPos(split, y); term.write(" ")
        term.setCursorPos(w, y); term.write(" ")
    end

    -- Draw tree panel (left)
    local maxLines = h - 8
    for i = 1, maxLines do
        local lineY = i + 5
        local idx = treeOffset + i - 1
        term.setCursorPos(2, lineY)
        if idx <= #treeNodes then
            local entry = treeNodes[idx]
            local node = entry.node
            local indent = entry.depth * 2
            local prefix = string.rep(" ", indent)
            local icon = node.expanded and "[-]" or "[+]"
            local text = prefix .. icon .. " " .. node.name
            if selectedPane == "tree" and idx == selTreeIndex then
                term.setBackgroundColor(colors.gray); term.setTextColor(colors.white)
            else
                term.setBackgroundColor(colors.white); term.setTextColor(colors.black)
            end
            term.write(string.sub(text .. string.rep(" ", split-3), 1, split-3))
        else
            term.setBackgroundColor(colors.white); term.setTextColor(colors.black)
            term.write(string.rep(" ", split-3))
        end
    end

    -- Draw files panel (right)
    for i = 1, maxLines do
        local lineY = i + 5
        local idx = filesOffset + i - 1
        term.setCursorPos(split+1, lineY)
        if idx <= #files then
            local name = files[idx]
            if selectedPane == "files" and idx == selFile then
                term.setBackgroundColor(colors.gray); term.setTextColor(colors.white)
            else
                term.setBackgroundColor(colors.white); term.setTextColor(colors.black)
            end
            local text = " " .. name
            term.write(string.sub(text .. string.rep(" ", w-split-1), 1, w-split-1))
        else
            term.setBackgroundColor(colors.white); term.setTextColor(colors.black)
            term.write(string.rep(" ", w-split-1))
        end
    end

    -- Draw scrollbars (after content)
    local yStart = 6
    local yEnd = h - 2
    -- Tree scrollbar at column split-2 (right edge of tree panel)
    local treeScrollX = split - 2
    if treeScrollX > 2 then
        drawScrollbar(treeScrollX, yStart, yEnd, #treeNodes, maxLines, treeOffset)
    end
    -- Files scrollbar at column w-1 (right edge of files panel)
    local filesScrollX = w - 1
    if filesScrollX > split + 1 then
        drawScrollbar(filesScrollX, yStart, yEnd, #files, maxLines, filesOffset)
    end

    -- Menu overlay
    if showMenu then
        local items = {"Open", "Run...", "Move...", "Copy...", "Delete", "Rename", "Create Dir"}
        local menuWidth = 14
        local startX, startY = 2, 3
        term.setBackgroundColor(colors.lightGray)
        for i = 1, #items do
            term.setCursorPos(startX+menuWidth, startY+i-1); term.write(" ")
        end
        term.setCursorPos(startX+3, startY+#items); term.write(string.rep(" ",12))
        term.setBackgroundColor(colors.white)
        term.setTextColor(colors.black)
        for i, item in ipairs(items) do
            term.setCursorPos(startX, startY+i-1)
            local line = " " .. item
            term.write(line .. string.rep(" ", menuWidth - #line))
        end
    end

    -- Bottom status line
    term.setCursorPos(1, h)
    term.setBackgroundColor(colors.lightGray); term.setTextColor(colors.black)
    term.clearLine()
    local hints = " F1=Menu F3=Exit Tab=Switch"
    term.write(hints)
    if errorMsg ~= "" and os.epoch("utc") < errorMsgExpire then
        term.setCursorPos(#hints+2, h)
        term.setBackgroundColor(colors.red); term.setTextColor(colors.white)
        term.write(" " .. errorMsg .. " ")
    elseif errorMsg ~= "" then
        errorMsg = ""
    end

    -- Mouse cursor
    term.setCursorPos(mouseX, mouseY)
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    term.write("")
end

-- Проверка попадания в область скроллбара с небольшим допуском
local function isMouseOnScrollbar(mouseX, scrollX)
    return mouseX >= scrollX - 1 and mouseX <= scrollX + 1
end

-- Handle mouse clicks on scrollbars
local function handleScrollbarClick(pane, mouseY)
    local yStart = 6
    local yEnd = h - 2
    local trackHeight = yEnd - yStart + 1
    local total, visible
    if pane == "tree" then
        total = #treeNodes
        visible = h - 8
    else
        total = #files
        visible = h - 8
    end
    if total <= visible then return end

    local relative = (mouseY - yStart) / trackHeight
    relative = math.max(0, math.min(1, relative))
    local maxOffset = total - visible
    local newOffset = math.floor(relative * maxOffset) + 1
    newOffset = math.max(1, math.min(newOffset, maxOffset))
    
    if pane == "tree" then
        treeOffset = newOffset
        clampTreeOffset()
    else
        filesOffset = newOffset
        clampFilesOffset()
    end
    dragScrollbar = pane
    dragStartMouseY = mouseY
    dragStartOffset = (pane == "tree") and treeOffset or filesOffset
end

-- Handle mouse clicks on tree (detect icon or name)
local function handleTreeClickAt(rowIdx, clickX, isDoubleClick)
    local entry = treeNodes[rowIdx]
    if not entry then return end
    local node = entry.node
    local indent = entry.depth * 2
    local iconStartX = 2 + indent
    local nameStartX = iconStartX + 3   -- after "[+] "
    -- If click is on the icon area
    if clickX >= iconStartX and clickX < iconStartX + 3 then
        node:toggle()
        updateTreeStructure()
        clampTreeOffset()
        ensureTreeSelectionVisible()
    elseif clickX >= nameStartX then
        if isDoubleClick then
            navigateToNode(node)
        else
            selTreeIndex = rowIdx
            selectedPane = "tree"
            ensureTreeSelectionVisible()
        end
    end
end

-- Handle file list click
local function handleFilesClickAt(rowIdx, isDoubleClick)
    if rowIdx >= 1 and rowIdx <= #files then
        selFile = rowIdx
        selectedPane = "files"
        ensureFilesSelectionVisible()
        if isDoubleClick then
            local full = fs.combine(currentPath, files[selFile])
            term.clear(); term.setCursorPos(1,1)
            local ok = safeRun(full, "running file")
            if not ok then print("\n" .. errorMsg) else print("\nPress any key...") end
            os.pullEvent("key")
            updateFilesStructure()
            clampFilesOffset()
        end
    end
end

-- ============================================================================
-- MODIFIED MAIN LOOP – only redraw when necessary
-- ============================================================================

-- Disable cursor blinking to reduce visual noise
term.setCursorBlink(false)

-- Initial refresh and flag to draw once
fullRefresh()
local redraw = true

while true do
    -- Redraw only if something changed
    if redraw then
        draw()
        redraw = false
    end

    -- Wait for next event (no timer needed)
    local event, p1, p2, p3 = os.pullEvent()

    if event == "mouse_click" then
        mouseX, mouseY = p2, p3
        -- Menu button
        if mouseY == 2 and mouseX >= 1 and mouseX <= 6 then
            showMenu = not showMenu
            redraw = true
        elseif showMenu and mouseX >= 1 and mouseX <= 12 and mouseY > 2 and mouseY <= 9 then
            handleFileAction(mouseY - 2)
            redraw = true
        else
            showMenu = false
            local split = math.floor(w/2)
            local clickRow = mouseY - 5
            -- Check scrollbars first (с допуском)
            local treeScrollX = split - 2
            local filesScrollX = w - 1
            local handled = false
            if mouseY >= 6 and mouseY <= h-2 then
                if isMouseOnScrollbar(mouseX, treeScrollX) then
                    handleScrollbarClick("tree", mouseY)
                    redraw = true
                    handled = true
                elseif isMouseOnScrollbar(mouseX, filesScrollX) then
                    handleScrollbarClick("files", mouseY)
                    redraw = true
                    handled = true
                end
            end
            if not handled and mouseY >= 6 and mouseY <= h-2 then
                local isDouble = (os.epoch("utc") - lastClickTime < 500) and (p1 == lastClickButton)
                if mouseX < split then
                    -- Tree panel
                    local realRow = treeOffset + clickRow - 1
                    if realRow >= 1 and realRow <= #treeNodes then
                        handleTreeClickAt(realRow, mouseX, isDouble)
                        redraw = true
                    end
                else
                    -- Files panel
                    local realRow = filesOffset + clickRow - 1
                    if realRow >= 1 and realRow <= #files then
                        handleFilesClickAt(realRow, isDouble)
                        redraw = true
                    end
                end
                lastClickTime = os.epoch("utc")
                lastClickButton = p1
            end
        end

    elseif event == "mouse_drag" then
        mouseX, mouseY = p2, p3
        if dragScrollbar then
            local deltaY = mouseY - dragStartMouseY
            local yStart = 6
            local yEnd = h - 2
            local trackHeight = yEnd - yStart + 1
            local total, visible
            if dragScrollbar == "tree" then
                total = #treeNodes
                visible = h - 8
            else
                total = #files
                visible = h - 8
            end
            if total > visible then
                local maxOffset = total - visible
                local step = maxOffset / (trackHeight - 1)
                local newOffset = dragStartOffset + math.floor(deltaY * step + 0.5)
                newOffset = math.max(1, math.min(newOffset, maxOffset))
                if dragScrollbar == "tree" then
                    treeOffset = newOffset
                    clampTreeOffset()
                else
                    filesOffset = newOffset
                    clampFilesOffset()
                end
                redraw = true
                -- update drag start to prevent jumps
                dragStartMouseY = mouseY
                dragStartOffset = (dragScrollbar == "tree") and treeOffset or filesOffset
            end
        end

    elseif event == "mouse_up" then
        dragScrollbar = nil
        -- No need to redraw just because mouse was released

    elseif event == "mouse_move" then
        -- Ignore mouse movement entirely – no redraw needed
        mouseX, mouseY = p2, p3

    elseif event == "key" then
        if p1 == keys.f1 then
            showMenu = not showMenu
            redraw = true
        elseif p1 == keys.f3 then
            break
        elseif p1 == keys.f5 then
            handleFileAction(2)
            redraw = true
        elseif p1 == keys.f7 then
            handleFileAction(3)
            redraw = true
        elseif p1 == keys.f8 then
            handleFileAction(4)
            redraw = true
        elseif p1 == keys.f9 then
            handleFileAction(6)
            redraw = true
        elseif p1 == keys.n then
            handleFileAction(7)
            redraw = true
        elseif p1 == keys.delete then
            handleFileAction(5)
            redraw = true
        elseif p1 == keys.tab then
            selectedPane = (selectedPane == "tree") and "files" or "tree"
            redraw = true
        elseif p1 == keys.up then
            if selectedPane == "tree" then
                if selTreeIndex > 1 then
                    selTreeIndex = selTreeIndex - 1
                    ensureTreeSelectionVisible()
                    redraw = true
                end
            else
                if selFile > 1 then
                    selFile = selFile - 1
                    ensureFilesSelectionVisible()
                    redraw = true
                end
            end
        elseif p1 == keys.down then
            if selectedPane == "tree" then
                if selTreeIndex < #treeNodes then
                    selTreeIndex = selTreeIndex + 1
                    ensureTreeSelectionVisible()
                    redraw = true
                end
            else
                if selFile < #files then
                    selFile = selFile + 1
                    ensureFilesSelectionVisible()
                    redraw = true
                end
            end
        elseif p1 == keys.enter then
            if selectedPane == "tree" then
                local entry = treeNodes[selTreeIndex]
                if entry then
                    navigateToNode(entry.node)
                    redraw = true
                end
            else
                if #files > 0 then
                    local full = fs.combine(currentPath, files[selFile])
                    term.clear(); term.setCursorPos(1,1)
                    local ok = safeRun(full, "running file")
                    if not ok then print("\n" .. errorMsg) else print("\nPress any key...") end
                    os.pullEvent("key")
                    updateFilesStructure()
                    clampFilesOffset()
                    redraw = true
                end
            end
        elseif p1 == keys.plus or p1 == keys.add then
            if selectedPane == "tree" then
                local entry = treeNodes[selTreeIndex]
                if entry and not entry.node.expanded then
                    entry.node:expand()
                    updateTreeStructure()
                    clampTreeOffset()
                    ensureTreeSelectionVisible()
                    redraw = true
                end
            end
        elseif p1 == keys.minus or p1 == keys.subtract then
            if selectedPane == "tree" then
                local entry = treeNodes[selTreeIndex]
                if entry and entry.node.expanded then
                    entry.node:collapse()
                    updateTreeStructure()
                    clampTreeOffset()
                    ensureTreeSelectionVisible()
                    redraw = true
                end
            end
        end
    end
end

term.setBackgroundColor(colors.black); term.clear(); term.setCursorPos(1,1)