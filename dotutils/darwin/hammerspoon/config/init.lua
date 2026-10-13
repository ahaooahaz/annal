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

-- 从别的应用切到 Kitty 时，最多还原多少个被挤下去的窗口
local MAX_RESTORED_WINDOWS = 8

-- 确认焦点的间隔与最多确认次数
local FOCUS_CHECK_INTERVAL = 0.3
local MAX_FOCUS_CHECKS = 4


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
-- 用 Accessibility 接口接管键盘焦点
--
-- hs.window:becomeMain() 只会设置 AXMain，
-- 而在 AppKit 里 main window 和 key window（键盘焦点窗口）
-- 是两个不同的概念，只设 AXMain 不会把键盘焦点换过来。
--
-- 额外设置 AXFocused 才会真正把 key window 换成目标窗口。
----------------------------------------------------------------------

local function takeKeyboardFocus(window)
	local axWindow = hs.axuielement and hs.axuielement.windowElement(window)

	if not axWindow then
		-- 没有 axuielement 时退而求其次
		window:becomeMain()
		return false
	end

	axWindow:setAttributeValue("AXMain", true)
	axWindow:setAttributeValue("AXFocused", true)

	return true
end

----------------------------------------------------------------------
-- 判断两个矩形是否相交
----------------------------------------------------------------------

local function framesOverlap(frameA, frameB)
	if not frameA or not frameB then
		return false
	end

	return frameA.x < frameB.x + frameB.w
		and frameB.x < frameA.x + frameA.w
		and frameA.y < frameB.y + frameB.h
		and frameB.y < frameA.y + frameA.h
end

----------------------------------------------------------------------
-- 快照「原本压在另一块屏幕的 Kitty 上面」的那些窗口
--
-- 从别的应用切到 Kitty 时必须激活 Kitty，而激活会把 Kitty 的
-- 所有窗口一起带到前台，于是另一块屏幕上的 Kitty 会盖住
-- 原本压在它上面的窗口。
--
-- 这里在激活之前先把这些窗口按「从后到前」的顺序记下来，
-- 激活完成后重新 raise 一遍就能还原层级。
--
-- 参考窗口取「层级最低的那个非目标 Kitty 窗口」，
-- 这样比它浅的 Kitty 窗口自然也被覆盖到了。
----------------------------------------------------------------------

local function snapshotDisplacedWindows(targetWindow)
	local orderedWindows = hs.window.orderedWindows()
	local referenceIndex = nil

	for index = #orderedWindows, 1, -1 do
		local candidate = orderedWindows[index]
		local application = candidate:application()

		if
			application
			and application:bundleID() == KITTY_BUNDLE_ID
			and not isSameWindow(candidate, targetWindow)
		then
			referenceIndex = index
			break
		end
	end

	if not referenceIndex then
		return {}
	end

	local referenceFrame = orderedWindows[referenceIndex]:frame()
	local displacedWindows = {}

	--------------------------------------------------------------
	-- 由近及远地往上收集，这个顺序正好就是之后 raise 的顺序：
	-- 先 raise 离参考窗口最近的，最后 raise 最前面的，
	-- 这样它们之间的相对顺序也能保持。
	--
	-- 只收集和参考窗口有重叠的窗口，
	-- 不在同一块屏幕上的窗口重排了也看不出来，纯属多余的跳动。
	--------------------------------------------------------------

	for index = referenceIndex - 1, 1, -1 do
		local candidate = orderedWindows[index]
		local application = candidate:application()

		if
			application
			and application:bundleID() ~= KITTY_BUNDLE_ID
			and framesOverlap(candidate:frame(), referenceFrame)
		then
			table.insert(displacedWindows, candidate)
		end
	end

	-- 超出上限时丢掉层级最低的那些，保留用户最可能在看的几个
	while #displacedWindows > MAX_RESTORED_WINDOWS do
		table.remove(displacedWindows, 1)
	end

	return displacedWindows
end

