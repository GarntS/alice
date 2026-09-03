#ifndef ALICE_PLATFORM_BRIDGE_H_
#define ALICE_PLATFORM_BRIDGE_H_

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/**
 * alice_notify_panel_show:
 *
 * Called from the showPanel MethodChannel handler after creating/updating the
 * panel GTK window. Pushes a PanelCommand (including view_id) into the Dart
 * StreamSink registered by watch_panel_commands().
 */
void alice_notify_panel_show(const char* panel_id,
                              int64_t view_id,
                              bool include_icon_bytes,
                              double anchor_x,
                              double anchor_y,
                              double width,
                              double height);

/**
 * alice_notify_panel_hide:
 *
 * Pushes a null/None panel command into the Dart StreamSink, signalling
 * the panel Flutter app to hide its content.
 */
void alice_notify_panel_hide(void);

/** Replace the retained snapshot of native bar Flutter view IDs. */
void alice_set_bar_view_ids(const int64_t* view_ids, size_t count);

#ifdef __cplusplus
}
#endif

#endif  // ALICE_PLATFORM_BRIDGE_H_
