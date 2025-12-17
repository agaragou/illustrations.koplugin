local Dispatcher = require("dispatcher")
local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")
local NetworkMgr = require("ui/network/manager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local JSON = require("json")
local GestureRange = require("ui/gesturerange")
local _ = require("gettext")
local logger = require("logger")
local Device = require("device")
local Screen = Device.screen
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local Event = require("ui/event")
local Blitbuffer = require("ffi/blitbuffer")
local lfs = require("libs/libkoreader-lfs")
local ImageWidget = require("ui/widget/imagewidget")
local ButtonDialog = require("ui/widget/buttondialog")
local InputContainer = require("ui/widget/container/inputcontainer")
local CenterContainer = require("ui/widget/container/centercontainer")
local FrameContainer = require("ui/widget/container/framecontainer")
local TextBoxWidget = require("ui/widget/textboxwidget")
local ScrollableContainer = require("ui/widget/container/scrollablecontainer")
local VerticalGroup = require("ui/widget/verticalgroup")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local Button = require("ui/widget/button")
local TitleBar = require("ui/widget/titlebar")
local DataStorage = require("datastorage")
local InputDialog = require("ui/widget/inputdialog")
local ConfirmBox = require("ui/widget/confirmbox")
local RenderImage = require("ui/renderimage")

-- Define GalleryWindow class locally
local GalleryWindow = InputContainer:extend{
    modal = true,
    fullscreen = true,
    width = nil,
    height = nil,
    image_path = nil,
    page = nil,
    index = nil,
    total = nil,
    callback_prev = nil,
    callback_next = nil,
    callback_close = nil,
    callback_goto = nil,
    illustrations_plugin = nil,
    is_favorites = false,
}

function GalleryWindow:init()
    InputContainer._init(self)
    
    self.width = Screen:getWidth()
    self.height = Screen:getHeight()
    self.dimen = Geom:new{ x = 0, y = 0, w = self.width, h = self.height }
    
    -- 1. Image Widget
    self.image = ImageWidget:new{
        file = self.image_path,
        width = self.width,
        height = self.height,
        scale_factor = 0, -- Fit to screen keeping aspect ratio
        file_do_cache = false, -- Disable caching to prevent OOM on low-RAM devices
    }
    
    -- 2. Center Container (centers the image)
    self.center_wrapper = CenterContainer:new{
        dimen = self.dimen,
        self.image
    }
        
    -- 3. Frame Container (Black Background)
    self.frame_wrapper = FrameContainer:new{
        dimen = self.dimen,
        padding = 0,
        bordersize = 0,
        background = Blitbuffer.COLOR_BLACK,
        self.center_wrapper
    }
        
    -- Set as main child
    self[1] = self.frame_wrapper
        
    -- 4. Status Text (Overlay)
    self.status_text = TextBoxWidget:new{
        text = string.format("%d / %d", self.index, self.total),
        face = require("ui/font"):getFace("infofont"),
        fg_color = Blitbuffer.COLOR_WHITE,
        bg_color = Blitbuffer.COLOR_BLACK,
    }
        
    -- Setup Navigation
    if Device:isTouchDevice() then
        self.ges_events.TapPrev = {
            GestureRange:new{
                ges = "tap",
                range = Geom:new{ x = 0, y = 0, w = self.width * 0.3, h = self.height },
                func = function() self:onPrev() end,
            }
        }
        self.ges_events.TapNext = {
            GestureRange:new{
                ges = "tap",
                range = Geom:new{ x = self.width * 0.7, y = 0, w = self.width * 0.3, h = self.height },
                func = function() self:onNext() end,
            }
        }
        self.ges_events.TapMenu = {
            GestureRange:new{
                ges = "tap",
                range = Geom:new{ x = self.width * 0.3, y = 0, w = self.width * 0.4, h = self.height * 0.33 },
                func = function() self:showControls() end,
            }
        }
    end
        
    if Device:hasKeys() then
        self.key_events.Next = { { "Right" }, { "RPgFwd" } }
        self.key_events.Prev = { { "Left" }, { "RPgBack" } }
            
        self.key_events.Close = { { "Back" }, { "Esc" } }
        if Device:hasFewKeys() then
            table.insert(self.key_events.Close, { "Left" })
        else
            table.insert(self.key_events.Close, { "Menu" })
        end
    end
end
    
function GalleryWindow:paint(gc)
    -- Paint the main hierarchy (Frame -> Center -> Image)
    InputContainer.paint(self, gc)
        
    -- Paint Status Text Overlay
    if self.status_text then
        local txt_w = self.status_text:getWidth()
        local txt_h = self.status_text:getHeight()
        self.status_text.dimen.x = math.floor((self.width - txt_w) / 2)
        self.status_text.dimen.y = self.height - txt_h - 10
        self.status_text:paint(gc)
    end
end

function GalleryWindow:setImage(path, page, index)
    self.image_path = path
    self.page = page
    self.index = index
        
    -- ImageWidget doesn't support dynamic updates, so we replace it
    local new_image = ImageWidget:new{
        file = path,
        width = self.width,
        height = self.height,
        scale_factor = 0, -- Fit to screen keeping aspect ratio
        file_do_cache = false, -- Disable caching to prevent OOM on low-RAM devices
    }
        
    -- Replace in CenterContainer
    self.image = new_image
    self.center_wrapper[1] = self.image
        
    -- Update Status Text
    if self.status_text then
        self.status_text:setText(string.format("%d / %d", self.index, self.total))
    end
        
    -- Force repaint of the entire window
    UIManager:setDirty(self, function() return "ui", self.dimen end)
end

function GalleryWindow:onNext()
    if self.callback_next then self.callback_next() end
    return true
end

function GalleryWindow:onPrev()
    if self.callback_prev then self.callback_prev() end
    return true
end

function GalleryWindow:onClose()
    if self.callback_close then self.callback_close(true) end
    return true
end

-- Touch Event Handlers
function GalleryWindow:onTapPrev() return self:onPrev() end
function GalleryWindow:onTapNext() return self:onNext() end
function GalleryWindow:onTapMenu() return self:showControls() end
    
function GalleryWindow:showControls()
    -- Close the gallery first to ensure the dialog is visible
    -- We use callback_close to ensure the plugin's reference is cleared
    if self.callback_close then self.callback_close(false) end
    
    UIManager:nextTick(function()
        local buttons = {}
        
        -- Row 1: Navigation and Favorites
        local row1 = {}
        if self.page and self.page > 0 then
            table.insert(row1, {
                text = _("Go to Page ") .. self.page,
                callback = function()
                    UIManager:close(dialog)
                    if self.callback_goto then self.callback_goto(self.page) end
                end,
            })
        end
        
        table.insert(row1, {
            text = self.is_favorites and _("Remove from Favorites") or _("Add to Favorites"),
            callback = function()
                UIManager:close(dialog)
                if self.is_favorites then
                    self.illustrations_plugin:removeFromFavorites(self.image_path)
                    -- Return to gallery to refresh the list (and avoid showing deleted file)
                    if self.callback_thumbnails then self.callback_thumbnails() end
                else
                    self.illustrations_plugin:addToFavorites(self.image_path)
                    -- Resume viewing (stay on image)
                    if self.callback_resume then self.callback_resume(self.index) end
                end
            end,
        })
        table.insert(buttons, row1)
        
        -- Row 2: Gallery and Resume
        local row2 = {}
        table.insert(row2, {
            text = _("Open Gallery"),
            callback = function()
                UIManager:close(dialog)
                if self.callback_thumbnails then self.callback_thumbnails() end
            end,
        })
        table.insert(row2, {
            text = _("Resume"),
            callback = function()
                UIManager:close(dialog)
                -- Re-open gallery at current index
                if self.callback_resume then self.callback_resume(self.index) end
            end,
        })
        table.insert(buttons, row2)
        
        -- Row 3: Exit
        local row3 = {}
        table.insert(row3, {
            text = _("Exit"),
            callback = function()
                UIManager:close(dialog)
                -- Already closed, but safe to call again
                if self.callback_close then self.callback_close(true) end
            end,
        })
        table.insert(buttons, row3)

        dialog = ButtonDialog:new{
            buttons = buttons
        }
        UIManager:show(dialog)
    end)
end


-- Thumbnail Window Class
local ThumbnailWindow = InputContainer:extend{
    name = "ThumbnailWindow",
    page_size = 9,
}

function ThumbnailWindow:init()
    self.images = self.images or {}
    self.title = self.title or _("Gallery")
    
    -- Pagination State
    self.current_page = 1
    self.total_pages = math.ceil(#self.images / self.page_size)
    if self.total_pages < 1 then self.total_pages = 1 end
    
    -- Main Layout
    self.width = Screen:getWidth()
    self.height = Screen:getHeight()
    self.dimen = Geom:new{ x = 0, y = 0, w = self.width, h = self.height }
    
    -- 1. Title Bar
    local title_bar = TitleBar:new{
        width = self.width,
        title = self.title,
        show_parent = self,
        close_callback = function() self:onClose() end,
    }
    
    -- 2. Grid Container (Placeholder)
    self.grid_v_group = VerticalGroup:new{ align = "left" }
    
    -- Fixed Height for Scroll Area (80% of screen - SAFE)
    local scroll_h = math.floor(self.height * 0.80)
    
    self.scroll_container = ScrollableContainer:new{
        dimen = Geom:new{ x = 0, y = 0, w = self.width, h = scroll_h }, 
        self.grid_v_group,
    }

local LeftContainer = require("ui/widget/container/leftcontainer")
local RightContainer = require("ui/widget/container/rightcontainer")
-- thumbnail window init...

    -- 3. Bottom Bar (Controls)
    self.btn_prev = Button:new{
        text = "  <  ",
        callback = function() self:prevPage() end,
        bordersize = 1,
    }
    self.btn_next = Button:new{
        text = "  >  ",
        callback = function() self:nextPage() end,
        bordersize = 1,
    }
    self.lbl_page = TextBoxWidget:new{
        text = "Page 1 / 1",
        face = require("ui/font"):getFace("smallinfofont"),
        alignment = "center", -- Explicitly center the text inside the widget
        padding = 10,
    }
    
    local bottom_bar = HorizontalGroup:new{
        align = "center",
        padding = 15,
        self.btn_prev,
        self.lbl_page,
        self.btn_next,
    }
    
    -- 4. Root Group
    local root_group = VerticalGroup:new{
        align = "center",
        title_bar,
        self.scroll_container,
        bottom_bar,
    }

    self[1] = FrameContainer:new{
        dimen = self.dimen,
        padding = 0,
        bordersize = 0,
        background = Blitbuffer.COLOR_WHITE,
        root_group
    }
    
    self.cropping_widget = self.scroll_container
    
    -- Initial Population
    self:refreshGrid()
end

function ThumbnailWindow:refreshGrid()
    local start_idx = (self.current_page - 1) * self.page_size + 1
    local end_idx = math.min(start_idx + self.page_size - 1, #self.images)
    
    local page_items = {}
    for i = start_idx, end_idx do
        table.insert(page_items, self.images[i])
    end
    
    local rows = {}
    local cols = 3
    local row_items = {}
    
    -- Layout Metrics
    local padding = 10
    local item_w = math.floor((self.width - (cols + 1) * padding) / cols)
    
    -- Calculate height to fit 3 rows exactly in the 87% scroll area
    -- Available height for grid = Screen * 0.87
    -- We need to fit 3 rows + 4 paddings (top, mid, mid, bottom)
    local scroll_area_h = math.floor(self.height * 0.87)
    local max_h_per_row = math.floor((scroll_area_h - (3 + 1) * padding) / 3)
    
    -- Use the smaller of: Aspect Ratio Height (4/3) OR Max Fitting Height
    local item_h = math.min(math.floor(item_w * 4 / 3), max_h_per_row) 
    
    for i, img_data in ipairs(page_items) do
        local global_index = start_idx + i - 1
        
        -- 1. Create the ImageWidget (proven proper rendering)
        local img_widget = ImageWidget:new{
            file = img_data.path,
            width = item_w,
            height = item_h,
            scale_factor = 0, 
            file_do_cache = false,
        }
        
        -- 2. Create the Button (proven proper touch handling)
        -- We initialize it with empty text to act as a container shell
        local btn = Button:new{
            text = "",
            width = item_w,
            height = item_h,
            padding = 0,
            bordersize = 0,
            frame_bordersize = 0,
            callback = function()
                self:onClose()
                if self.callback_open then self.callback_open(global_index) end
            end,
        }
        
        -- IMPORTANT: Set text to nil so Button doesn't try to invert text color on click
        -- (which would crash because we are replacing the text widget with an image)
        btn.text = nil
        
        -- 3. TRANSPLANT: Replace Button's internal text widget with our ImageWidget
        -- Button structure: self.frame -> self.label_container -> self.label_widget
        if btn.label_container then
             -- Free the default empty text widget
             if btn.label_widget and btn.label_widget.free then
                 btn.label_widget:free()
             end
             
             -- Inject our image
             btn.label_container[1] = img_widget
             btn.label_widget = img_widget -- update reference
        end
        
        table.insert(row_items, btn)
        
        if #row_items == cols then
            table.insert(rows, HorizontalGroup:new{ gap = padding, table.unpack(row_items) })
            row_items = {}
        end
    end
    if #row_items > 0 then
        table.insert(rows, HorizontalGroup:new{ gap = padding, table.unpack(row_items) })
    end
    
    -- New Grid Group
    self.grid_v_group = VerticalGroup:new{ 
        align = "left", 
        padding = padding, 
        gap = padding,
        table.unpack(rows) 
    }
    
    -- Re-create ScrollableContainer (Stable way)
    local scroll_h = math.floor(self.height * 0.87)
    
    local new_scroll = ScrollableContainer:new{
        dimen = Geom:new{ x = 0, y = 0, w = self.width, h = scroll_h }, 
        self.grid_v_group,
    }
    
    -- Replace in Root Group
    self.scroll_container = new_scroll
    self.cropping_widget = new_scroll
    self[1][1][2] = new_scroll
    
    -- Update Controls
    self.lbl_page:setText(string.format("Page %d / %d", self.current_page, self.total_pages))
    
    if self.btn_prev.enableDisable then
        self.btn_prev:enableDisable(self.current_page > 1)
    end
    if self.btn_next.enableDisable then
        self.btn_next:enableDisable(self.current_page < self.total_pages)
    end
    
    UIManager:setDirty(self, "full")
end

function ThumbnailWindow:prevPage()
    if self.current_page > 1 then
        self.current_page = self.current_page - 1
        self:refreshGrid()
    end
end

function ThumbnailWindow:nextPage()
    if self.current_page < self.total_pages then
        self.current_page = self.current_page + 1
        self:refreshGrid()
    end
end

function ThumbnailWindow:onClose()
    if self.callback_close then self.callback_close() end
    UIManager:close(self)
    return true
end

-- Key events for closing
function ThumbnailWindow:onCloseKey() return self:onClose() end
ThumbnailWindow.key_events = {
    Close = { { "Back" }, { "Esc" }, { "Menu" } },
    PageBack = { { "Left" } },
    PageFwd = { { "Right" } },
}
-- Map Left/Right keys to pagination
function ThumbnailWindow:onPageBack() self:prevPage() return true end
function ThumbnailWindow:onPageFwd() self:nextPage() return true end


local Illustrations = WidgetContainer:extend{
    name = "Illustrations",
}

function Illustrations:init()
    self.ui.menu:registerToMainMenu(self)
    self.scan_cache = {}

    Dispatcher:registerAction("show_gallery_mode", {
        category = "none",
        event = "ShowGalleryMode",
        title = _("Illustrations: Show Gallery"),
        general = true,
    })
    
    Dispatcher:registerAction("show_illustrations_mode", {
        category = "none",
        event = "ShowIllustrationsMode",
        title = _("Illustrations: Show Illustrations"),
        general = true,
    })
    
    Dispatcher:registerAction("show_favorites_gallery", {
        category = "none",
        event = "ShowFavoritesGallery",
        title = _("Illustrations: Show Favorites"),
        general = true,
    })

    -- Check for updates safely
    UIManager:scheduleIn(3, function()
        self:checkUpdate()
    end)
end

function Illustrations:onShowGalleryMode()
    if self.ui.document then
        self:showGalleryMode()
    end
end

function Illustrations:onShowIllustrationsMode()
    if self.ui.document then
        self:showIllustrationsMode()
    end
end

function Illustrations:onShowFavoritesGallery()
    self:showFavoritesGallery()
end

-- Helper to get local version
function Illustrations:getLocalVersion()
    local info = debug.getinfo(1, "S")
    local source = info.source
    local base_path = source:match("^@(.+)/[^/]+$")
    if not base_path then return nil end
    
    local f, err = loadfile(base_path .. "/_meta.lua")
    if not f then return nil end
    
    local meta = f()
    return meta and meta.version
end

-- Update Checker
function Illustrations:checkUpdate()
    -- Only run check if we are NOT reading a book (Home screen / File Manager)
    if self.ui.document then return end

    -- Check setting (default true)
    local check_enabled = G_reader_settings:readSetting("illustrations_check_updates")
    if check_enabled == false then return end -- Explicitly false means disabled

    -- Basic check for network connection
    if not NetworkMgr:isOnline() then return end
    
    local current_version = self:getLocalVersion()
    if not current_version then return end
    
    -- URL of the remote _meta.lua
    local url = "https://raw.githubusercontent.com/agaragou/illustrations.koplugin/refs/heads/main/_meta.lua"
    
    local status, https = pcall(require, "ssl.https")
    if not status then return end

    local body, code, headers, status_line = https.request(url)
    
    if code == 200 and body then
        local remote_version = body:match("version%s*=%s*[\"']([^\"']+)[\"']")
        if not remote_version then
            remote_version = body:match("version%s*=%s*([%d%.]+)")
        end
        
        if remote_version then
            self.remote_version = remote_version -- Store for About dialog
            
            if self:compareVersions(remote_version, current_version) > 0 then
                UIManager:show(InfoMessage:new{
                    text = "Illustrations plugin\n" .. _("New version available: ") .. remote_version .. "\n" .. _("Current: ") .. current_version,
                    timeout = 5,
                })
            end
        end
    end
end

function Illustrations:onShowAbout()
    local current_version = self:getLocalVersion() or "?.?"
    local ver_status = "(latest)"
    
    if self.remote_version then
        if self:compareVersions(self.remote_version, current_version) > 0 then
            ver_status = "(v" .. self.remote_version .. " available!)"
        end
    end
    
    local settings_path = DataStorage:getSettingsDir() .. "/settings.reader.lua"
    local icons_root = self:getCachePaths() -- This is illustrations root
    
    local text = string.format("Illustrations plugin v%s %s\n\n", current_version, ver_status)
    text = text .. "Official repository:\nhttps://github.com/agaragou/illustrations.koplugin\n\n"
    text = text .. _("Settings stored in:") .. "\n" .. settings_path .. "\n\n"
    text = text .. _("Cache stored in:") .. "\n" .. icons_root
    
    UIManager:show(InfoMessage:new{
        text = text,
        timeout = nil, -- Stay until tapped
        show_icon = true,
        icon = "info",
    })
end

function Illustrations:compareVersions(v1, v2)
    local v1_str = tostring(v1)
    local v2_str = tostring(v2)
    
    local p1 = {}
    for part in v1_str:gmatch("%d+") do table.insert(p1, tonumber(part)) end
    local p2 = {}
    for part in v2_str:gmatch("%d+") do table.insert(p2, tonumber(part)) end
    
    for i = 1, math.max(#p1, #p2) do
        local n1 = p1[i] or 0
        local n2 = p2[i] or 0
        if n1 > n2 then return 1 end
        if n1 < n2 then return -1 end
    end
    return 0
end


function Illustrations:addToMainMenu(menu_items)
    local sub_item_table = {}
    
    -- 1. Settings Submenu
    local settings_items = {}
    
    -- Book-specific settings
    if self.ui.document then
        table.insert(settings_items, {
            text = _("Clear current book cache"),
            callback = function()
                self:clearBookCache()
            end,
        })
    end
    
    -- Global settings

    table.insert(settings_items, {
        text = _("Clear ALL books cache"),
        callback = function()
            self:clearAllCache()
        end,
    })
    
    table.insert(settings_items, {
        text = _("Clear Favorites"),
        callback = function()
            self:clearFavorites()
        end,
    })
    
    table.insert(settings_items, {
        text = _("About"),
        callback = function()
            self:onShowAbout()
        end,
    })
    
    table.insert(settings_items, {
        text = "----------------",
        enabled = false, 
        callback = function() end,
    })
    
    table.insert(settings_items, {
        text = _("Min Image Size"),
        sub_text_func = function()
            return tostring(G_reader_settings:readSetting("illustrations_min_size") or 300) .. "px"
        end,
        callback = function(menu)
            local current = G_reader_settings:readSetting("illustrations_min_size") or 300
            
            local dialog
            
            local function apply_setting(text)
                local size = tonumber(text)
                if size then
                    G_reader_settings:saveSetting("illustrations_min_size", size)
                    
                    -- Use the shared function silently IF we are in a book
                    if self.ui.document then
                        self:clearBookCache(true)
                    end
                    
                    -- Notify and refresh
                    UIManager:show(InfoMessage:new{
                        text = _("Setting saved."),
                        timeout = 2,
                    })
                end
            end

            dialog = InputDialog:new{
                title = _("Minimum Image Size (px)"),
                input = tostring(current),
                input_type = "number",
                callback = function(text) 
                    UIManager:close(dialog)
                    UIManager:nextTick(function() apply_setting(text) end)
                end,
                buttons = {
                    {
                        {
                            text = _("Cancel"),
                            id = "close",
                            callback = function()
                                UIManager:close(dialog)
                            end,
                        },
                        {
                            text = _("Apply"),
                            callback = function()
                                local text = dialog:getInputText()
                                UIManager:close(dialog)
                                UIManager:nextTick(function() apply_setting(text) end)
                            end,
                        },
                    }
                },
            }
            UIManager:show(dialog)
        end,
    })
    
    table.insert(settings_items, {
        text = _("Check for updates") .. " (v" .. (self:getLocalVersion() or "?") .. ")",
        checked_func = function()
            local current = G_reader_settings:readSetting("illustrations_check_updates")
            if current == nil then return true end -- Default on
            return current
        end,
        callback = function()
            local current = G_reader_settings:readSetting("illustrations_check_updates")
            if current == nil then current = true end
            G_reader_settings:saveSetting("illustrations_check_updates", not current)
        end,
    })
    
    if self.ui.document then
        table.insert(settings_items, {
            text = _("Allow Spoilers"),
            checked_func = function()
                return G_reader_settings:readSetting("illustrations_allow_spoilers")
            end,
            callback = function()
                local current = G_reader_settings:readSetting("illustrations_allow_spoilers")
                G_reader_settings:saveSetting("illustrations_allow_spoilers", not current)
            end,
        })
    end
    
    table.insert(sub_item_table, {
        text = _("Settings"),
        sub_item_table = settings_items
    })
    
    table.insert(sub_item_table, {
        text = "----------------",
        enabled = false, 
        callback = function() end,
    })
    
    -- 2. Favorites (Global)
    table.insert(sub_item_table, {
        text = _("Show Favorites Gallery"),
        callback = function()
            self:showFavoritesGallery()
        end,
    })
    
    -- 3. Book Illustrations (Book only)
    if self.ui.document then
        table.insert(sub_item_table, {
            text = _("Show Illustrations"),
            callback = function()
                self:showIllustrationsMode()
            end,
        })
        
        table.insert(sub_item_table, {
            text = _("Show Gallery"),
            callback = function()
                self:showGalleryMode()
            end,
        })
    end

    menu_items.illustrations = {
        text = _("Illustrations"),
        sorting_hint = "tools",
        sub_item_table = sub_item_table
    }
end

function Illustrations:showGalleryMode()
    self:findAndDisplayImages(true)
end

function Illustrations:showIllustrationsMode()
    self:findAndDisplayImages(false)
end



function Illustrations:getCachePaths()
    local doc = self.ui.document
    -- Doc might be nil in file browser
    
    local settings_dir = DataStorage:getSettingsDir()
    local cache_dir = DataStorage.getCacheDir and DataStorage:getCacheDir() or settings_dir:gsub("/settings$", "/cache")
    if cache_dir == settings_dir then cache_dir = settings_dir .. "/../cache" end
    
    local illustrations_root = cache_dir .. "/illustrations"
    
    -- IMPORTANT: Create the root folder if it doesn't exist
    if not lfs.attributes(illustrations_root) then
        lfs.mkdir(illustrations_root)
    end
    
    local book_dir = nil
    
    if doc then
        local doc_path = doc.file
        local doc_filename = doc_path:match("^.+/(.+)$") or doc_path
        local safe_dirname = doc_filename:gsub("[^%w%-_%.]", "_") .. "_extracted"
        book_dir = illustrations_root .. "/" .. safe_dirname .. "/"
    end
    
    return illustrations_root, book_dir
end


function Illustrations:getManifestPath()
    local root, book_dir = self:getCachePaths()
    if not book_dir then return nil end
    return book_dir .. "cache_manifest.lua"
end

function Illustrations:saveManifest(data)
    local path = self:getManifestPath()
    if not path then return end
    
    local f = io.open(path, "w")
    if not f then return end
    
    f:write("return {\n")
    f:write(string.format("  version = %d,\n", data.version or 1))
    f:write(string.format("  completed = %s,\n", tostring(data.completed)))
    f:write("  images = {\n")
    for _, img in ipairs(data.images) do
        f:write("    {\n")
        f:write(string.format("      path = %q,\n", img.path))
        f:write(string.format("      page = %d,\n", img.page))
        f:write(string.format("      valid = %s,\n", tostring(img.valid)))
        if img.width then f:write(string.format("      width = %d,\n", img.width)) end
        if img.height then f:write(string.format("      height = %d,\n", img.height)) end
        f:write("    },\n")
    end
    f:write("  }\n")
    f:write("}\n")
    f:close()
end

function Illustrations:loadManifest()
    local path = self:getManifestPath()
    if not path or not lfs.attributes(path) then return nil end
    
    local f, err = loadfile(path)
    if not f then return nil end
    
    -- Safe environment
    local env = {}
    setfenv(f, env)
    local status, res = pcall(f)
    if status then return res end
    return nil
end

function Illustrations:addToFavorites(source)
    local favorites_dir = self:getFavoritesPath()
    if not favorites_dir then return end
    
    if not lfs.attributes(favorites_dir) then
        lfs.mkdir(favorites_dir)
    end

    -- Case 1: Source is a file path (String)
    -- The internal gallery always works with extracted files
    if type(source) == "string" then
        local filename = source:match("^.+/(.+)$") or source
        local dest_path = favorites_dir .. "/" .. filename
        
        -- Copy file
        local cmd = "cp '" .. source .. "' '" .. dest_path .. "'"
        os.execute(cmd)
        
        -- UIManager:show(InfoMessage:new{ text = _("Added to Favorites") })
    else
         UIManager:show(InfoMessage:new{ text = _("Error: Only file paths supported in gallery mode") })
    end
end

function Illustrations:getFavoritesPath()
    local illustrations_root = self:getCachePaths()
    if not illustrations_root then return nil end
    return illustrations_root .. "/Favorites/"
end



function Illustrations:removeFromFavorites(image_path)
    os.remove(image_path)
    -- Verify removal
    if not lfs.attributes(image_path) then
        --UIManager:show(InfoMessage:new{ text = _("Removed from Favorites") })
    end
end

function Illustrations:showFavoritesGallery()
    local favorites_dir = self:getFavoritesPath()
    if not favorites_dir then return end
    
    if not lfs.attributes(favorites_dir) then
        lfs.mkdir(favorites_dir)
    end
    
    local images = {}
    for file in lfs.dir(favorites_dir) do
        if file ~= "." and file ~= ".." and file ~= ".DS_Store" then
             local full_path = favorites_dir .. file
             -- Retrieve original page number if preserved in metadata or filename, or just use 0
             table.insert(images, { path = full_path, page = 0 })
        end
    end
    
    if #images == 0 then
        UIManager:show(InfoMessage:new{ text = _("No favorites found.") })
        return
    end
    
    self:displayImages(images, true, nil, true) -- Pass is_favorites mode
end

function Illustrations:clearBookCache(silent)
    local root, book_dir = self:getCachePaths()
    if book_dir then
        local function do_clear()
            os.execute("rm -rf '" .. book_dir .. "'")
            if not silent then
                UIManager:show(InfoMessage:new{ text = _("Cache cleared.") })
            end
        end

        if silent then
            do_clear()
        else
            local text = _("Are you sure you want to delete the cache for this book?")
            UIManager:show(InfoMessage:new{
                text = text,
                timeout = nil, -- Stay until tapped
                show_icon = true,
                icon = "info",
            })
        end
    end
end

function Illustrations:clearAllCache()
    local illustrations_root, book_dir = self:getCachePaths()
    if illustrations_root then
        UIManager:show(ConfirmBox:new{
            text = _("Are you sure you want to delete ALL illustrations cache?\n(Favorites will NOT be deleted)"),
            ok_text = _("Delete All"),
            cancel_text = _("Cancel"),
            ok_callback = function()
                -- Iterate and delete everything EXCEPT Favorites
                for file in lfs.dir(illustrations_root) do
                    if file ~= "." and file ~= ".." and file ~= "Favorites" then
                         local full_path = illustrations_root .. "/" .. file
                         os.execute("rm -rf '" .. full_path .. "'")
                    end
                end
                UIManager:show(InfoMessage:new{ text = _("All book caches cleared.") })
            end
        })
    end
end

function Illustrations:clearFavorites()
    local favorites_dir = self:getFavoritesPath()
    if favorites_dir then
        UIManager:show(ConfirmBox:new{
            text = _("Are you sure you want to delete ALL Favorites?"),
            ok_text = _("Delete"),
            cancel_text = _("Cancel"),
            ok_callback = function()
                os.execute("rm -rf '" .. favorites_dir .. "'")
                UIManager:show(InfoMessage:new{ text = _("Favorites cleared.") })
            end
        })
    end
end

function Illustrations:getImagesFromPage(page)
    local images = {}
    local doc = self.ui.document
    if not doc then return images end

    -- Try to get HTML content using XPointers
    local html = nil
    
    if doc.getHTMLFromXPointers and doc.getPageXPointer then
        local start_xp = doc:getPageXPointer(page)
        local end_xp = doc:getPageXPointer(page + 1)
        
        if start_xp then
            if end_xp then
                html = doc:getHTMLFromXPointers(start_xp, end_xp)
            else
                html = doc:getHTMLFromXPointers(start_xp, nil) 
            end
        end
    end

    -- Fallback
    if not html and doc.getPageHTML then
        html = doc:getPageHTML(page)
    end

    if html then
        -- Pattern 1: Standard <img> tag
        for src in html:gmatch("<img[^>]+src%s*=%s*[\"']([^\"']+)[\"']") do
            table.insert(images, { src = src, page = page })
        end

        -- Pattern 2: SVG <image> tag
        -- xlink:href
        for src in html:gmatch("<image[^>]+xlink:href%s*=%s*[\"']([^\"']+)[\"']") do
            table.insert(images, { src = src, page = page })
        end
        
        -- href (some SVG usage)
        for src in html:gmatch("<image[^>]+href%s*=%s*[\"']([^\"']+)[\"']") do
            table.insert(images, { src = src, page = page })
        end
    end
    return images
end

function Illustrations:getImageDimensions(path)
    local bb = RenderImage:renderImageFile(path)
    if not bb then return 0, 0 end
    local w = bb:getWidth()
    local h = bb:getHeight()
    bb:free()
    return w, h
end



function Illustrations:findAndDisplayImages(is_gallery_mode)
    local doc = self.ui.document
    if not doc then
        return 
    end

    local current_page = self.ui:getCurrentPage()
    
    local allow_spoilers = G_reader_settings:readSetting("illustrations_allow_spoilers")
    local max_page = nil
    
    if not allow_spoilers then
        max_page = current_page
    end

    local illustrations_root, output_dir = self:getCachePaths()
    if not output_dir then return end

    local illustrations_root, storage_dir = self:getCachePaths()
    if not storage_dir then return end

    -- 1. Try Load Manifest
    local manifest = self:loadManifest()
    
    -- If valid manifest exists, JUST DISPLAY and return
    if manifest and manifest.completed then
        self:displayImages(manifest.images, is_gallery_mode, max_page)
        return
    end

    -- 2. Full Scan Required
    -- If we are here, it means either:
    -- a) It's a fresh book
    -- b) It's an old cache without manifest (Legacy)
    -- In both cases, we MUST scan and generate the manifest.
    
    if not lfs.attributes(storage_dir) then lfs.mkdir(storage_dir) end

    local loading = InfoMessage:new{
        text = _("First time setup: Scanning & Extracting..."),
    }
    UIManager:show(loading)
    UIManager:forceRePaint()

    local co = coroutine.create(function()
        local final_images = {}
        local ext = doc.file:lower():match("%.([^%.]+)$")
        local is_cbz = (ext == "cbz")

        if is_cbz then
            -- === CBZ STRATEGY: UNZIP ALL -> SORT -> MAP ===
            
            -- 1. Unzip All
            local cmd = string.format("unzip -j -o -q '%s' ", doc.file)
            cmd = cmd .. "'*.jpg' '*.jpeg' '*.png' '*.gif' '*.svg' '*.webp' -d '" .. storage_dir .. "'"
            os.execute(cmd)
            
            -- 2. List & Sort
            local files = {}
            for file in lfs.dir(storage_dir) do
                if file ~= "." and file ~= ".." and file ~= "cache_manifest.lua" then
                     table.insert(files, file)
                end
            end
            
            -- Natural Sort Helper
            table.sort(files, function(a, b)
                -- Extract numbers for comparison
                local function padnum(n) return string.format("%05d", n) end
                local na = a:gsub("%d+", padnum)
                local nb = b:gsub("%d+", padnum)
                return na < nb
            end)
            
            -- 3. Map to Manifest
            for i, filename in ipairs(files) do
                local full_path = storage_dir .. filename
                table.insert(final_images, {
                    path = full_path,
                    page = i, -- Assume sequential page mapping
                    valid = true, -- Always valid for comics
                    width = 0, -- Skip measurement
                    height = 0
                })
            end

        else
            -- === EPUB/FB2 STRATEGY: PAGE SCAN -> EXTRACT -> VALIDATE ===
            
            local all_images = {}
            local processed = 0
            local total_pages = doc:getPageCount()
            
            -- SCAN ALL PAGES (map structure)
            for page = 1, total_pages do
                local page_images = self:getImagesFromPage(page)
                if page_images then
                    for _, img in ipairs(page_images) do
                        table.insert(all_images, img)
                    end
                end
                
                processed = processed + 1
                if processed % 20 == 0 then coroutine.yield() end
            end
            
            -- BULK EXTRACT
            if #all_images > 0 then
                -- 1. Unzip All
                local cmd = string.format("unzip -j -o -q '%s' ", doc.file)
                cmd = cmd .. "'*.jpg' '*.jpeg' '*.png' '*.gif' '*.svg' '*.webp' -d '" .. storage_dir .. "'"
                os.execute(cmd)
                
                -- 2. Process & Validate Metadata
                local min_size = G_reader_settings:readSetting("illustrations_min_size") or 300
                local seen_paths = {}
    
                for _, img in ipairs(all_images) do
                     local clean_src = img.src:gsub("%.%./", ""):gsub("^/", "")
                     local basename = clean_src:match("^.+/(.+)$") or clean_src
                     local full_path = storage_dir .. basename
                     
                     if not seen_paths[full_path] then
                         seen_paths[full_path] = true
                         
                         local valid = false
                         local w, h = 0, 0
                         
                         if lfs.attributes(full_path) then
                             w, h = self:getImageDimensions(full_path)
                             if math.min(w, h) >= min_size then
                                 valid = true
                             else
                                 -- Delete invalid to save space
                                 os.remove(full_path)
                             end
                         end
                         
                         table.insert(final_images, {
                             path = full_path,
                             page = img.page,
                             valid = valid,
                             width = w,
                             height = h
                         })
                     end
                     
                     if processed % 10 == 0 then coroutine.yield() end
                end
            end
        end
        
        -- SAVE MANIFEST
        local new_manifest = {
            version = 1,
            completed = true,
            images = final_images
        }
        self:saveManifest(new_manifest)
        
        UIManager:scheduleIn(0, function()
            UIManager:close(loading)
            self:displayImages(final_images, is_gallery_mode, max_page)
        end)
    end)

    
    -- Scheduler
    local function resume()
        if coroutine.status(co) ~= "dead" then
            local ok, err = coroutine.resume(co)
            if not ok then
                logger.warn("Illustrations: Error scan: " .. tostring(err))
                UIManager:close(loading)
            else
                UIManager:scheduleIn(0.01, resume)
            end
        end
    end
    resume()
end

function Illustrations:displayImages(images, is_gallery_mode, max_page, is_favorites)
    local extracted_images = {}
    
    if is_favorites then
        -- Favorites are always valid paths
        for _, img in ipairs(images) do
             -- Compatibility map
             table.insert(extracted_images, { path = img.path, page = img.page or 0 })
        end
    else
        -- Manifest Mode
        -- 'images' is the manifest.images list
        local allow_spoilers = G_reader_settings:readSetting("illustrations_allow_spoilers")
        
        for _, img in ipairs(images) do
            if img.valid then
                -- Spoiler Check
                -- If max_page is set (from findAndDisplayImages passing it), we respect it.
                -- Or check global allow_spoilers logic if logical cohesion requires it here.
                -- Actually, findAndDisplayImages calculates max_page based on allow_spoilers.
                
                local visible = true
                if max_page and img.page > max_page then
                    visible = false
                end
                
                if visible then
                    table.insert(extracted_images, { path = img.path, page = img.page })
                end
            end
        end
    end

    if #extracted_images == 0 then
        UIManager:show(InfoMessage:new{
            text = _("No images found."),
        })
        return
    end

    -- Helper function to show a specific image
    local function showGalleryImage(index)
        if index < 1 then index = 1 end
        if index > #extracted_images then index = #extracted_images end
        
        local img = extracted_images[index]

        if self.grid_window then
            -- Reuse existing window
            self.grid_window:setImage(img.path, img.page, index)
            -- Update current index on reusing
            self.grid_window.index = index
        else
            -- Create new window
            -- Show the Gallery Window (using nextTick to ensure previous dialog is closed)
            UIManager:nextTick(function()
                local gallery = GalleryWindow:new{
                    image_path = img.path,
                    page = img.page,
                    index = index,
                    total = #extracted_images,
                    callback_prev = function() 
                        local new_idx = self.grid_window.index - 1
                        if new_idx < 1 then new_idx = #extracted_images end
                        showGalleryImage(new_idx)
                    end,
                    callback_next = function() 
                        local new_idx = self.grid_window.index + 1
                        if new_idx > #extracted_images then new_idx = 1 end
                        showGalleryImage(new_idx)
                    end,
                    callback_resume = function(index)
                        showGalleryImage(index)
                    end,
                    callback_close = function(do_refresh)
                        if self.grid_window then
                            UIManager:close(self.grid_window)
                            self.grid_window = nil
                        end
                        if do_refresh then
                            -- Force full repaint to clear artifacts
                            UIManager:setDirty(nil, "full")
                        end
                    end,
                    callback_goto = function(page)
                        self.ui:handleEvent(Event:new("GotoPage", page))
                        if self.grid_window then
                            UIManager:close(self.grid_window)
                            self.grid_window = nil
                            -- Force full repaint to clear artifacts
                            UIManager:setDirty(nil, "full")
                        end
                    end,
                    callback_thumbnails = function()
                        -- Close gallery is handled by the button callback in GalleryWindow
                        -- We just need to show thumbnails again
                        if is_favorites then
                            self:showFavoritesGallery()
                        else
                            self:showGalleryMode()
                        end
                    end,
                    illustrations_plugin = self,
                    is_favorites = is_favorites,
                }
                
                self.grid_window = gallery
                UIManager:show(gallery)
            end)
        end
    end


    if is_gallery_mode then
        -- Show Gallery (Grid) View
        UIManager:nextTick(function()
            local thumbs = ThumbnailWindow:new{
                images = extracted_images,
                title = is_favorites and _("Favorites") or _("Gallery"),
                callback_open = function(index)
                    -- Open single image view
                    showGalleryImage(index)
                end,
            }
            UIManager:show(thumbs)
        end)
    else
        -- Show Single Image View (Illustrations)
        local start_index = 1
        -- Try to find the image closest to current page (but not after, if possible)
        -- Actually, logic usually is "show all images found up to current page"
        -- If allow_spoilers is FALSE, extracted_images only contains safe images.
        -- We probably want to start from the *latest* one (most recently read)
        if not allow_spoilers then
            start_index = #extracted_images 
        end
        
        showGalleryImage(start_index)
    end
end

return Illustrations
