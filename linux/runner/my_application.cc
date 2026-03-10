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
  FlValue* value = fl_value_new_map();
  fl_value_set_string_take(value, "title", fl_value_new_string(media.title));
  fl_value_set_string_take(value, "artist", fl_value_new_string(media.artist));
  fl_value_set_string_take(value, "positionLabel",
                           fl_value_new_string(media.position_label));
  fl_value_set_string_take(value, "lengthLabel",
                           fl_value_new_string(media.length_label));
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


FlValue* build_tray_item_value(const TrayItemFFI& tray_item) {
  FlValue* value = fl_value_new_map();
  fl_value_set_string_take(value, "id", fl_value_new_string(tray_item.id));
  fl_value_set_string_take(value, "label", fl_value_new_string(tray_item.label));
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
    g_autoptr(GError) error = nullptr;
    spawned = g_spawn_command_line_async(command, &error);
    if (!spawned && error != nullptr) {
      g_warning("Failed to execute power command: %s", error->message);
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
  guint snapshot_timer_id;
  gboolean event_stream_active;
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

static FlValue* build_snapshot_value(const gchar* active_panel_id) {
  AliceSnapshotFFI* snapshot = alice_platform_read_snapshot();
  FlValue* value = fl_value_new_map();

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
                           build_tray_item_value(snapshot->tray_items[index]));
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
  gint margin_top = relative_anchor_y + 8;
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
    if (margin_right + static_cast<gint>(placement.width) > monitor_width) {
      margin_right = MAX(0, monitor_width - static_cast<gint>(placement.width));
    }
  } else {
    margin_left = (monitor_width - static_cast<gint>(placement.width)) / 2;
    margin_left = CLAMP(margin_left, 0,
                        MAX(0, monitor_width - static_cast<gint>(placement.width)));
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
                               build_snapshot_value(self->panel_id), nullptr,
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

static gboolean send_snapshot(gpointer user_data) {
  MyApplication* self = MY_APPLICATION(user_data);
  if (!self->event_stream_active || self->event_channel == nullptr) {
    self->snapshot_timer_id = 0;
    return G_SOURCE_REMOVE;
  }

  g_autoptr(GError) error = nullptr;
  if (!fl_event_channel_send(self->event_channel, build_snapshot_value(self->panel_id),
                             nullptr, &error)) {
    g_warning("Failed to send snapshot: %s", error->message);
  }

  return G_SOURCE_CONTINUE;
}

static FlMethodErrorResponse* platform_listen_cb(FlEventChannel* channel,
                                                 FlValue* args,
                                                 gpointer user_data) {
  MyApplication* self = MY_APPLICATION(user_data);
  self->event_stream_active = TRUE;
  if (self->snapshot_timer_id == 0) {
    self->snapshot_timer_id = g_timeout_add_seconds(1, send_snapshot, self);
  }
  send_snapshot(self);
  return nullptr;
}

static FlMethodErrorResponse* platform_cancel_cb(FlEventChannel* channel,
                                                 FlValue* args,
                                                 gpointer user_data) {
  MyApplication* self = MY_APPLICATION(user_data);
  self->event_stream_active = FALSE;
  if (self->snapshot_timer_id != 0) {
    g_source_remove(self->snapshot_timer_id);
    self->snapshot_timer_id = 0;
  }
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
  if (self->snapshot_timer_id != 0) {
    g_source_remove(self->snapshot_timer_id);
    self->snapshot_timer_id = 0;
  }
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
  self->snapshot_timer_id = 0;
  self->event_stream_active = FALSE;
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
