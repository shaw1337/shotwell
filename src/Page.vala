
public class PageMarker {
    public Gtk.Widget notebook_page;
    private Gtk.TreeRowReference row = null;
    
    public PageMarker(Gtk.Widget notebook_page, Gtk.TreeModel? model = null, Gtk.TreePath? path = null ) {
        this.notebook_page = notebook_page;
        if ((model != null) && (path != null))
            this.row = new Gtk.TreeRowReference(model, path);
    }
    
    public unowned Gtk.TreeRowReference get_row() {
        return row;
    }
}

public abstract class Page : Gtk.ScrolledWindow {
    public static const uint KEY_CTRL_L = Gdk.keyval_from_name("Control_L");
    public static const uint KEY_CTRL_R = Gdk.keyval_from_name("Control_R");
    public static const uint KEY_ALT_L = Gdk.keyval_from_name("Alt_L");
    public static const uint KEY_ALT_R = Gdk.keyval_from_name("Alt_R");
    public static const uint KEY_SHIFT_L = Gdk.keyval_from_name("Shift_L");
    public static const uint KEY_SHIFT_R = Gdk.keyval_from_name("Shift_R");

    protected enum TargetType {
        URI_LIST
    }
    
    // For now, assuming all drag-and-drop source functions are providing the same set of targets
    protected const Gtk.TargetEntry[] SOURCE_TARGET_ENTRIES = {
        { "text/uri-list", Gtk.TargetFlags.OTHER_APP, TargetType.URI_LIST }
    };
    
    public Gtk.UIManager ui = new Gtk.UIManager();
    public Gtk.ActionGroup action_group = null;
    public Gtk.ActionGroup common_action_group = null;
    
    private Gtk.MenuBar menu_bar = null;
    private PageMarker marker = null;
    private Gdk.Rectangle last_position = Gdk.Rectangle();
    private Gtk.Widget event_source = null;
    private bool dnd_enabled = false;

    public Page() {
        set_flags(Gtk.WidgetFlags.CAN_FOCUS);
    }

    public void set_event_source(Gtk.Widget event_source) {
        assert(this.event_source == null);

        this.event_source = event_source;
        event_source.set_flags(Gtk.WidgetFlags.CAN_FOCUS);

        // interested in mouse button and motion events on the event source
        event_source.add_events(Gdk.EventMask.BUTTON_PRESS_MASK | Gdk.EventMask.BUTTON_RELEASE_MASK
            | Gdk.EventMask.POINTER_MOTION_MASK | Gdk.EventMask.POINTER_MOTION_HINT_MASK
            | Gdk.EventMask.BUTTON_MOTION_MASK);
        event_source.button_press_event += on_button_pressed_internal;
        event_source.button_release_event += on_button_released_internal;
        event_source.motion_notify_event += on_motion_internal;
        
        // Use the app window's signals for window move/resize, esp. for resize, as this signal
        // is used to determine inner window resizes
        AppWindow.get_instance().add_events(Gdk.EventMask.STRUCTURE_MASK);
        AppWindow.get_instance().configure_event += on_configure_internal;
    }
    
    public Gtk.Widget? get_event_source() {
        return event_source;
    }
    
    public void set_marker(PageMarker marker) {
        this.marker = marker;
    }
    
    public PageMarker get_marker() {
        return marker;
    }
    
    public virtual Gtk.MenuBar get_menubar() {
        return menu_bar;
    }

    public abstract Gtk.Toolbar get_toolbar();
    
    public virtual void switching_from() {
    }
    
    public virtual void switched_to() {
    }
    
    public virtual void switching_to_fullscreen() {
    }
    
    public virtual void returning_from_fullscreen() {
    }
    
    public void set_item_sensitive(string path, bool sensitive) {
        ui.get_widget(path).sensitive = sensitive;
    }
    
    protected void init_ui(string ui_filename, string? menubar_path, string action_group_name, 
        Gtk.ActionEntry[]? entries = null, Gtk.ToggleActionEntry[]? toggle_entries = null) {
        init_ui_start(ui_filename, action_group_name, entries, toggle_entries);
        init_ui_bind(menubar_path);
    }
    
