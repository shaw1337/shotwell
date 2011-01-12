/* Copyright 2009-2011 Yorba Foundation
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution. 
 */

public class CollectionViewManager : ViewManager {
    private CollectionPage page;
    
    public CollectionViewManager(CollectionPage page) {
        this.page = page;
    }
    
    public override DataView create_view(DataSource source) {
        return page.create_thumbnail(source);
    }
}

public abstract class CollectionPage : MediaPage {
    private const double DESKTOP_SLIDESHOW_TRANSITION_SEC = 2.0;
    
    private Gtk.ToolButton rotate_button = null;
    private ExporterUI exporter = null;
    
    public CollectionPage(string page_name) {
        base (page_name);

        get_view().items_altered.connect(on_photos_altered);

        init_item_context_menu("/CollectionContextMenu");

        // set up page's toolbar (used by AppWindow for layout)
        Gtk.Toolbar toolbar = get_toolbar();
        
        // rotate tool
        rotate_button = new Gtk.ToolButton.from_stock("");
        rotate_button.set_related_action(get_action("RotateClockwise"));
        rotate_button.set_label(Resources.ROTATE_CW_LABEL);
        
        toolbar.insert(rotate_button, -1);

        // enhance tool
        Gtk.ToolButton enhance_button = new Gtk.ToolButton.from_stock(Resources.ENHANCE);
        enhance_button.set_related_action(get_action("Enhance"));

        toolbar.insert(enhance_button, -1);

        // separator
        toolbar.insert(new Gtk.SeparatorToolItem(), -1);
        
        // publish button
        Gtk.ToolButton publish_button = new Gtk.ToolButton.from_stock("");
        publish_button.set_related_action(get_action("Publish"));
        publish_button.set_icon_name(Resources.PUBLISH);
        publish_button.set_label(Resources.PUBLISH_LABEL);
        
        toolbar.insert(publish_button, -1);
        
        // separator to force slider to right side of toolbar
        Gtk.SeparatorToolItem separator = new Gtk.SeparatorToolItem();
        separator.set_expand(true);
        separator.set_draw(false);
        
        toolbar.insert(separator, -1);

        // ratings filter button
        MediaPage.FilterButton filter_button = create_filter_button();
        connect_filter_button(filter_button);
        toolbar.insert(filter_button, -1);

        Gtk.SeparatorToolItem drawn_separator = new Gtk.SeparatorToolItem();
        drawn_separator.set_expand(false);
        drawn_separator.set_draw(true);
        
        toolbar.insert(drawn_separator, -1);
        
        // zoom slider assembly
        MediaPage.ZoomSliderAssembly zoom_slider_assembly = create_zoom_slider_assembly();
        connect_slider(zoom_slider_assembly);
        toolbar.insert(zoom_slider_assembly, -1);
        
        show_all();

        // watch for updates to the external app settings
        Config.get_instance().external_app_changed.connect(on_external_app_changed);
    }

    private static InjectionGroup create_file_menu_injectables() {
        InjectionGroup group = new InjectionGroup("/MediaMenuBar/FileMenu/FileExtrasPlaceholder");
        
        group.add_menu_item("Print");
        group.add_separator();
        group.add_menu_item("Publish");
        group.add_menu_item("SendTo");
        group.add_menu_item("SetBackground");
        
        return group;
    }
    
    private static InjectionGroup create_edit_menu_injectables() {
        InjectionGroup group = new InjectionGroup("/MediaMenuBar/EditMenu/EditExtrasPlaceholder");
        
        group.add_menu_item("Duplicate");

        return group;
    }

    private static InjectionGroup create_view_menu_fullscreen_injectables() {
        InjectionGroup group = new InjectionGroup("/MediaMenuBar/ViewMenu/ViewExtrasFullscreenSlideshowPlaceholder");
        
        group.add_menu_item("Fullscreen", "CommonFullscreen");
        group.add_separator();
        group.add_menu_item("Slideshow");
        
        return group;
    }

