
public class CollectionPage : Gtk.ScrolledWindow {
    public static const int THUMB_X_PADDING = 20;
    public static const int THUMB_Y_PADDING = 20;
    public static const string BG_COLOR = "#777";

    // steppings should divide evenly into (Thumbnail.MAX_SCALE - Thumbnail.MIN_SCALE)
    public static const int MANUAL_STEPPING = 16;
    public static const int SLIDER_STEPPING = 1;

    private static const int IMPROVAL_PRIORITY = Priority.LOW;
    private static const int IMPROVAL_DELAY_MS = 500;
    
    private PhotoTable photoTable = new PhotoTable();
    private Gtk.Viewport viewport = new Gtk.Viewport(null, null);
    private Gtk.Table layoutTable = new Gtk.Table(0, 0, false);
    private Gtk.MenuBar menubar = null;
    private Gtk.Toolbar toolbar = new Gtk.Toolbar();
    private Gtk.HScale slider = null;
    private Gee.ArrayList<Thumbnail> thumbnailList = new Gee.ArrayList<Thumbnail>();
    private Gee.HashSet<Thumbnail> selectedList = new Gee.HashSet<Thumbnail>();
    private int currentX = 0;
    private int currentY = 0;
    private int cols = 0;
    private int thumbCount = 0;
    private int scale = Thumbnail.DEFAULT_SCALE;
    private bool improval_scheduled = false;

    // TODO: Mark fields for translation
    private const Gtk.ActionEntry[] ACTIONS = {
        { "File", null, "_File", null, null, null },
        { "Quit", Gtk.STOCK_QUIT, "_Quit", null, "Quit the program", Gtk.main_quit },
        
        { "Edit", null, "_Edit", null, null, on_edit_menu },
        { "SelectAll", Gtk.STOCK_SELECT_ALL, "Select _All", "<Ctrl>A", "Select all the photos in the library", on_select_all },
        { "Remove", Gtk.STOCK_DELETE, "_Remove", "Delete", "Remove the selected photos from the library", on_remove },
        
        { "Photos", null, "_Photos", null, null, null },
        { "IncreaseSize", Gtk.STOCK_ZOOM_IN, "Zoom _in", "KP_Add", "Increase the magnification of the thumbnails", on_increase_size },
        { "DecreaseSize", Gtk.STOCK_ZOOM_OUT, "Zoom _out", "KP_Subtract", "Decrease the magnification of the thumbnails", on_decrease_size },
        
        { "Help", null, "_Help", null, null, null },
        { "About", Gtk.STOCK_ABOUT, "_About", null, "About this application", on_about }
    };
    
    // TODO: Mark fields for translation
    private const Gtk.ActionEntry[] RIGHT_CLICK_ACTIONS = {
        { "Remove", Gtk.STOCK_DELETE, "_Remove", "Delete", "Remove the selected photos from the library", on_remove }
    };
    
    construct {
        Gtk.ActionGroup mainActionGroup = new Gtk.ActionGroup("CollectionActionGroup");
        mainActionGroup.add_actions(ACTIONS, this);
        AppWindow.get_ui_manager().insert_action_group(mainActionGroup, 0);
        
        Gtk.ActionGroup contextActionGroup = new Gtk.ActionGroup("CollectionContextActionGroup");
        contextActionGroup.add_actions(RIGHT_CLICK_ACTIONS, this);
        AppWindow.get_ui_manager().insert_action_group(contextActionGroup, 0);

        // this page's menu bar
        menubar = (Gtk.MenuBar) AppWindow.get_ui_manager().get_widget("/CollectionMenuBar");
        AppWindow.get_main_window().add_accel_group(AppWindow.get_ui_manager().get_accel_group());
        
        // set up page's toolbar (used by AppWindow for layout)
        //
        // thumbnail size slider
        slider = new Gtk.HScale.with_range(0, scaleToSlider(Thumbnail.MAX_SCALE), 1);
        slider.set_value(scaleToSlider(scale));
        slider.value_changed += on_slider_changed;
        slider.set_draw_value(false);

        Gtk.ToolItem toolitem = new Gtk.ToolItem();
        toolitem.add(slider);
        toolitem.set_expand(false);
        toolitem.set_size_request(200, -1);

        toolbar.insert(toolitem, -1);

        // scrollbar policy
        set_policy(Gtk.PolicyType.AUTOMATIC, Gtk.PolicyType.AUTOMATIC);
        
        // set table column and row padding ... this is done globally rather than per-thumbnail
        layoutTable.set_col_spacings(THUMB_X_PADDING);
        layoutTable.set_row_spacings(THUMB_Y_PADDING);
        
        // need to manually build viewport to set its background color
        viewport.add(layoutTable);
        viewport.modify_bg(Gtk.StateType.NORMAL, parse_color(BG_COLOR));

        // notice that this is capturing the viewport's resize, not the scrolled window's,
        // as that's what interesting when laying out the photos
        viewport.size_allocate += on_viewport_resize;

        // This signal handler is to load the collection page with photos when its viewport is
        // realized ... this is because if the collection page is loaded during construction, the
        // viewport does not respond properly to the layout table's resizing and it winds up tagging
        // extra space to the tail of the view.  This allows us to wait until the viewport is realized
        // and responds properly to resizing
        viewport.realize += on_viewport_realized;

        // when the viewport is exposed, the thumbnails are informed when they are exposed (and
        // should be showing their image) and when they're unexposed (so they can destroy the image,
        // freeing up memory)
        viewport.expose_event += on_viewport_exposed;
        
        // don't want to schedule thumbnail improvement in on_viewport_exposed because the redraws
        // will signal another expose event ... this schedules thumbnail improvement whenever the
        // window is scrolled
        get_hadjustment().value_changed += schedule_thumbnail_improval;
        get_vadjustment().value_changed += schedule_thumbnail_improval;
        
        add(viewport);
        
        button_press_event += on_click;
    }
    
