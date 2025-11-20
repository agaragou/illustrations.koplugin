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
    logger.info("Illustrations: init() called, registering actions")
    self.ui.menu:registerToMainMenu(self)
    
    Dispatcher:registerAction("show_all_illustrations", {
        category = "none",
        event = "ShowAllIllustrations",
        title = _("Show All illustrations (SPOILERS!)"),
        general = true,
    })
    
    Dispatcher:registerAction("show_chapter_illustrations", {
        category = "none",
        event = "ShowChapterIllustrations",
        title = _("Show illustrations to chapter end (Spoiler-free)"),
        general = true,
    })
end

function Illustrations:onShowAllIllustrations()
    self:showPreviewIllustrations()
end

function Illustrations:onShowChapterIllustrations()
    self:showPreviewChapterIllustrations()
end

function Illustrations:addToMainMenu(menu_items)
    menu_items.illustrations = {
        text = _("Illustrations"),
        sorting_hint = "tools",
        sub_item_table = {
            {
                text = _("Clear current book cache"),
                callback = function() self:clearBookCache() end,
            },
            {
                text = _("Clear ALL books cache"),
                callback = function() self:clearAllCache() end,
            },
            {
                text = "----------------",
                enabled = false, -- Visual separator
                callback = function() end,
            },
            {
                text = _("Show All illustrations (SPOILERS!)"),
                callback = function() self:showPreviewIllustrations() end,
            },
            {
                text = _("Show illustrations to chapter end (Spoiler-free)"),
                callback = function() self:showPreviewChapterIllustrations() end,
            },
        }
    }
end

function Illustrations:showPreviewIllustrations(max_page)
    local doc = self.ui.document
    if not doc then return end
    
    local scan_end = max_page or doc:getPageCount()
    
    self:findAndDisplayImages(1, scan_end, "Preview Illustrations", max_page)
end

function Illustrations:showPreviewChapterIllustrations()
    local doc = self.ui.document
    if not doc then return end
    
    local current_page = self.ui:getCurrentPage()
    if not current_page and self.ui.view then
        current_page = self.ui.view.current_page
    end
    
    local toc = doc:getToc()
    local end_page = doc:getPageCount()

    -- Find current chapter end
    if toc and current_page then
        -- Flatten TOC for easier search
        local function flatten(items, list)
            for _, item in ipairs(items) do
                table.insert(list, item)
                if item.children then
                    flatten(item.children, list)
                end
            end
        end
        local flat_toc = {}
        flatten(toc, flat_toc)
        
        for i, item in ipairs(flat_toc) do
            if item.page and item.page > current_page then
                -- This chapter starts after our current page, so the previous chapter ends at item.page - 1
                end_page = item.page - 1
                break
            end
        end
    end
    
    -- Show preview up to this page
    self:showPreviewIllustrations(end_page)
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



function Illustrations:findAndDisplayImages(start_page, end_page, title, max_page)
    local all_images = {}
    
    local InfoMessage = require("ui/widget/infomessage")
    local loading = InfoMessage:new{
        text = _("Scanning for images...\n0%"),
    }
    UIManager:show(loading)
    UIManager:forceRePaint()

    -- Async scanning using coroutine
    local co = coroutine.create(function()
        local total_pages = end_page - start_page + 1
        local processed = 0
        
        for page = start_page, end_page do
            local page_images = self:getImagesFromPage(page)
            for _, img in ipairs(page_images) do
                table.insert(all_images, img)
            end
            
            processed = processed + 1
            
            -- Yield every 10 pages to keep UI responsive
            if processed % 10 == 0 then
                coroutine.yield()
            end
        end
        
        -- Schedule UI update on main thread to avoid freeze
        UIManager:scheduleIn(0, function()
            UIManager:close(loading)

            if #all_images == 0 then
                UIManager:show(InfoMessage:new{
                    text = _("No illustrations found."),
                })
            else
                self:displayImages(all_images, title, max_page)
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
                -- Schedule next chunk
                UIManager:scheduleIn(0.01, resume)
            end
        end
    end

    resume()
end

function Illustrations:displayImages(images, title, max_page)
    -- Grid View (Gallery)
    logger.info("Illustrations: Starting Gallery View")
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
                        range = Geom:new{ x = self.width * 0.3, y = 0, w = self.width * 0.4, h = self.height },
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
                            text = "Resume Gallery",
                            callback = function()
                                UIManager:close(dialog)
                                -- Re-open gallery at current index
                                if self.callback_resume then self.callback_resume(self.index) end
                            end,
                        },
                        {
                            text = "Close Gallery",
                            callback = function()
                                UIManager:close(dialog)
                                -- Already closed, but safe to call again
                                if self.callback_close then self.callback_close(true) end
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
                    }
                    
                    self.grid_window = gallery
                    UIManager:show(gallery)
                end)
            end
        end

        -- Start with the first image
        showGalleryImage(1)
    end

return Illustrations
