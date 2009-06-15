
public abstract class BatchImportJob {
    public abstract string get_identifier();
    
    public abstract bool prepare(out File file_to_import);
}

// BatchImport performs the work of taking a file (supplied by BatchImportJob's) and properly importing
// it into the system, including database additions, thumbnail creation, and reporting it to AppWindow
// so it's properly added to various views and events.
public class BatchImport {
    private class DateComparator : Comparator<Photo> {
        public override int64 compare(Photo photo_a, Photo photo_b) {
            return photo_a.get_exposure_time() - photo_b.get_exposure_time();
        }
    }
    
    public static File? create_library_path(string filename, Exif.Data? exif, time_t ts, out bool collision) {
        File dir = AppWindow.get_photos_dir();
        time_t timestamp = ts;
        
        // use EXIF exposure timestamp over the supplied one (which probably comes from the file's
        // modified time, or is simply now())
        if (exif != null) {
            Exif.Entry entry = Exif.find_first_entry(exif, Exif.Tag.DATE_TIME_ORIGINAL, Exif.Format.ASCII);
            if (entry != null) {
                string datetime = entry.get_value();
                if (datetime != null) {
                    time_t stamp;
                    if (Exif.convert_datetime(datetime, out stamp)) {
                        timestamp = stamp;
                    }
                }
            }
        }
        
        // if no timestamp, use now()
        if (timestamp == 0)
            timestamp = time_t();
        
        Time tm = Time.local(timestamp);
        
        // build a directory tree inside the library:
        // yyyy/mm/dd
        dir = dir.get_child("%04u".printf(tm.year + 1900));
        dir = dir.get_child("%02u".printf(tm.month + 1));
        dir = dir.get_child("%02u".printf(tm.day));
        
        try {
            if (!dir.query_exists(null))
                dir.make_directory_with_parents(null);
        } catch (Error err) {
            error("Unable to create photo library directory %s", dir.get_path());
        }
        
        // if file doesn't exist, use that and done
        File file = dir.get_child(filename);
        if (!file.query_exists(null)) {
            collision = false;

            return file;
        }

        collision = true;

        string name, ext;
        disassemble_filename(file.get_basename(), out name, out ext);

        // generate a unique filename
        for (int ctr = 1; ctr < int.MAX; ctr++) {
            string new_name = (ext != null) ? "%s_%d.%s".printf(name, ctr, ext) : "%s_%d".printf(name, ctr);

            file = dir.get_child(new_name);
            
            if (!file.query_exists(null))
                return file;
        }
        
        return null;
    }

    private static int get_test_variable(string name) {
        string value = Environment.get_variable(name);
        if (value == null || value.length == 0)
            return 0;
        
        return value.to_int();
    }
    
    private Gee.Iterable<BatchImportJob> jobs;
    private BatchImport ref_holder = null;
    private SortedList<Photo> success = null;
    private Gee.ArrayList<string> failed = null;
    private Gee.ArrayList<string> skipped = null;
    private ImportID import_id = ImportID();
    private bool scheduled = false;
    private bool user_aborted = false;
    private int import_file_count = 0;
    
    // these are for debugging and testing only
    private int fail_every = 0;
    private int skip_every = 0;
    
    public BatchImport(Gee.Iterable<BatchImportJob> jobs) {
        this.jobs = jobs;
        this.fail_every = get_test_variable("SHOTWELL_FAIL_EVERY");
        this.skip_every = get_test_variable("SHOTWELL_SKIP_EVERY");
    }
    
    // Called for each Photo imported to the system
    public signal void imported(Photo photo);
    
    // Called when a job fails.  import_complete will also be called at the end of the batch
    public signal void import_job_failed(ImportResult result, BatchImportJob job, File? file);
    
    // Called at the end of the batched jobs; this will be signalled exactly once for the batch
    public signal void import_complete(ImportID import_id, SortedList<Photo> photos_by_date, 
        Gee.ArrayList<string> failed, Gee.ArrayList<string> skipped);

