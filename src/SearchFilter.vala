/* Copyright 2011 Yorba Foundation
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution. 
 */

// Bitfield values used to specify which search bar features we want.
[Flags]
public enum SearchFilterCriteria {
    NONE = 0,
    RECURSIVE,
    TEXT,
    FLAG,
    MEDIA,
    RATING,
    ALL = 0xFFFFFFFF
}

public enum RatingFilter {
    NO_FILTER = 0,
    REJECTED_OR_HIGHER = 1,
    UNRATED_OR_HIGHER = 2,
    ONE_OR_HIGHER = 3,
    TWO_OR_HIGHER = 4,
    THREE_OR_HIGHER = 5,
    FOUR_OR_HIGHER = 6,
    FIVE_OR_HIGHER = 7,
    REJECTED_ONLY = 8,
    UNRATED_ONLY = 9,
    ONE_ONLY = 10,
    TWO_ONLY = 11,
    THREE_ONLY = 12,
    FOUR_ONLY = 13,
    FIVE_ONLY = 14
}

 // Handles filtering via rating and text.
public abstract class SearchViewFilter : ViewFilter {
    // If this is true, allow the current rating or higher.
    private bool rating_allow_higher = true;
    
    // Rating to filter by.
    private Rating rating = Rating.REJECTED;
    private RatingFilter rating_filter = RatingFilter.REJECTED_OR_HIGHER;
    
    // Show flagged only if set to true.
    public bool flagged { get; set; default = false; }
    
    // Media types.
    public bool show_media_video { get; set; default = true; }
    public bool show_media_photos { get; set; default = true; }
    public bool show_media_raw { get; set; default = true; }
    
    // Search text filter.  Should only be set to lower-case.
    private string? search_filter = null;
    private string[]? search_filter_words = null;
    
    // Returns a bitmask of SearchFilterCriteria.
    // IMPORTANT: There is no signal on this, changing this value after the
    // view filter is installed will NOT update the GUI.
    public abstract uint get_criteria();
    
    public void set_rating_filter(RatingFilter rf) {
        rating_filter = rf;
        switch (rating_filter) {
            case RatingFilter.REJECTED_ONLY:
                rating = Rating.REJECTED;
                rating_allow_higher = false;
            break;
            
            case RatingFilter.REJECTED_OR_HIGHER:
                rating = Rating.REJECTED;
                rating_allow_higher = true;
            break;
            
            case RatingFilter.ONE_OR_HIGHER:
                rating = Rating.ONE;
                rating_allow_higher = true;
            break;
            
            case RatingFilter.ONE_ONLY:
                rating = Rating.ONE;
                rating_allow_higher = false;
            break;
            
            case RatingFilter.TWO_OR_HIGHER:
                rating = Rating.TWO;
                rating_allow_higher = true;
            break;
            
             case RatingFilter.TWO_ONLY:
                rating = Rating.TWO;
                rating_allow_higher = false;
            break;
            
            case RatingFilter.THREE_OR_HIGHER:
                rating = Rating.THREE;
                rating_allow_higher = true;
            break;
            
            case RatingFilter.THREE_ONLY:
                rating = Rating.THREE;
                rating_allow_higher = false;
            break;
            
            case RatingFilter.FOUR_OR_HIGHER:
                rating = Rating.FOUR;
                rating_allow_higher = true;
            break;
            
            case RatingFilter.FOUR_ONLY:
                rating = Rating.FOUR;
                rating_allow_higher = false;
            break;
            
            case RatingFilter.FIVE_OR_HIGHER:
                rating = Rating.FIVE;
                rating_allow_higher = true;
            break;
            
            case RatingFilter.FIVE_ONLY:
                rating = Rating.FIVE;
                rating_allow_higher = false;
            break;
            
            case RatingFilter.UNRATED_OR_HIGHER:
            default:
                rating = Rating.UNRATED;
                rating_allow_higher = true;
            break;
        }
    }
    
    public bool has_search_filter() {
        return !is_string_empty(search_filter);
    }
    
    public unowned string? get_search_filter() {
        return search_filter;
    }
       
    public unowned string[]? get_search_filter_words() {
        return search_filter_words;
    }
    
    public void set_search_filter(string? text) {
        search_filter = !is_string_empty(text) ? text.down() : null;
        search_filter_words = search_filter != null ? search_filter.split(" ") : null;
    }
    
    public void clear_search_filter() {
        search_filter = null;
        search_filter_words = null;
    }
    
    public bool get_rating_allow_higher() {
        return rating_allow_higher;
    }
    
    public Rating get_rating() {
        return rating;
    }
    
    public bool filter_by_media_type() {
        return ((show_media_video || show_media_photos || show_media_raw) && 
            !(show_media_video && show_media_photos && show_media_raw));
    }
}

