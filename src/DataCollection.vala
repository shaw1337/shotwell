/* Copyright 2009 Yorba Foundation
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution. 
 */

//
// DataCollection
//

// A Marker is an object for marking (selecting) DataObjects in a DataCollection to then perform
// an action on all of them.  This mechanism allows for performing mass operations in a generic
// way, as well as dealing with the (perpetual) issue of removing items from a Collection within
// an iterator.
public interface Marker : Object {
    public abstract void mark(DataObject object);
    
    public abstract void mark_many(Gee.Iterable<DataObject> list);
    
    public abstract void mark_all();
    
    public abstract int count();
}

// MarkedAction is a callback to perform an action on the marked DataObject.  Return false to
// end iterating.
public delegate bool MarkedAction(DataObject object, Object user);

public class DataCollection {
    private class MarkerImpl : Object, Marker {
        public DataCollection owner;
        public Gee.HashSet<DataObject> marked = new Gee.HashSet<DataObject>();
        
        public MarkerImpl(DataCollection owner) {
            this.owner = owner;
            
            // if items are removed from main collection, they're removed from the marked list
            // as well
            owner.items_removed += on_items_removed;
        }
        
        public void mark(DataObject object) {
            assert(owner.contains(object));
            
            marked.add(object);
        }
        
        public void mark_many(Gee.Iterable<DataObject> list) {
            foreach (DataObject object in list) {
                assert(owner.contains(object));
                
                marked.add(object);
            }
        }
        
        public void mark_all() {
            foreach (DataObject object in owner.get_all())
                marked.add(object);
        }
        
        public int count() {
            return marked.size;
        }
        
        private void on_items_removed(Gee.Iterable<DataObject> removed) {
            foreach (DataObject object in removed)
                marked.remove(object);
        }
        
        // This method is called by DataCollection when it starts iterating over the marked list ...
        // the marker at this point stops monitoring the collection, preventing a possible
        // removal during an iteration, which is bad.
        public void freeze() {
            owner.items_removed -= on_items_removed;
        }
        
        public void finished() {
            marked = null;
        }
        
        public bool is_valid(DataCollection collection) {
            return (collection == owner) && (marked != null);
        }
    }
    
    public class OrderAddedComparator : Comparator<DataObject> {
        public override int64 compare(DataObject a, DataObject b) {
            return a.internal_get_ordinal() - b.internal_get_ordinal();
        }
    }
    
    private static OrderAddedComparator order_added_comparator = null;
    
    private SortedList<DataObject> list = new SortedList<DataObject>();
    private Gee.HashSet<DataObject> hash_set = new Gee.HashSet<DataObject>();
    private int added_counter = 0;

    // When this signal has been fired, the added items are part of the collection
    public virtual signal void items_added(Gee.Iterable<DataObject> added) {
    }
    
    // When this signal is fired, the removed items are no longer part of the collection
    public virtual signal void items_removed(Gee.Iterable<DataObject> removed) {
    }
    
    // When this signal is fired, the removed items are no longer part of the collection
    public virtual signal void contents_altered(Gee.Iterable<DataObject>? added,
        Gee.Iterable<DataObject>? removed) {
    }
    
    // This signal fires whenever any item in the collection signals it has been altered ...
    // this allows monitoring of all objects in the collection without having to register a
    // signal handler for each one
    public virtual signal void item_altered(DataObject item) {
    }

    // This signal fires whenever any item in the collection signals its metadata has been altered ...
    // this allows monitoring of all objects in the collection without having to register a
    // signal handler for each one
    public virtual signal void item_metadata_altered(DataObject object) {
    }
    
    // Fired when a new sort comparator is registered.
    public virtual signal void ordering_changed() {
    }
    
    public DataCollection() {
        list.resort(get_order_added_comparator());
    }
    
