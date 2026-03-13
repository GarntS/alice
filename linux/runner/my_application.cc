#include "my_application.h"

#include <flutter_linux/flutter_linux.h>
#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif
#include <gio/gio.h>
#include <gtk-layer-shell.h>

#include <cstring>
#include <signal.h>
#include <sys/prctl.h>
#include <unistd.h>

#include <glib/gstdio.h>

#include "alice_layer_shell_bridge.h"
#include "alice_platform_bridge.h"
#include "flutter/generated_plugin_registrant.h"

namespace {

constexpr char kPlatformChannelName[] = "alice/platform";
constexpr char kEventChannelName[] = "alice/platform/events";
constexpr char kBarWindowArgument[] = "--alice-window=bar";
constexpr char kPanelWindowArgument[] = "--alice-window=panel";
constexpr guint kSnapshotDebounceMs = 50;
constexpr guint kStatsIntervalSeconds = 1;
constexpr guint kClockIntervalSeconds = 30;
constexpr char kMprisPrefix[] = "org.mpris.MediaPlayer2.";
constexpr char kStatusNotifierPrefixKde[] = "org.kde.StatusNotifierItem";
constexpr char kStatusNotifierPrefixFreedesktop[] =
    "org.freedesktop.StatusNotifierItem";
constexpr char kStatusNotifierWatcherPath[] = "/StatusNotifierWatcher";
constexpr char kStatusNotifierWatcherKdeBusName[] =
    "org.kde.StatusNotifierWatcher";
constexpr char kStatusNotifierWatcherFreedesktopBusName[] =
    "org.freedesktop.StatusNotifierWatcher";
constexpr char kStatusNotifierWatcherKdeInterface[] =
    "org.kde.StatusNotifierWatcher";
constexpr char kStatusNotifierWatcherFreedesktopInterface[] =
    "org.freedesktop.StatusNotifierWatcher";
constexpr char kStatusNotifierItemKdeInterface[] = "org.kde.StatusNotifierItem";
constexpr char kStatusNotifierItemFreedesktopInterface[] =
    "org.freedesktop.StatusNotifierItem";
constexpr char kDefaultStatusNotifierItemPath[] = "/StatusNotifierItem";
constexpr gint kTrayIconSizePx = 16;
void configure_layer_shell_bar_window(GtkWindow* window) {
  AliceSurfacePlacementFFI bar_placement = alice_layer_shell_bar_placement();
  GdkDisplay* display = gdk_display_get_default();
  GdkMonitor* monitor =
      display == nullptr ? nullptr : gdk_display_get_primary_monitor(display);
  gint monitor_width = 1280;

  if (monitor != nullptr) {
    GdkRectangle geometry;
    gdk_monitor_get_geometry(monitor, &geometry);
    monitor_width = geometry.width;
  }

  gtk_layer_init_for_window(window);
  gtk_layer_set_namespace(window, "alice-bar");
  gtk_layer_set_layer(window, GTK_LAYER_SHELL_LAYER_TOP);
  gtk_layer_set_keyboard_mode(window, GTK_LAYER_SHELL_KEYBOARD_MODE_NONE);
  gtk_layer_set_anchor(window, GTK_LAYER_SHELL_EDGE_LEFT, TRUE);
  gtk_layer_set_anchor(window, GTK_LAYER_SHELL_EDGE_RIGHT, TRUE);
  gtk_layer_set_anchor(window, GTK_LAYER_SHELL_EDGE_TOP, TRUE);
  gtk_layer_set_anchor(window, GTK_LAYER_SHELL_EDGE_BOTTOM, FALSE);
  gtk_layer_set_margin(window, GTK_LAYER_SHELL_EDGE_LEFT, 0);
  gtk_layer_set_margin(window, GTK_LAYER_SHELL_EDGE_RIGHT, 0);
  gtk_layer_set_margin(window, GTK_LAYER_SHELL_EDGE_TOP, 0);
  gtk_layer_set_margin(window, GTK_LAYER_SHELL_EDGE_BOTTOM, 0);
  gtk_layer_auto_exclusive_zone_enable(window);
  gtk_layer_set_respect_close(window, TRUE);

  if (monitor != nullptr) {
    gtk_layer_set_monitor(window, monitor);
  }

  gtk_widget_set_size_request(GTK_WIDGET(window), monitor_width,
                              static_cast<gint>(bar_placement.height));
  gtk_window_set_default_size(window, monitor_width,
                              static_cast<gint>(bar_placement.height));
  gtk_window_resize(window, monitor_width, static_cast<gint>(bar_placement.height));
  gtk_window_set_resizable(window, FALSE);
  gtk_window_set_decorated(window, FALSE);
  gtk_window_set_skip_taskbar_hint(window, TRUE);
  gtk_window_set_skip_pager_hint(window, TRUE);
  g_message("Configured gtk-layer-shell bar window at %dx%u", monitor_width,
            bar_placement.height);
}

void configure_bar_fallback_window(GtkWindow* window) {
  AliceSurfacePlacementFFI bar_placement = alice_layer_shell_bar_placement();
  GdkDisplay* display = gdk_display_get_default();
  gint width = 1280;
  if (display != nullptr) {
    GdkMonitor* monitor = gdk_display_get_primary_monitor(display);
    if (monitor != nullptr) {
      GdkRectangle geometry;
      gdk_monitor_get_geometry(monitor, &geometry);
      width = geometry.width;
    }
  }

  gtk_window_set_default_size(window, width, static_cast<gint>(bar_placement.height));
  gtk_window_set_resizable(window, FALSE);
  gtk_window_set_decorated(window, FALSE);
  gtk_window_set_skip_taskbar_hint(window, TRUE);
  gtk_window_set_skip_pager_hint(window, TRUE);
  gtk_window_stick(window);
  gtk_window_set_keep_above(window, TRUE);
}

FlValue* build_time_zone_value(const AliceTimeZoneFFI& zone) {
  FlValue* value = fl_value_new_map();
  fl_value_set_string_take(value, "label", fl_value_new_string(zone.label));
  fl_value_set_string_take(value, "offsetHours",
                           fl_value_new_int(zone.offset_hours));
  return value;
}

FlValue* build_config_value() {
  AliceConfigFFI* config = alice_platform_load_config();
  if (config == nullptr) {
    return fl_value_new_map();
  }

  FlValue* value = fl_value_new_map();
  const char* theme_mode = "system";
  if (config->theme_mode == 1) {
    theme_mode = "light";
  } else if (config->theme_mode == 2) {
    theme_mode = "dark";
  }

  fl_value_set_string_take(value, "themeMode", fl_value_new_string(theme_mode));
  fl_value_set_string_take(value, "accentColor",
                           fl_value_new_string(config->accent_color));
  fl_value_set_string_take(value, "showNetworkLabel",
                           fl_value_new_bool(config->show_network_label));
  fl_value_set_string_take(value, "maxVisibleTrayItems",
                           fl_value_new_int(config->max_visible_tray_items));
  if (config->local_time_zone_label != nullptr &&
      config->local_time_zone_label[0] != '\0') {
    fl_value_set_string_take(
        value, "localTimeZoneLabel",
        fl_value_new_string(config->local_time_zone_label));
  }

  FlValue* time_zones = fl_value_new_list();
  for (size_t index = 0; index < config->time_zone_count; index++) {
    fl_value_append_take(time_zones,
                         build_time_zone_value(config->time_zones[index]));
  }
  fl_value_set_string_take(value, "timeZones", time_zones);

  FlValue* power = fl_value_new_map();
  fl_value_set_string_take(power, "lock",
                           fl_value_new_string(config->power_commands.lock));
  fl_value_set_string_take(
      power, "lockAndSuspend",
      fl_value_new_string(config->power_commands.lock_and_suspend));
  fl_value_set_string_take(power, "restart",
                           fl_value_new_string(config->power_commands.restart));
  fl_value_set_string_take(power, "poweroff",
                           fl_value_new_string(config->power_commands.poweroff));
  fl_value_set_string_take(value, "powerCommands", power);

  alice_platform_free_config(config);
  return value;
}

FlValue* build_workspace_value(const WorkspaceFFI& workspace) {
  FlValue* value = fl_value_new_map();
  fl_value_set_string_take(value, "label", fl_value_new_string(workspace.label));
  fl_value_set_string_take(value, "isFocused",
                           fl_value_new_bool(workspace.is_focused));
  fl_value_set_string_take(value, "isVisible",
                           fl_value_new_bool(workspace.is_visible));
  return value;
}

FlValue* build_media_value(const MediaFFI& media) {
  const char* title = media.title == nullptr ? "" : media.title;
  const char* artist = media.artist == nullptr ? "" : media.artist;
  const char* album_title = media.album_title == nullptr ? "" : media.album_title;
  const char* art_url = media.art_url == nullptr ? "" : media.art_url;
  const char* position_label =
      media.position_label == nullptr ? "" : media.position_label;
  const char* length_label =
      media.length_label == nullptr ? "" : media.length_label;
  FlValue* value = fl_value_new_map();
  fl_value_set_string_take(value, "title", fl_value_new_string(title));
  fl_value_set_string_take(value, "artist", fl_value_new_string(artist));
  fl_value_set_string_take(value, "albumTitle",
                           fl_value_new_string(album_title));
  fl_value_set_string_take(value, "artUrl", fl_value_new_string(art_url));
  fl_value_set_string_take(value, "positionLabel",
                           fl_value_new_string(position_label));
  fl_value_set_string_take(value, "lengthLabel",
                           fl_value_new_string(length_label));
  fl_value_set_string_take(value, "isPlaying",
                           fl_value_new_bool(media.is_playing));
  return value;
}

FlValue* build_network_value(const NetworkFFI& network_data) {
  FlValue* network = fl_value_new_map();
  const char* kind = "disconnected";
  if (network_data.kind == 0) {
    kind = "wifi";
  } else if (network_data.kind == 1) {
    kind = "wired";
  }
  fl_value_set_string_take(network, "kind", fl_value_new_string(kind));
  fl_value_set_string_take(network, "label",
                           fl_value_new_string(network_data.label));
  return network;
}

FlValue* build_disconnected_network_value() {
  FlValue* network = fl_value_new_map();
  fl_value_set_string_take(network, "kind", fl_value_new_string("disconnected"));
  fl_value_set_string_take(network, "label",
                           fl_value_new_string("Disconnected"));
  return network;
}


GHashTable* tray_icon_png_cache() {
  static GHashTable* cache = nullptr;
  if (cache == nullptr) {
    cache = g_hash_table_new_full(
        g_str_hash, g_str_equal, g_free,
        reinterpret_cast<GDestroyNotify>(g_bytes_unref));
  }
  return cache;
}

void free_rgba_buffer(guchar* pixels, gpointer user_data) {
  g_free(pixels);
}

GDBusConnection* tray_icon_session_bus() {
  static GDBusConnection* connection = nullptr;
  if (connection != nullptr) {
    return connection;
  }

  g_autoptr(GError) error = nullptr;
  connection = g_bus_get_sync(G_BUS_TYPE_SESSION, nullptr, &error);
  if (connection == nullptr) {
    return nullptr;
  }
  return connection;
}

GBytes* encode_pixbuf_png_bytes(GdkPixbuf* pixbuf, const gchar* cache_key) {
  if (pixbuf == nullptr) {
    return nullptr;
  }

  g_autoptr(GError) error = nullptr;
  gchar* buffer = nullptr;
  gsize size = 0;
  if (!gdk_pixbuf_save_to_buffer(pixbuf, &buffer, &size, "png", &error, nullptr) ||
      buffer == nullptr || size == 0) {
    if (buffer != nullptr) {
      g_free(buffer);
    }
    return nullptr;
  }

  GBytes* bytes = g_bytes_new_take(reinterpret_cast<guint8*>(buffer), size);
  if (cache_key != nullptr && cache_key[0] != '\0') {
    g_hash_table_insert(tray_icon_png_cache(), g_strdup(cache_key), g_bytes_ref(bytes));
  }
  return bytes;
}

GBytes* png_bytes_from_icon_pixmap_variant(gint width, gint height, GVariant* bytes_variant) {
  if (width <= 0 || height <= 0 || bytes_variant == nullptr) {
    return nullptr;
  }

  gsize length = 0;
  const guint8* argb = static_cast<const guint8*>(
      g_variant_get_fixed_array(bytes_variant, &length, sizeof(guint8)));
  if (argb == nullptr) {
    return nullptr;
  }

  const gsize expected_size = static_cast<gsize>(width) * static_cast<gsize>(height) * 4;
  if (length < expected_size) {
    return nullptr;
  }

  guchar* rgba = static_cast<guchar*>(g_malloc(expected_size));
  for (gsize index = 0; index < expected_size; index += 4) {
    const guint8 a = argb[index + 0];
    const guint8 r = argb[index + 1];
    const guint8 g = argb[index + 2];
    const guint8 b = argb[index + 3];
    rgba[index + 0] = r;
    rgba[index + 1] = g;
    rgba[index + 2] = b;
    rgba[index + 3] = a;
  }

  g_autoptr(GdkPixbuf) source = gdk_pixbuf_new_from_data(
      rgba, GDK_COLORSPACE_RGB, TRUE, 8, width, height, width * 4,
      free_rgba_buffer, nullptr);
  if (source == nullptr) {
    g_free(rgba);
    return nullptr;
  }

  g_autoptr(GdkPixbuf) scaled = nullptr;
  GdkPixbuf* target = source;
  if (width != kTrayIconSizePx || height != kTrayIconSizePx) {
    scaled = gdk_pixbuf_scale_simple(source, kTrayIconSizePx, kTrayIconSizePx,
                                     GDK_INTERP_BILINEAR);
    if (scaled != nullptr) {
      target = scaled;
    }
  }

  return encode_pixbuf_png_bytes(target, nullptr);
}

GBytes* load_tray_icon_png_bytes_from_sni_pixmap(const char* service_name,
                                                 const char* object_path) {
  if (service_name == nullptr || service_name[0] == '\0' || object_path == nullptr ||
      object_path[0] == '\0') {
    return nullptr;
  }

  g_autofree gchar* cache_key =
      g_strdup_printf("pixmap|%s|%s", service_name, object_path);
  GBytes* cached = static_cast<GBytes*>(
      g_hash_table_lookup(tray_icon_png_cache(), cache_key));
  if (cached != nullptr) {
    return g_bytes_ref(cached);
  }

  GDBusConnection* session_bus = tray_icon_session_bus();
  if (session_bus == nullptr) {
    return nullptr;
  }

  const char* item_interfaces[] = {
      kStatusNotifierItemKdeInterface,
      kStatusNotifierItemFreedesktopInterface,
  };
  for (const char* item_interface : item_interfaces) {
    g_autoptr(GError) error = nullptr;
    g_autoptr(GVariant) result = g_dbus_connection_call_sync(
        session_bus, service_name, object_path, "org.freedesktop.DBus.Properties",
        "Get", g_variant_new("(ss)", item_interface, "IconPixmap"),
        G_VARIANT_TYPE("(v)"), G_DBUS_CALL_FLAGS_NONE, 200, nullptr, &error);
    if (result == nullptr) {
      continue;
    }

    g_autoptr(GVariant) boxed_value = nullptr;
    g_variant_get(result, "(@v)", &boxed_value);
    if (boxed_value == nullptr) {
      continue;
    }
    g_autoptr(GVariant) pixmaps = g_variant_get_variant(boxed_value);
    if (pixmaps == nullptr || !g_variant_is_of_type(pixmaps, G_VARIANT_TYPE("a(iiay)"))) {
      continue;
    }

    GBytes* best_bytes = nullptr;
    gint64 best_area = 0;
    const gsize child_count = g_variant_n_children(pixmaps);
    for (gsize index = 0; index < child_count; index++) {
      g_autoptr(GVariant) entry = g_variant_get_child_value(pixmaps, index);
      gint32 width = 0;
      gint32 height = 0;
      g_autoptr(GVariant) bytes_variant = nullptr;
      g_variant_get(entry, "(ii@ay)", &width, &height, &bytes_variant);
      const gint64 area = static_cast<gint64>(width) * static_cast<gint64>(height);
      if (area <= 0) {
        continue;
      }

      g_autoptr(GBytes) png_bytes =
          png_bytes_from_icon_pixmap_variant(width, height, bytes_variant);
      if (png_bytes == nullptr) {
        continue;
      }

      if (area > best_area) {
        if (best_bytes != nullptr) {
          g_bytes_unref(best_bytes);
        }
        best_bytes = g_bytes_ref(png_bytes);
        best_area = area;
      }
    }

    if (best_bytes != nullptr) {
      g_hash_table_insert(tray_icon_png_cache(), g_strdup(cache_key),
                          g_bytes_ref(best_bytes));
      return best_bytes;
    }
  }

  return nullptr;
}

GBytes* load_tray_icon_png_bytes(const char* icon_name, const char* icon_theme_path) {
  if (icon_name == nullptr || icon_name[0] == '\0') {
    return nullptr;
  }

  const char* theme_path = icon_theme_path == nullptr ? "" : icon_theme_path;
  g_autofree gchar* cache_key = g_strdup_printf("%s|%s", icon_name, theme_path);
  GHashTable* cache = tray_icon_png_cache();
  GBytes* cached = static_cast<GBytes*>(g_hash_table_lookup(cache, cache_key));
  if (cached != nullptr) {
    return g_bytes_ref(cached);
  }

  g_autoptr(GError) error = nullptr;
  g_autoptr(GdkPixbuf) pixbuf = nullptr;
  if (g_path_is_absolute(icon_name)) {
    pixbuf = gdk_pixbuf_new_from_file_at_scale(
        icon_name, kTrayIconSizePx, kTrayIconSizePx, TRUE, &error);
  } else {
    GtkIconTheme* icon_theme = gtk_icon_theme_get_default();
    if (icon_theme != nullptr && icon_theme_path != nullptr &&
        icon_theme_path[0] != '\0') {
      gtk_icon_theme_append_search_path(icon_theme, icon_theme_path);
    }
    pixbuf = icon_theme == nullptr
                 ? nullptr
                 : gtk_icon_theme_load_icon(
                       icon_theme, icon_name, kTrayIconSizePx,
                       static_cast<GtkIconLookupFlags>(GTK_ICON_LOOKUP_FORCE_SIZE),
                       &error);
  }

  if (pixbuf == nullptr) {
    return nullptr;
  }
  return encode_pixbuf_png_bytes(pixbuf, cache_key);
}

FlValue* build_tray_item_value(const TrayItemFFI& tray_item, bool include_icon_bytes) {
  FlValue* value = fl_value_new_map();
  fl_value_set_string_take(value, "id", fl_value_new_string(tray_item.id));
  fl_value_set_string_take(value, "label", fl_value_new_string(tray_item.label));
  fl_value_set_string_take(value, "serviceName",
                           fl_value_new_string(tray_item.service_name));
  fl_value_set_string_take(value, "objectPath",
                           fl_value_new_string(tray_item.object_path));
  if (include_icon_bytes) {
    g_autoptr(GBytes) icon_bytes =
        load_tray_icon_png_bytes(tray_item.icon_name, tray_item.icon_theme_path);
    if (icon_bytes == nullptr) {
      g_autofree gchar* label_icon_name = g_ascii_strdown(tray_item.label, -1);
      icon_bytes = load_tray_icon_png_bytes(label_icon_name, tray_item.icon_theme_path);
    }
    if (icon_bytes == nullptr) {
      icon_bytes = load_tray_icon_png_bytes_from_sni_pixmap(
          tray_item.service_name, tray_item.object_path);
    }
    if (icon_bytes != nullptr) {
      gsize length = 0;
      const guint8* data =
          static_cast<const guint8*>(g_bytes_get_data(icon_bytes, &length));
      if (data != nullptr && length > 0) {
        fl_value_set_string_take(value, "iconPngBytes",
                                 fl_value_new_uint8_list(data, length));
      }
    }
  }
  return value;
}

FlValue* build_clock_value(const ClockFFI& clock_data) {
  FlValue* clock = fl_value_new_map();
  fl_value_set_string_take(clock, "timeZoneCode",
                           fl_value_new_string(clock_data.time_zone_code));
  fl_value_set_string_take(clock, "dateLabel",
                           fl_value_new_string(clock_data.date_label));
  fl_value_set_string_take(clock, "timeLabel",
                           fl_value_new_string(clock_data.time_label));
  return clock;
}

FlValue* build_fallback_clock_value() {
  FlValue* clock = fl_value_new_map();
  fl_value_set_string_take(clock, "timeZoneCode", fl_value_new_string("UTC"));
  fl_value_set_string_take(clock, "dateLabel", fl_value_new_string("-- ---"));
  fl_value_set_string_take(clock, "timeLabel", fl_value_new_string("--:--"));
  return clock;
}

bool execute_command_for_action(const char* action) {
  AliceConfigFFI* config = alice_platform_load_config();
  if (config == nullptr || action == nullptr) {
    if (config != nullptr) {
      alice_platform_free_config(config);
    }
    return false;
  }

  const char* command = nullptr;
  if (strcmp(action, "lock") == 0) {
    command = config->power_commands.lock;
  } else if (strcmp(action, "lockAndSuspend") == 0) {
    command = config->power_commands.lock_and_suspend;
  } else if (strcmp(action, "restart") == 0) {
    command = config->power_commands.restart;
  } else if (strcmp(action, "poweroff") == 0) {
    command = config->power_commands.poweroff;
  }

  gboolean spawned = FALSE;
  if (command != nullptr && command[0] != '\0') {
    gchar* argv[] = {
        const_cast<gchar*>("/bin/sh"),
        const_cast<gchar*>("-c"),
        const_cast<gchar*>(command),
        nullptr,
    };
    GError* error = nullptr;
    GPid pid = 0;
    spawned = g_spawn_async(
        nullptr, argv, nullptr,
        static_cast<GSpawnFlags>(G_SPAWN_SEARCH_PATH | G_SPAWN_DO_NOT_REAP_CHILD),
        nullptr, nullptr, &pid, &error);
    if (spawned) {
      g_spawn_close_pid(pid);
    } else if (error != nullptr) {
      g_warning("Failed to execute power command: %s", error->message);
      g_clear_error(&error);
    }
  }

  alice_platform_free_config(config);
  return spawned;
}

}  // namespace

struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;
  FlMethodChannel* platform_channel;
  FlEventChannel* event_channel;
  GtkWindow* window;
  GtkWindow* dismiss_window;
  guint snapshot_debounce_id;
  guint stats_timer_id;
  guint clock_timer_id;
  gboolean event_stream_active;
  GDBusConnection* session_bus;
  guint tray_item_properties_changed_id;
  guint mpris_properties_changed_id;
  guint name_owner_changed_id;
  guint status_notifier_watcher_kde_registration_id;
  guint status_notifier_watcher_freedesktop_registration_id;
  guint status_notifier_watcher_kde_owner_id;
  guint status_notifier_watcher_freedesktop_owner_id;
  GDBusNodeInfo* status_notifier_watcher_node_info;
  GHashTable* status_notifier_registered_items;
  gboolean status_notifier_host_registered;
  GPid sway_pid;
  GIOChannel* sway_stdout_channel;
  guint sway_stdout_watch_id;
  GFileMonitor* net_dir_monitor;
  GHashTable* net_file_monitors;
  gboolean layer_shell_supported;
  gboolean is_panel_process;
  gboolean panel_first_frame_received;
  pid_t parent_pid;
  gchar* panel_id;
  gdouble panel_anchor_x;
  gdouble panel_anchor_y;
  gdouble panel_width;
  gdouble panel_height;
  gchar* panel_alignment;
  gchar* panel_socket_path;
  GPid panel_pid;
  GSocketService* panel_socket_service;
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

