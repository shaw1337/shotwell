/* Copyright 2009-2011 Yorba Foundation
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution. 
 */

private class CheckerboardItemText {
    private static int one_line_height = 0;
    
    private string text;
    private bool marked_up;
    private Pango.Alignment alignment;
    private Pango.Layout layout = null;
    private bool single_line = true;
    private int height = 0;
    
    public Gdk.Rectangle allocation = Gdk.Rectangle();
    
    public CheckerboardItemText(string text, Pango.Alignment alignment = Pango.Alignment.LEFT,
        bool marked_up = false) {
        this.text = text;
        this.marked_up = marked_up;
        this.alignment = alignment;
        
        single_line = is_single_line();
    }
    
    private bool is_single_line() {
        return !String.contains_char(text, '\n');
    }
    
    public bool is_marked_up() {
        return marked_up;
    }
    
    public bool is_set_to(string text, bool marked_up, Pango.Alignment alignment) {
        return (this.marked_up == marked_up && this.alignment == alignment && this.text == text);
    }
    
    public string get_text() {
        return text;
    }
    
    public int get_height() {
        if (height == 0)
            update_height();
        
        return height;
    }
    
    public Pango.Layout get_pango_layout(int max_width = 0) {
        if (layout == null)
            create_pango();
        
        if (max_width > 0)
            layout.set_width(max_width * Pango.SCALE);
        
        return layout;
    }
    
    public void clear_pango_layout() {
        layout = null;
    }
    
    private void update_height() {
        if (one_line_height != 0 && single_line)
            height = one_line_height;
        else
            create_pango();
    }
    
    private void create_pango() {
        // create layout for this string and ellipsize so it never extends past its laid-down width
        layout = AppWindow.get_instance().create_pango_layout(null);
        if (!marked_up)
            layout.set_text(text, -1);
        else
            layout.set_markup(text, -1);
        
        layout.set_ellipsize(Pango.EllipsizeMode.END);
        layout.set_alignment(alignment);
        
        // getting pixel size is expensive, and we only need the height, so use cached values
        // whenever possible
        if (one_line_height != 0 && single_line) {
            height = one_line_height;
        } else {
            int width;
            layout.get_pixel_size(out width, out height);
            
            // cache first one-line height discovered
            if (one_line_height == 0 && single_line)
                one_line_height = height;
        }
    }
}

public abstract class CheckerboardItem : ThumbnailView {
    // Collection properties CheckerboardItem understands
    // SHOW_TITLES (bool)
    public const string PROP_SHOW_TITLES = "show-titles";
    // SHOW_SUBTITLES (bool)
    public const string PROP_SHOW_SUBTITLES = "show-subtitles";
    
    public const int FRAME_WIDTH = 3;
    public const int LABEL_PADDING = 4;
    public const int BORDER_WIDTH = 1;
    
    public const int TRINKET_SCALE = 12;
    public const int TRINKET_PADDING = 1;
    
    public const int BRIGHTEN_SHIFT = 0x18;
    
    public Dimensions requisition = Dimensions();
    public Gdk.Rectangle allocation = Gdk.Rectangle();
    
    private bool exposure = false;
    private CheckerboardItemText? title = null;
    private bool title_visible = true;
    private CheckerboardItemText? subtitle = null;
    private bool subtitle_visible = false;
    private Gdk.Pixbuf pixbuf = null;
    private Gdk.Pixbuf display_pixbuf = null;
    private Gdk.Pixbuf brightened = null;
    private Dimensions pixbuf_dim = Dimensions();
    private int col = -1;
    private int row = -1;
    private int horizontal_trinket_offset = 0;
    
    public CheckerboardItem(ThumbnailSource source, Dimensions initial_pixbuf_dim, string title,
        bool marked_up = false, Pango.Alignment alignment = Pango.Alignment.LEFT) {
        base(source);
        
        pixbuf_dim = initial_pixbuf_dim;
        this.title = new CheckerboardItemText(title, alignment, marked_up);
        
        // Don't calculate size here, wait for the item to be assigned to a ViewCollection
        // (notify_membership_changed) and calculate when the collection's property settings
        // are known
    }
    
    public override string get_name() {
        return (title != null) ? title.get_text() : base.get_name();
    }
    
    public string get_title() {
        return (title != null) ? title.get_text() : "";
    }
    
    public void set_title(string text, bool marked_up = false,
        Pango.Alignment alignment = Pango.Alignment.LEFT) {
        if (title != null && title.is_set_to(text, marked_up, alignment))
            return;
        
        title = new CheckerboardItemText(text, alignment, marked_up);
        
        if (title_visible) {
            recalc_size("set_title");
            notify_view_altered();
        }
    }
    
    public void clear_title() {
        if (title == null)
            return;
        
        title = null;
        
        if (title_visible) {
            recalc_size("clear_title");
            notify_view_altered();
        }
    }
    
    private void set_title_visible(bool visible) {
        if (title_visible == visible)
            return;
        
        title_visible = visible;
        
        recalc_size("set_title_visible");
        notify_view_altered();
    }
    
    public string get_subtitle() {
        return (subtitle != null) ? subtitle.get_text() : "";
    }
    
    public void set_subtitle(string text, bool marked_up = false, 
        Pango.Alignment alignment = Pango.Alignment.LEFT) {
        if (subtitle != null && subtitle.is_set_to(text, marked_up, alignment))
            return;
        
        subtitle = new CheckerboardItemText(text, alignment, marked_up);
        
        if (subtitle_visible) {
            recalc_size("set_subtitle");
            notify_view_altered();
        }
    }
    
    public void clear_subtitle() {
        if (subtitle == null)
            return;
        
        subtitle = null;
        
        if (subtitle_visible) {
            recalc_size("clear_subtitle");
            notify_view_altered();
        }
    }
    
    private void set_subtitle_visible(bool visible) {
        if (subtitle_visible == visible)
            return;
        
        subtitle_visible = visible;
        
        recalc_size("set_subtitle_visible");
        notify_view_altered();
    }
    
    protected override void notify_membership_changed(DataCollection? collection) {
        bool title_visible = (bool) get_collection_property(PROP_SHOW_TITLES, true);
        bool subtitle_visible = (bool) get_collection_property(PROP_SHOW_SUBTITLES, false);
        
        bool altered = false;
        if (this.title_visible != title_visible) {
            this.title_visible = title_visible;
            altered = true;
        }
        
        if (this.subtitle_visible != subtitle_visible) {
            this.subtitle_visible = subtitle_visible;
            altered = true;
        }
        
        if (altered || !requisition.has_area()) {
            recalc_size("notify_membership_changed");
            notify_view_altered();
        }
        
        base.notify_membership_changed(collection);
    }
    