    private static InjectionGroup create_photos_menu_edits_injectables() {
        InjectionGroup group = new InjectionGroup("/MediaMenuBar/PhotosMenu/PhotosExtrasEditsPlaceholder");
        
        group.add_menu_item("RotateClockwise");
        group.add_menu_item("RotateCounterclockwise");
        group.add_menu_item("FlipHorizontally");
        group.add_menu_item("FlipVertically");
        group.add_separator();
        group.add_menu_item("Enhance");
        group.add_menu_item("Revert");
        
        return group;
    }
  
    private static InjectionGroup create_photos_menu_date_injectables() {
        InjectionGroup group = new InjectionGroup("/MediaMenuBar/PhotosMenu/PhotosExtrasDateTimePlaceholder");
        
        group.add_menu_item("AdjustDateTime");
        
        return group;
    }

    private static InjectionGroup create_photos_menu_externals_injectables() {
        InjectionGroup group = new InjectionGroup("/MediaMenuBar/PhotosMenu/PhotosExtrasExternalsPlaceholder");
        
        group.add_menu_item("ExternalEdit");
        group.add_menu_item("ExternalEditRAW");
        group.add_menu_item("PlayVideo");
        
        return group;
    }
    
    protected override void init_collect_ui_filenames(Gee.List<string> ui_filenames) {
        base.init_collect_ui_filenames(ui_filenames);
        
        ui_filenames.add("collection.ui");
    }
    
    protected override Gtk.ActionEntry[] init_collect_action_entries() {
        Gtk.ActionEntry[] actions = base.init_collect_action_entries();

        Gtk.ActionEntry print = { "Print", Gtk.STOCK_PRINT, TRANSLATABLE, "<Ctrl>P",
            TRANSLATABLE, on_print };
        print.label = Resources.PRINT_MENU;
        print.tooltip = Resources.PRINT_TOOLTIP;
        actions += print;
        
        Gtk.ActionEntry publish = { "Publish", Resources.PUBLISH, TRANSLATABLE, "<Ctrl><Shift>P",
            TRANSLATABLE, on_publish };
        publish.label = Resources.PUBLISH_MENU;
        publish.tooltip = Resources.PUBLISH_TOOLTIP;
        actions += publish;
  
        Gtk.ActionEntry rotate_right = { "RotateClockwise", Resources.CLOCKWISE,
            TRANSLATABLE, "<Ctrl>R", TRANSLATABLE, on_rotate_clockwise };
        rotate_right.label = Resources.ROTATE_CW_MENU;
        rotate_right.tooltip = Resources.ROTATE_CW_TOOLTIP;
        actions += rotate_right;

        Gtk.ActionEntry rotate_left = { "RotateCounterclockwise", Resources.COUNTERCLOCKWISE,
            TRANSLATABLE, "<Ctrl><Shift>R", TRANSLATABLE, on_rotate_counterclockwise };
        rotate_left.label = Resources.ROTATE_CCW_MENU;
        rotate_left.tooltip = Resources.ROTATE_CCW_TOOLTIP;
        actions += rotate_left;

        Gtk.ActionEntry hflip = { "FlipHorizontally", Resources.HFLIP, TRANSLATABLE, null,
            TRANSLATABLE, on_flip_horizontally };
        hflip.label = Resources.HFLIP_MENU;
        hflip.tooltip = Resources.HFLIP_TOOLTIP;
        actions += hflip;
        
        Gtk.ActionEntry vflip = { "FlipVertically", Resources.VFLIP, TRANSLATABLE, null,
            TRANSLATABLE, on_flip_vertically };
        vflip.label = Resources.VFLIP_MENU;
        vflip.tooltip = Resources.VFLIP_TOOLTIP;
        actions += vflip;

        Gtk.ActionEntry enhance = { "Enhance", Resources.ENHANCE, TRANSLATABLE, "<Ctrl>E",
            TRANSLATABLE, on_enhance };
        enhance.label = Resources.ENHANCE_MENU;
        enhance.tooltip = Resources.ENHANCE_TOOLTIP;
        actions += enhance;

        Gtk.ActionEntry revert = { "Revert", Gtk.STOCK_REVERT_TO_SAVED, TRANSLATABLE, null,
            TRANSLATABLE, on_revert };
        revert.label = Resources.REVERT_MENU;
        revert.tooltip = Resources.REVERT_TOOLTIP;
        actions += revert;
        
        Gtk.ActionEntry set_background = { "SetBackground", null, TRANSLATABLE, "<Ctrl>B",
            TRANSLATABLE, on_set_background };
        set_background.label = Resources.SET_BACKGROUND_MENU;
        set_background.tooltip = Resources.SET_BACKGROUND_TOOLTIP;
        actions += set_background;

        Gtk.ActionEntry duplicate = { "Duplicate", null, TRANSLATABLE, "<Ctrl>D", TRANSLATABLE,
            on_duplicate_photo };
        duplicate.label = Resources.DUPLICATE_PHOTO_MENU;
        duplicate.tooltip = Resources.DUPLICATE_PHOTO_TOOLTIP;
        actions += duplicate;

        Gtk.ActionEntry adjust_date_time = { "AdjustDateTime", null, TRANSLATABLE, null,
            TRANSLATABLE, on_adjust_date_time };
        adjust_date_time.label = Resources.ADJUST_DATE_TIME_MENU;
        adjust_date_time.tooltip = Resources.ADJUST_DATE_TIME_TOOLTIP;
        actions += adjust_date_time;
        
        Gtk.ActionEntry external_edit = { "ExternalEdit", Gtk.STOCK_EDIT, TRANSLATABLE, "<Ctrl>Return",
            TRANSLATABLE, on_external_edit };
        external_edit.label = Resources.EXTERNAL_EDIT_MENU;
        external_edit.tooltip = Resources.EXTERNAL_EDIT_TOOLTIP;
        actions += external_edit;
        
        Gtk.ActionEntry edit_raw = { "ExternalEditRAW", null, TRANSLATABLE, "<Ctrl><Shift>Return", 
            TRANSLATABLE, on_external_edit_raw };
        edit_raw.label = Resources.EXTERNAL_EDIT_RAW_MENU;
        edit_raw.tooltip = Resources.EXTERNAL_EDIT_RAW_TOOLTIP;
        actions += edit_raw;
        
        Gtk.ActionEntry slideshow = { "Slideshow", null, TRANSLATABLE, "F5", TRANSLATABLE,
            on_slideshow };
        slideshow.label = _("_Slideshow");
        slideshow.tooltip = _("Play a slideshow");
        actions += slideshow;
        
        return actions;
    }
    