static AliceSurfacePlacementFFI resolved_panel_placement(MyApplication* self) {
  AliceSurfacePlacementFFI placement = alice_layer_shell_panel_placement();
  if (self->panel_width > 0) {
    placement.width = static_cast<uint32_t>(self->panel_width);
  }
  if (self->panel_height > 0) {
    placement.height = static_cast<uint32_t>(self->panel_height);
  }
  return placement;
}

static gchar* current_executable_path() {
  return g_file_read_link("/proc/self/exe", nullptr);
}

static gchar* default_panel_socket_path() {
  const gchar* runtime_dir = g_get_user_runtime_dir();
  if (runtime_dir == nullptr || runtime_dir[0] == '\0') {
    runtime_dir = g_get_tmp_dir();
  }
  return g_strdup_printf("%s/alice-panel-%d.sock", runtime_dir, getpid());
}

static gchar** build_panel_process_argv(MyApplication* self) {
  g_autoptr(GPtrArray) args =
      g_ptr_array_new_with_free_func(reinterpret_cast<GDestroyNotify>(g_free));

  gchar* executable = current_executable_path();
  if (executable == nullptr) {
    return nullptr;
  }
  g_ptr_array_add(args, executable);
  g_ptr_array_add(args, g_strdup(kPanelWindowArgument));
  g_ptr_array_add(args,
                  g_strdup_printf("--alice-panel-socket=%s", self->panel_socket_path));
  g_ptr_array_add(args,
                  g_strdup_printf("--alice-parent-pid=%d", getpid()));

  if (self->dart_entrypoint_arguments != nullptr) {
    for (gint index = 0; self->dart_entrypoint_arguments[index] != nullptr; index++) {
      const gchar* arg = self->dart_entrypoint_arguments[index];
      if (g_str_has_prefix(arg, "--alice-window=") ||
          g_str_has_prefix(arg, "--alice-panel-socket=")) {
        continue;
      }
      g_ptr_array_add(args, g_strdup(arg));
    }
  }

  g_ptr_array_add(args, nullptr);
  return reinterpret_cast<gchar**>(g_ptr_array_free(g_steal_pointer(&args), FALSE));
}

static FlValue* build_snapshot_value(MyApplication* self,
                                     const gchar* active_panel_id) {
  AliceSnapshotFFI* snapshot = alice_platform_read_snapshot();
  FlValue* value = fl_value_new_map();
  const gboolean panel_process = self->is_panel_process;
  const gboolean tray_panel_open =
      active_panel_id != nullptr && g_strcmp0(active_panel_id, "trayOverflow") == 0;
  const gboolean include_tray_icon_bytes = !panel_process || tray_panel_open;

  if (active_panel_id != nullptr && active_panel_id[0] != '\0') {
    fl_value_set_string_take(value, "activePanelId",
                             fl_value_new_string(active_panel_id));
  } else {
    fl_value_set_string_take(value, "activePanelId", fl_value_new_null());
  }

  FlValue* workspaces = fl_value_new_list();
  if (snapshot != nullptr) {
    for (size_t index = 0; index < snapshot->workspace_count; index++) {
      fl_value_append_take(workspaces,
                           build_workspace_value(snapshot->workspaces[index]));
    }
  }
  fl_value_set_string_take(value, "workspaces", workspaces);

  if (snapshot != nullptr && snapshot->media != nullptr) {
    fl_value_set_string_take(value, "media",
                             build_media_value(*snapshot->media));
  } else {
    fl_value_set_string_take(value, "media", fl_value_new_null());
  }

  fl_value_set_string_take(
      value, "memoryUsagePercent",
      fl_value_new_float(snapshot != nullptr ? snapshot->memory_usage_percent
                                             : 0.0));
  fl_value_set_string_take(
      value, "cpuUsageCores",
      fl_value_new_float(snapshot != nullptr ? snapshot->cpu_usage_cores : 0.0));
  FlValue* tray_items = fl_value_new_list();
  if (snapshot != nullptr) {
    fl_value_set_string_take(value, "network",
                             build_network_value(snapshot->network));
    fl_value_set_string_take(value, "clock",
                             build_clock_value(snapshot->clock));
    for (size_t index = 0; index < snapshot->tray_item_count; index++) {
      fl_value_append_take(tray_items,
                           build_tray_item_value(snapshot->tray_items[index],
                                                 include_tray_icon_bytes));
    }
  } else {
    fl_value_set_string_take(value, "network",
                             build_disconnected_network_value());
    fl_value_set_string_take(value, "clock", build_fallback_clock_value());
  }
  fl_value_set_string_take(value, "trayItems", tray_items);

  if (snapshot != nullptr) {
    alice_platform_free_snapshot(snapshot);
  }
  return value;
}

static void update_panel_window_geometry(MyApplication* self) {
  if (!self->is_panel_process || self->window == nullptr) {
    return;
  }

  AliceSurfacePlacementFFI placement = resolved_panel_placement(self);
  GdkDisplay* display = gdk_display_get_default();
  GdkMonitor* monitor = nullptr;
  gint monitor_width = 1280;
  gint monitor_height = 720;
  gint monitor_x = 0;
  gint monitor_y = 0;
  if (display != nullptr) {
    const gint monitor_count = gdk_display_get_n_monitors(display);
    for (gint index = 0; index < monitor_count; index++) {
      GdkMonitor* candidate = gdk_display_get_monitor(display, index);
      if (candidate == nullptr) {
        continue;
      }
      GdkRectangle geometry;
      gdk_monitor_get_geometry(candidate, &geometry);
      const gboolean in_x =
          self->panel_anchor_x >= geometry.x &&
          self->panel_anchor_x < geometry.x + geometry.width;
      const gboolean in_y =
          self->panel_anchor_y >= geometry.y &&
          self->panel_anchor_y < geometry.y + geometry.height;
      if (in_x && in_y) {
        monitor = candidate;
        monitor_x = geometry.x;
        monitor_y = geometry.y;
        monitor_width = geometry.width;
        monitor_height = geometry.height;
        break;
      }
    }
  }
  if (monitor == nullptr && display != nullptr) {
    monitor = gdk_display_get_primary_monitor(display);
    if (monitor != nullptr) {
      GdkRectangle geometry;
      gdk_monitor_get_geometry(monitor, &geometry);
      monitor_x = geometry.x;
      monitor_y = geometry.y;
      monitor_width = geometry.width;
      monitor_height = geometry.height;
    }
  }
  const gint relative_anchor_x =
      static_cast<gint>(self->panel_anchor_x) - monitor_x;
  const gint relative_anchor_y =
      static_cast<gint>(self->panel_anchor_y) - monitor_y;
  gint margin_top = relative_anchor_y;
  margin_top = CLAMP(
      margin_top, 0,
      MAX(0, monitor_height - static_cast<gint>(placement.height)));
  const gboolean align_right =
      g_strcmp0(self->panel_alignment, "right") == 0;
  gint margin_left = 0;
  gint margin_right = 0;
  if (align_right) {
    margin_right = monitor_width - relative_anchor_x;
    margin_right = CLAMP(margin_right, 0, monitor_width);
    const gint placement_width = static_cast<gint>(placement.width);
    if (margin_right + placement_width > monitor_width) {
      margin_right = MAX(0, monitor_width - placement_width);
    }
  } else {
    const gint placement_width = static_cast<gint>(placement.width);
    margin_left = relative_anchor_x - (placement_width / 2);
    margin_left =
        CLAMP(margin_left, 0, MAX(0, monitor_width - placement_width));
  }

  if (self->layer_shell_supported && gtk_layer_is_supported()) {
    if (monitor != nullptr) {
      if (self->dismiss_window != nullptr) {
        gtk_layer_set_monitor(self->dismiss_window, monitor);
      }
      gtk_layer_set_monitor(self->window, monitor);
    }
    gtk_layer_set_anchor(self->window, GTK_LAYER_SHELL_EDGE_LEFT, !align_right);
    gtk_layer_set_anchor(self->window, GTK_LAYER_SHELL_EDGE_RIGHT, align_right);
    gtk_layer_set_margin(self->window, GTK_LAYER_SHELL_EDGE_TOP, margin_top);
    gtk_layer_set_margin(self->window, GTK_LAYER_SHELL_EDGE_LEFT, margin_left);
    gtk_layer_set_margin(self->window, GTK_LAYER_SHELL_EDGE_RIGHT, margin_right);
  }

  gtk_widget_set_size_request(GTK_WIDGET(self->window),
                              static_cast<gint>(placement.width),
                              static_cast<gint>(placement.height));
  gtk_window_resize(self->window, static_cast<gint>(placement.width),
                    static_cast<gint>(placement.height));
}

static void apply_panel_visibility(MyApplication* self) {
  if (!self->is_panel_process || self->window == nullptr) {
    return;
  }

  update_panel_window_geometry(self);
  if (self->panel_id != nullptr && self->panel_first_frame_received) {
    if (self->dismiss_window != nullptr) {
      gtk_widget_show_all(GTK_WIDGET(self->dismiss_window));
    }
    gtk_widget_show_all(GTK_WIDGET(self->window));
  } else {
    if (self->dismiss_window != nullptr) {
      gtk_widget_hide(GTK_WIDGET(self->dismiss_window));
    }
    gtk_widget_hide(GTK_WIDGET(self->window));
  }
}

static void clear_panel_state(MyApplication* self) {
  g_clear_pointer(&self->panel_id, g_free);
  g_clear_pointer(&self->panel_alignment, g_free);
  self->panel_anchor_x = 0;
  self->panel_anchor_y = 0;
  self->panel_width = 0;
  self->panel_height = 0;
}

static gboolean panel_window_delete_event(GtkWidget* widget,
                                          GdkEvent* event,
                                          gpointer user_data) {
  MyApplication* self = MY_APPLICATION(user_data);
  if (!self->is_panel_process) {
    return FALSE;
  }

  clear_panel_state(self);
  apply_panel_visibility(self);
  return TRUE;
}

static gboolean dismiss_window_button_press_event(GtkWidget* widget,
                                                  GdkEventButton* event,
                                                  gpointer user_data) {
  MyApplication* self = MY_APPLICATION(user_data);
  if (!self->is_panel_process) {
    return FALSE;
  }

  clear_panel_state(self);
  apply_panel_visibility(self);
  return TRUE;
}

static gboolean on_panel_socket_incoming(GSocketService* service,
                                         GSocketConnection* connection,
                                         GObject* source_object,
                                         gpointer user_data) {
  MyApplication* self = MY_APPLICATION(user_data);
  g_autoptr(GError) error = nullptr;
  gchar buffer[128] = {0};
  gssize bytes = g_input_stream_read(
      g_io_stream_get_input_stream(G_IO_STREAM(connection)), buffer,
      sizeof(buffer) - 1, nullptr, &error);
  if (bytes <= 0) {
    return TRUE;
  }

  g_strstrip(buffer);
  if (g_str_has_prefix(buffer, "show:")) {
    g_auto(GStrv) parts = g_strsplit(buffer, ":", 7);
    if (g_strv_length(parts) == 7) {
      g_free(self->panel_id);
      g_free(self->panel_alignment);
      self->panel_id = g_strdup(parts[1]);
      self->panel_alignment = g_strdup(parts[2]);
      self->panel_anchor_x = g_ascii_strtod(parts[3], nullptr);
      self->panel_anchor_y = g_ascii_strtod(parts[4], nullptr);
      self->panel_width = g_ascii_strtod(parts[5], nullptr);
      self->panel_height = g_ascii_strtod(parts[6], nullptr);
      apply_panel_visibility(self);
    }
  } else if (strcmp(buffer, "hide") == 0) {
    clear_panel_state(self);
    apply_panel_visibility(self);
  }
  if (self->event_stream_active && self->event_channel != nullptr) {
    g_autoptr(GError) snapshot_error = nullptr;
    if (!fl_event_channel_send(self->event_channel,
                               build_snapshot_value(self, self->panel_id), nullptr,
                               &snapshot_error)) {
      g_warning("Failed to send snapshot: %s", snapshot_error->message);
    }
  }
  return TRUE;
}

