local Dispatcher = require("dispatcher")
local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")
local NetworkMgr = require("ui/network/manager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
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
    modal = true,
    fullscreen = true,
    width = nil,
    height = nil,
    images = nil,
    callback_open = nil,
    callback_close = nil,
    title = "Gallery",
}

function ThumbnailWindow:init()
    InputContainer._init(self)
    
    self.width = Screen:getWidth()
    self.height = Screen:getHeight()
    self.dimen = Geom:new{ x = 0, y = 0, w = self.width, h = self.height }
    
    -- Grid Layout Calculation
    local cols = 3
    local padding = 10
    local item_width = math.floor((self.width - (cols + 1) * padding) / cols)
    -- Aspect ratio 3:4 for book covers/pages usually works well, or 1:1
    -- Let's use 3:4 ratio for thumbnails
    local item_height = math.floor(item_width * 4 / 3) 
    
    local v_group = VerticalGroup:new{
        align = "left",
    }
    
    -- Add Title Bar
    local title_bar = TitleBar:new{
        width = self.width,
        title = self.title,
        show_parent = self,
        close_callback = function() self:onClose() end,
    }
    table.insert(v_group, title_bar)
    
    -- Grid Content
    local grid_v_group = VerticalGroup:new{
        align = "left",
        padding = padding,
        gap = padding,
    }
    
    local current_row = nil
    
    for i, img in ipairs(self.images) do
        if (i - 1) % cols == 0 then
            current_row = HorizontalGroup:new{
                align = "top",
                gap = padding,
            }
            table.insert(grid_v_group, current_row)
        end
        
        -- Thumbnail Image
        local image_widget = ImageWidget:new{
            file = img.path,
            width = item_width,
            height = item_height,
            scale_factor = 0, -- Fit to box
            file_do_cache = false, -- Disable cache
        }
        
        -- Frame for border/padding
        local thumb_frame = FrameContainer:new{
            bordersize = 1,
            padding = 0,
            dimen = Geom:new{w = item_width, h = item_height},
            CenterContainer:new{
                dimen = Geom:new{w = item_width, h = item_height},
                image_widget
            }
        }
        
        table.insert(current_row, thumb_frame)
    end
    
    -- Scrollable Area
    local scroll_height = self.height - title_bar:getHeight()
    local scroll_container = ScrollableContainer:new{
        dimen = Geom:new{w = self.width, h = scroll_height},
        show_parent = self, -- Critical for repaint!
        grid_v_group,
    }

    table.insert(v_group, scroll_container)
    
    self[1] = FrameContainer:new{
        dimen = self.dimen,
        padding = 0,
        bordersize = 0,
        background = Blitbuffer.COLOR_WHITE,
        v_group
    }
    
    -- Set cropping widget for ScrollableContainer to work correctly with UIManager
    self.cropping_widget = scroll_container
    
    -- Register events on the main window using registerTouchZones
    self:registerTouchZones({
        {
            id = "thumb_tap",
            ges = "tap",
            screen_zone = { ratio_x = 0, ratio_y = 0, ratio_w = 1, ratio_h = 1 },
            handler = function(ges)
                -- Calculate which item was clicked
                local x = ges.pos.x
                local y = ges.pos.y - title_bar:getHeight() -- Adjust for title bar
                
                -- Add scroll offset
                local scroll_off = scroll_container:getScrolledOffset()
                
                local real_y = y + scroll_off.y
                local real_x = x + scroll_off.x
                
                -- Grid calculations
                -- We have padding around the grid and between items
                -- grid_v_group has padding
                
                -- Effective coordinates inside the grid content
                local content_x = real_x - padding
                local content_y = real_y - padding
                
                if content_x < 0 or content_y < 0 then return end
                
                local col = math.floor(content_x / (item_width + padding))
                local row = math.floor(content_y / (item_height + padding))
                
                -- Check if we are inside the item (accounting for gap)
                local in_col_x = content_x % (item_width + padding)
                local in_row_y = content_y % (item_height + padding)
                
                if in_col_x > item_width or in_row_y > item_height then
                    return -- Clicked in the gap
                end
                
                if col >= 0 and col < cols then
                    local index = (row * cols) + col + 1
                    if index <= #self.images then
                        self:onClose()
                        if self.callback_open then self.callback_open(index) end
                    end
                end
                return true
            end
        },
        {
            id = "thumb_swipe",
            ges = "swipe",
            screen_zone = { ratio_x = 0, ratio_y = 0, ratio_w = 1, ratio_h = 1 },
            handler = function(ges)
                local res = scroll_container:handleEvent(ges)
                if res then UIManager:setDirty(self, "ui") end
                return res
            end
        },
        {
            id = "thumb_pan",
            ges = "pan",
            screen_zone = { ratio_x = 0, ratio_y = 0, ratio_w = 1, ratio_h = 1 },
            handler = function(ges)
                local res = scroll_container:handleEvent(ges)
                if res then UIManager:setDirty(self, "ui") end
                return res
            end
        },
        {
            id = "thumb_pan_release",
            ges = "pan_release",
            screen_zone = { ratio_x = 0, ratio_y = 0, ratio_w = 1, ratio_h = 1 },
            handler = function(ges)
                local res = scroll_container:handleEvent(ges)
                if res then UIManager:setDirty(self, "ui") end
                return res
            end
        },
        {
            id = "thumb_hold_pan",
            ges = "hold_pan",
            screen_zone = { ratio_x = 0, ratio_y = 0, ratio_w = 1, ratio_h = 1 },
            handler = function(ges)
                local res = scroll_container:handleEvent(ges)
                if res then UIManager:setDirty(self, "ui") end
                return res
            end
        },
        {
            id = "thumb_hold_release",
            ges = "hold_release",
            screen_zone = { ratio_x = 0, ratio_y = 0, ratio_w = 1, ratio_h = 1 },
            handler = function(ges)
                local res = scroll_container:handleEvent(ges)
                if res then UIManager:setDirty(self, "ui") end
                return res
            end
        },
    })
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
}