    public Gtk.Toolbar get_toolbar() {
        return toolbar;
    }
    
    public Gtk.MenuBar get_menubar() {
        return menubar;
    }
    
    public void add_photo(PhotoID photoID, File file) {
        Thumbnail thumbnail = new Thumbnail(photoID, file, scale);
        
        thumbnailList.add(thumbnail);
        thumbCount++;
        
        attach_thumbnail(thumbnail);
        
        thumbnail.show();
    }
    
    public void remove_photo(Thumbnail thumbnail) {
        thumbnailList.remove(thumbnail);
        selectedList.remove(thumbnail);

        ThumbnailCache.remove(thumbnail.get_photo_id());
        photoTable.remove(thumbnail.get_photo_id());

        layoutTable.remove(thumbnail);
        
        assert(thumbCount > 0);
        thumbCount--;
    }
    
    private Timer repackTimer = new Timer();
    
    public void repack() {
        int rows = (thumbCount / cols) + 1;
        
        debug("repack() scale=%d thumbCount=%d rows=%d cols=%d", scale, thumbCount, rows, cols);
        
        repackTimer.start();
        
        viewport.size_allocate -= on_viewport_resize;
        viewport.realize -= on_viewport_realized;
        viewport.expose_event -= on_viewport_exposed;
        
        layoutTable.resize(rows, cols);

        currentX = 0;
        currentY = 0;

        foreach (Thumbnail thumbnail in thumbnailList) {
            layoutTable.remove(thumbnail);
            attach_thumbnail(thumbnail);
        }

        viewport.size_allocate += on_viewport_resize;
        viewport.realize += on_viewport_realized;
        viewport.expose_event += on_viewport_exposed;

        debug("repack: %lfms", repackTimer.elapsed());
        
        show_all();
        schedule_thumbnail_improval();
    }
    
    private void attach_thumbnail(Thumbnail thumbnail) {
        layoutTable.attach(thumbnail, currentX, currentX + 1, currentY, currentY + 1,
            Gtk.AttachOptions.SHRINK | Gtk.AttachOptions.EXPAND,
            Gtk.AttachOptions.SHRINK | Gtk.AttachOptions.FILL,
            0, 0);

        if(++currentX >= cols) {
            currentX = 0;
            currentY++;
        }
    }
    
    private void on_viewport_resize(Gtk.Viewport v, Gdk.Rectangle allocation) {
        int newCols = allocation.width / (Thumbnail.get_max_width(scale) + (THUMB_X_PADDING * 2));
        if (newCols < 1)
            newCols = 1;
        
        if (cols != newCols) {
            cols = newCols;
            repack();
        }
    }
    
    public Thumbnail? get_thumbnail_at(double xd, double yd) {
        int x = (int) xd;
        int y = (int) yd;

        int xadj = (int) viewport.get_hadjustment().get_value();
        int yadj = (int) viewport.get_vadjustment().get_value();
        
        x += xadj;
        y += yadj;
        
        foreach (Thumbnail thumbnail in thumbnailList) {
            Gtk.Allocation alloc = thumbnail.allocation;
            if ((x >= alloc.x) && (y >= alloc.y) && (x <= (alloc.x + alloc.width))
                && (y <= (alloc.y + alloc.height))) {
                return thumbnail;
            }
        }
        
        return null;
    }
    