----------------------------------------------------------------------
-- 把快照里的窗口重新 raise 回去
--
-- 按「由后到前」的顺序 raise，最后一个 raise 的窗口在最上层，
-- 它们之间的相对顺序就还原了。
--
-- 这些 raise 必须挤在同一轮事件循环里一次发完。
-- 实测用定时器把它们错开的话，激活状态还没落定时
-- 个别应用（例如 Chrome）会趁机把自己整个激活，抢走焦点。
----------------------------------------------------------------------

local function restoreDisplacedWindows(displacedWindows)
	for _, candidate in ipairs(displacedWindows) do
		if candidate:id() and not candidate:isMinimized() then
			candidate:raise()
		end
	end
end

----------------------------------------------------------------------
-- 接管键盘焦点并抬升窗口
----------------------------------------------------------------------

local function raiseAndFocusWindow(window)
	if not window or not window:id() then
		return
	end

	takeKeyboardFocus(window)
	window:raise()
end

----------------------------------------------------------------------
-- 激活应用
--
-- 优先设置 AXFrontmost，失败时退回 activate(false)。
-- 两者都会让 AppKit 把这个应用的所有窗口一起带到前台。
----------------------------------------------------------------------

local function activateApplication(application)
	if not application then
		return
	end

	local axApplication = hs.axuielement and hs.axuielement.applicationElement(application)

	if axApplication and axApplication:setAttributeValue("AXFrontmost", true) then
		return
	end

	application:activate(false)
end

----------------------------------------------------------------------
-- 确认焦点真的落在目标窗口上，否则抢回来
--
-- 还原层级时要 raise 别的应用的窗口，而个别应用（实测是 Chrome）
-- 会借着 AXRaise 把自己整个激活，顺手把焦点抢走。
--
-- 这里宁可牺牲层级，也要保证焦点落在目标终端上：
-- 发现焦点跑了就重新激活 Kitty 抢回来
-- （代价是另一块屏幕上的 Kitty 会再次被带到前台）。
----------------------------------------------------------------------

local function ensureWindowFocused(window, retriesLeft)
	if not window or not window:id() or retriesLeft <= 0 then
		return
	end

	local application = window:application()

	if not application then
		return
	end

	if application:isFrontmost() and isSameWindow(hs.window.focusedWindow(), window) then
		return
	end

	if not application:isFrontmost() then
		activateApplication(application)
	end

	raiseAndFocusWindow(window)

	hs.timer.doAfter(FOCUS_CHECK_INTERVAL, function()
		ensureWindowFocused(window, retriesLeft - 1)
	end)
end

----------------------------------------------------------------------
-- 只把单个 Kitty 窗口提升到最前并聚焦
--
-- 本机实测（macOS 26 + Kitty + Hammerspoon）结论：
--
-- 1. window:raise() 是「手术刀」：只抬升目标窗口，
--    不会牵动同一个应用的其他窗口。
--
-- 2. 任何应用级激活（window:focus() / application:activate() /
--    AXFrontmost）都会被 AppKit 的「恢复整个窗口组」行为
--    放大成「把 Kitty 的所有窗口一起带到前台」，
--    于是另一块屏幕上的 Kitty 也被提升到最上层。
--    （和系统设置 com.apple.WindowManager AppWindowGroupingBehavior
--    无关，实测改成 0 也一样。）
--
-- 3. 激活之后 Kitty 还会把 key window 换回它自己记住的那个窗口，
--    覆盖我们指定的目标窗口。
--
-- 因此分两条路：
--
--   * Kitty 已经在最前台时（焦点本来就在某个 Kitty 窗口里，
--     也就是左右来回切的场景）完全不激活应用，
--     只用 AX 转移键盘焦点 + raise 目标窗口，
--     另一块屏幕上的 Kitty 层级完全不动。
--
--   * Kitty 在后台时必须激活。激活前先快照「原本压在另一块
--     Kitty 上面的那些窗口」，激活后把焦点纠正到目标窗口，
--     再把那些窗口 raise 回原位。
----------------------------------------------------------------------