    // A singleton list is used when a single item has been added/remove/selected/unselected
    // and needs to be reported via a signal, which uses a list as a parameter ... although this
    // seems wasteful, can't reuse a single singleton list because it's possible for a method
    // that needs it to be called from within a signal handler for another method, corrupting the
    // shared list's contents mid-signal
    protected static Gee.ArrayList<DataObject> get_singleton(DataObject object) {
        Gee.ArrayList<DataObject> singleton = new Gee.ArrayList<DataObject>();
        singleton.add(object);
        
        return singleton;
    }
    
    public virtual bool valid_type(DataObject object) {
        return true;
    }
    
    public static OrderAddedComparator get_order_added_comparator() {
        if (order_added_comparator == null)
            order_added_comparator = new OrderAddedComparator();
        
        return order_added_comparator;
    }
    
    public virtual void set_comparator(Comparator<DataObject> comparator) {
        list.resort(comparator);
        ordering_changed();
    }
    
    // Return to natural ordering of DataObjects, which is order-added
    public virtual void reset_comparator() {
        list.resort(get_order_added_comparator());
        ordering_changed();
    }
    
    public virtual Gee.Iterable<DataObject> get_all() {
        return list;
    }
    
    public virtual int get_count() {
        return list.size;
    }
    
    public virtual DataObject get_at(int index) {
        return list.get(index);
    }
    
    public virtual int index_of(DataObject object) {
        return list.locate(object);
    }
    
    public virtual bool contains(DataObject object) {
        if (!hash_set.contains(object))
            return false;
        
        assert(object.get_membership() == this);
        
        return true;
    }
    
    private void internal_add(DataObject object) {
        assert(valid_type(object));
        
        object.internal_set_membership(this, added_counter++);
        
        bool added = list.add(object);
        assert(added);
        added = hash_set.add(object);
        assert(added);
    }
    
    private void internal_remove(DataObject object) {
        object.internal_clear_membership();
        
        bool removed = list.remove(object);
        assert(removed);
        removed = hash_set.remove(object);
        assert(removed);
    }
    
    // Returns false if item is already part of the collection.
    public bool add(DataObject object) {
        if (contains(object)) {
            debug("Cannot add %s: already present", object.to_string());
            
            return false;
        }
        
        internal_add(object);
        
        // fire signal after added using singleton list
        Gee.List<DataObject> added = get_singleton(object);
        items_added(added);
        contents_altered(added, null);
        
        return true;
    }
    
    // Returns number of items added to collection.
    public int add_many(Gee.Iterable<DataObject> objects) {
        Gee.ArrayList<DataObject> added = new Gee.ArrayList<DataObject>();
        foreach (DataObject object in objects) {
            if (contains(object)) {
                debug("Cannot add %s: already present", object.to_string());
                
                continue;
            }
            
            internal_add(object);
            added.add(object);
        }
        
        // signal once all have been added
        if (added.size > 0) {
            items_added(added);
            contents_altered(added, null);
        }
        
        return added.size;
    }
    
    // Obtain a marker to build a list of objects to perform an action upon.
    public Marker start_marking() {
        return new MarkerImpl(this);
    }
    
    // Obtain a marker with a single item marked.  More can be added.
    public Marker mark(DataObject object) {
        Marker marker = new MarkerImpl(this);
        marker.mark(object);
        
        return marker;
    }
    
    // Iterate over all the marked objects performing a user-supplied action on each one.  The
    // marker is invalid after calling this method.
    public void act_on_marked(Marker m, MarkedAction action, Object? user = null) {
        MarkerImpl marker = (MarkerImpl) m;
        
        assert(marker.is_valid(this));
        
        // freeze the marker to prepare it for iteration
        marker.freeze();
        
        // iterate, breaking if the callback asks to stop
        foreach (DataObject object in marker.marked) {
            // although marker tracks when items are removed, catch it here as well
            if (!contains(object)) {
                warning("act_on_marked: marker holding ref to unknown %s", object.to_string());
                
                continue;
            }
            
            if (!action(object, user))
                break;
        }
        
        // invalidate the marker
        marker.finished();
    }

