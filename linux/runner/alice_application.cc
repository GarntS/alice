#include "alice_application.h"

#include <flutter_linux/flutter_linux.h>
#include <gio/gio.h>
#include <gtk-layer-shell.h>

#include <cstring>

#include "alice_layer_shell_bridge.h"
#include "alice_platform_bridge.h"
#include "flutter/generated_plugin_registrant.h"

namespace {

constexpr char kPlatformChannelName[] = "alice/platform";

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

}  // namespace

// ---------------------------------------------------------------------------
// AlicePanel — one panel window (created lazily on first showPanel call)
// ---------------------------------------------------------------------------

typedef struct _AlicePanel AlicePanel;
typedef struct _AliceApplication AliceApplication;

struct _AlicePanel {
  GtkApplicationWindow* gtk_window;
  FlView*               fl_view;
  int64_t               view_id;
  gchar*                panel_id;
  // Geometry stored on each showPanel call
  gdouble               anchor_x;
  gdouble               anchor_y;
  gdouble               width;
  gdouble               height;
  gchar*                alignment;
  gboolean              include_icon_bytes;
  gint                  panel_top_gap_px;
  // Back-references
  _AliceApplication*    app;
};

struct _AliceNotificationPopup {
  GtkApplicationWindow* gtk_window;
  FlView*               fl_view;
  int64_t               view_id;
  gint                  panel_top_gap_px;
  _AliceApplication*    app;
};

typedef struct _AliceNotificationPopup AliceNotificationPopup;

struct _AliceApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;
  FlMethodChannel* platform_channel;
  GtkWindow* bar_window;
  FlView*    bar_fl_view;
  GHashTable* panels;          // gchar* panel_id → AlicePanel*
  AliceNotificationPopup* notification_popup;
  GtkWindow* dismiss_window;
  gboolean layer_shell_supported;
  gchar* current_panel_id;     // currently shown panel_id (or nullptr)
};

G_DEFINE_TYPE(AliceApplication, alice_application, GTK_TYPE_APPLICATION)

// ---------------------------------------------------------------------------
// Forward declarations
// ---------------------------------------------------------------------------

static void update_panel_window_geometry(AliceApplication* self, AlicePanel* panel);
static void update_notification_popup_geometry(AliceApplication* self,
                                               AliceNotificationPopup* popup);

// ---------------------------------------------------------------------------
// AlicePanel cleanup
// ---------------------------------------------------------------------------

static void alice_panel_free(gpointer data) {
  AlicePanel* panel = static_cast<AlicePanel*>(data);
  g_free(panel->panel_id);
  g_free(panel->alignment);
  g_free(panel);
}

static void alice_notification_popup_free(AliceNotificationPopup* popup) {
  g_free(popup);
}

// ---------------------------------------------------------------------------
// Layer-shell helpers
// ---------------------------------------------------------------------------

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