// This class provides a default predicate implementation used for CollectionPage
// as well as Trash and Offline.
public abstract class DefaultSearchViewFilter : SearchViewFilter {
    public override bool predicate(DataView view) {
        MediaSource source = ((Thumbnail) view).get_media_source();
        uint criteria = get_criteria();
        
        // Ratings filter
        if ((SearchFilterCriteria.RATING & criteria) != 0) {
            if (get_rating_allow_higher() && source.get_rating() < get_rating())
                return false;
            else if (!get_rating_allow_higher() && source.get_rating() != get_rating())
                return false;
        }
        
        // Flag state.
        if ((SearchFilterCriteria.FLAG & criteria) != 0) {
            if (flagged && source is Flaggable && !((Flaggable) source).is_flagged())
                return false;
        }
        
        // Media type.
        if (((SearchFilterCriteria.MEDIA & criteria) != 0) && filter_by_media_type()) {
            if (source is VideoSource) {
                if (!show_media_video)
                    return false;
            } else if (source is Photo) {
                if (((Photo) source).get_master_file_format() == PhotoFileFormat.RAW) {
                    if (!show_media_photos && !show_media_raw)
                        return false;
                } else if (!show_media_photos)
                    return false;
            }
        }
        
        if (((SearchFilterCriteria.TEXT & criteria) != 0) && has_search_filter()) {
            unowned string? media_keywords = source.get_indexable_keywords();
            
            unowned string? event_keywords = null;
            Event? event = source.get_event();
            if (event != null)
                event_keywords = event.get_indexable_keywords();
            
            Gee.List<Tag>? tags = Tag.global.fetch_for_source(source);
            int tags_size = (tags != null) ? tags.size : 0;
            
            foreach (unowned string word in get_search_filter_words()) {
                if (media_keywords != null && media_keywords.contains(word))
                    continue;
                
                if (event_keywords != null && event_keywords.contains(word))
                    continue;
                
                if (tags_size > 0) {
                    bool found = false;
                    for (int ctr = 0; ctr < tags_size; ctr++) {
                        unowned string? tag_keywords = tags[ctr].get_indexable_keywords();
                        if (tag_keywords != null && tag_keywords.contains(word)) {
                            found = true;
                            
                            break;
                        }
                    }
                    
                    if (found)
                        continue;
                }
                
                // failed all tests (this even works if none of the Indexables have strings,
                // as they fail the implicit AND test)
                return false;
            }
        }
        
        return true;
    }
}

public class TextAction {
    public string? value {
        get {
            return text;
        }
    }
    
    private string? text = null;
    private bool sensitive = true;
    private bool visible = true;
    
    public signal void text_changed(string? text);
    
    public signal void sensitivity_changed(bool sensitive);
    
    public signal void visibility_changed(bool visible);
    
    public TextAction(string? init = null) {
        text = init;
    }
    
    public void set_text(string? text) {
        if (this.text != text) {
            this.text = text;
            text_changed(text);
        }
    }
    
    public void clear() {
        set_text(null);
    }
    
    public bool is_sensitive() {
        return sensitive;
    }
    
    public void set_sensitive(bool sensitive) {
        if (this.sensitive != sensitive) {
            this.sensitive = sensitive;
            sensitivity_changed(sensitive);
        }
    }
    
    public bool is_visible() {
        return visible;
    }
    
    public void set_visible(bool visible) {
        if (this.visible != visible) {
            this.visible = visible;
            visibility_changed(visible);
        }
    }
}

public class TextActionEntry : Gtk.Entry {
    private TextAction action;
    
    public TextActionEntry(TextAction action) {
        this.action = action;
        
        set_nullable_text(action.value);
        
        action.text_changed.connect(on_action_text_changed);
        action.sensitivity_changed.connect(on_sensitivity_changed);
        action.visibility_changed.connect(on_visibility_changed);
        
        buffer.deleted_text.connect(on_entry_changed);
        buffer.inserted_text.connect(on_entry_changed);
    }
    
    ~TextActionEntry() {
        action.text_changed.disconnect(on_action_text_changed);
        action.sensitivity_changed.disconnect(on_sensitivity_changed);
        action.visibility_changed.disconnect(on_visibility_changed);
        
        buffer.deleted_text.disconnect(on_entry_changed);
        buffer.inserted_text.disconnect(on_entry_changed);
    }
    
    public TextAction get_text_action() {
        return action;
    }
    
    private void on_action_text_changed(string? text) {
        buffer.deleted_text.disconnect(on_entry_changed);
        buffer.inserted_text.disconnect(on_entry_changed);
        set_nullable_text(text);
        buffer.deleted_text.connect(on_entry_changed);
        buffer.inserted_text.connect(on_entry_changed);
    }
    
    private void on_entry_changed() {
        action.text_changed.disconnect(on_action_text_changed);
        action.set_text(get_text());
        action.text_changed.connect(on_action_text_changed);
    }
    
    private void on_sensitivity_changed(bool sensitive) {
        this.sensitive = sensitive;
    }
    
    private void on_visibility_changed(bool visible) {
        ((Gtk.Widget) this).visible = visible;
    }
    
    private void set_nullable_text(string? text) {
        set_text(text != null ? text : "");
    }
}

public class SearchFilterActions {
    public unowned Gtk.ToggleAction? flagged {
        get {
            return get_action("CommonDisplayFlagged") as Gtk.ToggleAction;
        }
    }
    
    public unowned Gtk.ToggleAction? photos {
        get {
            return get_action("CommonDisplayPhotos") as Gtk.ToggleAction;
        }
    }
    
    public unowned Gtk.ToggleAction? videos {
        get {
            return get_action("CommonDisplayVideos") as Gtk.ToggleAction;
        }
    }
    
    public unowned Gtk.ToggleAction? raw {
        get {
            return get_action("CommonDisplayRaw") as Gtk.ToggleAction;
        }
    }
    
    public unowned Gtk.RadioAction? rating {
        get {
            return get_action("CommonDisplayUnratedOrHigher") as Gtk.RadioAction;
        }
    }
    