    protected override InjectionGroup[] init_collect_injection_groups() {
        InjectionGroup[] groups = base.init_collect_injection_groups();
        
        groups += create_file_menu_injectables();
        groups += create_edit_menu_injectables();
        groups += create_view_menu_fullscreen_injectables();
        groups += create_photos_menu_edits_injectables();
        groups += create_photos_menu_date_injectables();
        groups += create_photos_menu_externals_injectables();
        
        return groups;
    }
    
    private bool selection_has_video() {
        return MediaSourceCollection.has_video((Gee.Collection<MediaSource>) get_view().get_selected_sources());
    }
    
    private bool page_has_photo() {
        return MediaSourceCollection.has_photo((Gee.Collection<MediaSource>) get_view().get_sources());
    }
    
    private bool selection_has_photo() {
        return MediaSourceCollection.has_photo((Gee.Collection<MediaSource>) get_view().get_selected_sources());
    }

    protected override void update_actions(int selected_count, int count) {
        base.update_actions(selected_count, count);

        bool one_selected = selected_count == 1;
        bool has_selected = selected_count > 0;

        bool primary_is_video = false;
        if (has_selected)
            if (get_view().get_selected_at(0).get_source() is Video)
                primary_is_video = true;

        bool selection_has_videos = selection_has_video();
        bool page_has_photos = page_has_photo();
        
        // don't allow duplication of the selection if it contains a video -- videos are huge and
        // and they're not editable anyway, so there seems to be no use case for duplicating them
        set_action_sensitive("Duplicate", has_selected && (!selection_has_videos));
        set_action_visible("ExternalEdit", (!primary_is_video));
        set_action_sensitive("ExternalEdit", 
            one_selected && !is_string_empty(Config.get_instance().get_external_photo_app()));
        set_action_visible("ExternalEditRAW",
            one_selected && (!primary_is_video)
            && ((Photo) get_view().get_selected_at(0).get_source()).get_master_file_format() == 
                PhotoFileFormat.RAW
            && !is_string_empty(Config.get_instance().get_external_raw_app()));
        set_action_sensitive("Revert", (!selection_has_videos) && can_revert_selected());
        set_action_sensitive("Enhance", (!selection_has_videos) && has_selected);
        set_action_important("Enhance", true);
        set_action_sensitive("RotateClockwise", (!selection_has_videos) && has_selected);
        set_action_important("RotateClockwise", true);
        set_action_sensitive("RotateCounterclockwise", (!selection_has_videos) && has_selected);
        set_action_important("RotateCounterclockwise", true);
        set_action_sensitive("FlipHorizontally", (!selection_has_videos) && has_selected);
        set_action_sensitive("FlipVertically", (!selection_has_videos) && has_selected);
        set_action_sensitive("AdjustDateTime", (!selection_has_videos) && has_selected);
        set_action_sensitive("NewEvent", has_selected);
        set_action_sensitive("AddTags", has_selected);
        set_action_sensitive("ModifyTags", one_selected);
        set_action_sensitive("Slideshow", page_has_photos && (!primary_is_video));
        
        set_action_sensitive("SetBackground", (!selection_has_videos) && has_selected );
        if (has_selected) {
            Gtk.Action? set_background = get_action("SetBackground");
            if (set_background != null) {
                set_background.label = one_selected
                    ? Resources.SET_BACKGROUND_MENU
                    : Resources.SET_BACKGROUND_SLIDESHOW_MENU;
            }
        }
        
        set_action_sensitive("Print", (!selection_has_videos) && one_selected);
        
        set_action_sensitive("Publish", has_selected);
        set_action_important("Publish", true);
    }