static void configure_layer_shell_notification_popup_window(GtkWindow* window) {
  AliceSurfacePlacementFFI placement = alice_layer_shell_notification_popup_placement();
  GdkDisplay* display = gdk_display_get_default();
  GdkMonitor* monitor =
      display == nullptr ? nullptr : gdk_display_get_primary_monitor(display);

  gtk_layer_init_for_window(window);
  gtk_layer_set_namespace(window, "alice-notification-popups");
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

  gint initial_height = static_cast<gint>(placement.height);
  if (initial_height <= 0 && monitor != nullptr) {
    GdkRectangle geometry;
    gdk_monitor_get_geometry(monitor, &geometry);
    initial_height = geometry.height;
  }
  if (initial_height <= 0) {
    initial_height = 720;
  }

  gtk_widget_set_size_request(GTK_WIDGET(window), static_cast<gint>(placement.width),
                              initial_height);
  gtk_window_set_default_size(window, static_cast<gint>(placement.width),
                              initial_height);
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

static void configure_notification_popup_fallback_window(GtkWindow* window) {
  AliceSurfacePlacementFFI placement = alice_layer_shell_notification_popup_placement();
  gint initial_height = static_cast<gint>(placement.height);
  GdkDisplay* display = gdk_display_get_default();
  GdkMonitor* monitor = display == nullptr ? nullptr : gdk_display_get_primary_monitor(display);
  if (initial_height <= 0 && monitor != nullptr) {
    GdkRectangle geometry;
    gdk_monitor_get_geometry(monitor, &geometry);
    initial_height = geometry.height;
  }
  if (initial_height <= 0) {
    initial_height = 720;
  }
  gtk_window_set_default_size(window, static_cast<gint>(placement.width),
                              initial_height);
  gtk_window_set_resizable(window, FALSE);
  gtk_window_set_decorated(window, FALSE);
  gtk_window_set_skip_taskbar_hint(window, TRUE);
  gtk_window_set_skip_pager_hint(window, TRUE);
  gtk_window_set_keep_above(window, TRUE);
  gtk_window_set_accept_focus(window, FALSE);
}

// ---------------------------------------------------------------------------
// Panel geometry
// ---------------------------------------------------------------------------

static void update_panel_window_geometry(AliceApplication* self, AlicePanel* panel) {
  GtkWindow* win = GTK_WINDOW(panel->gtk_window);

  AliceSurfacePlacementFFI placement = alice_layer_shell_panel_placement();
  if (panel->width > 0) {
    placement.width = static_cast<uint32_t>(panel->width);
  }
  if (panel->height > 0) {
    placement.height = static_cast<uint32_t>(panel->height);
  }

  GdkDisplay* display = gdk_display_get_default();
  GdkMonitor* monitor = nullptr;
  gint monitor_width = 1280;
  gint monitor_height = 720;
  gint monitor_x = 0;
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
          panel->anchor_x >= geometry.x &&
          panel->anchor_x < geometry.x + geometry.width;
      const gboolean in_y =
          panel->anchor_y >= geometry.y &&
          panel->anchor_y < geometry.y + geometry.height;
      if (in_x && in_y) {
        monitor = candidate;
        monitor_x = geometry.x;
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
      monitor_width = geometry.width;
      monitor_height = geometry.height;
    }
  }

  const gint relative_anchor_x =
      static_cast<gint>(panel->anchor_x) - monitor_x;
  // On wlroots/Sway, layer-shell margins are measured from the edge of the
  // usable area (after exclusive zones), not the raw monitor origin.  The bar
  // has already claimed 44 px of exclusive zone at the top, so margin_top = 0
  // places the panel flush with the bar's bottom edge.
  gint margin_top = panel->panel_top_gap_px;
  margin_top = CLAMP(
      margin_top, 0,
      MAX(0, monitor_height - static_cast<gint>(placement.height)));
  const gboolean align_right =
      g_strcmp0(panel->alignment, "right") == 0;
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
      gtk_layer_set_monitor(win, monitor);
    }
    gtk_layer_set_anchor(win, GTK_LAYER_SHELL_EDGE_LEFT, !align_right);
    gtk_layer_set_anchor(win, GTK_LAYER_SHELL_EDGE_RIGHT, align_right);
    gtk_layer_set_margin(win, GTK_LAYER_SHELL_EDGE_TOP, margin_top);
    gtk_layer_set_margin(win, GTK_LAYER_SHELL_EDGE_LEFT, margin_left);
    gtk_layer_set_margin(win, GTK_LAYER_SHELL_EDGE_RIGHT, margin_right);
  }

  gtk_widget_set_size_request(GTK_WIDGET(win),
                              static_cast<gint>(placement.width),
                              static_cast<gint>(placement.height));
  gtk_window_resize(win, static_cast<gint>(placement.width),
                    static_cast<gint>(placement.height));
}

