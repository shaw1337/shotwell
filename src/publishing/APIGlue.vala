/* Copyright 2011 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */
namespace Publishing.Glue {

public class PublisherWrapperInteractor : ServiceInteractor, Spit.Publishing.Publisher {
    private Spit.Publishing.Publisher wrapped;
    private Spit.Publishing.PluginHost new_api_host;
    private weak PublishingDialog old_api_dialog;
    
    public PublisherWrapperInteractor(Spit.Publishing.PluginHost new_api_host,
        PublishingDialog old_api_dialog) {
        
        base(old_api_dialog);
        this.wrapped = new_api_host.get_publisher();
        this.new_api_host = new_api_host;
        this.old_api_dialog = old_api_dialog;
    }
    
    public Spit.Publishing.Service get_service() {
        return wrapped.get_service();
    }
    
    public void start() {
        wrapped.start();
    }
    
    public void stop() {
        debug("PublisherWrapperInteractor: stop( ) invoked.");

        old_api_dialog = null;
        new_api_host.stop_publishing();

        wrapped = null;
        new_api_host = null;
    }
    
    public bool is_running() {
        if (wrapped == null)
            return false;
        else
            return wrapped.is_running();
    }
    
    public override string get_name() {
        return wrapped.get_service().get_pluggable_name();
    }
    
    public override void start_interaction() {
        debug("PublisherWrapperInteractor: start_interaction( ): invoked.");
        start();
    }
    
    public override void cancel_interaction() {
        debug("PublisherWrapperInteractor: cancel_interaction( ): invoked.");
        stop();
    }
}

public class DialogInteractorWrapper : PublishingDialog, Spit.HostInterface,
    Spit.Publishing.PluginHost {
    Spit.Publishing.PluginHost plugin_host;
    Spit.Publishing.Publishable[] publishables;
    
    public DialogInteractorWrapper(Gee.Collection<MediaSource> to_publish) {
        base(to_publish);
        
        publishables = new Spit.Publishing.Publishable[0];
        
        foreach (MediaSource current_media_item in to_publish)
            publishables += new MediaSourcePublishableWrapper(current_media_item);
    }
    
    public void set_plugin_host(Spit.Publishing.PluginHost plugin_host) {
        this.plugin_host = plugin_host;
    }

    public void install_dialog_pane(Spit.Publishing.DialogPane pane,
        Spit.Publishing.PluginHost.ButtonMode button_mode) {
        debug("DialogInteractorWrapper: install_pane( ): invoked.");

        plugin_host.install_dialog_pane(pane, button_mode);
    }
    
    public void post_error(Error err) {
        debug("DialogInteractorWrapper.post_error( ): err = '%s'.", err.message);

        plugin_host.post_error(err);
    }

    public void stop_publishing() {
        debug("DialogInteractorWrapper.stop_publishing( ): invoked.");
        
        plugin_host.stop_publishing();
    }

    public Spit.Publishing.Publisher get_publisher() {
        return plugin_host.get_publisher();
    }

    public void install_static_message_pane(string message,
        Spit.Publishing.PluginHost.ButtonMode button_mode) {
        plugin_host.install_static_message_pane(message, button_mode);
    }
    
    public void install_pango_message_pane(string markup,
        Spit.Publishing.PluginHost.ButtonMode button_mode) {
        plugin_host.install_pango_message_pane(markup, button_mode);
    }
    
    public void install_success_pane() {
        plugin_host.install_success_pane();
    }
    
    public void install_account_fetch_wait_pane() {
        plugin_host.install_account_fetch_wait_pane();
    }
    
    public void install_login_wait_pane() {
        plugin_host.install_login_wait_pane();
    }
    
    public void install_welcome_pane(string welcome_message,
        Spit.Publishing.LoginCallback on_login_clicked) {
        plugin_host.install_welcome_pane(welcome_message, on_login_clicked);
    }
    
    public void set_service_locked(bool locked) {
        plugin_host.set_service_locked(locked);
    }

    public void set_dialog_default_widget(Gtk.Widget widget) {
        plugin_host.set_dialog_default_widget(widget);
    }
    
    public Spit.Publishing.Publisher.MediaType get_publishable_media_type() {
        return plugin_host.get_publishable_media_type();
    }
    
    public GLib.File get_module_file() {
        return plugin_host.get_module_file();
    }
    
    public int get_config_int(string key, int default_value) {
        return plugin_host.get_config_int(key, default_value);
    }
    
    public string? get_config_string(string key, string? default_value) {
        return plugin_host.get_config_string(key, default_value);
    }
    
    public bool get_config_bool(string key, bool default_value) {
        return plugin_host.get_config_bool(key, default_value);
    }
    
    public double get_config_double(string key, double default_value) {
        return plugin_host.get_config_double(key, default_value);
    }
    
    public void set_config_int(string key, int value) {
        plugin_host.set_config_int(key, value);
    }
    
    public void set_config_string(string key, string? value) {
        plugin_host.set_config_string(key, value);
    }
    
    public void set_config_bool(string key, bool value) {
        plugin_host.set_config_bool(key, value);
    }
    
    public void set_config_double(string key, double value) {
        plugin_host.set_config_double(key, value);
    }

    public void unset_config_key(string key) {
        plugin_host.unset_config_key(key);
    }

    public Spit.Publishing.Publishable[] get_publishables() {
        return publishables;
    }
    
    public Spit.Publishing.ProgressCallback? serialize_publishables(int content_major_axis,
        bool strip_metadata = false) {
        return plugin_host.serialize_publishables(content_major_axis, strip_metadata);
    }
}

public class MediaSourcePublishableWrapper : Spit.Publishing.Publishable, GLib.Object {
    private static int name_ticker = 0;

