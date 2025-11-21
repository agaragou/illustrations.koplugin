local Dispatcher = require("dispatcher")
local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")
local logger = require("logger")

local Illustrations = WidgetContainer:extend{
    name = "Illustrations",
}

function Illustrations:init()
    self.ui.menu:registerToMainMenu(self)
    
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
end

function Illustrations:onShowGalleryMode()
    self:showGalleryMode()
end

function Illustrations:onShowIllustrationsMode()
    self:showIllustrationsMode()
end

function Illustrations:addToMainMenu(menu_items)
    if not self.ui.document then return end
    menu_items.illustrations = {
        text = _("Illustrations"),
        sorting_hint = "tools",
        sub_item_table = {
            {
                text = _("Settings"),
                sub_item_table = {
                    {
                        text = _("Clear current book cache"),
                        callback = function()
                            self:clearBookCache()
                        end,
                    },
                    {
                        text = _("Clear ALL books cache"),
                        callback = function()
                            self:clearAllCache()
                        end,
                    },
                    {
                        text = "----------------",
                        enabled = false, -- Visual separator
                        callback = function() end,
                    },
                    {
                        text = _("Allow Spoilers"),
                        checked_func = function()
                            return G_reader_settings:readSetting("illustrations_allow_spoilers")
                        end,
                        callback = function()
                            local current = G_reader_settings:readSetting("illustrations_allow_spoilers")
                            G_reader_settings:saveSetting("illustrations_allow_spoilers", not current)
                        end,
                    },
                }
            },
            {
                text = "----------------",
                enabled = false, -- Visual separator
                callback = function() end,
            },
            {
                text = _("Show Illustrations"),
                callback = function()
                    self:showIllustrationsMode()
                end,
            },
            {
                text = _("Show Gallery"),
                callback = function()
                    self:showGalleryMode()
                end,
            },
        }
    }
end

function Illustrations:showGalleryMode()
    self:findAndDisplayImages(true)
end

function Illustrations:showIllustrationsMode()
    self:findAndDisplayImages(false)
end



function Illustrations:getCachePaths()
    local DataStorage = require("datastorage")
    local doc = self.ui.document
    if not doc then return nil, nil end
    
    local doc_path = doc.file
    local doc_filename = doc_path:match("^.+/(.+)$") or doc_path
    local safe_dirname = doc_filename:gsub("[^%w%-_%.]", "_") .. "_extracted"
    
    local settings_dir = DataStorage:getSettingsDir()
    local cache_dir = DataStorage.getCacheDir and DataStorage:getCacheDir() or settings_dir:gsub("/settings$", "/cache")
    if cache_dir == settings_dir then cache_dir = settings_dir .. "/../cache" end
    
    local illustrations_root = cache_dir .. "/illustrations"
    local book_dir = illustrations_root .. "/" .. safe_dirname .. "/"
    
    return illustrations_root, book_dir
end

function Illustrations:clearBookCache()
    local root, book_dir = self:getCachePaths()
    if book_dir then
        local UIManager = require("ui/uimanager")
        local ConfirmBox = require("ui/widget/confirmbox")
        
        UIManager:show(ConfirmBox:new{
            text = _("Are you sure you want to delete the cache for this book?"),
            ok_text = _("Delete"),
            cancel_text = _("Cancel"),
            ok_callback = function()
                os.execute("rm -rf '" .. book_dir .. "'")
                UIManager:show(InfoMessage:new{ text = _("Cache cleared.") })
            end
        })
    end
end