    // Remove marked items from collection.  This two-step process allows for iterating in a foreach
    // loop and removing without creating a separate list.  The marker is invalid after this call.
    public void remove_marked(Marker m) {
        MarkerImpl marker = (MarkerImpl) m;
        
        assert(marker.is_valid(this));
        
        // freeze the marker before signalling, so it doesn't remove all its items
        marker.freeze();
        
        // remove everything in the marked list
        foreach (DataObject object in marker.marked) {
            // although marker should track items already removed, catch it here as well
            if (!contains(object)) {
                warning("remove_marked: marker holding ref to unknown %s", object.to_string());
                
                continue;
            }
            
            internal_remove(object);
        }
        
        // signal after removing
        if (marker.marked.size > 0) {
            items_removed(marker.marked);
            contents_altered(null, marker.marked);
        }
        
        // invalidate the marker
        marker.finished();
    }
    
    public void clear() {
        if (list.size == 0) {
            assert(hash_set.size == 0);
            
            return;
        }
        
        // remove everything in the list, but have to maintain a new list for reporting the signal.
        // Don't use an iterator, as list is modified in internal_remove().
        Gee.ArrayList<DataObject> removed = new Gee.ArrayList<DataObject>();
        while (list.size > 0) {
            DataObject object = list.get(0);
            removed.add(object);
            internal_remove(object);
        }
        
        // report after removal
        items_removed(removed);
        contents_altered(null, removed);
        
        // the hash set should be cleared as well when finished
        assert(hash_set.size == 0);
    }
    
    // This method is only called by DataObject to report when it has been altered, so observers of
    // this collection may be notified as well.
    public void internal_notify_altered(DataObject object) {
        assert(contains(object));
        
        item_altered(object);
    }
    
    // This method is only called by DataObject to report when its metadata has been altered, so
    // observers of this collection may be notified as well.
    public void internal_notify_metadata_altered(DataObject object) {
        assert(contains(object));
        
        item_metadata_altered(object);
    }
}

//
// SourceCollection
//

public class SourceCollection : DataCollection {
    // When this signal is fired, the item is still part of the collection
    public virtual signal void item_destroyed(DataSource source) {
    }
    
    public override bool valid_type(DataObject object) {
        return object is DataSource;
    }
    
    // Destroy all marked items.
    public void destroy_marked(Marker marker) {
        Marker remove_marker = start_marking();
        act_on_marked(marker, destroy_source, remove_marker);
        
        // remove once all destroyed
        remove_marked(remove_marker);
    }
    
    private bool destroy_source(DataObject object, Object user) {
        DataSource source = (DataSource) object;
        
        source.internal_mark_for_destroy();
        source.destroy();
        item_destroyed(source);
        
        ((Marker) user).mark(source);
        
        return true;
    }
}

public delegate int64 GetSourceDatabaseKey(DataSource source);

// A DatabaseSourceCollection is a SourceCollection that understands database keys (IDs) and the
// nature that a row in a database can only be instantiated once in the system, and so it tracks
// their existance in a map so they can be fetched by their key.
public class DatabaseSourceCollection : SourceCollection {
    private GetSourceDatabaseKey source_key_func;
    private Gee.HashMap<int64?, DataSource> map = new Gee.HashMap<int64?, DataSource>(int64_hash, 
        int64_equal, direct_equal);
        
    public DatabaseSourceCollection(GetSourceDatabaseKey source_key_func) {
        this.source_key_func = source_key_func;
    }

    public override void items_added(Gee.Iterable<DataObject> added) {
        foreach (DataObject object in added) {
            DataSource source = (DataSource) object;
            int64 key = source_key_func(source);
            
            assert(!map.has_key(key));
            
            map.set(key, source);
        }
        
        base.items_added(added);
    }
    
    public override void items_removed(Gee.Iterable<DataObject> removed) {
        foreach (DataObject object in removed) {
            int64 key = source_key_func((DataSource) object);

            bool is_removed = map.unset(key);
            assert(is_removed);
        }
        
        base.items_removed(removed);
    }
    
    protected DataSource fetch_by_key(int64 key) {
        return map.get(key);
    }
}

//
// ViewCollection
//