    public unowned TextAction text {
        get {
            assert(_text != null);
            return _text;
        }
    }
    
    private Gtk.ActionGroup action_group = new Gtk.ActionGroup("SearchFilterActionGroup");
    private SearchFilterCriteria criteria = SearchFilterCriteria.ALL;
    private TextAction? _text = null;
    private bool has_flagged = true;
    private bool has_photos = true;
    private bool has_videos = true;
    private bool has_raw = true;
    
    public signal void flagged_toggled(bool on);
    
    public signal void photos_toggled(bool on);
    
    public signal void videos_toggled(bool on);
    
    public signal void raw_toggled(bool on);
    
    public signal void rating_changed(RatingFilter filter);
    
    public signal void text_changed(string? text);
    
    // Ticket #3290 - Hide some search bar fields when they
    // cannot be used.
    // Part 1 - we use this to announce when the criteria have changed,
    // and the toolbar can listen for it and hide or show widgets accordingly.
    public signal void criteria_changed();
    
    public SearchFilterActions() {
        // the getters defined above should not be used until register() returns
        register();
        
        flagged.toggled.connect(on_flagged_value_toggled);
        photos.toggled.connect(on_photos_value_toggled);
        videos.toggled.connect(on_videos_value_toggled);
        raw.toggled.connect(on_raw_value_toggled);
        rating.changed.connect(on_rating_value_changed);
        text.text_changed.connect(on_text_changed);
    }
    
    public Gtk.ActionGroup get_action_group() {
        return action_group;
    }
    
    public SearchFilterCriteria get_criteria() {
        return criteria;
    }
    
    public unowned Gtk.Action? get_action(string name) {
        return action_group.get_action(name);
    }
    
    public void set_action_sensitive(string name, bool sensitive) {
        Gtk.Action? action = get_action(name);
        if (action != null)
            action.sensitive = sensitive;
    }
    
    public void reset() {
        flagged.active = false;
        photos.active = false;
        raw.active = false;
        videos.active = false;
        rating.current_value = RatingFilter.UNRATED_OR_HIGHER;
        text.set_text(null);
    }
    
    public void set_sensitive_for_search_criteria(SearchFilterCriteria criteria) {
        this.criteria = criteria;
        update_sensitivities();
        
        // Announce that we've gotten a new criteria...
        criteria_changed();
    }
    
    public void monitor_page_contents(Page? old_page, Page? new_page) {
        CheckerboardPage? old_tracked_page = old_page as CheckerboardPage;
        if (old_tracked_page != null) {
            Core.ViewTracker? tracker = old_tracked_page.get_view_tracker();
            if (tracker is MediaViewTracker)
                tracker.updated.disconnect(on_media_tracker_updated);
            else if (tracker is CameraViewTracker)
                tracker.updated.disconnect(on_camera_tracker_updated);
        }
        
        CheckerboardPage? new_tracked_page = new_page as CheckerboardPage;
        if (new_tracked_page != null) {
            Core.ViewTracker? tracker = new_tracked_page.get_view_tracker();
            if (tracker is MediaViewTracker) {
                tracker.updated.connect(on_media_tracker_updated);
                on_media_tracker_updated(tracker);
                
                return;
            } else if (tracker is CameraViewTracker) {
                tracker.updated.connect(on_camera_tracker_updated);
                on_camera_tracker_updated(tracker);
                
                return;
            }
        }
        
        // go with default behavior of making none of the filters available.
        has_flagged = false;
        has_photos = false;
        has_videos = false;
        has_raw = false;
        
        update_sensitivities();
    }
    
    private void on_media_tracker_updated(Core.Tracker t) {
        MediaViewTracker tracker = (MediaViewTracker) t;
        
        has_flagged = tracker.all.flagged > 0;
        has_photos = tracker.all.photos > 0;
        has_videos = tracker.all.videos > 0;
        has_raw = tracker.all.raw > 0;
        
        update_sensitivities();
    }
    
    private void on_camera_tracker_updated(Core.Tracker t) {
        CameraViewTracker tracker = (CameraViewTracker) t;
        
        has_flagged = false;
        has_photos = tracker.all.photos > 0;
        has_videos = tracker.all.videos > 0;
        has_raw = tracker.all.raw > 0;

        update_sensitivities();
    }
    
    private void update_sensitivities() {
        flagged.set_stock_id(((SearchFilterCriteria.FLAG & criteria) != 0 && has_flagged) ?
            Resources.ICON_FILTER_FLAGGED : Resources.ICON_FILTER_FLAGGED_DISABLED);
        
        bool allow_media = (SearchFilterCriteria.MEDIA & criteria) != 0;
        videos.set_stock_id((allow_media && has_videos) ?
             Resources.ICON_FILTER_VIDEOS :  Resources.ICON_FILTER_VIDEOS_DISABLED);
        photos.set_stock_id((allow_media && has_photos) ?
             Resources.ICON_FILTER_PHOTOS :  Resources.ICON_FILTER_PHOTOS_DISABLED);
        raw.set_stock_id((allow_media && has_raw) ?
             Resources.ICON_FILTER_RAW :  Resources.ICON_FILTER_RAW_DISABLED);
        
        bool allow_ratings = (SearchFilterCriteria.RATING & criteria) != 0;
        set_action_sensitive("CommonDisplayRejectedOnly", allow_ratings);
        set_action_sensitive("CommonDisplayRejectedOrHigher", allow_ratings);
        set_action_sensitive("CommonDisplayUnratedOrHigher", allow_ratings);
        set_action_sensitive("CommonDisplayOneOrHigher", allow_ratings);
        set_action_sensitive("CommonDisplayTwoOrHigher", allow_ratings);
        set_action_sensitive("CommonDisplayThreeOrHigher", allow_ratings);
        set_action_sensitive("CommonDisplayFourOrHigher", allow_ratings);
        set_action_sensitive("CommonDisplayFiveOrHigher", allow_ratings);
        
        // Ticket #3343 - Don't disable the text field, even
        // when no searchable items are available.
        text.set_sensitive(true);
    }
    