    private void on_photos_altered() {
        // since the photo can be altered externally to Shotwell now, need to make the revert
        // command available appropriately, even if the selection doesn't change
        set_action_sensitive("Revert", can_revert_selected());
    }
    
    private void on_print() {
        if (get_view().get_selected_count() == 1)
            PrintManager.get_instance().spool_photo((Photo) get_view().get_selected_at(0).get_source());
    }
    
    private void on_external_app_changed() {
        int selected_count = get_view().get_selected_count();
        
        set_action_sensitive("ExternalEdit", selected_count == 1 && Config.get_instance().get_external_photo_app() != "");
    }
    
    // see #2020
    // double clcik = switch to photo page
    // Super + double click = open in external editor
    // Enter = switch to PhotoPage
    // Ctrl + Enter = open in external editor (handled with accelerators)
    // Shift + Ctrl + Enter = open in external RAW editor (handled with accelerators)
    protected override void on_item_activated(CheckerboardItem item, CheckerboardPage.Activator 
        activator, CheckerboardPage.KeyboardModifiers modifiers) {
        Thumbnail thumbnail = (Thumbnail) item;

        // none of the fancy Super, Ctrl, Shift, etc., keyboard accelerators apply to videos,
        // since they can't be RAW files or be opened in an external editor, etc., so if this is
        // a video, just play it and do a short-circuit return
        if (thumbnail.get_media_source() is Video) {
            on_play_video();
            return;
        }
        
        LibraryPhoto? photo = thumbnail.get_media_source() as LibraryPhoto;
        if (photo == null)
            return;
        
        // switch to full-page view or open in external editor
        debug("activating %s", photo.to_string());

        if (activator == CheckerboardPage.Activator.MOUSE) {
            if (modifiers.super_pressed)
                on_external_edit();
            else
                LibraryWindow.get_app().switch_to_photo_page(this, photo);
        } else if (activator == CheckerboardPage.Activator.KEYBOARD) {
            if (!modifiers.shift_pressed && !modifiers.ctrl_pressed)
                LibraryWindow.get_app().switch_to_photo_page(this, photo);
        }
    }

    public override GLib.Icon? get_icon() {
        return new GLib.ThemedIcon(Resources.ICON_PHOTOS);
    }