    protected void init_load_ui(string ui_filename) {
        File ui_file = Resources.get_ui(ui_filename);

        try {
            ui.add_ui_from_file(ui_file.get_path());
        } catch (Error gle) {
            error("Error loading UI file %s: %s", ui_file.get_path(), gle.message);
        }
    }
    
    protected void init_ui_start(string ui_filename, string action_group_name,
        Gtk.ActionEntry[]? entries = null, Gtk.ToggleActionEntry[]? toggle_entries = null) {
        init_load_ui(ui_filename);

        action_group = new Gtk.ActionGroup(action_group_name);
        if (entries != null)
            action_group.add_actions(entries, this);
        if (toggle_entries != null)
            action_group.add_toggle_actions(toggle_entries, this);
    }
    
    protected void init_ui_bind(string? menubar_path) {
        ui.insert_action_group(action_group, 0);
        common_action_group = AppWindow.get_instance().get_common_action_group();
        ui.insert_action_group(common_action_group, 0);
        
        if (menubar_path != null)
            menu_bar = (Gtk.MenuBar) ui.get_widget(menubar_path);

        ui.ensure_update();
    }
    
    // This method enables drag-and-drop on the event source and routes its events through this
    // object
    public void enable_drag_source(Gdk.DragAction actions) {
        if (dnd_enabled)
            return;
            
        assert(event_source != null);
        
        Gtk.drag_source_set(event_source, Gdk.ModifierType.BUTTON1_MASK, SOURCE_TARGET_ENTRIES, actions);
        event_source.drag_begin += on_drag_begin;
        event_source.drag_data_get += on_drag_data_get;
        event_source.drag_data_delete += on_drag_data_delete;
        event_source.drag_end += on_drag_end;
        event_source.drag_failed += on_drag_failed;
        
        dnd_enabled = true;
    }
    
    public void disable_drag_source() {
        if (!dnd_enabled)
            return;

        assert(event_source != null);
        
        event_source.drag_begin -= on_drag_begin;
        event_source.drag_data_get -= on_drag_data_get;
        event_source.drag_data_delete -= on_drag_data_delete;
        event_source.drag_end -= on_drag_end;
        event_source.drag_failed -= on_drag_failed;
        Gtk.drag_source_unset(event_source);
        
        dnd_enabled = false;
    }
    
    public bool is_dnd_enabled() {
        return dnd_enabled;
    }
    
    private void on_drag_begin(Gdk.DragContext context) {
        drag_begin(context);
    }
    
    private void on_drag_data_get(Gdk.DragContext context, Gtk.SelectionData selection_data,
        uint info, uint time) {
        drag_data_get(context, selection_data, info, time);
    }
    
    private void on_drag_data_delete(Gdk.DragContext context) {
        drag_data_delete(context);
    }
    
    private void on_drag_end(Gdk.DragContext context) {
        drag_end(context);
    }
    
    // wierdly, Gtk 2.16.1 doesn't supply a drag_failed virtual method in the GtkWidget impl ...
    // Vala binds to it, but it's not available in gtkwidget.h, and so gcc complains.  Have to
    // makeshift one for now.
    public virtual bool source_drag_failed(Gdk.DragContext context, Gtk.DragResult drag_result) {
        return false;
    }
    
    private bool on_drag_failed(Gdk.DragContext context, Gtk.DragResult drag_result) {
        return source_drag_failed(context, drag_result);
    }
    
    protected virtual bool on_left_click(Gdk.EventButton event) {
        return false;
    }
    
    protected virtual bool on_middle_click(Gdk.EventButton event) {
        return false;
    }
    
    protected virtual bool on_right_click(Gdk.EventButton event) {
        return false;
    }
    
    protected virtual bool on_left_released(Gdk.EventButton event) {
        return false;
    }
    
    protected virtual bool on_middle_released(Gdk.EventButton event) {
        return false;
    }
    
    protected virtual bool on_right_released(Gdk.EventButton event) {
        return false;
    }
    