    private MediaSource wrapped;
    private GLib.File? serialized_file = null;
    
    public MediaSourcePublishableWrapper(MediaSource to_wrap) {
        wrapped = to_wrap;
    }
    
    public void clean_up() {
        if (serialized_file == null)
            return;

        debug("cleaning up temporary publishing file '%s'.", serialized_file.get_path());

        try {
            serialized_file.delete(null);
        } catch (Error err) {
            warning("couldn't delete temporary publishing file '%s'.", serialized_file.get_path());
        }

        serialized_file = null;
    }

    public GLib.File serialize_for_publishing(int content_major_axis,
        bool strip_metadata = false) throws Spit.Publishing.PublishingError {

        if (wrapped is LibraryPhoto) {
            LibraryPhoto photo = (LibraryPhoto) wrapped;

            GLib.File to_file =
                AppDirs.get_temp_dir().get_child("publishing-%d.jpg".printf(name_ticker++));

            debug("writing photo '%s' to temporary file '%s' for publishing.",
                photo.get_source_id(), to_file.get_path());
            try {
                Scaling scaling = (content_major_axis > 0) ?
                    Scaling.for_best_fit(content_major_axis, false) : Scaling.for_original();
                photo.export(to_file, scaling, Jpeg.Quality.HIGH, PhotoFileFormat.JFIF);
            } catch (Error err) {
                throw new Spit.Publishing.PublishingError.LOCAL_FILE_ERROR(
                    "unable to serialize photo '%s' for publishing.", photo.get_name());
            }

            serialized_file = to_file;
        } else if (wrapped is Video) {
            Video video = (Video) wrapped;

            string basename;
            string extension;
            disassemble_filename(video.get_file().get_basename(), out basename, out extension);

            GLib.File to_file =
                GLib.File.new_for_path("publishing-%d.%s".printf(name_ticker++, extension));

            debug("writing video '%s' to temporary file '%s' for publishing.",
                video.get_source_id(), to_file.get_path());
            try {
                video.export(to_file);
            } catch (Error err) {
                throw new Spit.Publishing.PublishingError.LOCAL_FILE_ERROR(
                    "unable to serialize video '%s' for publishing.", video.get_name());
            }

            serialized_file = to_file;
        } else {
            error("MediaSourcePublishableWrapper.serialize_for_publishing( ): unknown media type.");
        }

        return serialized_file;
    }

    public string get_publishing_name() {
        return wrapped.get_name();
    }

    public string? get_publishing_description() {
        return null;
    }

    public string[] get_publishing_keywords() {
        string[] result = new string[0];
        
        Gee.Collection<Tag>? tagset = Tag.global.fetch_sorted_for_source(wrapped);
        if (tagset != null) {
            foreach (Tag tag in tagset) {
                result += tag.get_name();
            }
        }
        
        return (result.length > 0) ? result : null;
    }

    public Spit.Publishing.Publisher.MediaType get_media_type() {
        if (wrapped is LibraryPhoto)
            return Spit.Publishing.Publisher.MediaType.PHOTO;
        else if (wrapped is Video)
            return Spit.Publishing.Publisher.MediaType.VIDEO;
        else
            return Spit.Publishing.Publisher.MediaType.NONE;
    }
    
    public GLib.File? get_serialized_file() {
        return serialized_file;
    }
    