static void update_notification_popup_geometry(AliceApplication* self,
                                               AliceNotificationPopup* popup) {
  GtkWindow* win = GTK_WINDOW(popup->gtk_window);
  AliceSurfacePlacementFFI popup_placement = alice_layer_shell_notification_popup_placement();
  AliceSurfacePlacementFFI bar_placement = alice_layer_shell_bar_placement();

  GdkDisplay* display = gdk_display_get_default();
  GdkMonitor* monitor = display == nullptr ? nullptr : gdk_display_get_primary_monitor(display);
  gint monitor_height = 720;
  if (monitor != nullptr) {
    GdkRectangle geometry;
    gdk_monitor_get_geometry(monitor, &geometry);
    monitor_height = geometry.height;
  }
  if (monitor != nullptr && self->layer_shell_supported && gtk_layer_is_supported()) {
    gtk_layer_set_monitor(win, monitor);
  }

  const gint margin_top = static_cast<gint>(bar_placement.height) + popup->panel_top_gap_px;
  const gint popup_height = MAX(1, monitor_height - margin_top);
  if (self->layer_shell_supported && gtk_layer_is_supported()) {
    gtk_layer_set_margin(win, GTK_LAYER_SHELL_EDGE_TOP, margin_top);
    gtk_layer_set_margin(win, GTK_LAYER_SHELL_EDGE_RIGHT, 0);
  } else if (monitor != nullptr) {
    GdkRectangle geometry;
    gdk_monitor_get_geometry(monitor, &geometry);
    gtk_window_move(win,
                    geometry.x + geometry.width - static_cast<gint>(popup_placement.width),
                    geometry.y + margin_top);
  }

  gtk_widget_set_size_request(GTK_WIDGET(popup->fl_view),
                              static_cast<gint>(popup_placement.width),
                              popup_height);
  gtk_widget_set_size_request(GTK_WIDGET(win),
                              static_cast<gint>(popup_placement.width),
                              popup_height);
  gtk_window_resize(win, static_cast<gint>(popup_placement.width),
                    popup_height);
}

// ---------------------------------------------------------------------------
// Panel window delete-event (prevent destroy; hide instead)
// ---------------------------------------------------------------------------

static gboolean panel_window_delete_event(GtkWidget* widget,
                                          GdkEvent* event,
                                          gpointer user_data) {
  AlicePanel* panel = static_cast<AlicePanel*>(user_data);
  AliceApplication* self = panel->app;
  if (self->current_panel_id != nullptr &&
      g_strcmp0(self->current_panel_id, panel->panel_id) == 0) {
    g_clear_pointer(&self->current_panel_id, g_free);
    if (self->dismiss_window != nullptr) {
      gtk_widget_hide(GTK_WIDGET(self->dismiss_window));
    }
  }
  gtk_widget_hide(widget);
  alice_notify_panel_hide();
  return TRUE;
}

// ---------------------------------------------------------------------------
// Dismiss overlay button-press
// ---------------------------------------------------------------------------

static gboolean dismiss_window_button_press_event(GtkWidget* widget,
                                                  GdkEventButton* event,
                                                  gpointer user_data) {
  AliceApplication* self = ALICE_APPLICATION(user_data);
  if (self->current_panel_id != nullptr) {
    AlicePanel* panel = static_cast<AlicePanel*>(
        g_hash_table_lookup(self->panels, self->current_panel_id));
    if (panel != nullptr) {
      gtk_widget_hide(GTK_WIDGET(panel->gtk_window));
    }
    g_clear_pointer(&self->current_panel_id, g_free);
    gtk_widget_hide(GTK_WIDGET(self->dismiss_window));
  }
  alice_notify_panel_hide();
  return TRUE;
}

// ---------------------------------------------------------------------------
// ensure_panel — create AlicePanel on first showPanel call for a given id
// ---------------------------------------------------------------------------