local function focusSingleWindow(window)
	if not window then
		return false
	end

	local application = window:application()

	-- 如果 Kitty 整个应用被隐藏，先恢复
	if application and application:isHidden() then
		application:unhide()
	end

	local wasMinimized = window:isMinimized()

	restoreWindow(window)

	local function run()
		local currentApplication = window:application()

		----------------------------------------------------------
		-- Kitty 已经在最前台：只动目标窗口
		--
		-- 这里一定不能激活应用，否则另一块屏幕上的 Kitty
		-- 会被系统一起提升到最上层。
		----------------------------------------------------------

		if not currentApplication or currentApplication:isFrontmost() then
			raiseAndFocusWindow(window)
			return
		end

		----------------------------------------------------------
		-- Kitty 在后台：必须激活才能拿到键盘焦点
		----------------------------------------------------------

		local displacedWindows = snapshotDisplacedWindows(window)

		raiseAndFocusWindow(window)
		activateApplication(currentApplication)

		-- 激活后 Kitty 会把焦点抢回它自己记住的窗口，这里纠正回来
		hs.timer.doAfter(0.08, function()
			raiseAndFocusWindow(window)
		end)

		hs.timer.doAfter(0.25, function()
			raiseAndFocusWindow(window)
		end)

		-- 等激活引起的窗口重排彻底结束，再还原被挤下去的窗口
		hs.timer.doAfter(0.35, function()
			restoreDisplacedWindows(displacedWindows)
			raiseAndFocusWindow(window)

			-- 还原过程中焦点可能被别的应用抢走，这里反复确认
			hs.timer.doAfter(FOCUS_CHECK_INTERVAL, function()
				ensureWindowFocused(window, MAX_FOCUS_CHECKS)
			end)
		end)
	end

	-- 取消最小化需要一点时间，等窗口恢复后再聚焦
	if wasMinimized then
		hs.timer.doAfter(0.1, run)
	else
		run()
	end

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
--
-- 使用模块级的 arrangeSession 做互斥：
-- Kitty 尚未运行时，Ctrl + Shift + L / Ctrl + Shift + H / Ctrl + Shift + T
-- 三个快捷键都会走到这里。如果不加锁，每个快捷键都会各自启动一个
-- 轮询循环，每个循环在自己的 newWindowRequested 上各发一次
-- Command + N，最终会多开出好几个窗口。
--
-- 同一时间只允许存在一个会话，后来的调用直接复用已有会话。
----------------------------------------------------------------------

local arrangeSession = nil

local function waitAndArrangeKitty()
	--------------------------------------------------------------
	-- 已经有会话在跑，直接复用，不再启动新的循环
	--------------------------------------------------------------

	if arrangeSession then
		return
	end

	local session = {
		retryCount = 0,
		newWindowRequested = false,
	}

	arrangeSession = session

	--------------------------------------------------------------
	-- 结束会话
	--
	-- 只有自己仍然是当前会话时才清空，避免误清掉别的会话。
	--------------------------------------------------------------

	local function finish()
		if arrangeSession == session then
			arrangeSession = nil
		end
	end

	local function check()
		-- 会话已被其他路径结束
		if arrangeSession ~= session then
			return
		end

		session.retryCount = session.retryCount + 1

		if session.retryCount > MAX_RETRY_COUNT then
			finish()
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
			if not session.newWindowRequested then
				session.newWindowRequested = true
				createNewKittyWindow()
			end

			hs.timer.doAfter(RETRY_INTERVAL, check)
			return
		end

		----------------------------------------------------------
		-- 已有至少两个窗口，开始排列
		----------------------------------------------------------

		-- 先结束会话，再执行排列：
		-- 排列本身可能要几百毫秒，期间不应该阻塞新的会话。
		finish()

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
	--------------------------------------------------------------
	-- 已经有等待会话在跑
	--
	-- 用户可能连续按下 Ctrl + Shift + L / Ctrl + Shift + H / Ctrl + Shift + T，
	-- 此时不要再启动 Kitty、也不要再开新的轮询循环。
	--------------------------------------------------------------

	if arrangeSession then
		return
	end

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

	focusSingleWindow(window)
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

	focusSingleWindow(window)
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
