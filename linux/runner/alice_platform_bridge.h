#ifndef ALICE_PLATFORM_BRIDGE_H_
#define ALICE_PLATFORM_BRIDGE_H_

#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

/**
 * alice_notify_panel_show:
 *
 * Called by the panel-process socket listener after updating GTK window
 * geometry. Pushes a PanelCommand into the Dart StreamSink registered by
 * watch_panel_commands().
 */
void alice_notify_panel_show(const char* panel_id,
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

#ifdef __cplusplus
}
#endif

#endif  // ALICE_PLATFORM_BRIDGE_H_