    private bool on_button_pressed_internal(Gdk.EventButton event) {
        switch (event.button) {
            case 1:
                if (event_source != null)
                    event_source.grab_focus();
                
                return on_left_click(event);

            case 2:
                return on_middle_click(event);
            
            case 3:
                return on_right_click(event);
            
            default:
                return false;
        }
    }
    
    private bool on_button_released_internal(Gdk.EventButton event) {
        switch (event.button) {
            case 1:
                return on_left_released(event);
            
            case 2:
                return on_middle_released(event);
            
            case 3:
                return on_right_released(event);
            
            default:
                return false;
        }
    }

    protected virtual bool on_ctrl_pressed(Gdk.EventKey event) {
        return false;
    }
    
    protected virtual bool on_ctrl_released(Gdk.EventKey event) {
        return false;
    }
    
    protected virtual bool on_alt_pressed(Gdk.EventKey event) {
        return false;
    }
    
    protected virtual bool on_alt_released(Gdk.EventKey event) {
        return false;
    }
    
    protected virtual bool on_shift_pressed(Gdk.EventKey event) {
        return false;
    }
    
    protected virtual bool on_shift_released(Gdk.EventKey event) {
        return false;
    }
    
    public bool notify_modifier_pressed(Gdk.EventKey event) {
        // can't use a switch statement here due to this bug:
        // http://bugzilla.gnome.org/show_bug.cgi?id=585292
        if (event.keyval == KEY_CTRL_L || event.keyval == KEY_CTRL_R)
            return on_ctrl_pressed(event);
        
        if (event.keyval == KEY_ALT_L || event.keyval == KEY_ALT_R)
            return on_alt_pressed(event);
        
        if (event.keyval == KEY_SHIFT_L || event.keyval == KEY_SHIFT_R)
            return on_shift_pressed(event);
        
        return false;
    }

    public bool notify_modifier_released(Gdk.EventKey event) {
        // can't use a switch statement here due to this bug:
        // http://bugzilla.gnome.org/show_bug.cgi?id=585292
        if (event.keyval == KEY_CTRL_L || event.keyval == KEY_CTRL_R)
            return on_ctrl_released(event);
        
        if (event.keyval == KEY_ALT_L || event.keyval == KEY_ALT_R)
            return on_alt_released(event);
        
        if (event.keyval == KEY_SHIFT_L || event.keyval == KEY_SHIFT_R)
            return on_shift_released(event);
        
        return false;
    }
    
    protected virtual void on_move(Gdk.Rectangle rect) {
    }
    
    protected virtual void on_resize(Gdk.Rectangle rect) {
    }
    
    private bool on_configure_internal(Gdk.EventConfigure event) {
        Gdk.Rectangle rect = Gdk.Rectangle();
        rect.x = event.x;
        rect.y = event.y;
        rect.width = event.width;
        rect.height = event.height;
        
        if (last_position.x != rect.x || last_position.y != rect.y)
            on_move(rect);
        
        if (last_position.width != rect.width || last_position.height != rect.height)
            on_resize(rect);
        
        last_position = rect;
        
        return false;
    }
    
    protected virtual bool on_motion(Gdk.EventMotion event, int x, int y, Gdk.ModifierType mask) {
        return false;
    }
    
    private bool on_motion_internal(Gdk.EventMotion event) {
        int x, y;
        Gdk.ModifierType mask;
        if (event.is_hint) {
            event_source.window.get_pointer(out x, out y, out mask);
            
            Gtk.Adjustment hadj = get_hadjustment();
            Gtk.Adjustment vadj = get_vadjustment();
            
            // adjust x and y to viewport values
            x = (x + (int) hadj.get_value()).clamp((int) hadj.get_lower(), (int) hadj.get_upper());
            y = (y + (int) vadj.get_value()).clamp((int) vadj.get_lower(), (int) vadj.get_upper());
        } else {
            x = (int) event.x;
            y = (int) event.y;
            mask = event.state;
        }
        
        return on_motion(event, x, y, mask);
    }
}

public abstract class CheckerboardPage : Page {
    private static const int AUTOSCROLL_PIXELS = 50;
    private static const int AUTOSCROLL_TICKS_MSEC = 50;
    