    protected override void notify_collection_property_set(string name, Value? old, Value val) {
        switch (name) {
            case PROP_SHOW_TITLES:
                set_title_visible((bool) val);
            break;
            
            case PROP_SHOW_SUBTITLES:
                set_subtitle_visible((bool) val);
            break;
        }
        
        base.notify_collection_property_set(name, old, val);
    }
    
    // The alignment point is the coordinate on the y-axis (relative to the top of the
    // CheckerboardItem) which this item should be aligned to.  This allows for
    // bottom-alignment along the bottom edge of the thumbnail.
    public int get_alignment_point() {
        return FRAME_WIDTH + BORDER_WIDTH + pixbuf_dim.height;
    }
    
    public virtual void exposed() {
        exposure = true;
    }
    
    public virtual void unexposed() {
        exposure = false;
        
        if (title != null)
            title.clear_pango_layout();
        
        if (subtitle != null)
            subtitle.clear_pango_layout();
    }
    
    public virtual bool is_exposed() {
        return exposure;
    }

    public bool has_image() {
        return pixbuf != null;
    }
    
    public Gdk.Pixbuf? get_image() {
        return pixbuf;
    }
    
    public void set_image(Gdk.Pixbuf pixbuf) {
        this.pixbuf = pixbuf;
        display_pixbuf = pixbuf;
        pixbuf_dim = Dimensions.for_pixbuf(pixbuf);
        
        recalc_size("set_image");
        notify_view_altered();
    }
    
    public void clear_image(Dimensions dim) {
        bool had_image = pixbuf != null;
        
        pixbuf = null;
        display_pixbuf = null;
        pixbuf_dim = dim;
        
        recalc_size("clear_image");
        
        if (had_image)
            notify_view_altered();
    }
    
    public static int get_max_width(int scale) {
        // width is frame width (two sides) + frame padding (two sides) + width of pixbuf (text
        // never wider)
        return (FRAME_WIDTH * 2) + scale;
    }
    
    private void recalc_size(string reason) {
        Dimensions old_requisition = requisition;
        
        // only add in the text heights if they're displayed
        int title_height = (title != null && title_visible)
            ? title.get_height() + LABEL_PADDING : 0;
        int subtitle_height = (subtitle != null && subtitle_visible)
            ? subtitle.get_height() + LABEL_PADDING : 0;
        
        // width is frame width (two sides) + frame padding (two sides) + width of pixbuf
        // (text never wider)
        requisition.width = (FRAME_WIDTH * 2) + (BORDER_WIDTH * 2) + pixbuf_dim.width;
        
        // height is frame width (two sides) + frame padding (two sides) + height of pixbuf
        // + height of text + label padding (between pixbuf and text)
        requisition.height = (FRAME_WIDTH * 2) + (BORDER_WIDTH * 2)
            + pixbuf_dim.height + title_height + subtitle_height;
        
#if TRACE_REFLOW_ITEMS
        debug("recalc_size %s: %s title_height=%d subtitle_height=%d requisition=%s", 
            get_source().get_name(), reason, title_height, subtitle_height, requisition.to_string());
#endif
        
        if (!requisition.approx_equals(old_requisition)) {
#if TRACE_REFLOW_ITEMS
            debug("recalc_size %s: %s notifying geometry altered", get_source().get_name(), reason);
#endif
            notify_geometry_altered();
        }
    }
    
    protected static Dimensions get_border_dimensions(Dimensions object_dim, int border_width) {
        Dimensions dimensions = Dimensions();
        dimensions.width = object_dim.width + (border_width * 2);
        dimensions.height = object_dim.height + (border_width * 2);
        return dimensions;
    }
    
    protected static Gdk.Point get_border_origin(Gdk.Point object_origin, int border_width) {
        Gdk.Point origin = Gdk.Point();
        origin.x = object_origin.x - border_width;
        origin.y = object_origin.y - border_width;
        return origin;
    }
    
    protected virtual void paint_border(Cairo.Context ctx, Dimensions object_dimensions,
        Gdk.Point object_origin, int border_width) {
        if (border_width == 1) {
            ctx.rectangle(object_origin.x - border_width, object_origin.y - border_width,
                object_dimensions.width + (border_width * 2),
                object_dimensions.height + (border_width * 2));
            ctx.fill();
        } else {
            Dimensions dimensions = get_border_dimensions(object_dimensions, border_width);
            Gdk.Point origin = get_border_origin(object_origin, border_width);
            
            // amount of rounding needed on corners varies by size of object
            double scale = int.max(object_dimensions.width, object_dimensions.height);
            draw_rounded_corners_filled(ctx, dimensions, origin, 0.25 * scale);
        }
    }

    protected virtual void paint_image(Cairo.Context ctx, Gdk.Pixbuf pixbuf, Gdk.Point origin) {
        if (pixbuf.get_has_alpha()) {
            ctx.rectangle(origin.x, origin.y, pixbuf.get_width(), pixbuf.get_height());
            ctx.fill();
        }
        Gdk.cairo_set_source_pixbuf(ctx, pixbuf, origin.x, origin.y);
        ctx.paint();
    }

    private int get_selection_border_width(int scale) {
        return ((scale <= ((Thumbnail.MIN_SCALE + Thumbnail.MAX_SCALE) / 3)) ? 2 : 3)
            + BORDER_WIDTH;
    }
    
    protected virtual Gdk.Pixbuf? get_top_left_trinket(int scale) {
        return null;
    }
    
    protected virtual Gdk.Pixbuf? get_top_right_trinket(int scale) {
        return null;
    }
    
    protected virtual Gdk.Pixbuf? get_bottom_left_trinket(int scale) {
        return null;
    }
    
    protected virtual Gdk.Pixbuf? get_bottom_right_trinket(int scale) {
        return null;
    }
    