static gboolean start_panel_socket_service(MyApplication* self) {
  if (!self->is_panel_process || self->panel_socket_path == nullptr) {
    return FALSE;
  }

  g_unlink(self->panel_socket_path);
  GSocketAddress* address = G_SOCKET_ADDRESS(
      g_unix_socket_address_new(self->panel_socket_path));
  self->panel_socket_service = g_socket_service_new();
  g_signal_connect(self->panel_socket_service, "incoming",
                   G_CALLBACK(on_panel_socket_incoming), self);

  g_autoptr(GError) error = nullptr;
  if (!g_socket_listener_add_address(
          G_SOCKET_LISTENER(self->panel_socket_service), address,
          G_SOCKET_TYPE_STREAM, G_SOCKET_PROTOCOL_DEFAULT, nullptr, nullptr,
          &error)) {
    g_warning("Failed to bind panel socket: %s", error->message);
    g_clear_object(&self->panel_socket_service);
    g_object_unref(address);
    return FALSE;
  }

  g_object_unref(address);
  g_socket_service_start(self->panel_socket_service);
  return TRUE;
}

static gboolean monitor_parent_process(gpointer user_data) {
  MyApplication* self = MY_APPLICATION(user_data);
  if (!self->is_panel_process || self->parent_pid <= 1) {
    return G_SOURCE_REMOVE;
  }

  if (kill(self->parent_pid, 0) != 0) {
    g_application_quit(G_APPLICATION(self));
    return G_SOURCE_REMOVE;
  }

  return G_SOURCE_CONTINUE;
}

static void configure_panel_parent_lifecycle(MyApplication* self) {
  if (!self->is_panel_process || self->parent_pid <= 1) {
    return;
  }

  if (prctl(PR_SET_PDEATHSIG, SIGTERM) != 0) {
    g_warning("Failed to configure panel parent-death signal");
  }

  if (getppid() != self->parent_pid) {
    g_application_quit(G_APPLICATION(self));
    return;
  }

  g_timeout_add_seconds(1, monitor_parent_process, self);
}

static void clear_panel_process(MyApplication* self) {
  if (self->panel_pid != 0) {
    g_spawn_close_pid(self->panel_pid);
    self->panel_pid = 0;
  }
}

static void on_panel_process_exit(GPid pid, gint status, gpointer user_data) {
  MyApplication* self = MY_APPLICATION(user_data);
  if (self->panel_pid == pid) {
    clear_panel_process(self);
  } else {
    g_spawn_close_pid(pid);
  }
}

static gboolean ensure_panel_process_running(MyApplication* self) {
  if (self->is_panel_process) {
    return TRUE;
  }
  if (self->panel_pid != 0) {
    return TRUE;
  }
  if (self->panel_socket_path == nullptr) {
    self->panel_socket_path = default_panel_socket_path();
  }

  g_auto(GStrv) argv = build_panel_process_argv(self);
  if (argv == nullptr) {
    return FALSE;
  }

  GError* error = nullptr;
  GPid child_pid = 0;
  if (!g_spawn_async(nullptr, argv, nullptr,
                     static_cast<GSpawnFlags>(G_SPAWN_DO_NOT_REAP_CHILD), nullptr,
                     nullptr, &child_pid, &error)) {
    g_warning("Failed to spawn panel process: %s", error->message);
    g_clear_error(&error);
    return FALSE;
  }

  self->panel_pid = child_pid;
  g_child_watch_add(child_pid, on_panel_process_exit, self);
  return TRUE;
}

static gboolean send_panel_command(MyApplication* self, const gchar* command) {
  if (!ensure_panel_process_running(self) || self->panel_socket_path == nullptr) {
    return FALSE;
  }

  for (gint attempt = 0; attempt < 20; attempt++) {
    GSocketClient* client = g_socket_client_new();
    GSocketAddress* address =
        G_SOCKET_ADDRESS(g_unix_socket_address_new(self->panel_socket_path));
    g_autoptr(GError) error = nullptr;
    GSocketConnection* connection = g_socket_client_connect(
        client, G_SOCKET_CONNECTABLE(address), nullptr, &error);
    g_object_unref(address);
    if (connection != nullptr) {
      const gsize length = strlen(command);
      gsize written = 0;
      gboolean ok = g_output_stream_write_all(
          g_io_stream_get_output_stream(G_IO_STREAM(connection)), command, length,
          &written, nullptr, &error);
      g_object_unref(connection);
      g_object_unref(client);
      return ok && written == length;
    }
    g_object_unref(client);
    if (attempt == 19 && self->panel_pid != 0) {
      clear_panel_process(self);
      if (!ensure_panel_process_running(self)) {
        return FALSE;
      }
    }
    g_usleep(25 * 1000);
  }

  return FALSE;
}

static gboolean send_snapshot_now(gpointer user_data) {
  MyApplication* self = MY_APPLICATION(user_data);
  self->snapshot_debounce_id = 0;
  if (!self->event_stream_active || self->event_channel == nullptr) {
    return G_SOURCE_REMOVE;
  }

  g_autoptr(GError) error = nullptr;
  if (!fl_event_channel_send(self->event_channel,
                             build_snapshot_value(self, self->panel_id), nullptr,
                             &error)) {
    g_warning("Failed to send snapshot: %s", error->message);
  }

  return G_SOURCE_REMOVE;
}

static void schedule_snapshot(MyApplication* self) {
  if (!self->event_stream_active || self->event_channel == nullptr) {
    return;
  }
  if (self->snapshot_debounce_id != 0) {
    return;
  }
  self->snapshot_debounce_id =
      g_timeout_add(kSnapshotDebounceMs, send_snapshot_now, self);
}

static gboolean stats_tick(gpointer user_data) {
  schedule_snapshot(MY_APPLICATION(user_data));
  return G_SOURCE_CONTINUE;
}

static gboolean clock_tick(gpointer user_data) {
  schedule_snapshot(MY_APPLICATION(user_data));
  return G_SOURCE_CONTINUE;
}

static gboolean is_relevant_dbus_name(const gchar* name) {
  if (name == nullptr) {
    return FALSE;
  }
  return g_str_has_prefix(name, kMprisPrefix) ||
         g_str_has_prefix(name, kStatusNotifierPrefixKde) ||
         g_str_has_prefix(name, kStatusNotifierPrefixFreedesktop);
}

static gboolean is_tray_dbus_name(const gchar* name) {
  if (name == nullptr) {
    return FALSE;
  }
  return g_str_has_prefix(name, kStatusNotifierPrefixKde) ||
         g_str_has_prefix(name, kStatusNotifierPrefixFreedesktop);
}

static gchar* canonical_status_notifier_item_id(const gchar* sender_name,
                                                const gchar* service_or_path) {
  if (service_or_path == nullptr || service_or_path[0] == '\0') {
    return nullptr;
  }

  if (service_or_path[0] == '/') {
    if (sender_name == nullptr || sender_name[0] == '\0') {
      return nullptr;
    }
    return g_strdup_printf("%s%s", sender_name, service_or_path);
  }

  if (strchr(service_or_path, '/') != nullptr) {
    return g_strdup(service_or_path);
  }

  return g_strdup_printf("%s%s", service_or_path, kDefaultStatusNotifierItemPath);
}

static void emit_status_notifier_item_signal(MyApplication* self,
                                             const gchar* signal_name,
                                             const gchar* item_id) {
  if (self->session_bus == nullptr) {
    return;
  }
  if (item_id == nullptr || item_id[0] == '\0') {
    return;
  }

  g_dbus_connection_emit_signal(
      self->session_bus, nullptr, kStatusNotifierWatcherPath,
      kStatusNotifierWatcherKdeInterface, signal_name,
      g_variant_new("(s)", item_id), nullptr);
  g_dbus_connection_emit_signal(self->session_bus, nullptr,
                                kStatusNotifierWatcherPath,
                                kStatusNotifierWatcherFreedesktopInterface,
                                signal_name, g_variant_new("(s)", item_id),
                                nullptr);
}

static void emit_status_notifier_host_signal(MyApplication* self,
                                             const gchar* signal_name) {
  if (self->session_bus == nullptr) {
    return;
  }

  g_dbus_connection_emit_signal(
      self->session_bus, nullptr, kStatusNotifierWatcherPath,
      kStatusNotifierWatcherKdeInterface, signal_name, nullptr, nullptr);
  g_dbus_connection_emit_signal(
      self->session_bus, nullptr, kStatusNotifierWatcherPath,
      kStatusNotifierWatcherFreedesktopInterface, signal_name, nullptr,
      nullptr);
}

static GVariant* build_registered_status_notifier_items_variant(
    MyApplication* self) {
  g_autoptr(GPtrArray) items =
      g_ptr_array_new_with_free_func(reinterpret_cast<GDestroyNotify>(g_free));
  if (self->status_notifier_registered_items != nullptr) {
    GHashTableIter iter;
    gpointer key = nullptr;
    gpointer value = nullptr;
    g_hash_table_iter_init(&iter, self->status_notifier_registered_items);
    while (g_hash_table_iter_next(&iter, &key, &value)) {
      g_ptr_array_add(items, g_strdup(static_cast<const gchar*>(key)));
    }
  }
  g_ptr_array_sort(items, reinterpret_cast<GCompareFunc>(g_strcmp0));

  GVariantBuilder builder;
  g_variant_builder_init(&builder, G_VARIANT_TYPE("as"));
  for (guint index = 0; index < items->len; index++) {
    g_variant_builder_add(&builder, "s",
                          static_cast<const gchar*>(items->pdata[index]));
  }
  return g_variant_builder_end(&builder);
}

static gboolean add_registered_status_notifier_item(MyApplication* self,
                                                    const gchar* item_id) {
  if (self->status_notifier_registered_items == nullptr || item_id == nullptr ||
      item_id[0] == '\0') {
    return FALSE;
  }
  if (g_hash_table_contains(self->status_notifier_registered_items, item_id)) {
    return FALSE;
  }

  g_hash_table_insert(self->status_notifier_registered_items, g_strdup(item_id),
                      GINT_TO_POINTER(1));
  emit_status_notifier_item_signal(self, "StatusNotifierItemRegistered", item_id);
  return TRUE;
}

static gboolean remove_registered_status_notifier_item(MyApplication* self,
                                                       const gchar* item_id) {
  if (self->status_notifier_registered_items == nullptr || item_id == nullptr ||
      item_id[0] == '\0') {
    return FALSE;
  }

  if (!g_hash_table_remove(self->status_notifier_registered_items, item_id)) {
    return FALSE;
  }

  emit_status_notifier_item_signal(self, "StatusNotifierItemUnregistered",
                                   item_id);
  return TRUE;
}