    private void on_flagged_value_toggled(Gtk.ToggleAction action) {
        Config.get_instance().set_search_flagged(action.active);
    }
    
    private void on_photos_value_toggled(Gtk.ToggleAction action) {
        Config.get_instance().set_show_media_photos(action.active);
    }
    
    private void on_videos_value_toggled(Gtk.ToggleAction action) {
        Config.get_instance().set_show_media_video(action.active);
    }
    
    private void on_raw_value_toggled(Gtk.ToggleAction action) {
        Config.get_instance().set_show_media_raw(action.active);
    }
    
    private void on_rating_value_changed(Gtk.RadioAction action, Gtk.RadioAction current) {
        Config.get_instance().set_photo_rating_filter((RatingFilter) current.current_value);
    }
    
    private void on_text_changed(TextAction action, string? text) {
        Config.get_instance().set_search_text(text != null ? text : "");
        text_changed(text);
    }
    
    private void register() {
        _text = new TextAction(Config.get_instance().get_search_text());
        
        Gtk.RadioActionEntry[] view_filter_actions = new Gtk.RadioActionEntry[0];
        
        Gtk.RadioActionEntry rejected_only = { "CommonDisplayRejectedOnly", null, TRANSLATABLE,
            "<Ctrl>8", TRANSLATABLE, RatingFilter.REJECTED_ONLY };
        rejected_only.label = Resources.DISPLAY_REJECTED_ONLY_MENU;
        rejected_only.tooltip = Resources.DISPLAY_REJECTED_ONLY_TOOLTIP;
        view_filter_actions += rejected_only;
        
        Gtk.RadioActionEntry rejected_or_higher = { "CommonDisplayRejectedOrHigher", null, TRANSLATABLE,
            "<Ctrl>9", TRANSLATABLE, RatingFilter.REJECTED_OR_HIGHER };
        rejected_or_higher.label = Resources.DISPLAY_REJECTED_OR_HIGHER_MENU;
        rejected_or_higher.tooltip = Resources.DISPLAY_REJECTED_OR_HIGHER_TOOLTIP;
        view_filter_actions += rejected_or_higher;
        
        Gtk.RadioActionEntry unrated_or_higher = { "CommonDisplayUnratedOrHigher", null, TRANSLATABLE, 
            "<Ctrl>0", TRANSLATABLE, RatingFilter.UNRATED_OR_HIGHER };
        unrated_or_higher.label = Resources.DISPLAY_UNRATED_OR_HIGHER_MENU;
        unrated_or_higher.tooltip = Resources.DISPLAY_UNRATED_OR_HIGHER_TOOLTIP;
        view_filter_actions += unrated_or_higher;
        
        Gtk.RadioActionEntry one_or_higher = { "CommonDisplayOneOrHigher", null, TRANSLATABLE,
            "<Ctrl>1", TRANSLATABLE, RatingFilter.ONE_OR_HIGHER };
        one_or_higher.label = Resources.DISPLAY_ONE_OR_HIGHER_MENU;
        one_or_higher.tooltip = Resources.DISPLAY_ONE_OR_HIGHER_TOOLTIP;
        view_filter_actions += one_or_higher;
        
        Gtk.RadioActionEntry two_or_higher = { "CommonDisplayTwoOrHigher", null, TRANSLATABLE,
            "<Ctrl>2", TRANSLATABLE, RatingFilter.TWO_OR_HIGHER };
        two_or_higher.label = Resources.DISPLAY_TWO_OR_HIGHER_MENU;
        two_or_higher.tooltip = Resources.DISPLAY_TWO_OR_HIGHER_TOOLTIP;
        view_filter_actions += two_or_higher;
        
        Gtk.RadioActionEntry three_or_higher = { "CommonDisplayThreeOrHigher", null, TRANSLATABLE,
            "<Ctrl>3", TRANSLATABLE, RatingFilter.THREE_OR_HIGHER };
        three_or_higher.label = Resources.DISPLAY_THREE_OR_HIGHER_MENU;
        three_or_higher.tooltip = Resources.DISPLAY_THREE_OR_HIGHER_TOOLTIP;
        view_filter_actions += three_or_higher;
        
        Gtk.RadioActionEntry four_or_higher = { "CommonDisplayFourOrHigher", null, TRANSLATABLE,
            "<Ctrl>4", TRANSLATABLE, RatingFilter.FOUR_OR_HIGHER };
        four_or_higher.label = Resources.DISPLAY_FOUR_OR_HIGHER_MENU;
        four_or_higher.tooltip = Resources.DISPLAY_FOUR_OR_HIGHER_TOOLTIP;
        view_filter_actions += four_or_higher;
        
        Gtk.RadioActionEntry five_or_higher = { "CommonDisplayFiveOrHigher", null, TRANSLATABLE,
            "<Ctrl>5", TRANSLATABLE, RatingFilter.FIVE_OR_HIGHER };
        five_or_higher.label = Resources.DISPLAY_FIVE_OR_HIGHER_MENU;
        five_or_higher.tooltip = Resources.DISPLAY_FIVE_OR_HIGHER_TOOLTIP;
        view_filter_actions += five_or_higher;
        
        action_group.add_radio_actions(view_filter_actions, Config.get_instance().get_photo_rating_filter(),
            on_rating_changed);
        
        Gtk.ToggleActionEntry[] toggle_actions = new Gtk.ToggleActionEntry[0];
        
        Gtk.ToggleActionEntry flagged_action = { "CommonDisplayFlagged", Resources.ICON_FILTER_FLAGGED,
            TRANSLATABLE, null, TRANSLATABLE, on_flagged_toggled, Config.get_instance().get_search_flagged() };
        flagged_action.label = _("Flagged");
        flagged_action.tooltip = _("Flagged");
        toggle_actions += flagged_action;
        
        Gtk.ToggleActionEntry photos_action = { "CommonDisplayPhotos", Resources.ICON_FILTER_PHOTOS,
            TRANSLATABLE, null, TRANSLATABLE, on_photos_toggled, Config.get_instance().get_show_media_photos() };
        photos_action.label = _("Photos");
        photos_action.tooltip = _("Photos");
        toggle_actions += photos_action;
        
        Gtk.ToggleActionEntry videos_action = { "CommonDisplayVideos", Resources.ICON_FILTER_VIDEOS,
            TRANSLATABLE, null, TRANSLATABLE, on_videos_toggled, Config.get_instance().get_show_media_video() };
        videos_action.label = _("Videos");
        videos_action.tooltip = _("Videos");
        toggle_actions += videos_action;
        
        Gtk.ToggleActionEntry raw_action = { "CommonDisplayRaw", Resources.ICON_FILTER_RAW, TRANSLATABLE,
            null, TRANSLATABLE, on_raw_toggled, Config.get_instance().get_show_media_raw() };
        raw_action.label = _("RAW Photos");
        raw_action.tooltip = _("RAW photos");
        toggle_actions += raw_action;
        
        action_group.add_toggle_actions(toggle_actions, this);
    }
    