    public void paint(Cairo.Context ctx, Gdk.Color bg_color, Gdk.Color selected_color,
        Gdk.Color text_color, Gdk.Color? border_color) {
        // calc the top-left point of the pixbuf
        Gdk.Point pixbuf_origin = Gdk.Point();
        pixbuf_origin.x = allocation.x + FRAME_WIDTH + BORDER_WIDTH;
        pixbuf_origin.y = allocation.y + FRAME_WIDTH + BORDER_WIDTH;
        
        ctx.set_line_width(FRAME_WIDTH);
        Gdk.cairo_set_source_color(ctx, selected_color);
        
        // draw selection border
        if (is_selected()) {
            // border thickness depends on the size of the thumbnail
            ctx.save();
            paint_border(ctx, pixbuf_dim, pixbuf_origin,
                get_selection_border_width(int.max(pixbuf_dim.width, pixbuf_dim.height)));
            ctx.restore();
        }
        
        // draw border
        if (border_color != null) {
            ctx.save();
            Gdk.cairo_set_source_color(ctx, border_color);
            paint_border(ctx, pixbuf_dim, pixbuf_origin, BORDER_WIDTH);
            ctx.restore();
        }
        
        if (display_pixbuf != null) {
            ctx.save();
            Gdk.cairo_set_source_color(ctx, bg_color);
            paint_image(ctx, display_pixbuf, pixbuf_origin);
            ctx.restore();
        }
        
        Gdk.cairo_set_source_color(ctx, text_color);
        
        // title and subtitles are LABEL_PADDING below bottom of pixbuf
        int text_y = allocation.y + FRAME_WIDTH + pixbuf_dim.height + FRAME_WIDTH + LABEL_PADDING;
        if (title != null && title_visible) {
            // get the layout sized so its with is no more than the pixbuf's
            // resize the text width to be no more than the pixbuf's
            title.allocation = { allocation.x + FRAME_WIDTH, text_y, pixbuf_dim.width,
                title.get_height() };
            
            ctx.move_to(title.allocation.x, title.allocation.y);
            Pango.cairo_show_layout(ctx, title.get_pango_layout(pixbuf_dim.width));
            
            text_y += title.get_height() + LABEL_PADDING;
        }
        
        if (subtitle != null && subtitle_visible) {
            subtitle.allocation = { allocation.x + FRAME_WIDTH, text_y, pixbuf_dim.width,
                subtitle.get_height() };
            
            ctx.move_to(subtitle.allocation.x, subtitle.allocation.y);
            Pango.cairo_show_layout(ctx, subtitle.get_pango_layout(pixbuf_dim.width));
            
            // increment text_y if more text lines follow
        }
        
        Gdk.cairo_set_source_color(ctx, selected_color);
        
        // draw trinkets last
        Gdk.Pixbuf? trinket = get_bottom_left_trinket(TRINKET_SCALE);
        if (trinket != null) {
            int x = pixbuf_origin.x + TRINKET_PADDING + get_horizontal_trinket_offset();
            int y = pixbuf_origin.y + pixbuf_dim.height - trinket.get_height() -
                TRINKET_PADDING;
            Gdk.cairo_set_source_pixbuf(ctx, trinket, x, y);
            ctx.rectangle(x, y, trinket.get_width(), trinket.get_height());
            ctx.fill();
        }
        
        trinket = get_top_left_trinket(TRINKET_SCALE);
        if (trinket != null) {
            int x = pixbuf_origin.x + TRINKET_PADDING + get_horizontal_trinket_offset();
            int y = pixbuf_origin.y + TRINKET_PADDING;
            Gdk.cairo_set_source_pixbuf(ctx, trinket, x, y);
            ctx.rectangle(x, y, trinket.get_width(), trinket.get_height());
            ctx.fill();
        }
        
        trinket = get_top_right_trinket(TRINKET_SCALE);
        if (trinket != null) {
            int x = pixbuf_origin.x + pixbuf_dim.width - trinket.width - 
                get_horizontal_trinket_offset() - TRINKET_PADDING;
            int y = pixbuf_origin.y + TRINKET_PADDING;
            Gdk.cairo_set_source_pixbuf(ctx, trinket, x, y);
            ctx.rectangle(x, y, trinket.get_width(), trinket.get_height());
            ctx.fill();
        }
        
        trinket = get_bottom_right_trinket(TRINKET_SCALE);
        if (trinket != null) {
            int x = pixbuf_origin.x + pixbuf_dim.width - trinket.width - 
                get_horizontal_trinket_offset() - TRINKET_PADDING;
            int y = pixbuf_origin.y + pixbuf_dim.height - trinket.height - 
                TRINKET_PADDING;
            Gdk.cairo_set_source_pixbuf(ctx, trinket, x, y);
            ctx.rectangle(x, y, trinket.get_width(), trinket.get_height());
            ctx.fill();
        }
    }
    
    protected void set_horizontal_trinket_offset(int horizontal_trinket_offset) {
        assert(horizontal_trinket_offset >= 0);
        this.horizontal_trinket_offset = horizontal_trinket_offset;
    }
    
    protected int get_horizontal_trinket_offset() {
        return horizontal_trinket_offset;
    }

    public void set_grid_coordinates(int col, int row) {
        this.col = col;
        this.row = row;
    }
    
    public int get_column() {
        return col;
    }
    
    public int get_row() {
        return row;
    }
    
    public void brighten() {
        // "should" implies "can" and "didn't already"
        if (brightened != null || pixbuf == null)
            return;
        
        // create a new lightened pixbuf to display
        brightened = pixbuf.copy();
        shift_colors(brightened, BRIGHTEN_SHIFT, BRIGHTEN_SHIFT, BRIGHTEN_SHIFT, 0);
        
        display_pixbuf = brightened;
        
        notify_view_altered();
    }
    
    public void unbrighten() {
        // "should", "can", "didn't already"
        if (brightened == null || pixbuf == null)
            return;
        
        brightened = null;

        // return to the normal image
        display_pixbuf = pixbuf;
        
        notify_view_altered();
    }
    
    public override void visibility_changed(bool visible) {
        // if going from visible to hidden, unbrighten
        if (!visible)
            unbrighten();
        
        base.visibility_changed(visible);
    }
    
    private bool query_tooltip_on_text(CheckerboardItemText text, Gtk.Tooltip tooltip) {
        if (!text.get_pango_layout().is_ellipsized())
            return false;
        
        if (text.is_marked_up())
            tooltip.set_markup(text.get_text());
        else
            tooltip.set_text(text.get_text());
        
        return true;
    }
    
    public bool query_tooltip(int x, int y, Gtk.Tooltip tooltip) {
        if (title != null && title_visible && coord_in_rectangle(x, y, title.allocation))
            return query_tooltip_on_text(title, tooltip);
        
        if (subtitle != null && subtitle_visible && coord_in_rectangle(x, y, subtitle.allocation))
            return query_tooltip_on_text(subtitle, tooltip);
        
        return false;
    }
}

public class CheckerboardLayout : Gtk.DrawingArea {
    public const int TOP_PADDING = 16;
    public const int BOTTOM_PADDING = 16;
    public const int ROW_GUTTER_PADDING = 24;

    // the following are minimums, as the pads and gutters expand to fill up the window width
    public const int COLUMN_GUTTER_PADDING = 24;
    