    private Gtk.Menu context_menu = null;
    private CollectionLayout layout = new CollectionLayout();
    private Gee.HashSet<LayoutItem> selected_items = new Gee.HashSet<LayoutItem>();
    private string page_name = null;
    private LayoutItem last_clicked_item = null;

    // for drag selection
    private bool drag_select = false;
    private Gdk.Point drag_start = Gdk.Point();
    private Gdk.Rectangle selection_band;
    private Gdk.GC selection_gc = null;
    private bool autoscroll_scheduled = false;

    public CheckerboardPage(string page_name) {
        this.page_name = page_name;
        
        set_event_source(layout);
        layout.expose_after += on_layout_exposed;
        layout.map += on_layout_mapped;

        add(layout);
    }
    
    public virtual string get_name() {
        return page_name;
    }
    
    public void init_context_menu(string path) {
        context_menu = (Gtk.Menu) ui.get_widget(path);
    }
    
    protected virtual void on_selection_changed(int count) {
    }
    
    public virtual Gtk.Menu? get_context_menu() {
        return context_menu;
    }
    
    protected virtual void on_item_activated(LayoutItem item) {
    }
    
    protected virtual bool on_context_invoked(Gtk.Menu context_menu) {
        return true;
    }
    
    public abstract LayoutItem? get_fullscreen_photo();
    
    public void refresh() {
        show_all();
        layout.refresh();
    }
    
    public void set_page_message(string message) {
        layout.set_message(message);
    }
    
    public void set_refresh_on_resize(bool refresh_on_resize) {
        layout.set_refresh_on_resize(refresh_on_resize);
    }
    
    public void set_layout_comparator(Comparator<LayoutItem> cmp) {
        layout.set_comparator(cmp);
    }
    
    public LayoutItem? get_item_at_pixel(double x, double y) {
        return layout.get_item_at_pixel(x, y);
    }
    
    public Gee.Iterable<LayoutItem> get_items() {
        return layout.items;
    }
    
    public Gee.Iterable<LayoutItem> get_selected() {
        return selected_items;
    }
    
    public void add_item(LayoutItem item) {
        layout.add_item(item);
    }
    
    public void remove_item(LayoutItem item) {
        selected_items.remove(item);
        layout.remove_item(item);
    }
    
    public int remove_selected() {
        int count = selected_items.size;
        
        foreach (LayoutItem item in selected_items)
            layout.remove_item(item);
        
        selected_items.clear();
        
        return count;
    }
    
    public int remove_all() {
        int count = layout.items.size;
        
        layout.clear();
        selected_items.clear();
        
        return count;
    }
    
    public int get_count() {
        return layout.items.size;
    }
    
    public void select_all() {
        bool changed = false;
        foreach (LayoutItem item in layout.items) {
            if (!item.is_selected()) {
                selected_items.add(item);
                item.select();
                changed = true;
            }
        }
        
        if (changed)
            on_selection_changed(selected_items.size);
    }

    public void unselect_all() {
        if (selected_items.size == 0)
            return;

        foreach (LayoutItem item in selected_items) {
            assert(item.is_selected());
            item.unselect();
        }
        
        selected_items.clear();
        
        on_selection_changed(0);
    }
    
    public void unselect_all_but(LayoutItem exception) {
        assert(exception.is_selected());
        
        if (selected_items.size == 0)
            return;
        
        bool changed = false;
        foreach (LayoutItem item in selected_items) {
            assert(item.is_selected());
            if (item != exception) {
                item.unselect();
                changed = true;
            }
        }
        
        selected_items.clear();
        selected_items.add(exception);

        if (changed)
            on_selection_changed(1);
    }

    public void select(LayoutItem item) {
        assert(layout.items.contains(item));
        
        if (!item.is_selected()) {
            item.select();
            selected_items.add(item);

            on_selection_changed(selected_items.size);
        }
    }
    
    public void unselect(LayoutItem item) {
        assert(layout.items.contains(item));
        
        if (item.is_selected()) {
            item.unselect();
            selected_items.remove(item);
            
            on_selection_changed(selected_items.size);
        }
    }