    private void on_rating_changed(Gtk.Action action, Gtk.Action current) {
        rating_changed((RatingFilter) ((Gtk.RadioAction) current).get_current_value());
    }
    
    private void on_flagged_toggled(Gtk.Action action) {
        flagged_toggled(((Gtk.ToggleAction) action).active);
    }
    
    private void on_photos_toggled(Gtk.Action action) {
        photos_toggled(((Gtk.ToggleAction) action).active);
    }
    
    private void on_videos_toggled(Gtk.Action action) {
        videos_toggled(((Gtk.ToggleAction) action).active);
    }
    
    private void on_raw_toggled(Gtk.Action action) {
        raw_toggled(((Gtk.ToggleAction) action).active);
    }
}

public class SearchFilterToolbar : Gtk.Toolbar {
    private const int FILTER_BUTTON_MARGIN = 12; // the distance between icon and edge of button
    private const float FILTER_ICON_STAR_SCALE = 0.65f; // changes the size of the filter icon
    private const float FILTER_ICON_SCALE = 0.75f; // changes the size of the all photos icon
    
    // filter_icon_base_width is the width (in px) of a single filter icon such as one star or an "X"
    private const int FILTER_ICON_BASE_WIDTH = 30;
    // filter_icon_plus_width is the width (in px) of the plus icon
    private const int FILTER_ICON_PLUS_WIDTH = 20;
    
    private class LabelToolItem : Gtk.ToolItem {
        private Gtk.Label label;
        
        public LabelToolItem(string s, int left_padding = 0, int right_padding = 0) {
            label = new Gtk.Label(s);
            if (left_padding != 0 || right_padding != 0) {
                Gtk.Alignment alignment = new Gtk.Alignment(0, 0.5f, 0, 0);
                alignment.add(label);
                alignment.left_padding = left_padding;
                alignment.right_padding = right_padding;
                add(alignment);
            } else {
                add(label);
            }
        }
        
        public void set_color(Gdk.Color color) {
            label.modify_fg(Gtk.StateType.NORMAL, color);
        }
    }
    
    private class ToggleActionToolButton : Gtk.ToggleToolButton {
        public ToggleActionToolButton(Gtk.Action action) {
            set_related_action(action);
        }
    }
    
    // Ticket #3260 - Add a 'close' context menu to
    // the searchbar.
    // The close menu. Populated below in the constructor.
    private Gtk.Menu close_menu = new Gtk.Menu();
    private Gtk.ImageMenuItem close_item = new Gtk.ImageMenuItem.from_stock(Gtk.Stock.CLOSE, null);
   
    // Text search box.
    protected class SearchBox : Gtk.ToolItem {
        private TextActionEntry entry;
        
        public SearchBox(TextAction action) {
            entry = new TextActionEntry(action);
            
            entry.primary_icon_stock = Resources.SEARCHBOX_FIND;
            entry.primary_icon_activatable = false;
            entry.secondary_icon_stock = Resources.SEARCHBOX_CLEAR;
            entry.secondary_icon_activatable = true;
            entry.width_chars = 23;
            entry.icon_release.connect(on_icon_release);
            entry.key_press_event.connect(on_escape_key); 
            add(entry);
        }
        