    public override CheckerboardItem? get_fullscreen_photo() {
        // if a selection, use first selected photo, otherwise, no go
        if (get_view().get_selected_count() > 0) {
            foreach (DataView view in get_view().get_selected()) {
                Thumbnail thumbnail = (Thumbnail) view;
                if (thumbnail.get_media_source() is Photo)
                    return thumbnail;
            }
            
            return null;
        }
        
        // no selection, so use first photo
        foreach (DataObject object in get_view().get_all()) {
            Thumbnail thumbnail = (Thumbnail) object;
            if (thumbnail.get_media_source() is Photo)
                return thumbnail;
        }
        
        return null;
    }
    
    protected override bool on_app_key_pressed(Gdk.EventKey event) {
        bool handled = true;
        
        switch (Gdk.keyval_name(event.keyval)) {
            case "Page_Up":
            case "KP_Page_Up":
            case "Page_Down":
            case "KP_Page_Down":
            case "Home":
            case "KP_Home":
            case "End":
            case "KP_End":
                key_press_event(event);
            break;
            case "bracketright":
                on_rotate_clockwise();
            break;
            case "bracketleft":
                on_rotate_counterclockwise();
            break;

            default:
                handled = false;
            break;
        }
        
        return handled ? true : base.on_app_key_pressed(event);
    }

    protected override void on_export() {
        if (exporter != null)
            return;
        
        Gee.Collection<MediaSource> export_list =
            (Gee.Collection<MediaSource>) get_view().get_selected_sources();
        if (export_list.size == 0)
            return;

        bool has_some_photos = selection_has_photo();
        bool has_some_videos = selection_has_video();
        assert(has_some_photos || has_some_videos);
               
        // if we don't have any photos, then everything is a video, so skip displaying the Export
        // dialog and go right to the video export operation
        if (!has_some_photos) {
            exporter = Video.export_many((Gee.Collection<Video>) export_list, on_export_completed);
            return;
        }

        string title =  (has_some_videos) ? 
            ngettext("Export Photo/Video", "Export Photos/Videos", export_list.size) :
            ngettext("Export Photo", "Export Photos", export_list.size);
        ExportDialog export_dialog = new ExportDialog(title);

        // Setting up the parameters object requires a bit of thinking about what the user wants.
        // If the selection contains only photos, then we do what we've done in previous versions
        // of Shotwell -- we use whatever settings the user selected on his last export operation
        // (the thinking here being that if you've been exporting small PNGs for your blog
        // for the last n export operations, then it's likely that for your (n + 1)-th export
        // operation you'll also be exporting a small PNG for your blog). However, if the selection
        // contains any videos, then we set the parameters to the "Current" operating mode, since
        // videos can't be saved as PNGs (or any other specific photo format).
        ExportFormatParameters export_params = (has_some_videos) ? ExportFormatParameters.current() :
            ExportFormatParameters.last();

        int scale;
        ScaleConstraint constraint;
        if (!export_dialog.execute(out scale, out constraint, ref export_params))
            return;
        
        Scaling scaling = Scaling.for_constraint(constraint, scale, false);
        
        // handle the single-photo case, which is treated like a Save As file operation
        if (export_list.size == 1) {
            LibraryPhoto photo = null;
            foreach (LibraryPhoto p in (Gee.Collection<LibraryPhoto>) export_list) {
                photo = p;
                break;
            }
            
            File save_as =
                ExportUI.choose_file(photo.get_export_basename_for_parameters(export_params));
            if (save_as == null)
                return;
            
            try {
                AppWindow.get_instance().set_busy_cursor();
                photo.export(save_as, scaling, export_params.quality,
                    photo.get_export_format_for_parameters(export_params), export_params.mode ==
                    ExportFormatMode.UNMODIFIED);
                AppWindow.get_instance().set_normal_cursor();
            } catch (Error err) {
                AppWindow.get_instance().set_normal_cursor();
                export_error_dialog(save_as, false);
            }
            
            return;
        }

        // multiple photos or videos
        File export_dir = ExportUI.choose_dir(title);
        if (export_dir == null)
            return;
        
        exporter = new ExporterUI(new Exporter(export_list, export_dir, scaling, export_params,
            false));
        exporter.export(on_export_completed);
    }
    