function Illustrations:clearAllCache()
    local illustrations_root, book_dir = self:getCachePaths()
    if illustrations_root then
        local UIManager = require("ui/uimanager")
        local ConfirmBox = require("ui/widget/confirmbox")
        
        UIManager:show(ConfirmBox:new{
            text = _("Are you sure you want to delete ALL illustrations cache?"),
            ok_text = _("Delete All"),
            cancel_text = _("Cancel"),
            ok_callback = function()
                os.execute("rm -rf '" .. illustrations_root .. "'")
                UIManager:show(InfoMessage:new{ text = _("All cache cleared.") })
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



    function Illustrations:findAndDisplayImages(is_gallery_mode)
        local doc = self.ui.document
        local UIManager = require("ui/uimanager")
        local InfoMessage = require("ui/widget/infomessage")
        local logger = require("logger")

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
            text = "Scanning book for images...",
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
                        text = "No images found.",
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

function Illustrations:displayImages(images, is_gallery_mode, max_page)
    -- Grid View (Gallery)
    local UIManager = require("ui/uimanager")
    local WidgetContainer = require("ui/widget/container/widgetcontainer")
    local ImageWidget = require("ui/widget/imagewidget")
    local ButtonDialog = require("ui/widget/buttondialog")
    local InputContainer = require("ui/widget/container/inputcontainer")
    local CenterContainer = require("ui/widget/container/centercontainer")
    local FrameContainer = require("ui/widget/container/framecontainer")
    local TextBoxWidget = require("ui/widget/textboxwidget")
    local InfoMessage = require("ui/widget/infomessage")
    local Device = require("device")
    local Screen = Device.screen
    local Geom = require("ui/geometry")
    local GestureRange = require("ui/gesturerange")
    local Event = require("ui/event")
    local Blitbuffer = require("ffi/blitbuffer")
    local lfs = require("libs/libkoreader-lfs")
    
    -- 1. Prepare Persistent Storage
    local illustrations_root, storage_dir = self:getCachePaths()
    
    -- Create directories
    if not lfs.attributes(illustrations_root) then
        lfs.mkdir(illustrations_root)
    end
    
    if not lfs.attributes(storage_dir) then
        lfs.mkdir(storage_dir)
    end
        
    local extracted_images = {}
    local seen_paths = {}
    local doc = self.ui.document
    local doc_path = doc.file
    
    for _, img in ipairs(images) do
        -- Filter by max_page if set
        if not max_page or img.page <= max_page then
            local clean_src = img.src:gsub("%.%./", ""):gsub("^/", "")
            local basename = clean_src:match("^.+/(.+)$") or clean_src
            local full_path = storage_dir .. basename
            
            -- Skip if we already have this image in the list
            if not seen_paths[full_path] then
                -- Check if already exists on disk
                if lfs.attributes(full_path) then
                    table.insert(extracted_images, { path = full_path, page = img.page })
                    seen_paths[full_path] = true
                else
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
                            table.insert(extracted_images, { path = full_path, page = img.page })
                            seen_paths[full_path] = true
                        end
                    else
                        -- Strategy 2: Unzip
                        -- Quote paths for safety
                        local cmd = string.format("unzip -j -o -q '%s' '*%s' -d '%s'", doc_path, clean_src, storage_dir)
                        os.execute(cmd)
                        
                        if lfs.attributes(full_path) then
                            table.insert(extracted_images, { path = full_path, page = img.page })
                            seen_paths[full_path] = true
                        end
                    end
                end
            end
        end
    end

        if #extracted_images == 0 then
             UIManager:show(InfoMessage:new{
                text = _("No images extracted.\nCheck logs for errors."),
            })
            return
        end

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
            local dialog
            dialog = ButtonDialog:new{
                buttons = {
                    {
                        {
                            text = "Go to Page " .. self.page,
                            callback = function()
                                UIManager:close(dialog)
                                if self.callback_goto then self.callback_goto(self.page) end
                            end,
                        },
                        {
                            text = "Open Gallery",
                            callback = function()
                                UIManager:close(dialog)
                                if self.callback_thumbnails then self.callback_thumbnails() end
                            end,
                        },
                    },
                    {
                        {
                            text = "Exit",
                            callback = function()
                                UIManager:close(dialog)
                                -- Already closed, but safe to call again
                                if self.callback_close then self.callback_close(true) end
                            end,
                        },
                        {
                            text = "Resume",
                            callback = function()
                                UIManager:close(dialog)
                                -- Re-open gallery at current index
                                if self.callback_resume then self.callback_resume(self.index) end
                            end,
                        }
                    }
                }
            }
            UIManager:show(dialog)
        end)
    end

    -- Helper function to show a specific image
    local function showGalleryImage(index)
        if index < 1 then index = 1 end
        if index > #extracted_images then index = #extracted_images end
        
        local img = extracted_images[index]

        if self.grid_window then
                -- Reuse existing window
                self.grid_window:setImage(img.path, img.page, index)
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
                            self:showGalleryMode()
                        end,
                    }
                    
                    self.grid_window = gallery
                    UIManager:show(gallery)
                end)
            end
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
    }

    function ThumbnailWindow:init()
        InputContainer._init(self)
        
        self.width = Screen:getWidth()
        self.height = Screen:getHeight()
        self.dimen = Geom:new{ x = 0, y = 0, w = self.width, h = self.height }
        
        local ScrollableContainer = require("ui/widget/container/scrollablecontainer")
        local VerticalGroup = require("ui/widget/verticalgroup")
        local HorizontalGroup = require("ui/widget/horizontalgroup")
        local FrameContainer = require("ui/widget/container/framecontainer")
        local CenterContainer = require("ui/widget/container/centercontainer")
        local Button = require("ui/widget/button")
        local TitleBar = require("ui/widget/titlebar")
        
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
            title = self.title or "Gallery",
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

    -- Logic to choose view mode
    if #extracted_images == 0 then
        UIManager:show(InfoMessage:new{
            text = "No images found.",
            timeout = 2,
        })
        return
    end

    if is_gallery_mode then
        -- Show Gallery (Grid) View
        UIManager:nextTick(function()
            local thumbs = ThumbnailWindow:new{
                images = extracted_images,
                title = "Gallery", -- Renamed from Thumbnails
                callback_open = function(index)
                    -- Open single image view
                    showGalleryImage(index)
                end,
            }
            UIManager:show(thumbs)
        end)
    else
        -- Show Single Image View (Illustrations)
        -- Start from the first image (or maybe the one closest to current page? 
        -- For now, first image is fine, or we could find the last one <= current page)
        
        local start_index = 1
        -- Try to find the image closest to current page (but not after, if possible)
        if not allow_spoilers then
            start_index = #extracted_images -- Show the last one found (closest to current page)
        end
        
        showGalleryImage(start_index)
    end
    end

return Illustrations