    public int get_count() {
        return thumbCount;
    }
    
    public void select_all() {
        foreach (Thumbnail thumbnail in thumbnailList) {
            selectedList.add(thumbnail);
            thumbnail.select();
        }
    }
    
    public void unselect_all() {
        foreach (Thumbnail thumbnail in selectedList) {
            assert(thumbnail.is_selected());
            thumbnail.unselect();
        }
        
        selectedList = new Gee.HashSet<Thumbnail>();
    }
    
    public Thumbnail[] get_selected() {
        Thumbnail[] thumbnails = new Thumbnail[selectedList.size];
        
        int ctr = 0;
        foreach (Thumbnail thumbnail in selectedList) {
            assert(thumbnail.is_selected());
            thumbnails[ctr++] = thumbnail;
        }
        
        return thumbnails;
    }
    
    public void select(Thumbnail thumbnail) {
        thumbnail.select();
        selectedList.add(thumbnail);
    }
    
    public void unselect(Thumbnail thumbnail) {
        thumbnail.unselect();
        selectedList.remove(thumbnail);
    }
    
    public void toggle_select(Thumbnail thumbnail) {
        if (thumbnail.toggle_select()) {
            // now selected
            selectedList.add(thumbnail);
        } else {
            // now unselected
            selectedList.remove(thumbnail);
        }
    }

    public int get_selected_count() {
        return selectedList.size;
    }
    
    public int increase_thumb_size() {
        if (scale == Thumbnail.MAX_SCALE)
            return scale;
        
        scale += MANUAL_STEPPING;
        if (scale > Thumbnail.MAX_SCALE) {
            scale = Thumbnail.MAX_SCALE;
        }
        
        foreach (Thumbnail thumbnail in thumbnailList) {
            thumbnail.resize(scale);
        }
        
        layoutTable.resize_children();
        
        schedule_thumbnail_improval();
        
        return scale;
    }
    
    public int decrease_thumb_size() {
        if (scale == Thumbnail.MIN_SCALE)
            return scale;
        
        scale -= MANUAL_STEPPING;
        if (scale < Thumbnail.MIN_SCALE) {
            scale = Thumbnail.MIN_SCALE;
        }
        
        foreach (Thumbnail thumbnail in thumbnailList) {
            thumbnail.resize(scale);
        }
        
        layoutTable.resize_children();
        
        schedule_thumbnail_improval();
        
        return scale;
    }
    
    public void set_thumb_size(int newScale) {
        assert(newScale >= Thumbnail.MIN_SCALE);
        assert(newScale <= Thumbnail.MAX_SCALE);
        
        scale = newScale;
        
        foreach (Thumbnail thumbnail in thumbnailList) {
            thumbnail.resize(scale);
        }
        
        layoutTable.resize_children();

        schedule_thumbnail_improval();
    }

    private void schedule_thumbnail_improval() {
        if (improval_scheduled == false) {
            improval_scheduled = true;
            Timeout.add_full(IMPROVAL_PRIORITY, IMPROVAL_DELAY_MS, improve_thumbnail_quality);
        }
    }
    
    private bool improve_thumbnail_quality() {
        foreach (Thumbnail thumbnail in thumbnailList) {
            if (thumbnail.is_exposed()) {
                thumbnail.paint_high_quality();
            }
        }
        
        improval_scheduled = false;
        
        debug("improve_thumbnail_quality");
        
        return false;
    }

    private void on_viewport_realized() {
        File[] photoFiles = photoTable.get_photo_files();
        foreach (File file in photoFiles) {
            PhotoID photoID = photoTable.get_id(file);
            add_photo(photoID, file);
        }
        
        show_all();
        schedule_thumbnail_improval();
    }

    private bool on_viewport_exposed(Gtk.Viewport v, Gdk.EventExpose event) {
        // since expose events can stack up, wait until the last one to do the full
        // search
        if (event.count == 0)
            check_exposure();

        return false;
    }
    
    private void on_about() {
        AppWindow.get_main_window().about_box();
    }
    
    private void set_item_sensitive(string path, bool sensitive) {
        Gtk.Widget widget = AppWindow.get_ui_manager().get_widget(path);
        widget.set_sensitive(sensitive);
    }
    
    private void on_edit_menu() {
        set_item_sensitive("/CollectionMenuBar/EditMenu/EditSelectAll", get_count() > 0);
        set_item_sensitive("/CollectionMenuBar/EditMenu/EditRemove", get_selected_count() > 0);
    }
    