    private void on_export_completed() {
        exporter = null;
    }
    
    private bool can_revert_selected() {
        foreach (DataSource source in get_view().get_selected_sources()) {
            LibraryPhoto? photo = source as LibraryPhoto;
            if (photo != null && (photo.has_transformations() || photo.has_editable()))
                return true;
        }
        
        return false;
    }
    
    private bool can_revert_editable_selected() {
        foreach (DataSource source in get_view().get_selected_sources()) {
            LibraryPhoto? photo = source as LibraryPhoto;
            if (photo != null && photo.has_editable())
                return true;
        }
        
        return false;
    }
   
    private void on_rotate_clockwise() {
        if (get_view().get_selected_count() == 0)
            return;
        
        RotateMultipleCommand command = new RotateMultipleCommand(get_view().get_selected(), 
            Rotation.CLOCKWISE, Resources.ROTATE_CW_FULL_LABEL, Resources.ROTATE_CW_TOOLTIP,
            _("Rotating"), _("Undoing Rotate"));
        get_command_manager().execute(command);
    }

    private void on_publish() {
        if (get_view().get_selected_count() > 0)
            PublishingDialog.go((Gee.Collection<MediaSource>) get_view().get_selected_sources());
    }

    private void on_rotate_counterclockwise() {
        if (get_view().get_selected_count() == 0)
            return;
        
        RotateMultipleCommand command = new RotateMultipleCommand(get_view().get_selected(), 
            Rotation.COUNTERCLOCKWISE, Resources.ROTATE_CCW_FULL_LABEL, Resources.ROTATE_CCW_TOOLTIP,
            _("Rotating"), _("Undoing Rotate"));
        get_command_manager().execute(command);
    }
    
    private void on_flip_horizontally() {
        if (get_view().get_selected_count() == 0)
            return;
        
        RotateMultipleCommand command = new RotateMultipleCommand(get_view().get_selected(),
            Rotation.MIRROR, Resources.HFLIP_LABEL, Resources.HFLIP_TOOLTIP, _("Flipping Horizontally"),
            _("Undoing Flip Horizontally"));
        get_command_manager().execute(command);
    }
    
    private void on_flip_vertically() {
        if (get_view().get_selected_count() == 0)
            return;
        
        RotateMultipleCommand command = new RotateMultipleCommand(get_view().get_selected(),
            Rotation.UPSIDE_DOWN, Resources.VFLIP_LABEL, Resources.VFLIP_TOOLTIP, _("Flipping Vertically"),
            _("Undoing Flip Vertically"));
        get_command_manager().execute(command);
    }
    
    private void on_revert() {
        if (get_view().get_selected_count() == 0)
            return;
        
        if (can_revert_editable_selected()) {
            if (!revert_editable_dialog(AppWindow.get_instance(),
                (Gee.Collection<Photo>) get_view().get_selected_sources())) {
                return;
            }
            
            foreach (DataObject object in get_view().get_selected_sources())
                ((Photo) object).revert_to_master();
        }
        
        RevertMultipleCommand command = new RevertMultipleCommand(get_view().get_selected());
        get_command_manager().execute(command);
    }
    
    private void on_enhance() {
        if (get_view().get_selected_count() == 0)
            return;
        
        EnhanceMultipleCommand command = new EnhanceMultipleCommand(get_view().get_selected());
        get_command_manager().execute(command);
    }
    
    private void on_duplicate_photo() {
        if (get_view().get_selected_count() == 0)
            return;
        
        DuplicateMultiplePhotosCommand command = new DuplicateMultiplePhotosCommand(
            get_view().get_selected());
        get_command_manager().execute(command);
    }

    private void on_adjust_date_time() {
        if (get_view().get_selected_count() == 0)
            return;

        PhotoSource photo_source = (PhotoSource) get_view().get_selected_at(0).get_source();

        AdjustDateTimeDialog dialog = new AdjustDateTimeDialog(photo_source,
            get_view().get_selected_count());

        int64 time_shift;
        bool keep_relativity, modify_originals;
        if (dialog.execute(out time_shift, out keep_relativity, out modify_originals)) {
            AdjustDateTimePhotosCommand command = new AdjustDateTimePhotosCommand(
                get_view().get_selected(), time_shift, keep_relativity, modify_originals);
            get_command_manager().execute(command);
        }
    }
    