static AlicePanel* ensure_panel(AliceApplication* self, const gchar* panel_id) {
  AlicePanel* panel = static_cast<AlicePanel*>(
      g_hash_table_lookup(self->panels, panel_id));
  if (panel != nullptr) {
    return panel;
  }

  panel = g_new0(AlicePanel, 1);
  panel->panel_id = g_strdup(panel_id);
  panel->app = self;

  FlEngine* engine = fl_view_get_engine(self->bar_fl_view);
  FlView* fl_view = fl_view_new_for_engine(engine);
  panel->fl_view = fl_view;

  GtkWindow* win = GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(self)));
  panel->gtk_window = GTK_APPLICATION_WINDOW(win);

  // Transparent background for panel window
  gtk_widget_set_app_paintable(GTK_WIDGET(win), TRUE);
  GdkScreen* screen = gtk_window_get_screen(win);
  if (screen != nullptr) {
    GdkVisual* visual = gdk_screen_get_rgba_visual(screen);
    if (visual != nullptr) {
      gtk_widget_set_visual(GTK_WIDGET(win), visual);
    }
  }

  GdkRGBA transparent = {0.0, 0.0, 0.0, 0.0};
  fl_view_set_background_color(fl_view, &transparent);
  gtk_widget_set_hexpand(GTK_WIDGET(fl_view), TRUE);
  gtk_widget_set_vexpand(GTK_WIDGET(fl_view), TRUE);

  AliceSurfacePlacementFFI placement = alice_layer_shell_panel_placement();
  gtk_widget_set_size_request(GTK_WIDGET(fl_view),
                              static_cast<gint>(placement.width),
                              static_cast<gint>(placement.height));
  gtk_widget_show(GTK_WIDGET(fl_view));
  gtk_container_add(GTK_CONTAINER(win), GTK_WIDGET(fl_view));

  gtk_window_set_title(win, "alice-panel");

  if (self->layer_shell_supported && gtk_layer_is_supported()) {
    configure_layer_shell_panel_window(win);
  } else {
    configure_panel_fallback_window(win);
  }

  // Read the view ID now — it may already be assigned by fl_view_new_for_engine.
  // It is also refreshed in showPanel after gtk_widget_show_all, so we are safe
  // either way.  Do NOT realize or show here: realizing without a mapped window
  // causes Flutter to attempt GL context setup before a wl_surface exists,
  // which produces "Failed to setup compositor shaders" warnings.
  panel->view_id = fl_view_get_id(fl_view);

  g_signal_connect(win, "delete-event",
                   G_CALLBACK(panel_window_delete_event), panel);

  // DO NOT call fl_register_plugins — plugins are engine-scoped; bar view
  // already registered them for this engine.

  g_hash_table_insert(self->panels, g_strdup(panel_id), panel);
  return panel;
}

static AliceNotificationPopup* ensure_notification_popup(AliceApplication* self) {
  if (self->notification_popup != nullptr) {
    return self->notification_popup;
  }

  AliceNotificationPopup* popup = g_new0(AliceNotificationPopup, 1);
  popup->app = self;

  FlEngine* engine = fl_view_get_engine(self->bar_fl_view);
  FlView* fl_view = fl_view_new_for_engine(engine);
  popup->fl_view = fl_view;

  GtkWindow* win = GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(self)));
  popup->gtk_window = GTK_APPLICATION_WINDOW(win);

  gtk_widget_set_app_paintable(GTK_WIDGET(win), TRUE);
  GdkScreen* screen = gtk_window_get_screen(win);
  if (screen != nullptr) {
    GdkVisual* visual = gdk_screen_get_rgba_visual(screen);
    if (visual != nullptr) {
      gtk_widget_set_visual(GTK_WIDGET(win), visual);
    }
  }

  GdkRGBA transparent = {0.0, 0.0, 0.0, 0.0};
  fl_view_set_background_color(fl_view, &transparent);
  gtk_widget_set_hexpand(GTK_WIDGET(fl_view), TRUE);
  gtk_widget_set_vexpand(GTK_WIDGET(fl_view), TRUE);

  AliceSurfacePlacementFFI placement = alice_layer_shell_notification_popup_placement();
  gtk_widget_set_size_request(GTK_WIDGET(fl_view),
                              static_cast<gint>(placement.width),
                              720);
  gtk_widget_show(GTK_WIDGET(fl_view));
  gtk_container_add(GTK_CONTAINER(win), GTK_WIDGET(fl_view));
  gtk_window_set_title(win, "alice-notification-popups");

  if (self->layer_shell_supported && gtk_layer_is_supported()) {
    configure_layer_shell_notification_popup_window(win);
  } else {
    configure_notification_popup_fallback_window(win);
  }

  popup->view_id = fl_view_get_id(fl_view);
  self->notification_popup = popup;
  return popup;
}