// A ViewManager allows an interface for ViewCollection to monitor a SourceCollection and
// (selectively) add DataViews automatically.
public abstract class ViewManager {
    // This predicate function can be used to filter which DataView objects should be included
    // in the collection as new source objects appear in the SourceCollection.  May be called more
    // than once for any DataSource object.
    public virtual bool include_in_view(DataSource source) {
        return true;
    }
    
    // If include_in_view returns true, this method will be called to instantiate a DataView object
    // for the ViewCollection.
    public abstract DataView create_view(DataSource source);
}

// A ViewFilter allows for items in a ViewCollection to be shown or hidden depending on the
// supplied predicate method.  For now, only one ViewFilter may be installed, although this may
// change in the future.
//
// Return true if view should be visible, false if it should be hidden.
public delegate bool ViewFilter(DataView view);

// A ViewCollection holds DataView objects, which are view instances wrapping DataSource objects.
// Thus, multiple views can exist of a single SourceCollection, each view displaying all or some
// of that SourceCollection.  A view collection also has a notion of order
// (first/last/next/previous) that can be overridden by child classes.  It also understands hidden
// objects, which are withheld entirely from the collection until they're made visible.
//
// The default implementation provides a browser which orders the view in the order they're
// stored in DataCollection, which is not specified.
public class ViewCollection : DataCollection {
    private class ToggleLists : Object {
        public Gee.ArrayList<DataView> selected = new Gee.ArrayList<DataView>();
        public Gee.ArrayList<DataView> unselected = new Gee.ArrayList<DataView>();
    }
    
    private ViewManager manager = null;
    private ViewFilter filter = null;
    private SortedList<DataView> selected = new SortedList<DataView>();
    private SortedList<DataView> visible = new SortedList<DataView>();
    private int geometry_freeze = 0;
    private int view_freeze = 0;
    
    // TODO: source-to-view mapping ... for now, only one view is allowed for each source.
    // This may need to change in the future.
    private Gee.HashMap<DataSource, DataView> source_map = new Gee.HashMap<DataSource, DataView>(
        direct_hash, direct_equal, direct_equal);
    
    // Signal aggregator.
    public virtual signal void items_selected(Gee.Iterable<DataView> selected) {
    }
    
    // Signal aggregator.
    public virtual signal void items_unselected(Gee.Iterable<DataView> unselected) {
    }
    
    // Signal aggregator.
    public virtual signal void items_state_changed(Gee.Iterable<DataView> changed) {
    }
    
    // Signal aggregator.
    public virtual signal void items_shown(Gee.Iterable<DataView> visible) {
    }
    
    // Signal aggregator.
    public virtual signal void items_hidden(Gee.Iterable<DataView> hidden) {
    }
    
    // Signal aggregator.
    public virtual signal void items_visibility_changed(Gee.Iterable<DataView> changed) {
    }
    
    // Signal aggregator.
    public virtual signal void item_view_altered(DataView view) {
    }
    
    // Signal aggregator.
    public virtual signal void item_geometry_altered(DataView view) {
    }
    
    public virtual signal void views_altered() {
    }
    
    public virtual signal void geometries_altered() {
    }
    
    public ViewCollection() {
        selected.resort(get_order_added_comparator());
        visible.resort(get_order_added_comparator());
    }
    
    public void monitor_source_collection(SourceCollection sources, ViewManager manager) {
        this.manager = manager;
        
        // load in all items from the SourceCollection, filtering with the manager
        on_sources_added((Gee.Iterable<DataSource>) sources.get_all());
        
        // subscribe to the SourceCollection to monitor it for additions and removals, reflecting
        // those changes in this collection
        sources.items_added += on_sources_added;
        sources.items_removed += on_sources_removed;
        sources.item_altered += on_source_altered;
        sources.item_metadata_altered += on_source_altered;
    }
    
    public void install_view_filter(ViewFilter filter) {
        // this currently replaces any existing ViewFilter
        this.filter = filter;
        
        // filter existing items
        reapply_view_filter();
    }
    