    // For a 40% alpha channel
    private const double SELECTION_ALPHA = 0.40;
    
    private class LayoutRow {
        public int y;
        public int height;
        public CheckerboardItem[] items;
        
        public LayoutRow(int y, int height, int num_in_row) {
            this.y = y;
            this.height = height;
            this.items = new CheckerboardItem[num_in_row];
        }
    }
    
    private ViewCollection view;
    private string page_name = "";
    private LayoutRow[] item_rows = null;
    private Gee.HashSet<CheckerboardItem> exposed_items = new Gee.HashSet<CheckerboardItem>();
    private Gtk.Adjustment hadjustment = null;
    private Gtk.Adjustment vadjustment = null;
    private string message = null;
    private Gdk.Color selected_color;
    private Gdk.Color unselected_color;
    private Gdk.Color border_color;
    private Gdk.Color bg_color;
    private Gdk.Rectangle visible_page = Gdk.Rectangle();
    private int last_width = 0;
    private int columns = 0;
    private int rows = 0;
    private Gdk.Point drag_origin = Gdk.Point();
    private Gdk.Point drag_endpoint = Gdk.Point();
    private Gdk.Rectangle selection_band = Gdk.Rectangle();
    private int scale = 0;
    private bool flow_scheduled = false;
    private bool exposure_dirty = true;
    private CheckerboardItem? anchor = null;
    private bool in_center_on_anchor = false;
    private bool size_allocate_due_to_reflow = false;
    private bool is_in_view = false;
    private bool reflow_needed = false;
    
    public CheckerboardLayout(ViewCollection view) {
        this.view = view;
        
        clear_drag_select();
        
        // subscribe to the new collection
        view.contents_altered.connect(on_contents_altered);
        view.items_altered.connect(on_items_altered);
        view.items_state_changed.connect(on_items_state_changed);
        view.items_visibility_changed.connect(on_items_visibility_changed);
        view.ordering_changed.connect(on_ordering_changed);
        view.views_altered.connect(on_views_altered);
        view.geometries_altered.connect(on_geometries_altered);
        view.items_selected.connect(on_items_selection_changed);
        view.items_unselected.connect(on_items_selection_changed);
        
        modify_bg(Gtk.StateType.NORMAL, Config.get_instance().get_bg_color());

        Config.get_instance().colors_changed.connect(on_colors_changed);

        // CheckerboardItems offer tooltips
        has_tooltip = true;
    }
    
    ~CheckerboardLayout() {
#if TRACE_DTORS
        debug("DTOR: CheckerboardLayout for %s", view.to_string());
#endif

        view.contents_altered.disconnect(on_contents_altered);
        view.items_altered.disconnect(on_items_altered);
        view.items_state_changed.disconnect(on_items_state_changed);
        view.items_visibility_changed.disconnect(on_items_visibility_changed);
        view.ordering_changed.disconnect(on_ordering_changed);
        view.views_altered.disconnect(on_views_altered);
        view.geometries_altered.disconnect(on_geometries_altered);
        view.items_selected.disconnect(on_items_selection_changed);
        view.items_unselected.disconnect(on_items_selection_changed);
        
        if (hadjustment != null)
            hadjustment.value_changed.disconnect(on_viewport_shifted);
        
        if (vadjustment != null)
            vadjustment.value_changed.disconnect(on_viewport_shifted);
        
        if (parent != null)
            parent.size_allocate.disconnect(on_viewport_resized);

        Config.get_instance().colors_changed.disconnect(on_colors_changed);
    }
    
    public void set_adjustments(Gtk.Adjustment hadjustment, Gtk.Adjustment vadjustment) {
        this.hadjustment = hadjustment;
        this.vadjustment = vadjustment;
        
        // monitor adjustment changes to report when the visible page shifts
        hadjustment.value_changed.connect(on_viewport_shifted);
        vadjustment.value_changed.connect(on_viewport_shifted);
        
        // monitor parent's size changes for a similar reason
        parent.size_allocate.connect(on_viewport_resized);
    }
    
    // This method allows for some optimizations to occur in reflow() by using the known max.
    // width of all items in the layout.
    public void set_scale(int scale) {
        this.scale = scale;
    }
    
    public int get_scale() {
        return scale;
    }
    
    public void set_name(string name) {
        page_name = name;
    }
    
    private void on_viewport_resized() {
        Gtk.Requisition req;
        size_request(out req);

        if (message == null) {
            // set the layout's new size to be the same as the parent's width but maintain 
            // it's own height
#if TRACE_REFLOW
            debug("on_viewport_resized: due_to_reflow=%s set_size_request %dx%d",
                size_allocate_due_to_reflow.to_string(), parent.allocation.width, req.height);
#endif
            set_size_request(parent.allocation.width, req.height);
        } else {
            // set the layout's width and height to always match the parent's
            set_size_request(parent.allocation.width, parent.allocation.height);
        }
        
        // possible for this widget's size_allocate not to be called, so need to update the page
        // rect here
        viewport_resized();

        if (!size_allocate_due_to_reflow)
            clear_anchor();
        else
            size_allocate_due_to_reflow = false;
    }
    
    private void on_viewport_shifted() {
        update_visible_page();
        need_exposure("on_viewport_shift");

        clear_anchor();
    }

    private void on_items_selection_changed() {
        clear_anchor();
    }

    private void clear_anchor() {
        if (in_center_on_anchor)
            return;

        anchor = null;
    }
    
    private void update_anchor() {
        assert(!in_center_on_anchor);

        Gee.List<CheckerboardItem> items_on_page = intersection(visible_page);
        if (items_on_page.size == 0) {
            anchor = null;
            return;
        }

        foreach (CheckerboardItem item in items_on_page) {
            if (item.is_selected()) {
                anchor = item;
                return;
            }
        }

        if (vadjustment.get_value() == 0) {
            anchor = null;
            return;
        }
        
        // this could be improved to always find the visual center...in the case where only
        // a few photos are in the last visible row, this can choose a photo near the right
        anchor = items_on_page.get((int) items_on_page.size / 2);
    }

    private void center_on_anchor(double upper) {
        if (anchor == null)
            return;

        in_center_on_anchor = true;

        // update the vadjustment's upper manually rather than waiting for GTK to do so
        // because subsequent calculations and settings rely on it ... updating upper 
        // will only happen later, when this event finishes
        vadjustment.set_upper(upper);
  
        double anchor_pos = anchor.allocation.y + (anchor.allocation.height / 2) - 
            (vadjustment.get_page_size() / 2);
        vadjustment.set_value(anchor_pos.clamp(vadjustment.get_lower(), 
            vadjustment.get_upper() - vadjustment.get_page_size()));

        in_center_on_anchor = false;
    }
    