    private void on_select_all() {
        select_all();
    }

    private void on_increase_size() {
        increase_thumb_size();
        slider.set_value(scaleToSlider(scale));
    }

    private void on_decrease_size() {
        decrease_thumb_size();
        slider.set_value(scaleToSlider(scale));
    }

    private bool on_click(CollectionPage c, Gdk.EventButton event) {
        switch (event.button) {
            case 1:
                return on_left_click(event);
            
            case 3:
                return on_right_click(event);
            
            default:
                return false;
        }
    }
        
    private bool on_left_click(Gdk.EventButton event) {
        // only interested in single-clicks presses for now
        if (event.type != Gdk.EventType.BUTTON_PRESS) {
            return false;
        }
        
        // mask out the modifiers we're interested in
        uint state = event.state & (Gdk.ModifierType.CONTROL_MASK | Gdk.ModifierType.SHIFT_MASK);
        
        Thumbnail thumbnail = get_thumbnail_at(event.x, event.y);
        if (thumbnail != null) {
            message("clicked on %s", thumbnail.get_file().get_basename());
            
            switch (state) {
                case Gdk.ModifierType.CONTROL_MASK: {
                    // with only Ctrl pressed, multiple selections are possible ... chosen item
                    // is toggled
                    toggle_select(thumbnail);
                } break;
                
                case Gdk.ModifierType.SHIFT_MASK: {
                    // TODO
                } break;
                
                case Gdk.ModifierType.CONTROL_MASK | Gdk.ModifierType.SHIFT_MASK: {
                    // TODO
                } break;
                
                default: {
                    // a "raw" click deselects all thumbnails and selects the single chosen
                    unselect_all();
                    select(thumbnail);
                } break;
            }
        } else {
            // user clicked on "dead" area
            unselect_all();
        }

        return false;
    }
    
    private bool on_right_click(Gdk.EventButton event) {
        // only interested in single-clicks for now
        if (event.type != Gdk.EventType.BUTTON_PRESS) {
            return false;
        }
        
        Thumbnail thumbnail = get_thumbnail_at(event.x, event.y);
        if (thumbnail != null) {
            // this counts as a select
            unselect_all();
            select(thumbnail);

            Gtk.Menu contextMenu = (Gtk.Menu) AppWindow.get_ui_manager().get_widget("/CollectionContextMenu");
            contextMenu.popup(null, null, null, event.button, event.time);
            
            return true;
        } else {
            // clicked on a "dead" area
        }
        
        return false;
    }
    
    private void on_remove() {
        // get a full list of the selected thumbnails, then iterate over that, as you can't remove
        // from a list you're iterating over
        Thumbnail[] thumbnails = get_selected();
        foreach (Thumbnail thumbnail in thumbnails) {
            remove_photo(thumbnail);
        }
        
        repack();
    }
    
    private void check_exposure() {
        Gdk.Rectangle viewrect = Gdk.Rectangle();
        viewrect.x = (int) viewport.get_hadjustment().get_value();
        viewrect.y = (int) viewport.get_vadjustment().get_value();
        viewrect.width = viewport.allocation.width;
        viewrect.height = viewport.allocation.height;

        Gdk.Rectangle thumbrect = Gdk.Rectangle();
        Gdk.Rectangle bitbucket = Gdk.Rectangle();

        foreach (Thumbnail thumbnail in thumbnailList) {
            Gtk.Allocation alloc = thumbnail.get_exposure();
            thumbrect.x = alloc.x;
            thumbrect.y = alloc.y;
            thumbrect.width = alloc.width;
            thumbrect.height = alloc.height;
            
            if (viewrect.intersect(thumbrect, bitbucket)) {
                thumbnail.exposed();
            } else {
                thumbnail.unexposed();
            }
        }
    }

    private double scaleToSlider(int value) {
        assert(value >= Thumbnail.MIN_SCALE);
        assert(value <= Thumbnail.MAX_SCALE);
        
        return (double) ((value - Thumbnail.MIN_SCALE) / SLIDER_STEPPING);
    }
    
    private int sliderToScale(double value) {
        int res = ((int) (value * SLIDER_STEPPING)) + Thumbnail.MIN_SCALE;

        assert(res >= Thumbnail.MIN_SCALE);
        assert(res <= Thumbnail.MAX_SCALE);
        
        return res;
    }
    
    private void on_slider_changed() {
        set_thumb_size(sliderToScale(slider.get_value()));
    }
}

