/* Copyright 2011 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public class MediaViewTracker : Core.ViewTracker {
    public MediaAccumulator all = new MediaAccumulator();
    public MediaAccumulator visible = new MediaAccumulator();
    public MediaAccumulator selected = new MediaAccumulator();
    
    public MediaViewTracker(ViewCollection collection) {
        base (collection);
        
        start(all, visible, selected);
    }
}

public class MediaAccumulator : Object, Core.TrackerAccumulator {
    public int total = 0;
    public int photos = 0;
    public int videos = 0;
    public int raw = 0;
    public int flagged = 0;
    
    public bool include(DataObject object) {
        DataSource source = ((DataView) object).get_source();
        
        total++;
        
        Photo? photo = source as Photo;
        if (photo != null) {
            photos++;
            
            if (photo.get_master_file_format() == PhotoFileFormat.RAW)
                raw++;
        } else if (source is VideoSource) {
            videos++;
        }
        
        Flaggable? flaggable = source as Flaggable;
        if (flaggable != null && flaggable.is_flagged())
            flagged++;
        
        // because of total, always fire "updated"
        return true;
    }
    
    public bool uninclude(DataObject object) {
        DataSource source = ((DataView) object).get_source();
        
        assert(total > 0);
        total--;
        
        Photo? photo = source as Photo;
        if (photo != null) {
            assert(photos > 0);
            photos--;
            if (photo.get_master_file_format() == PhotoFileFormat.RAW) {
                assert(raw > 0);
                raw--;
            }
        } else if (source is Video) {
            assert(videos > 0);
            videos--;
        }
        
        Flaggable? flaggable = source as Flaggable;
        if (flaggable != null && flaggable.is_flagged()) {
            assert(flagged > 0);
            flagged--;
        }
        
        // because of total, always fire "updated"
        return true;
    }
    
    public bool altered(DataObject object, Alteration alteration) {
        // the only alteration that can happen to MediaSources this accumulator is concerned with is
        // flagging; typeness and raw-ness don't change at runtime
        if (!alteration.has_detail("metadata", "flagged"))
            return false;
        
        Flaggable? flaggable = ((DataView) object).get_source() as Flaggable;
        if (flaggable == null)
            return false;
        
        if (flaggable.is_flagged()) {
            flagged++;
        } else {
            assert(flagged > 0);
            flagged--;
        }
        
        return true;
    }
    
    public string to_string() {
        return "%d photos/%d videos/%d raw/%d flagged".printf(photos, videos, raw, flagged);
    }
}