static gboolean remove_registered_status_notifier_items_for_service(
    MyApplication* self, const gchar* service_name) {
  if (self->status_notifier_registered_items == nullptr || service_name == nullptr ||
      service_name[0] == '\0') {
    return FALSE;
  }

  g_autoptr(GPtrArray) to_remove =
      g_ptr_array_new_with_free_func(reinterpret_cast<GDestroyNotify>(g_free));
  const gsize service_len = strlen(service_name);
  GHashTableIter iter;
  gpointer key = nullptr;
  gpointer value = nullptr;
  g_hash_table_iter_init(&iter, self->status_notifier_registered_items);
  while (g_hash_table_iter_next(&iter, &key, &value)) {
    const gchar* item_id = static_cast<const gchar*>(key);
    if (g_str_has_prefix(item_id, service_name) && item_id[service_len] == '/') {
      g_ptr_array_add(to_remove, g_strdup(item_id));
    }
  }

  gboolean removed_any = FALSE;
  for (guint index = 0; index < to_remove->len; index++) {
    removed_any = remove_registered_status_notifier_item(
                      self, static_cast<const gchar*>(to_remove->pdata[index])) ||
                  removed_any;
  }
  return removed_any;
}

static void status_notifier_watcher_method_call(
    GDBusConnection* connection, const gchar* sender_name,
    const gchar* object_path, const gchar* interface_name,
    const gchar* method_name, GVariant* parameters,
    GDBusMethodInvocation* invocation, gpointer user_data) {
  MyApplication* self = MY_APPLICATION(user_data);

  if (g_strcmp0(method_name, "RegisterStatusNotifierItem") == 0) {
    const gchar* service_or_path = nullptr;
    g_variant_get(parameters, "(&s)", &service_or_path);
    g_autofree gchar* item_id =
        canonical_status_notifier_item_id(sender_name, service_or_path);
    const gboolean added =
        item_id == nullptr ? FALSE : add_registered_status_notifier_item(self, item_id);
    g_dbus_method_invocation_return_value(invocation, nullptr);
    if (added) {
      schedule_snapshot(self);
    }
    return;
  }

  if (g_strcmp0(method_name, "RegisterStatusNotifierHost") == 0) {
    if (!self->status_notifier_host_registered) {
      self->status_notifier_host_registered = TRUE;
      emit_status_notifier_host_signal(self, "StatusNotifierHostRegistered");
    }
    g_dbus_method_invocation_return_value(invocation, nullptr);
    return;
  }

  g_dbus_method_invocation_return_dbus_error(
      invocation, "org.freedesktop.DBus.Error.UnknownMethod",
      "Unknown StatusNotifierWatcher method");
}

static GVariant* status_notifier_watcher_get_property(
    GDBusConnection* connection, const gchar* sender_name,
    const gchar* object_path, const gchar* interface_name,
    const gchar* property_name, GError** error, gpointer user_data) {
  MyApplication* self = MY_APPLICATION(user_data);

  if (g_strcmp0(property_name, "RegisteredStatusNotifierItems") == 0) {
    return build_registered_status_notifier_items_variant(self);
  }
  if (g_strcmp0(property_name, "IsStatusNotifierHostRegistered") == 0) {
    return g_variant_new_boolean(self->status_notifier_host_registered);
  }
  if (g_strcmp0(property_name, "ProtocolVersion") == 0) {
    return g_variant_new_int32(0);
  }

  g_set_error(error, G_DBUS_ERROR, G_DBUS_ERROR_UNKNOWN_PROPERTY,
              "Unknown property %s", property_name);
  return nullptr;
}

static void ensure_status_notifier_watcher(MyApplication* self) {
  if (self->is_panel_process) {
    return;
  }
  if (self->session_bus == nullptr) {
    return;
  }
  if (self->status_notifier_watcher_node_info != nullptr) {
    return;
  }

  constexpr char kWatcherIntrospectionXml[] =
      "<node>"
      "  <interface name='org.kde.StatusNotifierWatcher'>"
      "    <method name='RegisterStatusNotifierItem'>"
      "      <arg name='service' type='s' direction='in'/>"
      "    </method>"
      "    <method name='RegisterStatusNotifierHost'>"
      "      <arg name='service' type='s' direction='in'/>"
      "    </method>"
      "    <property name='RegisteredStatusNotifierItems' type='as' access='read'/>"
      "    <property name='IsStatusNotifierHostRegistered' type='b' access='read'/>"
      "    <property name='ProtocolVersion' type='i' access='read'/>"
      "    <signal name='StatusNotifierItemRegistered'>"
      "      <arg name='service' type='s'/>"
      "    </signal>"
      "    <signal name='StatusNotifierItemUnregistered'>"
      "      <arg name='service' type='s'/>"
      "    </signal>"
      "    <signal name='StatusNotifierHostRegistered'/>"
      "    <signal name='StatusNotifierHostUnregistered'/>"
      "  </interface>"
      "  <interface name='org.freedesktop.StatusNotifierWatcher'>"
      "    <method name='RegisterStatusNotifierItem'>"
      "      <arg name='service' type='s' direction='in'/>"
      "    </method>"
      "    <method name='RegisterStatusNotifierHost'>"
      "      <arg name='service' type='s' direction='in'/>"
      "    </method>"
      "    <property name='RegisteredStatusNotifierItems' type='as' access='read'/>"
      "    <property name='IsStatusNotifierHostRegistered' type='b' access='read'/>"
      "    <property name='ProtocolVersion' type='i' access='read'/>"
      "    <signal name='StatusNotifierItemRegistered'>"
      "      <arg name='service' type='s'/>"
      "    </signal>"
      "    <signal name='StatusNotifierItemUnregistered'>"
      "      <arg name='service' type='s'/>"
      "    </signal>"
      "    <signal name='StatusNotifierHostRegistered'/>"
      "    <signal name='StatusNotifierHostUnregistered'/>"
      "  </interface>"
      "</node>";

  g_autoptr(GError) error = nullptr;
  self->status_notifier_watcher_node_info =
      g_dbus_node_info_new_for_xml(kWatcherIntrospectionXml, &error);
  if (self->status_notifier_watcher_node_info == nullptr) {
    g_warning("Failed to parse StatusNotifierWatcher introspection: %s",
              error == nullptr ? "unknown error" : error->message);
    return;
  }

  static const GDBusInterfaceVTable watcher_vtable = {
      status_notifier_watcher_method_call, status_notifier_watcher_get_property,
      nullptr};

  GDBusInterfaceInfo* kde_interface_info = g_dbus_node_info_lookup_interface(
      self->status_notifier_watcher_node_info,
      kStatusNotifierWatcherKdeInterface);
  self->status_notifier_watcher_kde_registration_id = g_dbus_connection_register_object(
      self->session_bus, kStatusNotifierWatcherPath, kde_interface_info,
      &watcher_vtable, self, nullptr, &error);
  if (self->status_notifier_watcher_kde_registration_id == 0) {
    g_warning("Failed to register KDE StatusNotifierWatcher object: %s",
              error == nullptr ? "unknown error" : error->message);
    return;
  }

  GDBusInterfaceInfo* freedesktop_interface_info = g_dbus_node_info_lookup_interface(
      self->status_notifier_watcher_node_info,
      kStatusNotifierWatcherFreedesktopInterface);
  self->status_notifier_watcher_freedesktop_registration_id =
      g_dbus_connection_register_object(
          self->session_bus, kStatusNotifierWatcherPath,
          freedesktop_interface_info, &watcher_vtable, self, nullptr, &error);
  if (self->status_notifier_watcher_freedesktop_registration_id == 0) {
    g_warning("Failed to register freedesktop StatusNotifierWatcher object: %s",
              error == nullptr ? "unknown error" : error->message);
  }

  self->status_notifier_watcher_kde_owner_id = g_bus_own_name_on_connection(
      self->session_bus, kStatusNotifierWatcherKdeBusName,
      G_BUS_NAME_OWNER_FLAGS_REPLACE, nullptr, nullptr, nullptr, nullptr);
  self->status_notifier_watcher_freedesktop_owner_id = g_bus_own_name_on_connection(
      self->session_bus, kStatusNotifierWatcherFreedesktopBusName,
      G_BUS_NAME_OWNER_FLAGS_REPLACE, nullptr, nullptr, nullptr, nullptr);

  self->status_notifier_host_registered = TRUE;
  emit_status_notifier_host_signal(self, "StatusNotifierHostRegistered");
}

static void stop_status_notifier_watcher(MyApplication* self) {
  if (self->status_notifier_host_registered) {
    emit_status_notifier_host_signal(self, "StatusNotifierHostUnregistered");
    self->status_notifier_host_registered = FALSE;
  }
  if (self->status_notifier_watcher_kde_owner_id != 0) {
    g_bus_unown_name(self->status_notifier_watcher_kde_owner_id);
    self->status_notifier_watcher_kde_owner_id = 0;
  }
  if (self->status_notifier_watcher_freedesktop_owner_id != 0) {
    g_bus_unown_name(self->status_notifier_watcher_freedesktop_owner_id);
    self->status_notifier_watcher_freedesktop_owner_id = 0;
  }
  if (self->session_bus != nullptr) {
    if (self->status_notifier_watcher_kde_registration_id != 0) {
      g_dbus_connection_unregister_object(
          self->session_bus, self->status_notifier_watcher_kde_registration_id);
      self->status_notifier_watcher_kde_registration_id = 0;
    }
    if (self->status_notifier_watcher_freedesktop_registration_id != 0) {
      g_dbus_connection_unregister_object(
          self->session_bus,
          self->status_notifier_watcher_freedesktop_registration_id);
      self->status_notifier_watcher_freedesktop_registration_id = 0;
    }
  }
  if (self->status_notifier_registered_items != nullptr) {
    g_hash_table_remove_all(self->status_notifier_registered_items);
  }
  if (self->status_notifier_watcher_node_info != nullptr) {
    g_dbus_node_info_unref(self->status_notifier_watcher_node_info);
    self->status_notifier_watcher_node_info = nullptr;
  }
}

static void on_dbus_properties_changed(GDBusConnection* connection,
                                       const gchar* sender_name,
                                       const gchar* object_path,
                                       const gchar* interface_name,
                                       const gchar* signal_name,
                                       GVariant* parameters,
                                       gpointer user_data) {
  const gchar* changed_interface = nullptr;
  if (parameters != nullptr && g_variant_n_children(parameters) > 0) {
    g_variant_get_child(parameters, 0, "&s", &changed_interface);
  }

  const gboolean tray_change =
      is_tray_dbus_name(sender_name) ||
      g_strcmp0(changed_interface, kStatusNotifierItemKdeInterface) == 0 ||
      g_strcmp0(changed_interface, kStatusNotifierItemFreedesktopInterface) == 0;
  if (tray_change) {
    alice_platform_clear_tray_cache();
  }

  if (is_relevant_dbus_name(sender_name) ||
      g_strcmp0(changed_interface, kStatusNotifierItemKdeInterface) == 0 ||
      g_strcmp0(changed_interface, kStatusNotifierItemFreedesktopInterface) == 0) {
    schedule_snapshot(MY_APPLICATION(user_data));
  }
}

static void on_name_owner_changed(GDBusConnection* connection,
                                  const gchar* sender_name,
                                  const gchar* object_path,
                                  const gchar* interface_name,
                                  const gchar* signal_name,
                                  GVariant* parameters,
                                  gpointer user_data) {
  const gchar* name = nullptr;
  const gchar* old_owner = nullptr;
  const gchar* new_owner = nullptr;
  g_variant_get(parameters, "(&s&s&s)", &name, &old_owner, &new_owner);
  MyApplication* self = MY_APPLICATION(user_data);
  if (name != nullptr && old_owner != nullptr && old_owner[0] != '\0' &&
      new_owner != nullptr && new_owner[0] == '\0') {
    if (remove_registered_status_notifier_items_for_service(self, name)) {
      alice_platform_clear_tray_cache();
      schedule_snapshot(self);
    }
  }
  if (is_tray_dbus_name(name)) {
    alice_platform_clear_tray_cache();
  }
  if (is_relevant_dbus_name(name)) {
    schedule_snapshot(self);
  }
}