// ---------------------------------------------------------------------------
// Platform method channel
// ---------------------------------------------------------------------------

static void platform_method_call_cb(FlMethodChannel* channel,
                                    FlMethodCall* method_call,
                                    gpointer user_data) {
  AliceApplication* self = ALICE_APPLICATION(user_data);
  const gchar* method = fl_method_call_get_name(method_call);
  FlValue* args = fl_method_call_get_args(method_call);

  g_autoptr(FlMethodResponse) response = nullptr;
  if (strcmp(method, "showPanel") == 0) {
    gboolean ok = FALSE;
    if (args != nullptr) {
      FlValue* panel_id_val = fl_value_lookup_string(args, "panelId");
      if (panel_id_val != nullptr) {
        const gchar* panel_id_str = fl_value_get_string(panel_id_val);
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
        FlValue* include_bytes_value =
            fl_value_lookup_string(args, "includeTrayIconBytes");
        const gboolean include_bytes =
            include_bytes_value != nullptr && fl_value_get_bool(include_bytes_value);
        FlValue* gap_value = fl_value_lookup_string(args, "panelTopGapPx");
        const gint panel_gap = gap_value != nullptr
            ? static_cast<gint>(fl_value_get_int(gap_value))
            : 0;

        g_message("alice showPanel id=%s width=%.1f height=%.1f anchor=(%.1f,%.1f)",
                  panel_id_str, width, height, anchor_x, anchor_y);

        // Reusing/resizing the notifications panel's secondary FlView across
        // dynamic height changes can wedge Flutter's Linux multi-view renderer.
        // Recreate that native panel view only when its requested size changes.
        if (g_strcmp0(panel_id_str, "notifications") == 0) {
          AlicePanel* existing = static_cast<AlicePanel*>(
              g_hash_table_lookup(self->panels, panel_id_str));
          if (existing != nullptr &&
              (existing->width != width || existing->height != height)) {
            g_message("alice showPanel recreating notifications panel view_id=%ld old=%.1fx%.1f new=%.1fx%.1f",
                      static_cast<long>(existing->view_id), existing->width,
                      existing->height, width, height);
            gtk_widget_destroy(GTK_WIDGET(existing->gtk_window));
            g_hash_table_remove(self->panels, panel_id_str);
          }
        }

        AlicePanel* panel = ensure_panel(self, panel_id_str);

        // Store geometry on the panel
        panel->anchor_x = anchor_x;
        panel->anchor_y = anchor_y;
        panel->width = width;
        panel->height = height;
        g_free(panel->alignment);
        panel->alignment = g_strdup(alignment);
        panel->include_icon_bytes = include_bytes;
        panel->panel_top_gap_px = panel_gap;

        // Update current panel
        g_free(self->current_panel_id);
        self->current_panel_id = g_strdup(panel_id_str);

        // Hide any other visible panels
        GHashTableIter iter;
        gpointer key, value;
        g_hash_table_iter_init(&iter, self->panels);
        while (g_hash_table_iter_next(&iter, &key, &value)) {
          AlicePanel* other = static_cast<AlicePanel*>(value);
          if (g_strcmp0(other->panel_id, panel_id_str) != 0) {
            gtk_widget_hide(GTK_WIDGET(other->gtk_window));
          }
        }

        // Show the window at the correct size BEFORE notifying Dart, so that
        // the Wayland surface exists and the Flutter view reports the right
        // dimensions when Dart renders the first frame.
        update_panel_window_geometry(self, panel);
        // Keep the dismiss overlay disabled for the notifications panel while
        // investigating Linux multi-view geometry issues. Showing the overlay
        // can make panel failures look like input lockups, and the bounded
        // overlay experiment regressed notification-panel opening after popups.
        if (self->dismiss_window != nullptr &&
            g_strcmp0(panel_id_str, "notifications") != 0) {
          gtk_widget_show_all(GTK_WIDGET(self->dismiss_window));
        }
        gtk_widget_show_all(GTK_WIDGET(panel->gtk_window));

        // Refresh the view ID — in case it was not yet assigned before the
        // window was realized (fl_view_new_for_engine may defer registration).
        panel->view_id = fl_view_get_id(panel->fl_view);

        // Flush pending Wayland requests so the compositor sees the new
        // wl_surface before Flutter attempts to make the EGL context current.
        GdkDisplay* display = gdk_display_get_default();
        if (display != nullptr) {
          gdk_display_flush(display);
        }

        // Notify Dart — engine renders into an already-visible, correctly-sized view.
        g_message("alice showPanel notify Dart id=%s view_id=%ld", panel_id_str,
                  static_cast<long>(panel->view_id));
        alice_notify_panel_show(panel_id_str, panel->view_id, include_bytes != FALSE,
                                anchor_x, anchor_y, width, height);
        g_message("alice showPanel native complete id=%s", panel_id_str);

        ok = TRUE;
      }
    }
    response = ok
        ? FL_METHOD_RESPONSE(fl_method_success_response_new(fl_value_new_null()))
        : FL_METHOD_RESPONSE(fl_method_error_response_new(
              "panel_show_failed", "Failed to show panel", nullptr));
  } else if (strcmp(method, "showNotificationPopups") == 0) {
    FlValue* gap_value = args == nullptr ? nullptr : fl_value_lookup_string(args, "panelTopGapPx");
    const gint panel_gap = gap_value != nullptr
        ? static_cast<gint>(fl_value_get_int(gap_value))
        : 0;
    AliceNotificationPopup* popup = ensure_notification_popup(self);
    popup->panel_top_gap_px = panel_gap;
    update_notification_popup_geometry(self, popup);
    gtk_widget_show_all(GTK_WIDGET(popup->gtk_window));
    popup->view_id = fl_view_get_id(popup->fl_view);
    GdkDisplay* display = gdk_display_get_default();
    if (display != nullptr) {
      gdk_display_flush(display);
    }
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(
        fl_value_new_int(popup->view_id)));
  } else if (strcmp(method, "hideNotificationPopups") == 0) {
    if (self->notification_popup != nullptr) {
      gtk_widget_hide(GTK_WIDGET(self->notification_popup->gtk_window));
    }
    response =
        FL_METHOD_RESPONSE(fl_method_success_response_new(fl_value_new_null()));
  } else if (strcmp(method, "hidePanel") == 0) {
    if (self->current_panel_id != nullptr) {
      AlicePanel* panel = static_cast<AlicePanel*>(
          g_hash_table_lookup(self->panels, self->current_panel_id));
      if (panel != nullptr) {
        gtk_widget_hide(GTK_WIDGET(panel->gtk_window));
      }
      g_clear_pointer(&self->current_panel_id, g_free);
      if (self->dismiss_window != nullptr) {
        gtk_widget_hide(GTK_WIDGET(self->dismiss_window));
      }
    }
    alice_notify_panel_hide();
    response =
        FL_METHOD_RESPONSE(fl_method_success_response_new(fl_value_new_null()));
  } else {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }

  if (strcmp(method, "showPanel") == 0) {
    g_message("alice showPanel sending method response");
  }
  g_autoptr(GError) error = nullptr;
  if (!fl_method_call_respond(method_call, response, &error)) {
    g_warning("Failed to send method response: %s", error->message);
  }
  if (strcmp(method, "showPanel") == 0) {
    g_message("alice showPanel method response sent");
  }
}