    public void toggle_select(LayoutItem item) {
        if (item.toggle_select()) {
            // now selected
            selected_items.add(item);
        } else {
            // now unselected
            selected_items.remove(item);
        }
        
        on_selection_changed(selected_items.size);
    }

    public int get_selected_count() {
        return selected_items.size;
    }
    
    private override bool on_left_click(Gdk.EventButton event) {
        // only interested in single-click and double-clicks for now
        if ((event.type != Gdk.EventType.BUTTON_PRESS) && (event.type != Gdk.EventType.2BUTTON_PRESS))
            return false;
        
        // mask out the modifiers we're interested in
        uint state = event.state & (Gdk.ModifierType.CONTROL_MASK | Gdk.ModifierType.SHIFT_MASK);
        
        // use clicks for multiple selection and activation only; single selects are handled by
        // button release, to allow for multiple items to be selected then dragged
        LayoutItem item = get_item_at_pixel(event.x, event.y);
        if (item != null) {
            switch (state) {
                case Gdk.ModifierType.CONTROL_MASK:
                    // with only Ctrl pressed, multiple selections are possible ... chosen item
                    // is toggled
                    toggle_select(item);
                break;
                
                case Gdk.ModifierType.SHIFT_MASK:
                    // TODO
                break;
                
                case Gdk.ModifierType.CONTROL_MASK | Gdk.ModifierType.SHIFT_MASK:
                    // TODO
                break;
                
                default:
                    if (event.type == Gdk.EventType.2BUTTON_PRESS)
                        on_item_activated(item);
                    else {
                        // if user has selected multiple items and is preparing for a drag, don't
                        // want to unselect immediately, otherwise, let the released handler deal
                        // with it
                        if (get_selected_count() == 1)
                            unselect_all();
                        select(item);
                    }
                break;
            }
        } else {
            // user clicked on "dead" area
            unselect_all();
        }
        
        last_clicked_item = item;

        // need to determine if the signal should be passed to the DnD handlers
        // Return true to block the DnD handler, false otherwise

        if (item == null) {
            drag_select = true;
            drag_start.x = (int) event.x;
            drag_start.y = (int) event.y;
            selection_band.width = 0;
            selection_band.height = 0;

            return true;
        }

        return selected_items.size == 0;
    }
    
    private override bool on_left_released(Gdk.EventButton event) {
        // if drag-selecting, stop here and do nothing else
        if (drag_select) {
            drag_select = false;
            selection_band.width = 0;
            selection_band.height = 0;
            
            // force a repaint to remove the selection band
            layout.bin_window.invalidate_rect(null, false);
            
            return true;
        }
        
        // only interested in non-modified button releases
        if ((event.state & (Gdk.ModifierType.CONTROL_MASK | Gdk.ModifierType.SHIFT_MASK)) != 0)
            return false;
            
        LayoutItem item = get_item_at_pixel(event.x, event.y);
        if (item == null) {
            // released button on "dead" area
            return true;
        }
        
        if (last_clicked_item != item) {
            // user released mouse button after moving it off the initial item, or moved from dead
            // space onto one.  either way, unselect everything
            unselect_all();
        } else {
            // the idea is, if a user single-clicks on an item with no modifiers, then all other items
            // should be deselected, however, if they single-click in order to drag one or more items,
            // they should remain selected, hence performing this here rather than on_left_click
            // (item may not be selected if an unimplemented modifier key was used)
            if (item.is_selected())
                unselect_all_but(item);
        }

        return true;
    }
    
    private override bool on_right_click(Gdk.EventButton event) {
        // only interested in single-clicks for now
        if (event.type != Gdk.EventType.BUTTON_PRESS)
            return false;
        
        // get what's right-clicked upon
        LayoutItem item = get_item_at_pixel(event.x, event.y);
        if (item != null) {
            // mask out the modifiers we're interested in
            switch (event.state & (Gdk.ModifierType.CONTROL_MASK | Gdk.ModifierType.SHIFT_MASK)) {
                case Gdk.ModifierType.CONTROL_MASK:
                    // chosen item is toggled
                    toggle_select(item);
                break;
                
                case Gdk.ModifierType.SHIFT_MASK:
                    // TODO
                break;
                
                case Gdk.ModifierType.CONTROL_MASK | Gdk.ModifierType.SHIFT_MASK:
                    // TODO
                break;
                
                default:
                    // if the item is already selected, proceed; if item is not selected, a bare right
                    // click unselects everything else but it
                    if (!item.is_selected()) {
                        unselect_all();
                        select(item);
                    }
                break;
            }
        } else {
            // clicked in "dead" space, unselect everything
            unselect_all();
        }
        
        Gtk.Menu context_menu = get_context_menu();
        if (context_menu == null)
            return false;
            
        if (!on_context_invoked(context_menu))
            return false;
            
        context_menu.popup(null, null, null, event.button, event.time);

        return true;
    }
    