static void start_dbus_subscriptions(MyApplication* self) {
  if (self->session_bus != nullptr) {
    return;
  }

  g_autoptr(GError) error = nullptr;
  self->session_bus = g_bus_get_sync(G_BUS_TYPE_SESSION, nullptr, &error);
  if (self->session_bus == nullptr) {
    g_warning("Failed to connect to session bus: %s",
              error == nullptr ? "unknown error" : error->message);
    return;
  }

  self->mpris_properties_changed_id = g_dbus_connection_signal_subscribe(
      self->session_bus, nullptr, "org.freedesktop.DBus.Properties",
      "PropertiesChanged", "/org/mpris/MediaPlayer2", nullptr,
      G_DBUS_SIGNAL_FLAGS_NONE, on_dbus_properties_changed, self, nullptr);
  self->tray_item_properties_changed_id = g_dbus_connection_signal_subscribe(
      self->session_bus, nullptr, "org.freedesktop.DBus.Properties",
      "PropertiesChanged", nullptr, nullptr,
      G_DBUS_SIGNAL_FLAGS_NONE, on_dbus_properties_changed, self, nullptr);

  self->name_owner_changed_id = g_dbus_connection_signal_subscribe(
      self->session_bus, "org.freedesktop.DBus", "org.freedesktop.DBus",
      "NameOwnerChanged", "/org/freedesktop/DBus", nullptr,
      G_DBUS_SIGNAL_FLAGS_NONE, on_name_owner_changed, self, nullptr);
  ensure_status_notifier_watcher(self);
}

static void stop_dbus_subscriptions(MyApplication* self) {
  if (self->session_bus == nullptr) {
    return;
  }

  if (self->mpris_properties_changed_id != 0) {
    g_dbus_connection_signal_unsubscribe(self->session_bus,
                                         self->mpris_properties_changed_id);
    self->mpris_properties_changed_id = 0;
  }
  if (self->tray_item_properties_changed_id != 0) {
    g_dbus_connection_signal_unsubscribe(self->session_bus,
                                         self->tray_item_properties_changed_id);
    self->tray_item_properties_changed_id = 0;
  }
  if (self->name_owner_changed_id != 0) {
    g_dbus_connection_signal_unsubscribe(self->session_bus,
                                         self->name_owner_changed_id);
    self->name_owner_changed_id = 0;
  }

  stop_status_notifier_watcher(self);
  g_clear_object(&self->session_bus);
}

static void on_net_file_changed(GFileMonitor* monitor, GFile* file,
                                GFile* other_file, GFileMonitorEvent event_type,
                                gpointer user_data) {
  schedule_snapshot(MY_APPLICATION(user_data));
}

static void refresh_network_monitors(MyApplication* self) {
  if (self->net_file_monitors == nullptr) {
    return;
  }

  g_hash_table_remove_all(self->net_file_monitors);
  g_autoptr(GError) error = nullptr;
  GDir* dir = g_dir_open("/sys/class/net", 0, &error);
  if (dir == nullptr) {
    g_warning("Failed to open /sys/class/net: %s",
              error == nullptr ? "unknown error" : error->message);
    return;
  }

  const gchar* name = nullptr;
  while ((name = g_dir_read_name(dir)) != nullptr) {
    if (g_strcmp0(name, "lo") == 0) {
      continue;
    }
    g_autofree gchar* path =
        g_build_filename("/sys/class/net", name, "operstate", nullptr);
    g_autoptr(GFile) file = g_file_new_for_path(path);
    g_autoptr(GError) monitor_error = nullptr;
    GFileMonitor* monitor =
        g_file_monitor_file(file, G_FILE_MONITOR_NONE, nullptr, &monitor_error);
    if (monitor == nullptr) {
      continue;
    }
    g_signal_connect(monitor, "changed", G_CALLBACK(on_net_file_changed), self);
    g_hash_table_insert(self->net_file_monitors, g_strdup(path), monitor);
  }
  g_dir_close(dir);
}

static void on_net_dir_changed(GFileMonitor* monitor, GFile* file,
                               GFile* other_file, GFileMonitorEvent event_type,
                               gpointer user_data) {
  MyApplication* self = MY_APPLICATION(user_data);
  refresh_network_monitors(self);
  schedule_snapshot(self);
}

static void start_network_monitors(MyApplication* self) {
  if (self->net_dir_monitor != nullptr) {
    return;
  }

  g_autoptr(GFile) net_dir = g_file_new_for_path("/sys/class/net");
  g_autoptr(GError) error = nullptr;
  self->net_dir_monitor =
      g_file_monitor_directory(net_dir, G_FILE_MONITOR_NONE, nullptr, &error);
  if (self->net_dir_monitor == nullptr) {
    g_warning("Failed to monitor /sys/class/net: %s",
              error == nullptr ? "unknown error" : error->message);
    return;
  }

  g_signal_connect(self->net_dir_monitor, "changed",
                   G_CALLBACK(on_net_dir_changed), self);
  refresh_network_monitors(self);
}

static void stop_network_monitors(MyApplication* self) {
  g_clear_object(&self->net_dir_monitor);
  if (self->net_file_monitors != nullptr) {
    g_hash_table_remove_all(self->net_file_monitors);
  }
}

static void on_sway_process_exit(GPid pid, gint status, gpointer user_data) {
  MyApplication* self = MY_APPLICATION(user_data);
  if (self->sway_pid == pid) {
    g_spawn_close_pid(self->sway_pid);
    self->sway_pid = 0;
  } else {
    g_spawn_close_pid(pid);
  }
}

static gboolean on_sway_stdout_ready(GIOChannel* source,
                                     GIOCondition condition,
                                     gpointer user_data) {
  MyApplication* self = MY_APPLICATION(user_data);
  if (condition & (G_IO_HUP | G_IO_ERR | G_IO_NVAL)) {
    return G_SOURCE_REMOVE;
  }

  g_autoptr(GError) error = nullptr;
  g_autofree gchar* line = nullptr;
  gsize length = 0;
  GIOStatus status = g_io_channel_read_line(source, &line, &length, nullptr,
                                            &error);
  if (status == G_IO_STATUS_NORMAL && length > 0) {
    schedule_snapshot(self);
  }

  return G_SOURCE_CONTINUE;
}

static void start_sway_subscription(MyApplication* self) {
  if (self->sway_pid != 0) {
    return;
  }

  g_autofree gchar* swaymsg = g_find_program_in_path("swaymsg");
  if (swaymsg == nullptr) {
    g_warning("swaymsg not found; workspace events will be delayed");
    return;
  }

  gchar* argv[] = {const_cast<gchar*>(swaymsg),
                   const_cast<gchar*>("-t"),
                   const_cast<gchar*>("subscribe"),
                   const_cast<gchar*>("[\"workspace\"]"),
                   nullptr};
  g_autoptr(GError) error = nullptr;
  gint stdout_fd = -1;
  gint stderr_fd = -1;
  if (!g_spawn_async_with_pipes(nullptr, argv, nullptr,
                                static_cast<GSpawnFlags>(
                                    G_SPAWN_DO_NOT_REAP_CHILD |
                                    G_SPAWN_SEARCH_PATH),
                                nullptr, nullptr, &self->sway_pid, nullptr,
                                &stdout_fd, &stderr_fd, &error)) {
    g_warning("Failed to start swaymsg subscription: %s",
              error == nullptr ? "unknown error" : error->message);
    self->sway_pid = 0;
    return;
  }

  if (stderr_fd >= 0) {
    close(stderr_fd);
  }

  self->sway_stdout_channel = g_io_channel_unix_new(stdout_fd);
  g_io_channel_set_close_on_unref(self->sway_stdout_channel, TRUE);
  g_io_channel_set_encoding(self->sway_stdout_channel, nullptr, nullptr);
  g_io_channel_set_flags(self->sway_stdout_channel, G_IO_FLAG_NONBLOCK, nullptr);
  self->sway_stdout_watch_id =
      g_io_add_watch(self->sway_stdout_channel, static_cast<GIOCondition>(
                                                   G_IO_IN | G_IO_HUP | G_IO_ERR |
                                                   G_IO_NVAL),
                     on_sway_stdout_ready, self);
  g_child_watch_add(self->sway_pid, on_sway_process_exit, self);
}

static void stop_sway_subscription(MyApplication* self) {
  if (self->sway_stdout_watch_id != 0) {
    g_source_remove(self->sway_stdout_watch_id);
    self->sway_stdout_watch_id = 0;
  }
  if (self->sway_stdout_channel != nullptr) {
    g_io_channel_shutdown(self->sway_stdout_channel, TRUE, nullptr);
    g_io_channel_unref(self->sway_stdout_channel);
    self->sway_stdout_channel = nullptr;
  }
  if (self->sway_pid != 0) {
    kill(self->sway_pid, SIGTERM);
    g_spawn_close_pid(self->sway_pid);
    self->sway_pid = 0;
  }
}

static void start_event_sources(MyApplication* self) {
  if (self->stats_timer_id == 0) {
    self->stats_timer_id =
        g_timeout_add_seconds(kStatsIntervalSeconds, stats_tick, self);
  }
  if (self->clock_timer_id == 0) {
    self->clock_timer_id =
        g_timeout_add_seconds(kClockIntervalSeconds, clock_tick, self);
  }
  start_dbus_subscriptions(self);
  start_network_monitors(self);
  start_sway_subscription(self);
  schedule_snapshot(self);
}

static void stop_event_sources(MyApplication* self) {
  if (self->stats_timer_id != 0) {
    g_source_remove(self->stats_timer_id);
    self->stats_timer_id = 0;
  }
  if (self->clock_timer_id != 0) {
    g_source_remove(self->clock_timer_id);
    self->clock_timer_id = 0;
  }
  if (self->snapshot_debounce_id != 0) {
    g_source_remove(self->snapshot_debounce_id);
    self->snapshot_debounce_id = 0;
  }
  stop_dbus_subscriptions(self);
  stop_network_monitors(self);
  stop_sway_subscription(self);
}

static FlMethodErrorResponse* platform_listen_cb(FlEventChannel* channel,
                                                 FlValue* args,
                                                 gpointer user_data) {
  MyApplication* self = MY_APPLICATION(user_data);
  self->event_stream_active = TRUE;
  start_event_sources(self);
  return nullptr;
}

static FlMethodErrorResponse* platform_cancel_cb(FlEventChannel* channel,
                                                 FlValue* args,
                                                 gpointer user_data) {
  MyApplication* self = MY_APPLICATION(user_data);
  self->event_stream_active = FALSE;
  stop_event_sources(self);
  return nullptr;
}