static void setup_platform_channels(AliceApplication* self, FlView* view) {
  FlBinaryMessenger* messenger =
      fl_engine_get_binary_messenger(fl_view_get_engine(view));
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();

  self->platform_channel = fl_method_channel_new(messenger, kPlatformChannelName,
                                                 FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(self->platform_channel,
                                            platform_method_call_cb,
                                            g_object_ref(self),
                                            g_object_unref);
}

// ---------------------------------------------------------------------------
// Main window (bar + dismiss overlay)
// ---------------------------------------------------------------------------

static void create_main_window(AliceApplication* self) {
  GtkWindow* window =
      GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(self)));
  self->bar_window = window;

  // Dismiss overlay (no FlView — pure click target)
  self->dismiss_window =
      GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(self)));
  gtk_widget_set_app_paintable(GTK_WIDGET(self->dismiss_window), TRUE);
  GdkScreen* rgba_screen = gtk_window_get_screen(GTK_WINDOW(self->dismiss_window));
  if (rgba_screen != nullptr) {
    GdkVisual* visual = gdk_screen_get_rgba_visual(rgba_screen);
    if (visual != nullptr) {
      gtk_widget_set_visual(GTK_WIDGET(self->dismiss_window), visual);
    }
  }
  g_signal_connect(self->dismiss_window, "button-press-event",
                   G_CALLBACK(dismiss_window_button_press_event), self);
  gtk_widget_add_events(GTK_WIDGET(self->dismiss_window), GDK_BUTTON_PRESS_MASK);
  gtk_window_set_title(self->dismiss_window, "alice-panel-dismiss");

  gtk_widget_set_app_paintable(GTK_WIDGET(window), TRUE);
  GdkScreen* bar_screen = gtk_window_get_screen(window);
  if (bar_screen != nullptr) {
    GdkVisual* visual = gdk_screen_get_rgba_visual(bar_screen);
    if (visual != nullptr) {
      gtk_widget_set_visual(GTK_WIDGET(window), visual);
    }
  }

  gboolean use_header_bar = TRUE;

  if (self->layer_shell_supported && gtk_layer_is_supported()) {
    configure_layer_shell_bar_window(window);
    configure_layer_shell_dismiss_window(self->dismiss_window);
    use_header_bar = FALSE;
  } else if (self->layer_shell_supported) {
    g_warning("Rust layer-shell probe succeeded but gtk-layer-shell is unavailable; using GTK fallback window");
    configure_bar_fallback_window(window);
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
  } else {
    gtk_window_set_title(window, "alice");
  }

  g_autoptr(FlDartProject) project = fl_dart_project_new();

  FlView* view = fl_view_new(project);
  self->bar_fl_view = view;

  GdkRGBA background_color = {0.0, 0.0, 0.0, 0.0};
  fl_view_set_background_color(view, &background_color);
  gtk_widget_set_hexpand(GTK_WIDGET(view), TRUE);
  gtk_widget_set_vexpand(GTK_WIDGET(view), TRUE);

  gint initial_width = 1280;
  if (self->layer_shell_supported) {
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
  AliceSurfacePlacementFFI bar_placement = alice_layer_shell_bar_placement();
  gtk_widget_set_size_request(GTK_WIDGET(view), initial_width,
                              static_cast<gint>(bar_placement.height));
  gtk_widget_show(GTK_WIDGET(view));
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));
  gtk_widget_realize(GTK_WIDGET(view));

  fl_register_plugins(FL_PLUGIN_REGISTRY(view));
  setup_platform_channels(self, view);

  // Set up dismiss overlay content
  GtkWidget* dismiss_box = gtk_event_box_new();
  gtk_widget_set_app_paintable(dismiss_box, TRUE);
  gtk_container_add(GTK_CONTAINER(self->dismiss_window), dismiss_box);
  gtk_widget_show(dismiss_box);
  gtk_widget_hide(GTK_WIDGET(self->dismiss_window));

  gtk_widget_show_all(GTK_WIDGET(window));
  gtk_widget_grab_focus(GTK_WIDGET(view));
}