    private override bool on_motion(Gdk.EventMotion event, int x, int y, Gdk.ModifierType mask) {
        // only interested in motion during a drag select
        if (!drag_select)
            return false;
        
        Gdk.Point drag_end = Gdk.Point();
        drag_end.x = x;
        drag_end.y = y;
        
        // save new drag rectangle
        selection_band = Box.from_points(drag_start, drag_end).get_rectangle();
        
        updated_selection_band();

        // if out of bounds, schedule a check to auto-scroll the viewport
        if (!autoscroll_scheduled 
            && get_adjustment_relation(get_vadjustment(), y) != AdjustmentRelation.IN_RANGE) {
            Timeout.add(AUTOSCROLL_TICKS_MSEC, selection_autoscroll);
            autoscroll_scheduled = true;
        }

        return true;
    }
    
    private void updated_selection_band() {
        assert(drag_select);
        
        // get all items inside the selection
        Gee.List<LayoutItem> intersection = layout.intersection(selection_band);

        // deselect everything not in the intersection ... needs to be done outside the iterator
        Gee.ArrayList<LayoutItem> outside = new Gee.ArrayList<LayoutItem>();
        foreach (LayoutItem item in selected_items) {
            if (!intersection.contains(item))
                outside.add(item);
        }
        
        foreach (LayoutItem item in outside)
            unselect(item);
        
        // select everything in the intersection
        foreach (LayoutItem item in intersection)
            select(item);
        
        // for a refresh to paint the selection band
        layout.bin_window.invalidate_rect(null, false);
    }
    
    private bool selection_autoscroll() {
        if (!drag_select) { 
            autoscroll_scheduled = false;
            
            return false;
        }
        
        // as the viewport never scrolls horizontally, only interested in vertical
        Gtk.Adjustment vadj = get_vadjustment();

        int x, y;
        Gdk.ModifierType mask;
        layout.bin_window.get_pointer(out x, out y, out mask);
        
        int new_value = (int) vadj.get_value();
        switch (get_adjustment_relation(vadj, y)) {
            case AdjustmentRelation.BELOW:
                new_value -= AUTOSCROLL_PIXELS;
                selection_band.y -= AUTOSCROLL_PIXELS;
                if (selection_band.y < (int) vadj.get_lower())
                    selection_band.y = (int) vadj.get_lower();
            break;
            
            case AdjustmentRelation.ABOVE:
                new_value += AUTOSCROLL_PIXELS;
                selection_band.height += AUTOSCROLL_PIXELS;
                if ((selection_band.y + selection_band.height) > (int) vadj.get_upper())
                    selection_band.height = ((int) vadj.get_upper()) - selection_band.y;
            break;
            
            case AdjustmentRelation.IN_RANGE:
                autoscroll_scheduled = false;
                
                return false;
            
            default:
                warn_if_reached();
            break;
        }
        
        vadj.set_value(new_value);
        
        updated_selection_band();
        
        return true;
    }
    
    private void on_layout_mapped() {
         // set up GC's for painting selection
        Gdk.GCValues gc_values = Gdk.GCValues();
        gc_values.foreground = fetch_color(LayoutItem.SELECTED_COLOR, layout.bin_window);
        gc_values.function = Gdk.Function.COPY;
        gc_values.fill = Gdk.Fill.SOLID;
        gc_values.line_width = 0;
        
        Gdk.GCValuesMask mask = 
            Gdk.GCValuesMask.FOREGROUND 
            | Gdk.GCValuesMask.FUNCTION 
            | Gdk.GCValuesMask.FILL
            | Gdk.GCValuesMask.LINE_WIDTH;

        selection_gc = new Gdk.GC.with_values(layout.bin_window, gc_values, mask);
    }