    // This is used when conditions outside of the collection have changed and the entire collection
    // should be re-filtered.
    public void reapply_view_filter() {
        if (filter == null)
            return;
        
        Marker visible_marker = start_marking();
        Marker hidden_marker = start_marking();
        
        // iterate through base.all(), otherwise merely iterating the visible items
        foreach (DataObject object in base.get_all()) {
            DataView view = (DataView) object;
            
            if (filter(view)) {
                if (!view.is_visible())
                    visible_marker.mark(object);
            } else {
                if (view.is_visible())
                    hidden_marker.mark(object);
            }
        }
        
        show_marked(visible_marker);
        hide_marked(hidden_marker);
    }
    
    public void reset_view_filter() {
        this.filter = null;
        
        // reset visibility of all items
        show_all();
    }
    
    public override bool valid_type(DataObject object) {
        return object is DataView;
    }
    
    private void on_sources_added(Gee.Iterable<DataSource> added) {
        // add only source items which are to be included by the manager ... do this in batches
        // to take advantage of add_many()
        Gee.ArrayList<DataView> created_views = new Gee.ArrayList<DataView>();
        foreach (DataSource source in added) {
            if (manager.include_in_view(source))
                created_views.add(manager.create_view(source));
        }
        
        if (created_views.size > 0)
            add_many(created_views);
    }
    
    private void on_sources_removed(Gee.Iterable<DataSource> removed) {
        // mark all view items associated with the source to be removed
        Marker marker = start_marking();
        foreach (DataSource source in removed) {
            DataView view = source_map.get(source);
            
            // ignore if not represented in this view
            if (view != null)
                marker.mark(view);
        }
        
        remove_marked(marker);
    }
    
    private void on_source_altered(DataObject object) {
        DataSource source = (DataSource) object;
        
        // let ViewManager decide whether or not to keep, but only add if not already present
        // and only remove if already present
        bool include = manager.include_in_view(source);
        if (include && !has_view_for_source(source)) {
            add(manager.create_view(source));
        } else if (!include && has_view_for_source(source)) {
            Marker marker = mark(get_view_for_source(source));
            remove_marked(marker);
        }
    }
    
    // Keep the source map and state tables synchronized
    public override void items_added(Gee.Iterable<DataObject> added) {
        foreach (DataObject object in added) {
            DataView view = (DataView) object;
            source_map.set(view.get_source(), view);
            
            if (view.is_selected())
                selected.add(view);
            
            if (filter != null)
                view.internal_set_visible(filter(view));
            
            if (view.is_visible())
                visible.add(view);
        }
        
        base.items_added(added);
    }
    
    // Keep the source map and state tables synchronized
    public override void items_removed(Gee.Iterable<DataObject> removed) {
        foreach (DataObject object in removed) {
            DataView view = (DataView) object;

            bool is_removed = source_map.unset(view.get_source());
            assert(is_removed);
            
            if (view.is_selected()) {
                is_removed = selected.remove(view);
                assert(is_removed);
            }
            
            if (view.is_visible()) {
                is_removed = visible.remove(view);
                assert(is_removed);
            }
        }
        
        base.items_removed(removed);
    }
    
    private void filter_altered_item(DataObject object) {
        if (filter == null)
            return;
        
        Marker marker = mark(object);
        if (filter((DataView) object))
            show_marked(marker);
        else
            hide_marked(marker);
    }
    
    public override void item_altered(DataObject object) {
        filter_altered_item(object);
        
        base.item_altered(object);
    }
    
    public override void item_metadata_altered(DataObject object) {
        filter_altered_item(object);
        
        base.item_metadata_altered(object);
    }
    
    public override void set_comparator(Comparator<DataView> comparator) {
        selected.resort(comparator);
        visible.resort(comparator);
        
        base.set_comparator(comparator);
    }
    
    public override void reset_comparator() {
        selected.resort(get_order_added_comparator());
        visible.resort(get_order_added_comparator());
        
        base.reset_comparator();
    }
    
    public override Gee.Iterable<DataObject> get_all() {
        return visible;
    }
    