    private void on_contents_altered(Gee.Iterable<DataObject>? added, 
        Gee.Iterable<DataObject>? removed) {
        if (added != null)
            message = null;
        
        if (removed != null) {
            foreach (DataObject object in removed)
                exposed_items.remove((CheckerboardItem) object);
        }
        
        // release spatial data structure ... contents_altered means a reflow is required, and since
        // items may be removed, this ensures we're not holding the ref on a removed view
        item_rows = null;
        
        need_reflow("on_contents_altered");
    }
    
    private void on_items_altered() {
        need_reflow("on_items_altered");
    }
    
    private void on_items_state_changed(Gee.Iterable<DataView> changed) {
        items_dirty("on_items_state_changed", changed);
    }
    
    private void on_items_visibility_changed(Gee.Iterable<DataView> changed) {
        need_reflow("on_items_visibility_changed");
    }
    
    private void on_ordering_changed() {
        need_reflow("on_ordering_changed");
    }
    
    private void on_views_altered(Gee.Collection<DataView> altered) {
        items_dirty("on_views_altered", altered);
    }
    
    private void on_geometries_altered() {
        need_reflow("on_geometries_altered");
    }
    
    private void need_reflow(string caller) {
        if (flow_scheduled)
            return;

        if (!is_in_view) {
            reflow_needed = true;
            return;
        }
        
#if TRACE_REFLOW
        debug("need_reflow %s: %s", page_name, caller);
#endif
        flow_scheduled = true;
        Idle.add_full(Priority.HIGH, do_reflow);
    }
    
    private bool do_reflow() {
        reflow("do_reflow");
        need_exposure("do_reflow");

        flow_scheduled = false;
        
        return false;
    }

    private void need_exposure(string caller) {
#if TRACE_REFLOW
        debug("need_exposure %s: %s", page_name, caller);
#endif
        exposure_dirty = true;
        queue_draw();
    }
    
    public void set_message(string? text) {
        if (text == message)
            return;
        
        message = text;
        
        if (text != null) {
            // message is being set, change size to match parent's; if no parent, then the size 
            // will be set later when added to the parent
            if (parent != null)
                set_size_request(parent.allocation.width, parent.allocation.height);
        } else {
            // message is being cleared, layout all the items again
            need_reflow("set_message");
        }
    }
    
    public void unset_message() {
        set_message(null);
    }
    
    private void update_visible_page() {
        if (hadjustment != null && vadjustment != null)
            visible_page = get_adjustment_page(hadjustment, vadjustment);
    }
    
    public void set_in_view(bool in_view) {
        is_in_view = in_view;
        
        if (in_view) {
            if (reflow_needed)
                need_reflow("set_in_view (true)");
            else
                need_exposure("set_in_view (true)");
        } else
            unexpose_items("set_in_view (false)");
    }
    
    public CheckerboardItem? get_item_at_pixel(double xd, double yd) {
        if (message != null || item_rows == null)
            return null;
            
        int x = (int) xd;
        int y = (int) yd;
        
        // binary search the rows for the one in range of the pixel
        LayoutRow in_range = null;
        int min = 0;
        int max = item_rows.length;
        for(;;) {
            int mid = min + ((max - min) / 2);
            LayoutRow row = item_rows[mid];
            
            if (row == null || y < row.y) {
                // undershot
                // row == null happens when there is an exact number of elements to fill the last row
                max = mid - 1;
            } else if (y > (row.y + row.height)) {
                // undershot
                min = mid + 1;
            } else {
                // bingo
                in_range = row;
                
                break;
            }
            
            if (min > max)
                break;
        }
        
        if (in_range == null)
            return null;
        
        // look for item in row's column in range of the pixel
        foreach (CheckerboardItem item in in_range.items) {
            // this happens on an incompletely filled-in row (usually the last one with empty
            // space remaining)
            if (item == null)
                continue;
            
            if (x < item.allocation.x) {
                // overshot ... this happens because there's gaps in the columns
                break;
            }
            
            // need to verify actually over item's full dimensions, since they vary in size inside 
            // a row
            if (x <= (item.allocation.x + item.allocation.width) && y >= item.allocation.y 
                && y <= (item.allocation.y + item.allocation.height))
                return item;
        }

        return null;
    }
    
    public Gee.List<CheckerboardItem> get_visible_items() {
        return intersection(visible_page);
    }
    
    public Gee.List<CheckerboardItem> intersection(Gdk.Rectangle area) {
        Gee.ArrayList<CheckerboardItem> intersects = new Gee.ArrayList<CheckerboardItem>();
        
        Gdk.Rectangle bitbucket = Gdk.Rectangle();
        foreach (LayoutRow row in item_rows) {
            if (row == null)
                continue;
            
            if ((area.y + area.height) < row.y) {
                // overshoot
                break;
            }
            
            if ((row.y + row.height) < area.y) {
                // haven't reached it yet
                continue;
            }
            
            // see if the row intersects the area
            Gdk.Rectangle row_rect = Gdk.Rectangle();
            row_rect.x = 0;
            row_rect.y = row.y;
            row_rect.width = allocation.width;
            row_rect.height = row.height;
            
            if (area.intersect(row_rect, out bitbucket)) {
                // see what elements, if any, intersect the area
                foreach (CheckerboardItem item in row.items) {
                    if (item == null)
                        continue;
                    
                    if (area.intersect(item.allocation, out bitbucket))
                        intersects.add(item);
                }
            }
        }

        return intersects;
    }
    
    public CheckerboardItem? get_item_relative_to(CheckerboardItem item, CompassPoint point) {
        if (view.get_count() == 0)
            return null;
        
        assert(columns > 0);
        assert(rows > 0);
        
        int col = item.get_column();
        int row = item.get_row();
        
        if (col < 0 || row < 0) {
            critical("Attempting to locate item not placed in layout: %s", item.get_title());
            
            return null;
        }
        
        switch (point) {
            case CompassPoint.NORTH:
                if (--row < 0)
                    row = 0;
            break;
            
            case CompassPoint.SOUTH:
                if (++row >= rows)
                    row = rows - 1;
            break;
            
            case CompassPoint.EAST:
                if (++col >= columns) {
                    if(++row >= rows) {
                        row = rows - 1;
                        col = columns - 1;
                    } else {
                        col = 0;
                    }
                }
            break;
            
            case CompassPoint.WEST:
                if (--col < 0) {
                    if (--row < 0) {
                        row = 0;
                        col = 0;
                    } else {
                        col = columns - 1;
                    }
                }
            break;
            
            default:
                error("Bad compass point %d", (int) point);
        }
        
        CheckerboardItem? new_item = get_item_at_coordinate(col, row);
        
        if (new_item == null && point == CompassPoint.SOUTH) {
            // nothing directly below, get last item on next row
            new_item = (CheckerboardItem?) view.get_last();
            if (new_item.get_row() <= item.get_row())
                new_item = null;
        }

        return (new_item != null) ? new_item : item;
    }
    