        ~SearchBox() {
            entry.icon_release.disconnect(on_icon_release);
            entry.key_press_event.disconnect(on_escape_key);
        }
        
        private void on_icon_release(Gtk.EntryIconPosition pos, Gdk.Event event) {
            if (Gtk.EntryIconPosition.SECONDARY == pos)
                entry.get_text_action().clear();
        }
        
        public void get_focus() {
            entry.has_focus = true;
        }
        
        // Ticket #3124 - user should be able to clear 
        // the search textbox by typing 'Esc'. 
        private bool on_escape_key(Gdk.EventKey e) { 
            if(Gdk.keyval_name(e.keyval) == "Escape")
                entry.get_text_action().clear(); 
            
            // Continue processing this event, since the 
            // text entry functionality needs to see it too. 
            return false; 
        }
        
        public void set_bg_color(Gtk.StateType state, Gdk.Color? color) {
            entry.modify_bg(state, color);
        }
    }
    
    // Handles ratings filters.
    protected class RatingFilterButton : Gtk.ToolButton {
        public Gtk.Menu filter_popup = null;
        
        public RatingFilterButton() {
            set_icon_widget(get_filter_icon(RatingFilter.UNRATED_OR_HIGHER));
            set_homogeneous(false);
        }
        
        private Gtk.Widget get_filter_icon(RatingFilter filter) {
            string filename = null;

            switch (filter) {
                case RatingFilter.ONE_OR_HIGHER:
                    filename = Resources.ICON_FILTER_ONE_OR_BETTER;
                break;
                
                case RatingFilter.TWO_OR_HIGHER:
                    filename = Resources.ICON_FILTER_TWO_OR_BETTER;
                break;
                
                case RatingFilter.THREE_OR_HIGHER:
                    filename = Resources.ICON_FILTER_THREE_OR_BETTER;
                break;
                
                case RatingFilter.FOUR_OR_HIGHER:
                    filename = Resources.ICON_FILTER_FOUR_OR_BETTER;
                break;
                
                case RatingFilter.FIVE_OR_HIGHER:
                    filename = Resources.ICON_FILTER_FIVE;
                break;
                
                case RatingFilter.REJECTED_OR_HIGHER:
                    filename = Resources.ICON_FILTER_REJECTED_OR_BETTER;
                break;
                
                case RatingFilter.REJECTED_ONLY:
                    filename = Resources.ICON_RATING_REJECTED;
                break;
                
                case RatingFilter.UNRATED_OR_HIGHER:
                default:
                    filename = Resources.ICON_FILTER_UNRATED_OR_BETTER;
                break;
            }
            
            return new Gtk.Image.from_pixbuf(Resources.load_icon(filename,
                get_filter_icon_size(filter)));
        }

        private int get_filter_icon_size(RatingFilter filter) {
            int icon_base = (int) (FILTER_ICON_BASE_WIDTH * FILTER_ICON_SCALE);
            int icon_star_base = (int) (FILTER_ICON_BASE_WIDTH * FILTER_ICON_STAR_SCALE);
            int icon_plus = (int) (FILTER_ICON_PLUS_WIDTH * FILTER_ICON_STAR_SCALE);
            
            switch (filter) {
                case RatingFilter.ONE_OR_HIGHER:
                    return icon_star_base + icon_plus;
                case RatingFilter.TWO_OR_HIGHER:
                    return icon_star_base * 2 + icon_plus;
                case RatingFilter.THREE_OR_HIGHER:
                    return icon_star_base * 3 + icon_plus;
                case RatingFilter.FOUR_OR_HIGHER:
                    return icon_star_base * 4 + icon_plus;
                case RatingFilter.FIVE_OR_HIGHER:
                case RatingFilter.FIVE_ONLY:
                    return icon_star_base * 5;
                case RatingFilter.REJECTED_OR_HIGHER:
                    return Resources.ICON_FILTER_REJECTED_OR_BETTER_FIXED_SIZE;
                case RatingFilter.UNRATED_OR_HIGHER:
                    return Resources.ICON_FILTER_UNRATED_OR_BETTER_FIXED_SIZE;
                case RatingFilter.REJECTED_ONLY:
                    return icon_plus;
                default:
                    return icon_base;
            }
        }

        public void set_filter_icon(RatingFilter filter) {
            set_icon_widget(get_filter_icon(filter));
            set_size_request(get_filter_button_size(filter), -1);
            set_tooltip_text(Resources.get_rating_filter_tooltip(filter));
            show_all();
        }

        private int get_filter_button_size(RatingFilter filter) {
            return get_filter_icon_size(filter) + 2 * FILTER_BUTTON_MARGIN;
        }
    }
    
    // Used to disable the toolbar.
    private class DisabledViewFilter : SearchViewFilter {
        public override bool predicate(DataView view) {
            return true;
        }
        
        public override uint get_criteria() {
            return SearchFilterCriteria.NONE;
        }
    }
    
    public Gtk.UIManager ui = new Gtk.UIManager();
    