static void platform_method_call_cb(FlMethodChannel* channel,
                                    FlMethodCall* method_call,
                                    gpointer user_data) {
  MyApplication* self = MY_APPLICATION(user_data);
  const gchar* method = fl_method_call_get_name(method_call);
  FlValue* args = fl_method_call_get_args(method_call);

  g_autoptr(FlMethodResponse) response = nullptr;
  if (strcmp(method, "loadConfig") == 0) {
    response =
        FL_METHOD_RESPONSE(fl_method_success_response_new(build_config_value()));
  } else if (strcmp(method, "showPanel") == 0) {
    gboolean ok = FALSE;
    if (!self->is_panel_process && args != nullptr) {
      FlValue* panel_id = fl_value_lookup_string(args, "panelId");
      if (panel_id != nullptr) {
        const gchar* panel = fl_value_get_string(panel_id);
        FlValue* anchor_x_value = fl_value_lookup_string(args, "anchorX");
        FlValue* anchor_y_value = fl_value_lookup_string(args, "anchorY");
        FlValue* alignment_value = fl_value_lookup_string(args, "alignment");
        FlValue* width_value = fl_value_lookup_string(args, "width");
        FlValue* height_value = fl_value_lookup_string(args, "height");
        const double anchor_x =
            anchor_x_value == nullptr ? 0.0 : fl_value_get_float(anchor_x_value);
        const double anchor_y =
            anchor_y_value == nullptr ? 0.0 : fl_value_get_float(anchor_y_value);
        const double width =
            width_value == nullptr ? 0.0 : fl_value_get_float(width_value);
        const double height =
            height_value == nullptr ? 0.0 : fl_value_get_float(height_value);
        const gchar* alignment =
            alignment_value == nullptr ? "right" : fl_value_get_string(alignment_value);
        gchar* command = g_strdup_printf("show:%s:%s:%.1f:%.1f:%.1f:%.1f\n",
                                         panel, alignment, anchor_x, anchor_y,
                                         width, height);
        ok = send_panel_command(self, command);
        g_free(command);
      }
    }
    response = ok
        ? FL_METHOD_RESPONSE(fl_method_success_response_new(fl_value_new_null()))
        : FL_METHOD_RESPONSE(fl_method_error_response_new(
              "panel_spawn_failed", "Failed to show panel", nullptr));
  } else if (strcmp(method, "hidePanel") == 0) {
    if (self->is_panel_process) {
      clear_panel_state(self);
      apply_panel_visibility(self);
    } else {
      send_panel_command(self, "hide\n");
    }
    response =
        FL_METHOD_RESPONSE(fl_method_success_response_new(fl_value_new_null()));
  } else if (strcmp(method, "sendMediaAction") == 0) {
    FlValue* action = args == nullptr ? nullptr : fl_value_lookup_string(args, "action");
    const gchar* action_name = action == nullptr ? nullptr : fl_value_get_string(action);
    if (action_name != nullptr && alice_platform_send_media_action(action_name)) {
      response = FL_METHOD_RESPONSE(
          fl_method_success_response_new(fl_value_new_null()));
    } else {
      response = FL_METHOD_RESPONSE(fl_method_error_response_new(
          "media_action_failed", "Failed to send media action", nullptr));
    }
  } else if (strcmp(method, "sendTrayAction") == 0) {
    FlValue* service_name_value =
        args == nullptr ? nullptr : fl_value_lookup_string(args, "serviceName");
    FlValue* object_path_value =
        args == nullptr ? nullptr : fl_value_lookup_string(args, "objectPath");
    FlValue* action_value =
        args == nullptr ? nullptr : fl_value_lookup_string(args, "action");
    FlValue* x_value = args == nullptr ? nullptr : fl_value_lookup_string(args, "x");
    FlValue* y_value = args == nullptr ? nullptr : fl_value_lookup_string(args, "y");
    const gchar* service_name =
        service_name_value == nullptr ? nullptr : fl_value_get_string(service_name_value);
    const gchar* object_path =
        object_path_value == nullptr ? nullptr : fl_value_get_string(object_path_value);
    const gchar* action_name =
        action_value == nullptr ? nullptr : fl_value_get_string(action_value);
    const gint x = x_value == nullptr ? 0 : static_cast<gint>(fl_value_get_int(x_value));
    const gint y = y_value == nullptr ? 0 : static_cast<gint>(fl_value_get_int(y_value));
    if (service_name != nullptr && object_path != nullptr && action_name != nullptr &&
        alice_platform_send_tray_action(service_name, object_path, action_name, x, y)) {
      response = FL_METHOD_RESPONSE(
          fl_method_success_response_new(fl_value_new_null()));
    } else {
      response = FL_METHOD_RESPONSE(fl_method_error_response_new(
          "tray_action_failed", "Failed to send tray action", nullptr));
    }
  } else if (strcmp(method, "executePowerAction") == 0) {
    FlValue* action = args == nullptr ? nullptr : fl_value_lookup_string(args, "action");
    const gchar* action_name = action == nullptr ? nullptr : fl_value_get_string(action);
    if (action_name != nullptr && execute_command_for_action(action_name)) {
      response = FL_METHOD_RESPONSE(
          fl_method_success_response_new(fl_value_new_null()));
    } else {
      response = FL_METHOD_RESPONSE(fl_method_error_response_new(
          "power_action_failed", "Failed to execute power action", nullptr));
    }
  } else if (strcmp(method, "focusWorkspace") == 0) {
    FlValue* label = args == nullptr ? nullptr : fl_value_lookup_string(args, "label");
    const gchar* label_text = label == nullptr ? nullptr : fl_value_get_string(label);
    if (label_text != nullptr && alice_platform_focus_workspace(label_text)) {
      if (self->event_stream_active && self->event_channel != nullptr) {
        g_autoptr(GError) snapshot_error = nullptr;
        if (!fl_event_channel_send(self->event_channel,
                                   build_snapshot_value(self, self->panel_id), nullptr,
                                   &snapshot_error)) {
          g_warning("Failed to send snapshot: %s", snapshot_error->message);
        }
      }
      response = FL_METHOD_RESPONSE(
          fl_method_success_response_new(fl_value_new_null()));
    } else {
      response = FL_METHOD_RESPONSE(fl_method_error_response_new(
          "focus_workspace_failed", "Failed to focus workspace", nullptr));
    }
  } else {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }

  g_autoptr(GError) error = nullptr;
  if (!fl_method_call_respond(method_call, response, &error)) {
    g_warning("Failed to send method response: %s", error->message);
  }
}

static void setup_platform_channels(MyApplication* self, FlView* view) {
  FlBinaryMessenger* messenger =
      fl_engine_get_binary_messenger(fl_view_get_engine(view));
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();

  self->platform_channel = fl_method_channel_new(messenger, kPlatformChannelName,
                                                 FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(self->platform_channel,
                                            platform_method_call_cb,
                                            g_object_ref(self),
                                            g_object_unref);

  self->event_channel =
      fl_event_channel_new(messenger, kEventChannelName, FL_METHOD_CODEC(codec));
  fl_event_channel_set_stream_handlers(self->event_channel, platform_listen_cb,
                                       platform_cancel_cb, g_object_ref(self),
                                       g_object_unref);
}

static char** build_dart_entrypoint_arguments(MyApplication* self) {
  g_autoptr(GPtrArray) args =
      g_ptr_array_new_with_free_func(reinterpret_cast<GDestroyNotify>(g_free));

  if (self->dart_entrypoint_arguments != nullptr) {
    for (gint index = 0; self->dart_entrypoint_arguments[index] != nullptr; index++) {
      const gchar* arg = self->dart_entrypoint_arguments[index];
      if (g_str_has_prefix(arg, "--alice-window=") ||
          g_str_has_prefix(arg, "--alice-panel-socket=")) {
        continue;
      }
      g_ptr_array_add(args, g_strdup(arg));
    }
  }

  if (self->is_panel_process) {
    g_ptr_array_add(args, g_strdup(kPanelWindowArgument));
  } else {
    g_ptr_array_add(args, g_strdup(kBarWindowArgument));
  }

  g_ptr_array_add(args, nullptr);
  return reinterpret_cast<gchar**>(g_ptr_array_free(g_steal_pointer(&args), FALSE));
}

static void configure_layer_shell_panel_window(GtkWindow* window) {
  AliceSurfacePlacementFFI placement = alice_layer_shell_panel_placement();
  GdkDisplay* display = gdk_display_get_default();
  GdkMonitor* monitor =
      display == nullptr ? nullptr : gdk_display_get_primary_monitor(display);

  gtk_layer_init_for_window(window);
  gtk_layer_set_namespace(window, "alice-panel");
  gtk_layer_set_layer(window, GTK_LAYER_SHELL_LAYER_OVERLAY);
  gtk_layer_set_keyboard_mode(window, GTK_LAYER_SHELL_KEYBOARD_MODE_NONE);
  gtk_layer_set_anchor(window, GTK_LAYER_SHELL_EDGE_TOP, TRUE);
  gtk_layer_set_anchor(window, GTK_LAYER_SHELL_EDGE_RIGHT, TRUE);
  gtk_layer_set_anchor(window, GTK_LAYER_SHELL_EDGE_LEFT, FALSE);
  gtk_layer_set_anchor(window, GTK_LAYER_SHELL_EDGE_BOTTOM, FALSE);
  gtk_layer_set_margin(window, GTK_LAYER_SHELL_EDGE_TOP, 0);
  gtk_layer_set_margin(window, GTK_LAYER_SHELL_EDGE_RIGHT, 0);
  gtk_layer_set_margin(window, GTK_LAYER_SHELL_EDGE_LEFT, 0);
  gtk_layer_set_margin(window, GTK_LAYER_SHELL_EDGE_BOTTOM, 0);
  gtk_layer_set_exclusive_zone(window, 0);
  gtk_layer_set_respect_close(window, TRUE);
  if (monitor != nullptr) {
    gtk_layer_set_monitor(window, monitor);
  }

  gtk_widget_set_size_request(GTK_WIDGET(window), static_cast<gint>(placement.width),
                              static_cast<gint>(placement.height));
  gtk_window_set_default_size(window, static_cast<gint>(placement.width),
                              static_cast<gint>(placement.height));
  gtk_window_set_resizable(window, FALSE);
  gtk_window_set_decorated(window, FALSE);
  gtk_window_set_skip_taskbar_hint(window, TRUE);
  gtk_window_set_skip_pager_hint(window, TRUE);
  gtk_window_set_accept_focus(window, FALSE);
}

static void configure_layer_shell_dismiss_window(GtkWindow* window) {
  GdkDisplay* display = gdk_display_get_default();
  GdkMonitor* monitor =
      display == nullptr ? nullptr : gdk_display_get_primary_monitor(display);

  gtk_layer_init_for_window(window);
  gtk_layer_set_namespace(window, "alice-panel-dismiss");
  gtk_layer_set_layer(window, GTK_LAYER_SHELL_LAYER_TOP);
  gtk_layer_set_keyboard_mode(window, GTK_LAYER_SHELL_KEYBOARD_MODE_NONE);
  gtk_layer_set_anchor(window, GTK_LAYER_SHELL_EDGE_TOP, TRUE);
  gtk_layer_set_anchor(window, GTK_LAYER_SHELL_EDGE_RIGHT, TRUE);
  gtk_layer_set_anchor(window, GTK_LAYER_SHELL_EDGE_LEFT, TRUE);
  gtk_layer_set_anchor(window, GTK_LAYER_SHELL_EDGE_BOTTOM, TRUE);
  gtk_layer_set_margin(window, GTK_LAYER_SHELL_EDGE_TOP, 0);
  gtk_layer_set_margin(window, GTK_LAYER_SHELL_EDGE_RIGHT, 0);
  gtk_layer_set_margin(window, GTK_LAYER_SHELL_EDGE_LEFT, 0);
  gtk_layer_set_margin(window, GTK_LAYER_SHELL_EDGE_BOTTOM, 0);
  gtk_layer_set_exclusive_zone(window, 0);
  gtk_layer_set_respect_close(window, TRUE);
  if (monitor != nullptr) {
    gtk_layer_set_monitor(window, monitor);
  }

  gtk_window_set_resizable(window, FALSE);
  gtk_window_set_decorated(window, FALSE);
  gtk_window_set_skip_taskbar_hint(window, TRUE);
  gtk_window_set_skip_pager_hint(window, TRUE);
  gtk_window_set_accept_focus(window, FALSE);
}

static void configure_panel_fallback_window(GtkWindow* window) {
  AliceSurfacePlacementFFI placement = alice_layer_shell_panel_placement();
  gtk_window_set_default_size(window, static_cast<gint>(placement.width),
                              static_cast<gint>(placement.height));
  gtk_window_set_resizable(window, FALSE);
  gtk_window_set_decorated(window, FALSE);
  gtk_window_set_skip_taskbar_hint(window, TRUE);
  gtk_window_set_skip_pager_hint(window, TRUE);
  gtk_window_set_keep_above(window, TRUE);
  gtk_window_set_accept_focus(window, FALSE);
}

static void first_frame_panel_cb(MyApplication* self) {
  self->panel_first_frame_received = TRUE;
  apply_panel_visibility(self);
}

static void create_main_window(MyApplication* self) {
  GtkWindow* window =
      GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(self)));
  self->window = window;
  if (self->is_panel_process) {
    self->dismiss_window =
        GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(self)));
    gtk_widget_set_app_paintable(GTK_WIDGET(window), TRUE);
    GdkScreen* rgba_screen = gtk_window_get_screen(window);
    if (rgba_screen != nullptr) {
      GdkVisual* visual = gdk_screen_get_rgba_visual(rgba_screen);
      if (visual != nullptr) {
        gtk_widget_set_visual(GTK_WIDGET(window), visual);
        gtk_widget_set_app_paintable(GTK_WIDGET(self->dismiss_window), TRUE);
        gtk_widget_set_visual(GTK_WIDGET(self->dismiss_window), visual);
      }
    }
    g_signal_connect(window, "delete-event",
                     G_CALLBACK(panel_window_delete_event), self);
    g_signal_connect(self->dismiss_window, "button-press-event",
                     G_CALLBACK(dismiss_window_button_press_event), self);
    gtk_widget_add_events(GTK_WIDGET(self->dismiss_window), GDK_BUTTON_PRESS_MASK);
  }

  gboolean use_header_bar = !self->is_panel_process;