    public override int get_count() {
        return visible.size;
    }
    
    public override DataObject get_at(int index) {
        return visible.get(index);
    }
    
    public virtual DataView? get_first() {
        return (get_count() > 0) ? (DataView?) get_at(0) : null;
    }
    
    public virtual DataView? get_last() {
        return (get_count() > 0) ? (DataView?) get_at(get_count() - 1) : null;
    }
    
    public virtual DataView? get_next(DataView view) {
        if (get_count() == 0)
            return null;
        
        int index = index_of(view);
        if (index < 0)
            return null;
        
        index++;
        if (index >= get_count())
            index = 0;
        
        return (DataView?) get_at(index);
    }
    
    public virtual DataView? get_previous(DataView view) {
        if (get_count() == 0)
            return null;
        
        int index = index_of(view);
        if (index < 0)
            return null;
        
        index--;
        if (index < 0)
            index = get_count() - 1;
        
        return (DataView?) get_at(index);
    }

    // Selects all the marked items.  The marker will be invalid after this call.
    public void select_marked(Marker marker) {
        Gee.ArrayList<DataView> selected = new Gee.ArrayList<DataView>();
        act_on_marked(marker, select_item, selected);
        
        if (selected.size > 0) {
            items_selected(selected);
            items_state_changed(selected);
        }
    }
    
    // Selects all items.
    public void select_all() {
        Marker marker = start_marking();
        marker.mark_all();
        select_marked(marker);
    }
    
    private bool select_item(DataObject object, Object user) {
        DataView view = (DataView) object;
        if (view.is_selected()) {
            assert(selected.contains(view));
            
            return true;
        }
            
        view.internal_set_selected(true);
        bool added = selected.add(view);
        assert(added);

        ((Gee.ArrayList<DataView>) user).add(view);
        
        return true;
    }
    
    // Unselects all the marked items.  The marker will be invalid after this call.
    public void unselect_marked(Marker marker) {
        Gee.ArrayList<DataView> unselected = new Gee.ArrayList<DataView>();
        act_on_marked(marker, unselect_item, unselected);
        
        if (unselected.size > 0) {
            items_unselected(unselected);
            items_state_changed(unselected);
        }
    }
    
    // Unselects all items.
    public void unselect_all() {
        Marker marker = start_marking();
        marker.mark_all();
        unselect_marked(marker);
    }
    
    // Unselects all items but the one specified.
    public void unselect_all_but(DataView exception) {
        Marker marker = start_marking();
        foreach (DataObject object in get_all()) {
            DataView view = (DataView) object;
            if (view != exception)
                marker.mark(view);
        }
        
        unselect_marked(marker);
    }
    
    private bool unselect_item(DataObject object, Object user) {
        DataView view = (DataView) object;
        if (!view.is_selected()) {
            assert(!selected.contains(view));
            
            return true;
        }
        
        view.internal_set_selected(false);
        bool removed = selected.remove(view);
        assert(removed);
        
        ((Gee.ArrayList<DataView>) user).add(view);
        
        return true;
    }
    
    // Toggle the selection state of all marked items.  The marker will be invalid after this
    // call.
    public void toggle_marked(Marker marker) {
        ToggleLists lists = new ToggleLists();
        act_on_marked(marker, toggle_item, lists);
        
        if (lists.selected.size > 0) {
            items_selected(lists.selected);
            items_state_changed(lists.selected);
        }
        
        if (lists.unselected.size > 0) {
            items_unselected(lists.unselected);
            items_state_changed(lists.unselected);
        }
    }
    
    private bool toggle_item(DataObject object, Object user) {
        DataView view = (DataView) object;
        ToggleLists lists = (ToggleLists) user;
        
        // toggle the selection state of the view, adding or removing it from the selected list
        // to maintain state and adding it to the ToggleLists for the caller to signal with
        if (view.internal_toggle()) {
            bool added = selected.add(view);
            assert(added);
            
            lists.selected.add(view);
        } else {
            bool removed = selected.remove(view);
            assert(removed);
            
            lists.unselected.add(view);
        }
        
        return true;
    }
    
