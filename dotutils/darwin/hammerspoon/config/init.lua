----------------------------------------------------------------------
-- Hammerspoon + Kitty 双屏配置
--
-- Ctrl + Shift + T
--   如果左右屏幕都已有 Kitty：
--     恢复窗口，并将 Kitty 的所有窗口显示到前台。
--
--   如果任意屏幕没有 Kitty：
--     启动 Kitty、创建缺少的窗口，然后分别放到左右屏幕。
--
-- Ctrl + Shift + H
--   聚焦左边屏幕上的 Kitty。
--
-- Ctrl + Shift + L
--   聚焦右边屏幕上的 Kitty。
----------------------------------------------------------------------

----------------------------------------------------------------------
-- 配置
----------------------------------------------------------------------

local KITTY_BUNDLE_ID = "net.kovidgoyal.kitty"

-- 每次检查窗口的间隔
local RETRY_INTERVAL = 0.25

-- 最多等待约 10 秒
local MAX_RETRY_COUNT = 40

----------------------------------------------------------------------
-- 获取 Kitty 应用
----------------------------------------------------------------------

local function getKittyApplication()
	return hs.application.get(KITTY_BUNDLE_ID) or hs.application.find("kitty") or hs.application.find("Kitty")
end

----------------------------------------------------------------------
-- 获取屏幕，并按照从左到右排序
----------------------------------------------------------------------

local function getScreensLeftToRight()
	local screens = hs.screen.allScreens()

	table.sort(screens, function(screenA, screenB)
		local frameA = screenA:fullFrame()
		local frameB = screenB:fullFrame()

		if frameA.x == frameB.x then
			return frameA.y < frameB.y
		end

		return frameA.x < frameB.x
	end)

	return screens
end

----------------------------------------------------------------------
-- 获取最左和最右屏幕
----------------------------------------------------------------------