#ifdef GDK_WINDOWING_X11
  GdkScreen* screen = gtk_window_get_screen(window);
  if (!self->is_panel_process && GDK_IS_X11_SCREEN(screen)) {
    const gchar* wm_name = gdk_x11_screen_get_window_manager_name(screen);
    if (g_strcmp0(wm_name, "GNOME Shell") != 0) {
      use_header_bar = FALSE;
    }
  }
#endif

  if (self->is_panel_process) {
    gtk_window_set_title(window, "alice-panel");
    gtk_window_set_title(self->dismiss_window, "alice-panel-dismiss");
    if (self->layer_shell_supported && gtk_layer_is_supported()) {
      configure_layer_shell_dismiss_window(self->dismiss_window);
      configure_layer_shell_panel_window(window);
    } else {
      configure_panel_fallback_window(window);
    }
  } else if (self->layer_shell_supported) {
    AliceSurfacePlacementFFI bar_placement = alice_layer_shell_bar_placement();
    g_message("Layer-shell support detected; target bar height is %u px",
              bar_placement.height);
    if (gtk_layer_is_supported()) {
      configure_layer_shell_bar_window(window);
    } else {
      g_warning("Rust layer-shell probe succeeded but gtk-layer-shell is unavailable; using GTK fallback window");
      configure_bar_fallback_window(window);
    }
    use_header_bar = FALSE;
  } else {
    g_message("Layer-shell support not detected; using GTK window fallback");
    gtk_window_set_default_size(window, 1280, 720);
  }

  if (use_header_bar) {
    GtkHeaderBar* header_bar = GTK_HEADER_BAR(gtk_header_bar_new());
    gtk_widget_show(GTK_WIDGET(header_bar));
    gtk_header_bar_set_title(header_bar, "alice");
    gtk_header_bar_set_show_close_button(header_bar, TRUE);
    gtk_window_set_titlebar(window, GTK_WIDGET(header_bar));
  } else if (!self->is_panel_process) {
    gtk_window_set_title(window, "alice");
  }

  g_autoptr(FlDartProject) project = fl_dart_project_new();
  g_auto(GStrv) dart_entrypoint_arguments = build_dart_entrypoint_arguments(self);
  fl_dart_project_set_dart_entrypoint_arguments(project, dart_entrypoint_arguments);

  FlView* view = fl_view_new(project);
  GdkRGBA background_color;
  gdk_rgba_parse(&background_color,
                 self->is_panel_process ? "rgba(0,0,0,0)" : "#000000");
  fl_view_set_background_color(view, &background_color);
  gtk_widget_set_hexpand(GTK_WIDGET(view), TRUE);
  gtk_widget_set_vexpand(GTK_WIDGET(view), TRUE);

  gint initial_width = self->is_panel_process ? 320 : 1280;
  gint initial_height = self->is_panel_process ? 220 : 44;
  if (!self->is_panel_process && self->layer_shell_supported) {
    GdkDisplay* display = gdk_display_get_default();
    if (display != nullptr) {
      GdkMonitor* monitor = gdk_display_get_primary_monitor(display);
      if (monitor != nullptr) {
        GdkRectangle geometry;
        gdk_monitor_get_geometry(monitor, &geometry);
        initial_width = geometry.width;
      }
    }
  }
  gtk_widget_set_size_request(GTK_WIDGET(view), initial_width, initial_height);
  gtk_widget_show(GTK_WIDGET(view));
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));
  gtk_widget_realize(GTK_WIDGET(view));

  fl_register_plugins(FL_PLUGIN_REGISTRY(view));
  setup_platform_channels(self, view);

  if (self->is_panel_process) {
    GtkWidget* dismiss_box = gtk_event_box_new();
    gtk_widget_set_app_paintable(dismiss_box, TRUE);
    gtk_container_add(GTK_CONTAINER(self->dismiss_window), dismiss_box);
    gtk_widget_show(dismiss_box);
    g_signal_connect_swapped(view, "first-frame", G_CALLBACK(first_frame_panel_cb),
                             self);
    gtk_widget_hide(GTK_WIDGET(self->dismiss_window));
    gtk_widget_hide(GTK_WIDGET(window));
  } else {
    gtk_widget_show_all(GTK_WIDGET(window));
    gtk_widget_grab_focus(GTK_WIDGET(view));
  }
}

static void my_application_activate(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);
  AliceLayerShellCapabilitiesFFI layer_shell =
      alice_layer_shell_detect_capabilities();
  self->layer_shell_supported = layer_shell.layer_shell_supported;
  create_main_window(self);
  if (!self->is_panel_process) {
    ensure_panel_process_running(self);
  } else {
    configure_panel_parent_lifecycle(self);
    start_panel_socket_service(self);
  }
}

static gboolean my_application_local_command_line(GApplication* application,
                                                  gchar*** arguments,
                                                  int* exit_status) {
  MyApplication* self = MY_APPLICATION(application);
  self->dart_entrypoint_arguments = g_strdupv(*arguments + 1);

  for (gint index = 1; (*arguments)[index] != nullptr; index++) {
    const gchar* arg = (*arguments)[index];
    if (g_strcmp0(arg, kPanelWindowArgument) == 0) {
      self->is_panel_process = TRUE;
    } else if (g_str_has_prefix(arg, "--alice-panel-socket=")) {
      g_free(self->panel_socket_path);
      self->panel_socket_path = g_strdup(arg + strlen("--alice-panel-socket="));
    } else if (g_str_has_prefix(arg, "--alice-parent-pid=")) {
      self->parent_pid =
          static_cast<pid_t>(g_ascii_strtoll(arg + strlen("--alice-parent-pid="),
                                             nullptr, 10));
    }
  }

  g_autoptr(GError) error = nullptr;
  if (!g_application_register(application, nullptr, &error)) {
    g_warning("Failed to register: %s", error->message);
    *exit_status = 1;
    return TRUE;
  }

  g_application_activate(application);
  *exit_status = 0;
  return TRUE;
}

static void my_application_startup(GApplication* application) {
  G_APPLICATION_CLASS(my_application_parent_class)->startup(application);
}

static void my_application_shutdown(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);
  stop_event_sources(self);
  if (self->panel_socket_service != nullptr) {
    g_socket_service_stop(self->panel_socket_service);
  }
  if (self->is_panel_process) {
    if (self->panel_socket_path != nullptr) {
      g_unlink(self->panel_socket_path);
    }
  } else if (self->panel_pid != 0) {
    kill(self->panel_pid, SIGTERM);
    clear_panel_process(self);
  }
  G_APPLICATION_CLASS(my_application_parent_class)->shutdown(application);
}

static void my_application_dispose(GObject* object) {
  MyApplication* self = MY_APPLICATION(object);
  g_clear_pointer(&self->dart_entrypoint_arguments, g_strfreev);
  g_clear_object(&self->platform_channel);
  g_clear_object(&self->event_channel);
  g_clear_object(&self->panel_socket_service);
  stop_status_notifier_watcher(self);
  g_clear_object(&self->session_bus);
  g_clear_object(&self->net_dir_monitor);
  if (self->net_file_monitors != nullptr) {
    g_hash_table_destroy(self->net_file_monitors);
    self->net_file_monitors = nullptr;
  }
  if (self->status_notifier_registered_items != nullptr) {
    g_hash_table_destroy(self->status_notifier_registered_items);
    self->status_notifier_registered_items = nullptr;
  }
  if (self->sway_stdout_watch_id != 0) {
    g_source_remove(self->sway_stdout_watch_id);
    self->sway_stdout_watch_id = 0;
  }
  if (self->sway_stdout_channel != nullptr) {
    g_io_channel_unref(self->sway_stdout_channel);
    self->sway_stdout_channel = nullptr;
  }
  if (self->sway_pid != 0) {
    g_spawn_close_pid(self->sway_pid);
    self->sway_pid = 0;
  }
  g_clear_pointer(&self->panel_id, g_free);
  g_clear_pointer(&self->panel_alignment, g_free);
  g_clear_pointer(&self->panel_socket_path, g_free);
  G_OBJECT_CLASS(my_application_parent_class)->dispose(object);
}

static void my_application_class_init(MyApplicationClass* klass) {
  G_APPLICATION_CLASS(klass)->activate = my_application_activate;
  G_APPLICATION_CLASS(klass)->local_command_line =
      my_application_local_command_line;
  G_APPLICATION_CLASS(klass)->startup = my_application_startup;
  G_APPLICATION_CLASS(klass)->shutdown = my_application_shutdown;
  G_OBJECT_CLASS(klass)->dispose = my_application_dispose;
}

static void my_application_init(MyApplication* self) {
  self->window = nullptr;
  self->dismiss_window = nullptr;
  self->snapshot_debounce_id = 0;
  self->stats_timer_id = 0;
  self->clock_timer_id = 0;
  self->event_stream_active = FALSE;
  self->session_bus = nullptr;
  self->tray_item_properties_changed_id = 0;
  self->mpris_properties_changed_id = 0;
  self->name_owner_changed_id = 0;
  self->status_notifier_watcher_kde_registration_id = 0;
  self->status_notifier_watcher_freedesktop_registration_id = 0;
  self->status_notifier_watcher_kde_owner_id = 0;
  self->status_notifier_watcher_freedesktop_owner_id = 0;
  self->status_notifier_watcher_node_info = nullptr;
  self->status_notifier_registered_items =
      g_hash_table_new_full(g_str_hash, g_str_equal, g_free, nullptr);
  self->status_notifier_host_registered = FALSE;
  self->sway_pid = 0;
  self->sway_stdout_channel = nullptr;
  self->sway_stdout_watch_id = 0;
  self->net_dir_monitor = nullptr;
  self->net_file_monitors = g_hash_table_new_full(
      g_str_hash, g_str_equal, g_free, g_object_unref);
  self->layer_shell_supported = FALSE;
  self->is_panel_process = FALSE;
  self->panel_first_frame_received = FALSE;
  self->parent_pid = 0;
  self->panel_id = nullptr;
  self->panel_anchor_x = 0.0;
  self->panel_anchor_y = 0.0;
  self->panel_width = 0.0;
  self->panel_height = 0.0;
  self->panel_alignment = nullptr;
  self->panel_socket_path = nullptr;
  self->panel_pid = 0;
  self->panel_socket_service = nullptr;
}

MyApplication* my_application_new() {
  g_set_prgname(APPLICATION_ID);
  return MY_APPLICATION(g_object_new(my_application_get_type(),
                                     "application-id", APPLICATION_ID, "flags",
                                     G_APPLICATION_NON_UNIQUE, nullptr));
}