// ---------------------------------------------------------------------------
// GApplication overrides
// ---------------------------------------------------------------------------

// Suppress spurious ATK CRITICAL messages that fire when Flutter's multi-view
// accessibility code calls atk_socket_embed() with a NULL plug_id for
// secondary FlViews.  This is a Flutter bug; we silence only that specific
// domain/level so genuine ATK issues are not hidden.
static void atk_log_suppress(const gchar* /*log_domain*/,
                              GLogLevelFlags /*log_level*/,
                              const gchar* /*message*/,
                              gpointer /*user_data*/) {}

// Flutter on Wayland logs "Failed to setup compositor shaders, unable to make
// OpenGL context current" twice at startup when the FlView is first realized —
// the EGL surface isn't committed yet so the first shader-setup attempt fails,
// Flutter retries ~1 s later and succeeds.  The warning is harmless and
// unfixable from our side (it originates inside libflutter_linux_gtk.so).
static void flutter_compositor_warning_suppress(const gchar* log_domain,
                                                 GLogLevelFlags log_level,
                                                 const gchar* message,
                                                 gpointer /*user_data*/) {
  if (message != nullptr && strstr(message, "compositor shaders") != nullptr)
    return;  // swallow
  g_log_default_handler(log_domain, log_level, message, nullptr);
}