    private SearchFilterActions actions;
    private SearchBox search_box;
    private RatingFilterButton rating_button = new RatingFilterButton();
    private SearchViewFilter? search_filter = null;
    private LabelToolItem label_type;
    private LabelToolItem label_flagged;
    private LabelToolItem label_rating;
    private ToggleActionToolButton toolbtn_photos;
    private ToggleActionToolButton toolbtn_videos;
    private ToggleActionToolButton toolbtn_raw;
    private ToggleActionToolButton toolbtn_flag;
    private Gtk.SeparatorToolItem sepr_mediatype_flagged;
    private Gtk.SeparatorToolItem sepr_flagged_rating;
    
    public SearchFilterToolbar(SearchFilterActions actions) {
        this.actions = actions;
        search_box = new SearchBox(actions.text);
        
        set_name("search-filter-toolbar");
        set_icon_size(Gtk.IconSize.SMALL_TOOLBAR);
        
        File ui_file = Resources.get_ui("search_bar.ui");
        try {
            ui.add_ui_from_file(ui_file.get_path());
        } catch (Error err) {
            AppWindow.panic(_("Error loading UI file %s: %s").printf(
                ui_file.get_path(), err.message));
        }
        
        ui.insert_action_group(actions.get_action_group(), 0);
        
        // Ticket #3260 - Add a 'close' context menu to
        // the searchbar.
        // Prepare the close menu for use, but don't
        // display it yet; we'll connect it to secondary
        // click later on.
        ((Gtk.MenuItem) close_item).show();
        close_item.always_show_image = true;
        close_item.activate.connect(on_context_menu_close_chosen);
        close_menu.append(close_item);
       
        // Type label and toggles
        label_type = new LabelToolItem(_("Type"), 10, 5);
        insert(label_type, -1);
        
        toolbtn_photos = new ToggleActionToolButton(actions.photos); 
        toolbtn_videos = new ToggleActionToolButton(actions.videos);
        toolbtn_raw = new ToggleActionToolButton(actions.raw);
        
        insert(toolbtn_photos, -1);
        insert(toolbtn_videos, -1);
        insert(toolbtn_raw, -1);
        
        // separator
        sepr_mediatype_flagged = new Gtk.SeparatorToolItem();
        insert(sepr_mediatype_flagged, -1);
        
        // Flagged label and toggle
        label_flagged = new LabelToolItem(_("Flagged"));
        insert(label_flagged, -1);
        
        toolbtn_flag = new ToggleActionToolButton(actions.flagged);
        insert(toolbtn_flag, -1);
        
        // separator
        sepr_flagged_rating = new Gtk.SeparatorToolItem();
        insert(sepr_flagged_rating, -1);
        
        // Rating label and button
        label_rating = new LabelToolItem(_("Rating"));
        insert(label_rating, -1);
        rating_button.filter_popup = (Gtk.Menu) ui.get_widget("/FilterPopupMenu");
        rating_button.set_expand(false);
        rating_button.clicked.connect(on_filter_button_clicked);
        insert(rating_button, -1);
        
        // Separator to right-align the text box
        Gtk.SeparatorToolItem separator_align = new Gtk.SeparatorToolItem();
        separator_align.set_expand(true);
        separator_align.set_draw(false);
        insert(separator_align, -1);
        
        // Search box.
        insert(search_box, -1);
        
        // Set background color of toolbar and update them when the configuration is updated
        recompute_style_cascade();       
        Config.get_instance().colors_changed.connect(on_colors_changed);
        Config.get_instance().string_changed.connect(on_config_string_changed);
        on_colors_changed(); // Force color change on init.
        
        // hook up signals to actions to be notified when they change
        actions.flagged_toggled.connect(on_flagged_toggled);
        actions.photos_toggled.connect(on_photos_toggled);
        actions.videos_toggled.connect(on_videos_toggled);
        actions.raw_toggled.connect(on_raw_toggled);
        actions.rating_changed.connect(on_rating_changed);
        actions.text_changed.connect(on_search_text_changed);
        actions.criteria_changed.connect(on_criteria_changed);
        
        // #3260 part II Hook up close menu.
        popup_context_menu.connect(on_context_menu_requested);        
    }
    
    ~SearchFilterToolbar() {
        Config.get_instance().colors_changed.disconnect(on_colors_changed);
        Config.get_instance().string_changed.disconnect(on_config_string_changed);

        actions.flagged_toggled.disconnect(on_flagged_toggled);
        actions.photos_toggled.disconnect(on_photos_toggled);
        actions.videos_toggled.disconnect(on_videos_toggled);
        actions.raw_toggled.disconnect(on_raw_toggled);
        actions.rating_changed.disconnect(on_rating_changed);
        actions.text_changed.disconnect(on_search_text_changed);
        actions.criteria_changed.disconnect(on_criteria_changed);
        
        popup_context_menu.disconnect(on_context_menu_requested); 
    }
    
    private void on_colors_changed() {
        modify_bg(Gtk.StateType.NORMAL, Config.get_instance().get_bg_color());
        modify_base(Gtk.StateType.NORMAL, Config.get_instance().get_bg_color());
        search_box.set_bg_color(Gtk.StateType.NORMAL, Config.get_instance().get_bg_color());
        label_type.set_color(Config.get_instance().get_unselected_color());
        label_flagged.set_color(Config.get_instance().get_unselected_color());
        label_rating.set_color(Config.get_instance().get_unselected_color());
    }
    