    public GLib.DateTime get_exposure_date_time() {
        return new GLib.DateTime.from_unix_local(wrapped.get_exposure_time());
    }
}

public class GlueFactory {
    private class LegacyServiceCapabilitiesWrapper : ServiceCapabilities {
        public Spit.Publishing.Publisher.MediaType supported_media;
        public Spit.Publishing.Service new_api_service;
        public GlueFactory creator;

        public LegacyServiceCapabilitiesWrapper(GlueFactory creator,
            Spit.Publishing.Service new_api_service) {
            this.new_api_service = new_api_service;
            this.creator = creator;
            this.supported_media = new_api_service.get_supported_media();
        }

        public override string get_name() {
            return new_api_service.get_pluggable_name();
        }
        
        public override Spit.Publishing.Publisher.MediaType get_supported_media() {
            return supported_media;
        }
        
        public override ServiceInteractor factory(PublishingDialog host) {
            // verify that the host PublishingDialog instance is not just a vanilla
            // PublishingDialog but an instance of a specialized glue subclass
            if (!(host is DialogInteractorWrapper))
                error("GlueFactory: active publishing dialog isn't a DialogInteractorWrapper; " +
                    "glue can't work.");

            Spit.Publishing.Publishable[] publishables =
                ((DialogInteractorWrapper) host).get_publishables();

            debug("GlueFactory: setting up adapters to publish %d items.", publishables.length);

            creator.publishing_host = new Spit.Publishing.ConcretePublishingHost(new_api_service,
                host, publishables);

            ((DialogInteractorWrapper) host).set_plugin_host(creator.publishing_host);
            
            ServiceInteractor publisher_wrapper = new PublisherWrapperInteractor(
                creator.publishing_host, host);

            return publisher_wrapper;
        }
    }

    private static GlueFactory instance = null;

    private Spit.Publishing.ConcretePublishingHost publishing_host = null;
    private ServiceCapabilities[] legacy_capabilities_list;
    
    public signal void wrapped_services_changed();
    
    private GlueFactory() {
        load_pluggables();
        Plugins.Notifier.get_instance().pluggable_activation.connect(load_pluggables);
    }
    
    ~GlueFactory() {
        Plugins.Notifier.get_instance().pluggable_activation.disconnect(load_pluggables);
    }
    
    private void load_pluggables() {
        // ServiceCapabilities objects are used in the legacy publishing API to describe supported
        // web services. Every service has a ServiceCapabilities object that contains information
        // about things like the name of the service and the kinds of media that it supports
        // (e.g., photos, videos, etc.). ServiceCapabilities concern us here because they're
        // used to populate the list of available services that appears in the upper-right-hand
        // corner of the publishing dialog. So for every dynamically-loaded service, we need
        // to provide a ServiceCapabilities for interoperability with the old API.
        legacy_capabilities_list = new ServiceCapabilities[0];
        
        // load publishing services from plug-ins
        Gee.Collection<Spit.Pluggable> pluggables = Plugins.get_pluggables_for_type(
            typeof(Spit.Publishing.Service));
            
        debug("Publising API Glue: discovered %d pluggable publishing services.", pluggables.size);

        foreach (Spit.Pluggable pluggable in pluggables) {
            int pluggable_interface = pluggable.get_pluggable_interface(
                Spit.Publishing.CURRENT_INTERFACE, Spit.Publishing.CURRENT_INTERFACE);
            if (pluggable_interface != Spit.Publishing.CURRENT_INTERFACE) {
                warning("Unable to load publisher %s: reported interface %d.",
                    Plugins.get_pluggable_module_id(pluggable), pluggable_interface);
                
                continue;
            }
            
            Spit.Publishing.Service service =
                (Spit.Publishing.Service) pluggable;

            debug("Publishing API Glue: discovered pluggable publishing service '%s'.",
                service.get_pluggable_name());
            
            legacy_capabilities_list += new LegacyServiceCapabilitiesWrapper(this, service);
        }
        
        wrapped_services_changed();
    }
    
    public static GlueFactory get_instance() {
        if (instance == null)
            instance = new GlueFactory();

        return instance;
    }
    
    public ServiceCapabilities[] get_wrapped_services() {
        return legacy_capabilities_list;
    }
    
    public ServiceInteractor create_publisher(string service_name) {
        PublishingDialog active_dialog = PublishingDialog.get_active_instance();

        foreach (ServiceCapabilities caps in legacy_capabilities_list) {
            LegacyServiceCapabilitiesWrapper wrapper = (LegacyServiceCapabilitiesWrapper) caps;
            if (wrapper.get_name() == service_name)
                return wrapper.factory(active_dialog);
        }
        
        error("GlueFactory: unsupported service name '%s'.", service_name);
    }
}

}

