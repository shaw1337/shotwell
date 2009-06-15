
public class ThumbnailCache : Object {
    public static const Gdk.InterpType DEFAULT_INTERP = Gdk.InterpType.HYPER;
    public static const int DEFAULT_JPEG_QUALITY = 90;
    public static const int MAX_INMEMORY_DATA_SIZE = 256 * 1024;
    
    public static const int BIG_SCALE = 360;
    public static const int MEDIUM_SCALE = 128;
    public static const int SMALL_SCALE = 64;
    
    public static const int[] SCALES = { BIG_SCALE, MEDIUM_SCALE, SMALL_SCALE };
    
    public static const ulong KBYTE = 1024;
    public static const ulong MBYTE = 1024 * KBYTE;
    
    public static const ulong MAX_BIG_CACHED_BYTES = 25 * MBYTE;
    public static const ulong MAX_MEDIUM_CACHED_BYTES = 15 * MBYTE;
    public static const ulong MAX_SMALL_CACHED_BYTES = 10 * MBYTE;

    private static ThumbnailCache big = null;
    private static ThumbnailCache medium = null;
    private static ThumbnailCache small = null;
    
    // Doing this because static construct {} not working nor new'ing in the above statement
    public static void init() {
        big = new ThumbnailCache(BIG_SCALE, MAX_BIG_CACHED_BYTES);
        medium = new ThumbnailCache(MEDIUM_SCALE, MAX_MEDIUM_CACHED_BYTES);
        small = new ThumbnailCache(SMALL_SCALE, MAX_SMALL_CACHED_BYTES);
    }
    
    public static void terminate() {
    }
    
    public static void import(PhotoID photo_id, Gdk.Pixbuf original, bool force = false) {
        big._import(photo_id, original, force);
        spin_event_loop();

        medium._import(photo_id, original, force);
        spin_event_loop();

        small._import(photo_id, original, force);
        spin_event_loop();
    }
    
    public static void remove(PhotoID photo_id) {
        big._remove(photo_id);
        spin_event_loop();
        
        medium._remove(photo_id);
        spin_event_loop();
        
        small._remove(photo_id);
        spin_event_loop();
    }

    public static Gdk.Pixbuf? fetch(PhotoID photo_id, int scale) {
        if (scale > MEDIUM_SCALE) {
            return big._fetch(photo_id);
        } else if(scale > SMALL_SCALE) {
            return medium._fetch(photo_id);
        } else {
            return small._fetch(photo_id);
        }
    }
    
    public static void replace(PhotoID photo_id, int scale, Gdk.Pixbuf replacement) {
        ThumbnailCache cache = null;
        switch (scale) {
            case SMALL_SCALE:
                cache = small;
            break;
            
            case MEDIUM_SCALE:
                cache = medium;
            break;
            
            case BIG_SCALE:
                cache = big;
            break;
            
            default:
                error("Unknown scale %d", scale);
            break;
        }
        
        cache._replace(photo_id, replacement);
    }
    
    public static bool exists(PhotoID photo_id) {
        return big._exists(photo_id) && medium._exists(photo_id) && small._exists(photo_id);
    }
    
    private class ImageData {
        public Gdk.Pixbuf pixbuf;
        public ulong bytes;
        
        public ImageData(Gdk.Pixbuf pixbuf) {
            this.pixbuf = pixbuf;

            // This is not entirely accurate (see Gtk doc note on pixbuf Image Data), but close enough
            // for government work
            bytes = pixbuf.get_rowstride() * pixbuf.get_height();
        }
    }

    private File cache_dir;
    private int scale;
    private ulong max_cached_bytes;
    private Gdk.InterpType interp;
    private string jpeg_quality;
    private Gee.HashMap<int64?, ImageData> cache_map = new Gee.HashMap<int64?, ImageData>(
        int64_hash, int64_equal, direct_equal);
    private Gee.ArrayList<int64?> cache_lru = new Gee.ArrayList<int64?>(int64_equal);
    private ulong cached_bytes = 0;
    private ThumbnailCacheTable cache_table;
    
    private ThumbnailCache(int scale, ulong max_cached_bytes, Gdk.InterpType interp = DEFAULT_INTERP,
        int jpeg_quality = DEFAULT_JPEG_QUALITY) {
        assert(scale != 0);
        assert((jpeg_quality >= 0) && (jpeg_quality <= 100));

        this.cache_dir = AppWindow.get_data_subdir("thumbs", "thumbs%d".printf(scale));
        this.scale = scale;
        this.max_cached_bytes = max_cached_bytes;
        this.interp = interp;
        this.jpeg_quality = "%d".printf(jpeg_quality);
        this.cache_table = new ThumbnailCacheTable(scale);
    }
    
    private Gdk.Pixbuf? _fetch(PhotoID photo_id) {
        // use JPEG in memory cache if available
        ImageData data = cache_map.get(photo_id.id);
        if (data != null)
            return data.pixbuf;

        File file = get_cached_file(photo_id);

        debug("Fetching persistent thumbnail from disk [%lld] %s", photo_id.id, file.get_path());

        Gdk.Pixbuf pixbuf = null;
        try {
            pixbuf = new Gdk.Pixbuf.from_file(file.get_path());
        } catch (Error err) {
            error("%s", err.message);
        }
        
        int filesize = cache_table.get_filesize(photo_id);
        if(filesize > MAX_INMEMORY_DATA_SIZE) {
            // too big to store in memory, so return the pixbuf straight from disk
            debug("Persistant thumbnail [%lld] %s too large to cache in memory, loading straight from disk", 
                photo_id.id, file.get_path());

            return pixbuf;
        }
        
        // stash in memory for next time
        store_in_memory(photo_id, pixbuf);

        return pixbuf;
    }
    