    public int get_selected_count() {
        return selected.size;
    }
    
    public Gee.Iterable<DataView> get_selected() {
        return selected;
    }
    
    public DataView? get_selected_at(int index) {
        return selected.get(index);
    }
    
    public void hide_marked(Marker marker) {
        Gee.ArrayList<DataView> hidden = new Gee.ArrayList<DataView>();
        act_on_marked(marker, hide_item, hidden);
        
        if (hidden.size > 0) {
            items_hidden(hidden);
            items_visibility_changed(hidden);
        }
    }
    
    private bool hide_item(DataObject object, Object user) {
        DataView view = (DataView) object;
        if (!view.is_visible()) {
            assert(!visible.contains(view));
            
            return true;
        }
        
        view.internal_set_visible(false);
        bool removed = visible.remove(view);
        assert(removed);
        
        // hidden items must be removed from the selected list as well ... however, don't need
        // to actually deselect them, merely remove from the list while hidden and add back
        // when shown, hence no need to fire selection_changed signals
        if (view.is_selected()) {
            removed = selected.remove(view);
            assert(removed);
        }
        
        ((Gee.ArrayList<DataView>) user).add(view);
        
        return true;
    }
    
    public void show_marked(Marker marker) {
        Gee.ArrayList<DataView> shown = new Gee.ArrayList<DataView>();
        act_on_marked(marker, show_item, shown);
        
        if (shown.size > 0) {
            items_shown(shown);
            items_visibility_changed(shown);
        }
    }
    
    private bool show_item(DataObject object, Object user) {
        DataView view = (DataView) object;
        if (view.is_visible()) {
            assert(visible.contains(view));
            
            return true;
        }
        
        view.internal_set_visible(true);
        bool added = visible.add(view);
        assert(added);
        
        // see note in hide_item for selection handling with hidden/visible items
        if (view.is_selected()) {
            assert(!selected.contains(view));
            selected.add(view);
        }
        
        ((Gee.ArrayList<DataView>) user).add(view);
        
        return true;
    }
    
    public void show_all() {
        Marker marker = start_marking();
        
        // can't use mark_all() because that will only mark the visible items
        foreach (DataObject object in base.get_all())
            marker.mark(object);
        
        show_marked(marker);
    }
    
    public void hide_all() {
        Marker marker = start_marking();
        
        // *can* use mark_all() because it only marks the visible items, which is perfect
        marker.mark_all();
        
        hide_marked(marker);
    }
    
    public bool has_view_for_source(DataSource source) {
        return source_map.has_key(source);
    }
    
    public DataView? get_view_for_source(DataSource source) {
        return source_map.get(source);
    }
    
    // This is only used by DataView.
    public void internal_notify_view_altered(DataView view) {
        if (view_freeze == 0)
            item_view_altered(view);
    }
    
    // This is available to all users, for use when all items views change.
    public void notify_views_altered() {
        views_altered();
    }
    
    public void freeze_view_notifications() {
        view_freeze++;
    }
    
    public void thaw_view_notifications(bool autonotify) {
        assert(view_freeze > 0);
        view_freeze--;
        
        if (autonotify && view_freeze == 0)
            notify_views_altered();
    }
    
    public bool are_view_notifications_frozen() {
        return view_freeze > 0;
    }
    
    // This is only used by DataView.
    public void internal_notify_geometry_altered(DataView view) {
        if (geometry_freeze == 0)
            item_geometry_altered(view);
    }
    
    // This is available to all users, for use when all items in the view have changed sizes.
    public void notify_geometries_altered() {
        geometries_altered();
    }
    
    public void freeze_geometry_notifications() {
        geometry_freeze++;
    }
    
    public void thaw_geometry_notifications(bool autonotify) {
        assert(geometry_freeze > 0);
        geometry_freeze--;
        
        if (autonotify && geometry_freeze == 0)
            notify_geometries_altered();
    }
    
    public bool are_geometry_notifications_frozen() {
        return geometry_freeze > 0;
    }
}