    public CheckerboardItem? get_item_at_coordinate(int col, int row) {
        if (row >= item_rows.length)
            return null;
            
        LayoutRow item_row = item_rows[row];
        if (item_row == null)
            return null;
        
        if (col >= item_row.items.length)
            return null;
        
        return item_row.items[col];
    }
    
    public void set_drag_select_origin(int x, int y) {
        clear_drag_select();
        
        drag_origin.x = x.clamp(0, allocation.width);
        drag_origin.y = y.clamp(0, allocation.height);
    }
    
    public void set_drag_select_endpoint(int x, int y) {
        drag_endpoint.x = x.clamp(0, allocation.width);
        drag_endpoint.y = y.clamp(0, allocation.height);
        
        // drag_origin and drag_endpoint are maintained only to generate selection_band; all reporting
        // and drawing functions refer to it, not drag_origin and drag_endpoint
        Gdk.Rectangle old_selection_band = selection_band;
        selection_band = Box.from_points(drag_origin, drag_endpoint).get_rectangle();
        
        // force repaint of the union of the old and new, which covers the band reducing in size
        if (window != null) {
            Gdk.Rectangle union;
            selection_band.union(old_selection_band, out union);
            
            queue_draw_area(union.x, union.y, union.width, union.height);
        }
    }
    
    public Gee.List<CheckerboardItem>? items_in_selection_band() {
        if (!Dimensions.for_rectangle(selection_band).has_area())
            return null;

        return intersection(selection_band);
    }
    
    public bool is_drag_select_active() {
        return drag_origin.x >= 0 && drag_origin.y >= 0;
    }
    
    public void clear_drag_select() {
        selection_band = Gdk.Rectangle();
        drag_origin.x = -1;
        drag_origin.y = -1;
        drag_endpoint.x = -1;
        drag_endpoint.y = -1;
        
        // force a total repaint to clear the selection band
        queue_draw();
    }
    
    private void viewport_resized() {
        // update visible page rect
        update_visible_page();
        
        // only reflow() if the width has changed
        if (allocation.width != last_width) {
            int old_width = last_width;
            last_width = allocation.width;
            
            need_reflow("viewport_resized (%d -> %d)".printf(old_width, allocation.width));
        } else {
            // don't need to reflow but exposure may have changed
            need_exposure("viewport_resized");
        }
    }
    
    private void expose_items(string caller) {
        // create a new hash set of exposed items that represents an intersection of the old set
        // and the new
        Gee.HashSet<CheckerboardItem> new_exposed_items = new Gee.HashSet<CheckerboardItem>();
        
        view.freeze_notifications();
        
        Gee.List<CheckerboardItem> items = get_visible_items();
        foreach (CheckerboardItem item in items) {
            new_exposed_items.add(item);

            // if not in the old list, then need to expose
            if (!exposed_items.remove(item))
                item.exposed();
        }
        
        // everything remaining in the old exposed list is now unexposed
        foreach (CheckerboardItem item in exposed_items)
            item.unexposed();
        
        // swap out lists
        exposed_items = new_exposed_items;
        exposure_dirty = false;
        
#if TRACE_REFLOW
        debug("expose_items %s: exposed %d items, thawing", page_name, exposed_items.size);
#endif
        view.thaw_notifications();
#if TRACE_REFLOW
        debug("expose_items %s: thaw finished", page_name);
#endif
    }
    
    private void unexpose_items(string caller) {
        view.freeze_notifications();
        
        foreach (CheckerboardItem item in exposed_items)
            item.unexposed();
        
        exposed_items.clear();
        exposure_dirty = false;
        
#if TRACE_REFLOW
        debug("unexpose_items %s: thawing", page_name);
#endif
        view.thaw_notifications();
#if TRACE_REFLOW
        debug("unexpose_items %s: thawed", page_name);
#endif
    }
    