    private void recompute_style_cascade() {
        string toolbar_style = """
            style "search-filter-toolbar-style"
            {
                GtkToolbar::shadow-type = GTK_SHADOW_IN
                
                color["search_background"] = "%s"
                
                bg[NORMAL] = @search_background
                bg[PRELIGHT] = shade(1.02, @search_background)
                bg[ACTIVE] = shade(0.85, @search_background)
                
                fg[NORMAL] = "#ccc"
            }

            widget_class "*<SearchFilterToolbar>*" style "search-filter-toolbar-style"
        """.printf(Config.get_instance().get_bg_color().to_string());
        Gtk.rc_parse_string(toolbar_style);
    }
    
    private void on_config_string_changed(string path, string value) {
        if (path == Config.STRING_BG_COLOR) {
            recompute_style_cascade();
            this.reset_rc_styles();
        }
    }
    
    // Ticket #3260 part IV - display the context menu on secondary click
    private bool on_context_menu_requested(int x, int y, int button) { 
        close_menu.popup(null, null, null, button, Gtk.get_current_event_time()); 
        return false;
    }
    
    // Ticket #3260 part III - this runs whenever 'close'
    // is chosen in the context menu.
    private void on_context_menu_close_chosen() { 
        AppWindow aw = LibraryWindow.get_app();        
        
        // Try to obtain the action for toggling the searchbar.  If
        // it's null, then we're probably in direct edit mode, and 
        // shouldn't do anything anyway.
        Gtk.ToggleAction searchbar_toggle = aw.get_common_action("CommonDisplaySearchbar") as Gtk.ToggleAction;
        
        // Could we find the appropriate action?
        if(searchbar_toggle != null) {
            // Yes, hide the search bar.
            searchbar_toggle.set_active(false);
        }
    }
    
    private void on_flagged_toggled() {
        update();
    }
    
    private void on_videos_toggled() {
        update();
    }
    
    private void on_photos_toggled() {
        update();
    }
    
    private void on_raw_toggled() {
        update();
    }
    
    private void on_search_text_changed() {
        update();
    }
    
    private void on_rating_changed() {
        update();
    }
    
    // Ticket #3290, part II - listen for criteria change signals,
    // and show or hide widgets based on the criteria we just 
    // changed to.
    private void on_criteria_changed() {
        update();
    }
    
    public void set_view_filter(SearchViewFilter search_filter) {
        if (search_filter == this.search_filter)
            return;
        
        this.search_filter = search_filter;
        
        // Enable/disable toolbar features depending on what the filter offers
        actions.set_sensitive_for_search_criteria((SearchFilterCriteria) search_filter.get_criteria());
        rating_button.sensitive = (SearchFilterCriteria.RATING & search_filter.get_criteria()) != 0;
        
        update();
    }
    
    public void unset_view_filter() {
        set_view_filter(new DisabledViewFilter());
    }
    
    // Forces an update of the search filter.
    public void update() {
        if (null == search_filter) {
            // Search bar isn't being shown, need to toggle it.
            LibraryWindow.get_app().show_search_bar(true);
        }
        
        assert(null != search_filter);
        
        search_filter.set_search_filter(actions.text.value);
        search_filter.flagged = actions.flagged.active;
        search_filter.show_media_video = actions.videos.active;
        search_filter.show_media_photos = actions.photos.active;
        search_filter.show_media_raw = actions.raw.active;
        
        RatingFilter filter = (RatingFilter) actions.rating.current_value;
        search_filter.set_rating_filter(filter);
        rating_button.set_filter_icon(filter);
        
        // Ticket #3290, part III - check the current criteria
        // and show or hide widgets as needed.
        SearchFilterCriteria criteria = actions.get_criteria();
        
        search_box.visible = ((criteria & SearchFilterCriteria.TEXT) != 0);

        rating_button.visible = ((criteria & SearchFilterCriteria.RATING) != 0);
        label_rating.visible = ((criteria & SearchFilterCriteria.RATING) != 0);
        
        label_flagged.visible = ((criteria & SearchFilterCriteria.FLAG) != 0);
        toolbtn_flag.visible = ((criteria & SearchFilterCriteria.FLAG) != 0);
        
        label_type.visible = ((criteria & SearchFilterCriteria.MEDIA) != 0);
        toolbtn_photos.visible = ((criteria & SearchFilterCriteria.MEDIA) != 0); 
        toolbtn_videos.visible = ((criteria & SearchFilterCriteria.MEDIA) != 0);
        toolbtn_raw.visible = ((criteria & SearchFilterCriteria.MEDIA) != 0);

        // Ticket #3290, part IV - ensure that the separators
        // are shown and/or hidden as needed.
        sepr_mediatype_flagged.visible = (label_type.visible && label_flagged.visible);

        sepr_flagged_rating.visible = ((label_type.visible && label_rating.visible) || 
        	(label_flagged.visible && label_rating.visible));

        // Send update to view collection.
        search_filter.refresh();
    }
    
    private void position_filter_popup(Gtk.Menu menu, out int x, out int y, out bool push_in) {
        menu.realize();
        int rx, ry;
        AppWindow.get_instance().window.get_root_origin(out rx, out ry);
        
        x = rx + rating_button.allocation.x;
        y = ry + rating_button.allocation.y + rating_button.allocation.height +
            AppWindow.get_instance().get_current_page().get_menubar().allocation.height;

        push_in = false;
    }
    
    private void on_filter_button_clicked() {
        rating_button.filter_popup.popup(null, null, position_filter_popup, 0,
            Gtk.get_current_event_time());
    }
    
    public void take_focus() {
        search_box.get_focus();
    }
}