    public void schedule() {
        assert(!scheduled);
        
        // XXX: This is necessary because Idle.add doesn't ref SourceFunc:
        // http://bugzilla.gnome.org/show_bug.cgi?id=548427
        this.ref_holder = this;

        Idle.add(perform_import);
        scheduled = true;
    }

    private bool perform_import() {
        success = new SortedList<Photo>(new Gee.ArrayList<Photo>(), new DateComparator());
        failed = new Gee.ArrayList<string>();
        skipped = new Gee.ArrayList<string>();
        import_id = (new PhotoTable()).generate_import_id();

        foreach (BatchImportJob job in jobs) {
            if (AppWindow.has_user_quit())
                user_aborted = true;
                
            if (user_aborted) {
                import_job_failed(ImportResult.USER_ABORT, job, null);
                skipped.add(job.get_identifier());
                
                continue;
            }
            
            File file;
            if (job.prepare(out file)) {
                import(job, file, job.get_identifier());
            } else {
                import_job_failed(ImportResult.FILE_ERROR, job, null);
                failed.add(job.get_identifier());
            }
        }
        
        // report to AppWindow to organize into events
        if (success.size > 0)
            AppWindow.get_instance().batch_import_complete(success);
        
        // report completed
        import_complete(import_id, success, failed, skipped);

        // XXX: unref "this" ... vital that the self pointer is not touched from here on out
        ref_holder = null;
        
        return false;
    }

    private void import(BatchImportJob job, File file, string id) {
        if (user_aborted) {
            skipped.add(id);
            
            return;
        }
        
        FileType type = file.query_file_type(FileQueryInfoFlags.NOFOLLOW_SYMLINKS, null);
        
        ImportResult result;
        switch (type) {
            case FileType.DIRECTORY:
                result = import_dir(job, file);
            break;
            
            case FileType.REGULAR:
                result = import_file(file);
            break;
            
            default:
                debug("Skipping file %s (neither a directory nor a file)", file.get_path());
                result = ImportResult.NOT_A_FILE;
            break;
        }
        
        switch (result) {
            case ImportResult.SUCCESS:
                // all is well, photo(s) added to success list
            break;
            
            case ImportResult.USER_ABORT:
                // no fall-through in Vala
                user_aborted = true;
                skipped.add(id);
                import_job_failed(result, job, file);
            break;

            case ImportResult.NOT_A_FILE:
            case ImportResult.PHOTO_EXISTS:
                skipped.add(id);
                import_job_failed(result, job, file);
            break;
            
            default:
                failed.add(id);
                import_job_failed(result, job, file);
            break;
        }
    }
    
    private ImportResult import_dir(BatchImportJob job, File dir) {
        try {
            FileEnumerator enumerator = dir.enumerate_children("*",
                FileQueryInfoFlags.NOFOLLOW_SYMLINKS, null);
            if (enumerator == null)
                return ImportResult.FILE_ERROR;
            
            if (!spin_event_loop())
                return ImportResult.USER_ABORT;

            FileInfo info = null;
            while ((info = enumerator.next_file(null)) != null) {
                File subdir = dir.get_child(info.get_name());
                import(job, subdir, subdir.get_uri());
            }
        } catch (Error err) {
            debug("Unable to import from %s: %s", dir.get_path(), err.message);
            
            return ImportResult.FILE_ERROR;
        }
        
        return ImportResult.SUCCESS;
    }
    
    private ImportResult import_file(File file) {
        if (!spin_event_loop())
            return ImportResult.USER_ABORT;

        import_file_count++;
        if (fail_every > 0) {
            if (import_file_count % fail_every == 0)
                return ImportResult.FILE_ERROR;
        }
        
        if (skip_every > 0) {
            if (import_file_count % skip_every == 0)
                return ImportResult.NOT_A_FILE;
        }
        
        Photo photo;
        ImportResult result = Photo.import(file, import_id, out photo);
        if (result != ImportResult.SUCCESS)
            return result;
        
        success.add(photo);
        
        // report to AppWindow for system-wide inclusion
        AppWindow.get_instance().photo_imported(photo);

        // report to observers
        imported(photo);

        return ImportResult.SUCCESS;
    }
}
