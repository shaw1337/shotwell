/* Copyright 2009-2011 Yorba Foundation
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution. 
 */

int number_of_processors() {
    int n = (int) ExtendedPosix.sysconf(ExtendedPosix.ConfName._SC_NPROCESSORS_ONLN);
    return n <= 0 ? 1 : n;
}

// Return the directory in which Shotwell is installed, or null if uninstalled.
File? get_sys_install_dir(File exec_dir) {
    File prefix_dir = File.new_for_path(Resources.PREFIX);
    return exec_dir.has_prefix(prefix_dir) ? prefix_dir : null;
}

void sys_show_uri(Gdk.Screen screen, string uri) throws Error {
    Gtk.show_uri(screen, uri, Gdk.CURRENT_TIME);
}

int posix_wexitstatus(int status) {
    return (((status) & 0xff00) >> 8);
}