    private void on_layout_exposed() {
        // this method only used to draw selection rectangle
        if (selection_band.width == 0 || selection_band.height == 0)
            return;
        
        assert(selection_gc != null);

        // pixelate selection rectangle interior
        Gdk.Pixbuf pixbuf = Gdk.pixbuf_get_from_drawable(null, layout.bin_window, null, selection_band.x,
            selection_band.y, 0, 0, selection_band.width, selection_band.height);
        pixbuf.saturate_and_pixelate(pixbuf, 1.0f, true);
        
        // pixelated fill
        Gdk.draw_pixbuf(layout.bin_window, selection_gc, pixbuf, 0, 0, selection_band.x, selection_band.y,
            -1, -1, Gdk.RgbDither.NONE, 0, 0);

        // border
        Gdk.draw_rectangle(layout.bin_window, selection_gc, false, selection_band.x, selection_band.y,
            selection_band.width, selection_band.height);
    }
    
    public LayoutItem? get_first_item() {
        return (layout.items.size != 0) ? layout.items.get(0) : null;
    }
    
    public LayoutItem? get_last_item() {
        return (layout.items.size != 0) ? layout.items.get(layout.items.size - 1) : null;
    }
    
    public LayoutItem? get_next_item(LayoutItem current) {
        if (layout.items.size == 0)
            return null;
        
        int index = layout.items.index_of(current);

        // although items may be added while the page is away, not handling situations where an active
        // item is removed
        assert(index >= 0);

        index++;
        if (index >= layout.items.size)
            index = 0;
        
        return layout.items.get(index);
    }
    
    public LayoutItem? get_previous_item(LayoutItem current) {
        if (layout.items.size == 0)
            return null;
        
        int index = layout.items.index_of(current);
        
        // although items may be added while the page is away, not handling situations where an active
        // item is removed
        assert(index >= 0);

        index--;
        if (index < 0)
            index = (layout.items.size - 1);
        
        return layout.items.get(index);
    }
    
    public void cursor_to_item(LayoutItem item) {
        assert(layout.items.contains(item));
        
        unselect_all();
        select(item);

        // if item is in any way out of view, scroll to it
        Gtk.Adjustment vadj = get_vadjustment();
        if (get_adjustment_relation(vadj, item.allocation.y) == AdjustmentRelation.IN_RANGE
            && (get_adjustment_relation(vadj, item.allocation.y + item.allocation.height) == AdjustmentRelation.IN_RANGE))
            return;

        // scroll to see the new item
        int top = 0;
        if (item.allocation.y < vadj.get_value()) {
            top = item.allocation.y;
            top -= CollectionLayout.ROW_GUTTER_PADDING / 2;
        } else {
            top = item.allocation.y + item.allocation.height - (int) vadj.get_page_size();
            top += CollectionLayout.ROW_GUTTER_PADDING / 2;
        }
        
        vadj.set_value(top);
    }
    
    public void move_cursor(CompassPoint point) {
        // if nothing is selected, simply select the first and exit
        if (selected_items.size == 0) {
            cursor_to_item(layout.items.get(0));
            
            return;
        }
        
        // find the "first" selected item, which for now is the topmost, leftmost item in the layout
        // TODO: Revisit if this is the right choice.
        int first_col = int.MAX;
        int first_row = int.MAX;
        foreach (LayoutItem selected in selected_items) {
            first_col = int.min(selected.get_column(), first_col);
            first_row = int.min(selected.get_row(), first_row);
        }
        
        LayoutItem item = layout.get_item_at_coordinate(first_col, first_row);
        assert(item != null);
        
        // if more than one selected, select the first without moving, to not surprise the user
        if (selected_items.size > 1) {
            cursor_to_item(item);
            
            return;
        }
        
        item = layout.get_item_relative_to(item, point);
        if (item != null)
            cursor_to_item(item);
   }
}