local function getLeftAndRightScreens()
	local screens = getScreensLeftToRight()

	if #screens < 2 then
		return nil, nil
	end

	return screens[1], screens[#screens]
end

----------------------------------------------------------------------
-- 获取 Kitty 的标准窗口
----------------------------------------------------------------------

local function getKittyWindows()
	local application = getKittyApplication()

	if not application then
		return {}
	end

	local windows = {}

	for _, window in ipairs(application:allWindows()) do
		if window and window:isStandard() then
			table.insert(windows, window)
		end
	end

	-- 按照窗口 ID 排序，让窗口选择尽量稳定
	table.sort(windows, function(windowA, windowB)
		return (windowA:id() or 0) < (windowB:id() or 0)
	end)

	return windows
end

----------------------------------------------------------------------
-- 判断两个窗口是否是同一个窗口
----------------------------------------------------------------------

local function isSameWindow(windowA, windowB)
	if not windowA or not windowB then
		return false
	end

	return windowA:id() == windowB:id()
end

----------------------------------------------------------------------
-- 判断窗口是否位于指定屏幕
----------------------------------------------------------------------

local function isWindowOnScreen(window, screen)
	if not window or not screen then
		return false
	end

	local windowScreen = window:screen()

	if not windowScreen then
		return false
	end

	return windowScreen:id() == screen:id()
end

----------------------------------------------------------------------
-- 查找指定屏幕上的 Kitty 窗口
--
-- 如果一个屏幕存在多个 Kitty 窗口：
--   1. 优先选择没有最小化的窗口
--   2. 否则选择第一个匹配的窗口
----------------------------------------------------------------------

local function findKittyWindowOnScreen(screen)
	if not screen then
		return nil
	end

	local firstMatchedWindow = nil

	for _, window in ipairs(getKittyWindows()) do
		if isWindowOnScreen(window, screen) then
			if not firstMatchedWindow then
				firstMatchedWindow = window
			end

			if not window:isMinimized() then
				return window
			end
		end
	end

	return firstMatchedWindow
end

----------------------------------------------------------------------
-- 从窗口列表中选择一个未被占用的窗口
----------------------------------------------------------------------

local function findUnusedWindow(windows, excludedWindow)
	for _, window in ipairs(windows) do
		if not excludedWindow or not isSameWindow(window, excludedWindow) then
			return window
		end
	end

	return nil
end

----------------------------------------------------------------------
-- 恢复一个可能被最小化的窗口
----------------------------------------------------------------------

local function restoreWindow(window)
	if not window then
		return
	end

	if window:isMinimized() then
		window:unminimize()
	end
end

----------------------------------------------------------------------
-- 将窗口移动到指定屏幕并铺满可用区域
--
-- screen:frame() 会避开菜单栏和 Dock。
----------------------------------------------------------------------

local function moveWindowToScreen(window, screen)
	if not window or not screen then
		return false
	end

	restoreWindow(window)

	window:moveToScreen(screen, false, true, 0)

	window:setFrame(screen:frame(), 0)

	return true
end

----------------------------------------------------------------------
-- 将两个 Kitty 窗口显示到前台
--
-- macOS 同一时刻只有一个窗口能接收键盘输入，但调用
-- application:activate(true) 可以把 Kitty 的所有窗口带到前台。
----------------------------------------------------------------------

local function bringBothWindowsToFront(leftWindow, rightWindow)
	if not leftWindow or not rightWindow then
		return false
	end

	local application = getKittyApplication()

	if not application then
		return false
	end

	local previouslyFocusedWindow = hs.window.focusedWindow()
	local finalFocusWindow = leftWindow

	-- 如果按快捷键之前聚焦的是左右 Kitty 之一，则保持原来的焦点
	if previouslyFocusedWindow then
		if isSameWindow(previouslyFocusedWindow, leftWindow) then
			finalFocusWindow = leftWindow
		elseif isSameWindow(previouslyFocusedWindow, rightWindow) then
			finalFocusWindow = rightWindow
		end
	end

	-- 如果 Kitty 整个应用被隐藏，先恢复
	if application:isHidden() then
		application:unhide()
	end

	restoreWindow(leftWindow)
	restoreWindow(rightWindow)

	-- true 表示将这个应用的所有窗口带到前台
	application:activate(true)

	hs.timer.doAfter(0.15, function()
		restoreWindow(leftWindow)
		restoreWindow(rightWindow)

		leftWindow:raise()
		rightWindow:raise()
		finalFocusWindow:focus()
	end)

	return true
end

----------------------------------------------------------------------
-- 创建一个新的 Kitty OS 窗口
----------------------------------------------------------------------

local function createNewKittyWindow()
	local application = getKittyApplication()

	if not application then
		return false
	end

	application:activate(false)

	hs.timer.doAfter(0.1, function()
		-- Kitty 默认使用 Command + N 创建新的 OS 窗口
		hs.eventtap.keyStroke({ "cmd" }, "n")
	end)

	return true
end

----------------------------------------------------------------------
-- 把两个 Kitty 窗口安排到左右屏幕
----------------------------------------------------------------------

local function arrangeKittyWindows()
	local leftScreen, rightScreen = getLeftAndRightScreens()

	if not leftScreen or not rightScreen then
		hs.alert.show("需要至少连接两个屏幕")
		return false
	end

	local windows = getKittyWindows()

	if #windows < 2 then
		return false
	end

	--------------------------------------------------------------
	-- 优先使用已经位于左右屏幕的窗口
	--------------------------------------------------------------

	local leftWindow = findKittyWindowOnScreen(leftScreen)
	local rightWindow = findKittyWindowOnScreen(rightScreen)

	--------------------------------------------------------------
	-- 左边没有窗口时，选择一个窗口移动到左边
	--------------------------------------------------------------

	if not leftWindow then
		leftWindow = findUnusedWindow(windows, rightWindow)
	end

	--------------------------------------------------------------
	-- 右边没有窗口时，选择另一个窗口移动到右边
	--------------------------------------------------------------

	if not rightWindow then
		rightWindow = findUnusedWindow(windows, leftWindow)
	end

	if not leftWindow or not rightWindow then
		return false
	end

	if isSameWindow(leftWindow, rightWindow) then
		return false
	end

	--------------------------------------------------------------
	-- 移动窗口并铺满
	--------------------------------------------------------------

	moveWindowToScreen(leftWindow, leftScreen)
	moveWindowToScreen(rightWindow, rightScreen)

	--------------------------------------------------------------
	-- 等待窗口移动完成后显示到前台
	--------------------------------------------------------------

	hs.timer.doAfter(0.2, function()
		bringBothWindowsToFront(leftWindow, rightWindow)
	end)

	return true
end

----------------------------------------------------------------------
-- 等待 Kitty 启动并确保至少存在两个窗口
--
-- 这里使用局部轮询函数，不调用不存在的
-- waitForKittyStartup 方法。
----------------------------------------------------------------------

local function waitAndArrangeKitty()
	local retryCount = 0
	local newWindowRequested = false

	local function check()
		retryCount = retryCount + 1

		if retryCount > MAX_RETRY_COUNT then
			hs.alert.show("等待 Kitty 窗口超时")
			return
		end

		local application = getKittyApplication()

		----------------------------------------------------------
		-- Kitty 进程还没有出现
		----------------------------------------------------------

		if not application then
			hs.timer.doAfter(RETRY_INTERVAL, check)
			return
		end

		local windows = getKittyWindows()

		----------------------------------------------------------
		-- Kitty 尚未创建第一个窗口
		----------------------------------------------------------

		if #windows == 0 then
			hs.timer.doAfter(RETRY_INTERVAL, check)
			return
		end

		----------------------------------------------------------
		-- 只有一个窗口时，只发送一次 Command + N
		----------------------------------------------------------

		if #windows == 1 then
			if not newWindowRequested then
				newWindowRequested = true
				createNewKittyWindow()
			end

			hs.timer.doAfter(RETRY_INTERVAL, check)
			return
		end

		----------------------------------------------------------
		-- 已有至少两个窗口，开始排列
		----------------------------------------------------------

		if arrangeKittyWindows() then
			hs.alert.show("Kitty 已显示在左右屏幕")
		else
			hs.alert.show("无法安排 Kitty 窗口")
		end
	end

	check()
end

----------------------------------------------------------------------
-- Ctrl + Shift + T 的主要逻辑
----------------------------------------------------------------------

local function showOrCreateKittyOnBothScreens()
	local leftScreen, rightScreen = getLeftAndRightScreens()

	if not leftScreen or not rightScreen then
		hs.alert.show("需要至少连接两个屏幕")
		return
	end

	local application = getKittyApplication()

	--------------------------------------------------------------
	-- Kitty 已经在运行
	--------------------------------------------------------------

	if application then
		local leftWindow = findKittyWindowOnScreen(leftScreen)
		local rightWindow = findKittyWindowOnScreen(rightScreen)

		----------------------------------------------------------
		-- 两个屏幕都已有 Kitty
		--
		-- 不创建窗口
		-- 不移动窗口
		-- 不改变窗口大小
		-- 只将 Kitty 的全部窗口带到前台
		----------------------------------------------------------

		if leftWindow and rightWindow and not isSameWindow(leftWindow, rightWindow) then
			bringBothWindowsToFront(leftWindow, rightWindow)
			return
		end

		----------------------------------------------------------
		-- 任意一个屏幕没有 Kitty
		----------------------------------------------------------

		application:activate(false)
		waitAndArrangeKitty()
		return
	end

	--------------------------------------------------------------
	-- Kitty 尚未运行
	--------------------------------------------------------------

	local launched = hs.application.launchOrFocusByBundleID(KITTY_BUNDLE_ID)

	if not launched then
		hs.alert.show("无法启动 Kitty，请确认 Kitty 已安装")
		return
	end

	waitAndArrangeKitty()
end

----------------------------------------------------------------------
-- 聚焦左边屏幕上的 Kitty
----------------------------------------------------------------------

local function focusLeftKitty()
	local leftScreen, _ = getLeftAndRightScreens()

	if not leftScreen then
		hs.alert.show("需要至少连接两个屏幕")
		return
	end

	local window = findKittyWindowOnScreen(leftScreen)

	if not window then
		showOrCreateKittyOnBothScreens()
		return
	end

	local application = getKittyApplication()

	if application then
		application:unhide()
		application:activate(false)
	end

	restoreWindow(window)

	hs.timer.doAfter(0.1, function()
		window:raise()
		window:focus()
	end)
end

----------------------------------------------------------------------
-- 聚焦右边屏幕上的 Kitty
----------------------------------------------------------------------

local function focusRightKitty()
	local _, rightScreen = getLeftAndRightScreens()

	if not rightScreen then
		hs.alert.show("需要至少连接两个屏幕")
		return
	end

	local window = findKittyWindowOnScreen(rightScreen)

	if not window then
		showOrCreateKittyOnBothScreens()
		return
	end

	local application = getKittyApplication()

	if application then
		application:unhide()
		application:activate(false)
	end

	restoreWindow(window)

	hs.timer.doAfter(0.1, function()
		window:raise()
		window:focus()
	end)
end

----------------------------------------------------------------------
-- 快捷键绑定
----------------------------------------------------------------------

-- Ctrl + Shift + T
hs.hotkey.bind({ "ctrl", "shift" }, "T", function()
	showOrCreateKittyOnBothScreens()
end)

-- Ctrl + Shift + H
hs.hotkey.bind({ "ctrl", "shift" }, "H", function()
	focusLeftKitty()
end)

-- Ctrl + Shift + L
hs.hotkey.bind({ "ctrl", "shift" }, "L", function()
	focusRightKitty()
end)

----------------------------------------------------------------------
-- 配置加载完成
----------------------------------------------------------------------