static void alice_application_activate(GApplication* application) {
  g_log_set_handler("Atk", G_LOG_LEVEL_CRITICAL, atk_log_suppress, nullptr);
  g_log_set_handler(nullptr, G_LOG_LEVEL_WARNING,
                    flutter_compositor_warning_suppress, nullptr);

  AliceApplication* self = ALICE_APPLICATION(application);
  AliceLayerShellCapabilitiesFFI layer_shell =
      alice_layer_shell_detect_capabilities();
  self->layer_shell_supported = layer_shell.layer_shell_supported;
  create_main_window(self);
}

static gboolean alice_application_local_command_line(GApplication* application,
                                                  gchar*** arguments,
                                                  int* exit_status) {
  AliceApplication* self = ALICE_APPLICATION(application);
  self->dart_entrypoint_arguments = g_strdupv(*arguments + 1);

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

static void alice_application_startup(GApplication* application) {
  G_APPLICATION_CLASS(alice_application_parent_class)->startup(application);
}

static void alice_application_shutdown(GApplication* application) {
  G_APPLICATION_CLASS(alice_application_parent_class)->shutdown(application);
}

static void alice_application_dispose(GObject* object) {
  AliceApplication* self = ALICE_APPLICATION(object);
  g_clear_pointer(&self->dart_entrypoint_arguments, g_strfreev);
  g_clear_object(&self->platform_channel);
  g_clear_pointer(&self->current_panel_id, g_free);
  g_clear_pointer(&self->panels, g_hash_table_destroy);
  g_clear_pointer(&self->notification_popup, alice_notification_popup_free);
  G_OBJECT_CLASS(alice_application_parent_class)->dispose(object);
}

static void alice_application_class_init(AliceApplicationClass* klass) {
  G_APPLICATION_CLASS(klass)->activate = alice_application_activate;
  G_APPLICATION_CLASS(klass)->local_command_line =
      alice_application_local_command_line;
  G_APPLICATION_CLASS(klass)->startup = alice_application_startup;
  G_APPLICATION_CLASS(klass)->shutdown = alice_application_shutdown;
  G_OBJECT_CLASS(klass)->dispose = alice_application_dispose;
}

static void alice_application_init(AliceApplication* self) {
  self->bar_window = nullptr;
  self->bar_fl_view = nullptr;
  self->panels = g_hash_table_new_full(g_str_hash, g_str_equal,
                                       g_free, alice_panel_free);
  self->notification_popup = nullptr;
  self->dismiss_window = nullptr;
  self->layer_shell_supported = FALSE;
  self->current_panel_id = nullptr;
}

AliceApplication* alice_application_new() {
  g_set_prgname(APPLICATION_ID);
  return ALICE_APPLICATION(g_object_new(alice_application_get_type(),
                                     "application-id", APPLICATION_ID, "flags",
                                     G_APPLICATION_NON_UNIQUE, nullptr));
}