    private void reflow(string caller) {
        reflow_needed = false;
        
        // if set in message mode, nothing to do here
        if (message != null)
            return;
        
        // don't bother until layout is of some appreciable size (even this is too low)
        if (allocation.width <= 1)
            return;
        
        int total_items = view.get_count();
        
        // need to set_size in case all items were removed and the viewport size has changed
        if (total_items == 0) {
            set_size_request(allocation.width, 0);
            item_rows = new LayoutRow[0];

            return;
        }
        
#if TRACE_REFLOW
        debug("reflow %s: %s (%d items)", page_name, caller, total_items);
#endif
        
        // look for anchor if there is none currently
        if (anchor == null || !anchor.is_visible())
            update_anchor();
        
        // clear the rows data structure, as the reflow will completely rearrange it
        item_rows = null;
        
        // Step 1: Determine the widest row in the layout, and from it the number of columns.
        // If owner supplies an image scaling for all items in the layout, then this can be
        // calculated quickly.
        int max_cols = 0;
        if (scale > 0) {
            // calculate interior width
            int remaining_width = allocation.width - (COLUMN_GUTTER_PADDING * 2);
            int max_item_width = CheckerboardItem.get_max_width(scale);
            max_cols = remaining_width / max_item_width;
            if (max_cols <= 0)
                max_cols = 1;
            
            // if too large with gutters, decrease until columns fit
            while (max_cols > 1 
                && ((max_cols * max_item_width) + ((max_cols - 1) * COLUMN_GUTTER_PADDING) > remaining_width)) {
#if TRACE_REFLOW
                debug("reflow %s: scaled cols estimate: reducing max_cols from %d to %d", page_name,
                    max_cols, max_cols - 1);
#endif
                max_cols--;
            }
            
            // special case: if fewer items than columns, they are the columns
            if (total_items < max_cols)
                max_cols = total_items;
            
#if TRACE_REFLOW
            debug("reflow %s: scaled cols estimate: max_cols=%d remaining_width=%d max_item_width=%d",
                page_name, max_cols, remaining_width, max_item_width);
#endif
        } else {
            int x = COLUMN_GUTTER_PADDING;
            int col = 0;
            int row_width = 0;
            int widest_row = 0;

            for (int ctr = 0; ctr < total_items; ctr++) {
                CheckerboardItem item = (CheckerboardItem) view.get_at(ctr);
                Dimensions req = item.requisition;
                
                // the items must be requisitioned for this code to work
                assert(req.has_area());
                
                // carriage return (i.e. this item will overflow the view)
                if ((x + req.width + COLUMN_GUTTER_PADDING) > allocation.width) {
                    if (row_width > widest_row) {
                        widest_row = row_width;
                        max_cols = col;
                    }
                    
                    col = 0;
                    x = COLUMN_GUTTER_PADDING;
                    row_width = 0;
                }
                
                x += req.width + COLUMN_GUTTER_PADDING;
                row_width += req.width;
                
                col++;
            }
            
            // account for dangling last row
            if (row_width > widest_row)
                max_cols = col;
            
#if TRACE_REFLOW
            debug("reflow %s: manual cols estimate: max_cols=%d widest_row=%d", page_name, max_cols,
                widest_row);
#endif
        }
        
        assert(max_cols > 0);
        int max_rows = (total_items / max_cols) + 1;
        
        // Step 2: Now that the number of columns is known, find the maximum height for each row
        // and the maximum width for each column
        int row = 0;
        int tallest = 0;
        int widest = 0;
        int row_alignment_point = 0;
        int total_width = 0;
        int col = 0;
        int[] column_widths = new int[max_cols];
        int[] row_heights = new int[max_rows];
        int[] alignment_points = new int[max_rows];
        int gutter = 0;
        
        for (;;) {
            for (int ctr = 0; ctr < total_items; ctr++ ) {
                CheckerboardItem item = (CheckerboardItem) view.get_at(ctr);
                Dimensions req = item.requisition;
                int alignment_point = item.get_alignment_point();
                
                // alignment point better be sane
                assert(alignment_point < req.height);
                
                if (req.height > tallest)
                    tallest = req.height;
                
                if (req.width > widest)
                    widest = req.width;
                
                if (alignment_point > row_alignment_point)
                    row_alignment_point = alignment_point;
                
                // store largest thumb size of each column as well as track the total width of the
                // layout (which is the sum of the width of each column)
                if (column_widths[col] < req.width) {
                    total_width -= column_widths[col];
                    column_widths[col] = req.width;
                    total_width += req.width;
                }

                if (++col >= max_cols) {
                    alignment_points[row] = row_alignment_point;
                    row_heights[row++] = tallest;
                    
                    col = 0;
                    row_alignment_point = 0;
                    tallest = 0;
                }
            }
            
            // account for final dangling row
            if (col != 0) {
                alignment_points[row] = row_alignment_point;
                row_heights[row] = tallest;
            }
            
            // Step 3: Calculate the gutter between the items as being equidistant of the
            // remaining space (adding one gutter to account for the right-hand one)
            gutter = (allocation.width - total_width) / (max_cols + 1);
            
            // if only one column, gutter size could be less than minimums
            if (max_cols == 1)
                break;

            // have to reassemble if the gutter is too small ... this happens because Step One
            // takes a guess at the best column count, but when the max. widths of the columns are
            // added up, they could overflow
            if (gutter < COLUMN_GUTTER_PADDING) {
                max_cols--;
                max_rows = (total_items / max_cols) + 1;
                
#if TRACE_REFLOW
                debug("reflow %s: readjusting columns: alloc.width=%d total_width=%d widest=%d gutter=%d max_cols now=%d", 
                    page_name, allocation.width, total_width, widest, gutter, max_cols);
#endif
                
                col = 0;
                row = 0;
                tallest = 0;
                widest = 0;
                total_width = 0;
                row_alignment_point = 0;
                column_widths = new int[max_cols];
                row_heights = new int[max_rows];
                alignment_points = new int[max_rows];
            } else {
                break;
            }
        }

#if TRACE_REFLOW
        debug("reflow %s: width:%d total_width:%d max_cols:%d gutter:%d", page_name, allocation.width, 
            total_width, max_cols, gutter);
#endif
        
        // Step 4: Recalculate the height of each row according to the row's alignment point (which
        // may cause shorter items to extend below the bottom of the tallest one, extending the
        // height of the row)
        col = 0;
        row = 0;
        
        for (int ctr = 0; ctr < total_items; ctr++) {
            CheckerboardItem item = (CheckerboardItem) view.get_at(ctr);
            Dimensions req = item.requisition;
            
            // this determines how much padding the item requires to be bottom-alignment along the
            // alignment point; add to the height and you have the item's "true" height on the 
            // laid-down row
            int true_height = req.height + (alignment_points[row] - item.get_alignment_point());
            assert(true_height >= req.height);
            
            // add that to its height to determine it's actual height on the laid-down row
            if (true_height > row_heights[row]) {
#if TRACE_REFLOW
                debug("reflow %s: Adjusting height of row %d from %d to %d", page_name, row,
                    row_heights[row], true_height);
#endif
                row_heights[row] = true_height;
            }
            
            // carriage return
            if (++col >= max_cols) {
                col = 0;
                row++;
            }
        }
        
        // for the spatial structure
        item_rows = new LayoutRow[max_rows];
        
        // Step 5: Lay out the items in the space using all the information gathered
        int x = gutter;
        int y = TOP_PADDING;
        col = 0;
        row = 0;
        LayoutRow current_row = null;
        
        for (int ctr = 0; ctr < total_items; ctr++) {
            CheckerboardItem item = (CheckerboardItem) view.get_at(ctr);
            Dimensions req = item.requisition;
            
            // this centers the item in the column
            int xpadding = (column_widths[col] - req.width) / 2;
            assert(xpadding >= 0);
            
            // this bottom-aligns the item along the discovered alignment point
            int ypadding = alignment_points[row] - item.get_alignment_point();
            assert(ypadding >= 0);
            
            // save pixel and grid coordinates
            item.allocation = { x + xpadding, y + ypadding, req.width, req.height };
            item.set_grid_coordinates(col, row);
            
            // add to current row in spatial data structure
            if (current_row == null)
                current_row = new LayoutRow(y, row_heights[row], max_cols);
            
            current_row.items[col] = item;

            x += column_widths[col] + gutter;

            // carriage return
            if (++col >= max_cols) {
                assert(current_row != null);
                item_rows[row] = current_row;
                current_row = null;

                x = gutter;
                y += row_heights[row] + ROW_GUTTER_PADDING;
                col = 0;
                row++;
            }
        }
        
        // add last row to spatial data structure
        if (current_row != null)
            item_rows[row] = current_row;
        
        // save dimensions of checkerboard
        columns = max_cols;
        rows = row + 1;
        assert(rows == max_rows);
        
        // Step 6: Define the total size of the page as the size of the allocated width and
        // the height of all the items plus padding
        int total_height = y + row_heights[row] + BOTTOM_PADDING;
        if (total_height != allocation.height) {
#if TRACE_REFLOW
            debug("reflow %s: Changing layout dimensions from %dx%d to %dx%d", page_name, 
                allocation.width, allocation.height, allocation.width, total_height);
#endif
            set_size_request(allocation.width, total_height);
            size_allocate_due_to_reflow = true;
            
            // when height changes, center on the anchor to minimize amount of visual change
            center_on_anchor(total_height);
        }

    }
    