local Illustrations = WidgetContainer:extend{
    name = "Illustrations",
}

function Illustrations:init()
    self.ui.menu:registerToMainMenu(self)
    
    Dispatcher:registerAction("show_gallery_mode", {
        category = "none",
        event = "ShowGalleryMode",
        title = _("Illustrations: Show Gallery"),
    })
    
    Dispatcher:registerAction("show_illustrations_mode", {
        category = "none",
        event = "ShowIllustrationsMode",
        title = _("Illustrations: Show Illustrations"),
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
        
        if remote_version and self:compareVersions(remote_version, current_version) > 0 then
            UIManager:show(InfoMessage:new{
                text = "Illustrations plugin\n" .. _("New version available: ") .. remote_version .. "\n" .. _("Current: ") .. current_version,
                timeout = 5,
            })
        end
    end
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
    local book_dir = nil
    
    if doc then
        local doc_path = doc.file
        local doc_filename = doc_path:match("^.+/(.+)$") or doc_path
        local safe_dirname = doc_filename:gsub("[^%w%-_%.]", "_") .. "_extracted"
        book_dir = illustrations_root .. "/" .. safe_dirname .. "/"
    end
    
    return illustrations_root, book_dir
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
            UIManager:show(ConfirmBox:new{
                text = _("Are you sure you want to delete the cache for this book?"),
                ok_text = _("Delete"),
                cancel_text = _("Cancel"),
                ok_callback = do_clear
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

    -- Show info message
    local loading = InfoMessage:new{
        text = _("Scanning book for images..."),
    }
    UIManager:show(loading)
    UIManager:forceRePaint()

    -- Async scanning using coroutine
    local co = coroutine.create(function()
        local all_images = {}
        local processed = 0

        local total_pages = doc:getPageCount()
        
        for page = 1, total_pages do
            -- Optimization: If we are in spoiler-free mode, we CAN stop scanning after max_page
            if max_page and page > max_page then
                break
            end
            
            local page_images = self:getImagesFromPage(page)
            if page_images then
                for _, img in ipairs(page_images) do
                    table.insert(all_images, img)
                end
            end
            
            processed = processed + 1
            if processed % 10 == 0 then
                coroutine.yield()
            end
        end
        
        -- Schedule UI update
        UIManager:scheduleIn(0, function()
            UIManager:close(loading)

            if #all_images == 0 then
                UIManager:show(InfoMessage:new{
                    text = _("No images found."),
                    timeout = 2,
                })
            else
                self:displayImages(all_images, is_gallery_mode, max_page)
            end
        end)
    end)

    -- Scheduler to resume coroutine
    local function resume()
        if coroutine.status(co) ~= "dead" then
            local ok, err = coroutine.resume(co)
            if not ok then
                logger.warn("Illustrations: Error in scanning coroutine: " .. tostring(err))
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
    local seen_paths = {}
    local doc = self.ui.document

    if is_favorites then
        -- Direct path usage for favorites
        for _, img in ipairs(images) do
            local full_path = img.path
            if lfs.attributes(full_path) then
                table.insert(extracted_images, { path = full_path, page = 0 })
            end
        end
    else
        -- Normal extraction logic
        local illustrations_root, storage_dir = self:getCachePaths()
        -- Create directories
        if not lfs.attributes(illustrations_root) then lfs.mkdir(illustrations_root) end
        if not lfs.attributes(storage_dir) then lfs.mkdir(storage_dir) end
        
        local doc_path = doc.file
        
        for _, img in ipairs(images) do
            -- Filter by max_page if set
            if not max_page or img.page <= max_page then
                local clean_src = img.src:gsub("%.%./", ""):gsub("^/", "")
                local basename = clean_src:match("^.+/(.+)$") or clean_src
                local full_path = storage_dir .. basename
                
                -- Skip if we already have this image in the list
                if not seen_paths[full_path] then
                    -- Check if already exists on disk or extract
                    if not lfs.attributes(full_path) then
                        -- Extract if missing
                        local data = nil
                        
                        -- Strategy 1: getDocumentFileContent
                        if doc.getDocumentFileContent then
                            local prefixes = {"", "OPS/", "OEBPS/", "EPUB/", "images/"}
                            for _, prefix in ipairs(prefixes) do
                                local try_path = prefix .. clean_src
                                if prefix == "" then try_path = clean_src end
                                
                                data = doc:getDocumentFileContent(try_path)
                                if data then break end
                            end
                        end
                        
                        if data then
                            local f = io.open(full_path, "wb")
                            if f then
                                f:write(data)
                                f:close()
                            end
                        else
                            -- Strategy 2: Unzip
                            -- Quote paths for safety
                            local cmd = string.format("unzip -j -o -q '%s' '*%s' -d '%s'", doc_path, clean_src, storage_dir)
                            os.execute(cmd)
                        end
                    end
    
                    -- Now check if file exists and verify size
                    if lfs.attributes(full_path) then
                        local min_size = G_reader_settings:readSetting("illustrations_min_size") or 300
                        local w, h = self:getImageDimensions(full_path)
                        
                        -- Filter: smallest side must be >= min_size
                        if math.min(w, h) >= min_size then
                            table.insert(extracted_images, { path = full_path, page = img.page })
                            seen_paths[full_path] = true
                        else
                            -- Delete (optional, but cleaner cache)
                            os.remove(full_path)
                        end
                    end
                end
            end
        end
    end

    if #extracted_images == 0 then
            UIManager:show(InfoMessage:new{
            text = _("No images found.\n(Check 'Min Image Size' setting or Favorites)"),
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