    private void on_external_edit() {
        if (get_view().get_selected_count() != 1)
            return;
        
        Photo photo = (Photo) get_view().get_selected_at(0).get_source();
        try {
            AppWindow.get_instance().set_busy_cursor();
            photo.open_with_external_editor();
            AppWindow.get_instance().set_normal_cursor();
        } catch (Error err) {
            AppWindow.get_instance().set_normal_cursor();
            AppWindow.error_message(Resources.launch_editor_failed(err));
        }
    }
    
    private void on_external_edit_raw() {
        if (get_view().get_selected_count() != 1)
            return;
        
        Photo photo = (Photo) get_view().get_selected_at(0).get_source();
        if (photo.get_master_file_format() != PhotoFileFormat.RAW)
            return;

        try {
            AppWindow.get_instance().set_busy_cursor();
            photo.open_master_with_external_editor();
            AppWindow.get_instance().set_normal_cursor();
        } catch (Error err) {
            AppWindow.get_instance().set_normal_cursor();
            AppWindow.error_message(Resources.launch_editor_failed(err));
        }
    }
    
    public void on_set_background() {
        Gee.ArrayList<LibraryPhoto> photos = new Gee.ArrayList<LibraryPhoto>();
        MediaSourceCollection.filter_media((Gee.Collection<MediaSource>) get_view().get_selected_sources(),
            photos, null);
        
        if (photos.size == 1) {
            AppWindow.get_instance().set_busy_cursor();
            DesktopIntegration.set_background(photos[0]);
            AppWindow.get_instance().set_normal_cursor();
        } else if (photos.size > 1) {
            SetBackgroundSlideshowDialog dialog = new SetBackgroundSlideshowDialog();
            int delay;
            if (dialog.execute(out delay)) {
                AppWindow.get_instance().set_busy_cursor();
                DesktopIntegration.set_background_slideshow(photos, delay,
                    DESKTOP_SLIDESHOW_TRANSITION_SEC);
                AppWindow.get_instance().set_normal_cursor();
            }
        }
    }
    
    private void on_slideshow() {
        if (get_view().get_count() == 0)
            return;
        
        Thumbnail thumbnail = (Thumbnail) get_fullscreen_photo();
        if (thumbnail == null)
            return;
        
        LibraryPhoto? photo = thumbnail.get_media_source() as LibraryPhoto;
        if (photo == null)
            return;
        
        AppWindow.get_instance().go_fullscreen(new SlideshowPage(LibraryPhoto.global, get_view(),
            photo));
    }
           
    protected override bool on_ctrl_pressed(Gdk.EventKey? event) {
        rotate_button.set_related_action(get_action("RotateCounterclockwise"));
        rotate_button.set_label(Resources.ROTATE_CCW_LABEL);
        
        return base.on_ctrl_pressed(event);
    }
    
    protected override bool on_ctrl_released(Gdk.EventKey? event) {
        rotate_button.set_related_action(get_action("RotateClockwise"));
        rotate_button.set_label(Resources.ROTATE_CW_LABEL);
        
        return base.on_ctrl_released(event);
    }
}

public class LibraryPage : CollectionPage {
    public LibraryPage(ProgressMonitor? monitor = null) {
        base(_("Photos"));
        
        get_view().freeze_notifications();
        get_view().monitor_source_collection(LibraryPhoto.global, new CollectionViewManager(this),
            null, (Gee.Collection<DataSource>) LibraryPhoto.global.get_all(), monitor);
        get_view().thaw_notifications();
    }
    
    protected override void get_config_photos_sort(out bool sort_order, out int sort_by) {
        Config.get_instance().get_library_photos_sort(out sort_order, out sort_by);
    }

    protected override void set_config_photos_sort(bool sort_order, int sort_by) {
        Config.get_instance().set_library_photos_sort(sort_order, sort_by);
    }
}