    private void _import(PhotoID photo_id, Gdk.Pixbuf original, bool force = false) {
        File file = get_cached_file(photo_id);
        
        // if not forcing the cache operation, check if file exists and is represented in the
        // database before continuing
        if (!force) {
            if (_exists(photo_id))
                return;
        } else {
            // wipe previous from system and continue
            _remove(photo_id);
        }

        debug("Importing persistent thumbnail for [%lld] %s", photo_id.id, file.get_path());
        
        // scale according to cache's parameters
        Gdk.Pixbuf scaled = scale_pixbuf(original, scale, interp);
        
        // save scaled image as JPEG
        int filesize = -1;
        try {
            save_thumbnail(file, scaled);
        } catch (Error err) {
            error("%s", err.message);
        }
        
        // do NOT store in the in-memory cache ... if a lot of photos are being imported at
        // once, this will blow cache locality, especially when the user is viewing one portion
        // of the collection while new photos are added far off the viewport

        // store in database
        cache_table.add(photo_id, filesize, Dimensions.for_pixbuf(scaled));
    }
    
    private void _replace(PhotoID photo_id, Gdk.Pixbuf original) {
        File file = get_cached_file(photo_id);
        
        debug ("Replacing persistent thumbnail for [%lld] %s", photo_id.id, file.get_path());
        
        // Remove from in-memory cache, if present
        remove_from_memory(photo_id);
        
        // scale to cache's parameters
        Gdk.Pixbuf scaled = scale_pixbuf(original, scale, interp);
        
        // save scaled image as JPEG
        int filesize = -1;
        try {
            filesize = save_thumbnail(file, scaled);
        } catch (Error err) {
            error("%s", err.message);
        }
        
        // Store in in-memory cache; a _replace() probably represents a user-initiated
        // action (<cough>rotate</cough>) and the thumbnail will probably be fetched immediately.
        // This means the thumbnail will be cached in scales that aren't immediately needed, but the
        // benefit seems to outweigh the side-effects
        store_in_memory(photo_id, scaled);
        
        // store changes in database
        cache_table.replace(photo_id, filesize, Dimensions.for_pixbuf(scaled));
    }
    
    private void _remove(PhotoID photo_id) {
        File file = get_cached_file(photo_id);
        
        debug("Removing persistent thumbnail [%lld] %s", photo_id.id, file.get_path());

        // remove from in-memory cache
        remove_from_memory(photo_id);
        
        // remove from db table
        cache_table.remove(photo_id);
 
        // remove from disk
        if (file.query_exists(null)) {
            try {
                file.delete(null);
            } catch (Error err) {
                warning("%s", err.message);
            }
        }
    }
    
    private bool _exists(PhotoID photo_id) {
        File file = get_cached_file(photo_id);

        return file.query_exists(null) && cache_table.exists(photo_id);
    }
    
    private File get_cached_file(PhotoID photo_id) {
        return cache_dir.get_child("thumb%016llx.jpg".printf(photo_id.id));
    }
    
    private void store_in_memory(PhotoID photo_id, Gdk.Pixbuf thumbnail) {
        remove_from_memory(photo_id);
        
        ImageData data = new ImageData(thumbnail);
        cache_map.set(photo_id.id, data);
        cache_lru.insert(0, photo_id.id);
        
        cached_bytes += data.bytes;
        
        // trim cache
        while (cached_bytes > max_cached_bytes) {
            assert(cache_lru.size > 0);
            int index = cache_lru.size - 1;
            
            int64 id = cache_lru.get(index);
            cache_lru.remove_at(index);
            
            data = cache_map.get(id);
            assert(data.bytes <= cached_bytes);
            cached_bytes -= data.bytes;
            
            debug("Thumbnail cache %d overflow: removed %lu bytes, now %lu", scale, data.bytes, 
                cached_bytes);
            
            bool removed = cache_map.remove(id);
            assert(removed);
        }
    }
    
    private bool remove_from_memory(PhotoID photo_id) {
        ImageData data = cache_map.get(photo_id.id);
        if (data == null)
            return false;
        
        assert(cached_bytes >= data.bytes);
        cached_bytes -= data.bytes;

        // remove data from in-memory cache
        bool removed = cache_map.remove(photo_id.id);
        assert(removed);
        
        // remove from LRU
        removed = cache_lru.remove(photo_id.id);
        assert(removed);
        
        return true;
    }
    
    private int save_thumbnail(File file, Gdk.Pixbuf pixbuf) throws Error {
        if (!pixbuf.save(file.get_path(), "jpeg", "quality", jpeg_quality))
            error("Unable to save thumbnail %s", file.get_path());

        FileInfo info = file.query_info(FILE_ATTRIBUTE_STANDARD_SIZE, FileQueryInfoFlags.NOFOLLOW_SYMLINKS, 
            null);
        
        // this should never be huge
        assert(info.get_size() <= int.MAX);
        int filesize = (int) info.get_size();
        
        return filesize;
    }
}