    private void items_dirty(string reason, Gee.Iterable<DataView> items) {
        Gdk.Rectangle dirty = Gdk.Rectangle();
        foreach (DataView data_view in items) {
            CheckerboardItem item = (CheckerboardItem) data_view;
            
            if (!item.is_visible())
                continue;
            
            assert(view.contains(item));
            
            // if not allocated, need to reflow the entire layout; don't bother queueing a draw
            // for any of these, reflow will handle that
            if (item.allocation.width <= 0 || item.allocation.height <= 0) {
                need_reflow("items_dirty: %s".printf(reason));
                
                return;
            }
            
            // only mark area as dirty if visible in viewport
            Gdk.Rectangle intersection = Gdk.Rectangle();
            if (!visible_page.intersect(item.allocation, out intersection))
                continue;
            
            // grow the dirty area
            if (dirty.width == 0 || dirty.height == 0)
                dirty = intersection;
            else
                dirty.union(intersection, out dirty);
        }
        
        if (dirty.width > 0 && dirty.height > 0) {
#if TRACE_REFLOW
            debug("items_dirty %s (%s): Queuing draw of dirty area %s on visible_page %s",
                page_name, reason, rectangle_to_string(dirty), rectangle_to_string(visible_page));
#endif
            queue_draw_area(dirty.x, dirty.y, dirty.width, dirty.height);
        }
    }
    
    public override void map() {
        base.map();
        
        set_colors();
    }

    private void set_colors(bool in_focus = true) {
        // set up selected/unselected colors
        selected_color = fetch_color(
            Config.get_instance().get_selected_color(in_focus).to_string(), window);
        unselected_color = fetch_color(
            Config.get_instance().get_unselected_color().to_string(), window);
        border_color = fetch_color(
            Config.get_instance().get_border_color().to_string(), window);
        bg_color = this.get_style().bg[Gtk.StateType.NORMAL];
    }
    
    public override void size_allocate(Gdk.Rectangle allocation) {
        base.size_allocate(allocation);
        
        viewport_resized();
    }
    
    public override bool expose_event(Gdk.EventExpose event) {
        // Note: It's possible for expose_event to be called when in_view is false; this happens
        // when pages are switched prior to switched_to() being called, and some of the other
        // controls allow for events to be processed while they are orienting themselves.  Since
        // we want switched_to() to be the final call in the process (indicating that the page is
        // now in place and should do its thing to update itself), have to be be prepared for
        // GTK/GDK calls between the widgets being actually present on the screen and "switched to"
        
        // switch to Cairo
        Cairo.Context ctx = Gdk.cairo_create(event.window);
        
        // watch for message mode
        if (message == null) {
#if TRACE_REFLOW
            debug("expose_event %s: %s", page_name, rectangle_to_string(event.area));
#endif
            
            if (exposure_dirty)
                expose_items("expose_event");
            
            // have all items in the exposed area paint themselves
            foreach (CheckerboardItem item in intersection(event.area)) {
                item.paint(ctx, bg_color, item.is_selected() ? selected_color : unselected_color,
                    unselected_color, border_color);
            }
        } else {
            // draw the message in the center of the window
            Pango.Layout pango_layout = create_pango_layout(message);
            int text_width, text_height;
            pango_layout.get_pixel_size(out text_width, out text_height);
            
            int x = allocation.width - text_width;
            x = (x > 0) ? x / 2 : 0;
            
            int y = allocation.height - text_height;
            y = (y > 0) ? y / 2 : 0;
            
            Gdk.cairo_set_source_color(ctx, unselected_color);
            ctx.move_to(x, y);
            Pango.cairo_show_layout(ctx, pango_layout);
        }
        
        bool result = (base.expose_event != null) ? base.expose_event(event) : true;
        
        // draw the selection band last, so it appears floating over everything else
        draw_selection_band(ctx);
        
        return result;
    }
    
    private void draw_selection_band(Cairo.Context ctx) {
        // no selection band, nothing to draw
        if (selection_band.width <= 1 || selection_band.height <= 1)
            return;
        
        // This requires adjustments
        if (hadjustment == null || vadjustment == null)
            return;
        
        // find the visible intersection of the viewport and the selection band
        Gdk.Rectangle visible_page = get_adjustment_page(hadjustment, vadjustment);
        Gdk.Rectangle visible_band = Gdk.Rectangle();
        visible_page.intersect(selection_band, out visible_band);
        
        // pixelate selection rectangle interior
        if (visible_band.width > 1 && visible_band.height > 1) {
            set_source_color_with_alpha(ctx, selected_color, SELECTION_ALPHA);
            ctx.rectangle(visible_band.x, visible_band.y, visible_band.width,
                visible_band.height);
            ctx.fill();
        }
        
        // border
        // See this for an explanation of the adjustments to the band's dimensions
        // http://cairographics.org/FAQ/#sharp_lines
        ctx.set_line_width(1.0);
        ctx.set_line_cap(Cairo.LineCap.SQUARE);
        Gdk.cairo_set_source_color(ctx, selected_color);
        ctx.rectangle((double) selection_band.x + 0.5, (double) selection_band.y + 0.5,
            (double) selection_band.width - 1.0, (double) selection_band.height - 1.0);
        ctx.stroke();
    }
    
    public override bool query_tooltip(int x, int y, bool keyboard_mode, Gtk.Tooltip tooltip) {
        CheckerboardItem? item = get_item_at_pixel(x, y);
        
        return (item != null) ? item.query_tooltip(x, y, tooltip) : false;
    }
    
    private void on_colors_changed() {
        modify_bg(Gtk.StateType.NORMAL, Config.get_instance().get_bg_color());
        set_colors();
    }

    public override bool focus_in_event(Gdk.EventFocus event) {
        set_colors(true);
        items_dirty("focus_in_event", view.get_selected());
        
        return base.focus_in_event(event);
    }

    public override bool focus_out_event(Gdk.EventFocus event) {
        set_colors(false);
        items_dirty("focus_out_event", view.get_selected());
        
        return base.focus_out_event(event);
    }
}
