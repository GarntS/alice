#ifndef ALICE_PLATFORM_BRIDGE_H_
#define ALICE_PLATFORM_BRIDGE_H_

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
  char* label;
  int32_t offset_hours;
} AliceTimeZoneFFI;

typedef struct {
  char* lock;
  char* lock_and_suspend;
  char* restart;
  char* poweroff;
} AlicePowerCommandsFFI;

typedef struct {
  uint8_t theme_mode;
  char* accent_color;
  bool show_network_label;
  uint32_t max_visible_tray_items;
  char* local_time_zone_label;
  AliceTimeZoneFFI* time_zones;
  size_t time_zone_count;
  AlicePowerCommandsFFI power_commands;
} AliceConfigFFI;

typedef struct {
  char* label;
  bool is_focused;
  bool is_visible;
} WorkspaceFFI;

typedef struct {
  char* title;
  char* artist;
  char* album_title;
  char* art_url;
  char* position_label;
  char* length_label;
  bool is_playing;
} MediaFFI;

typedef struct {
  uint8_t kind;
  char* label;
} NetworkFFI;

typedef struct {
  char* time_zone_code;
  char* date_label;
  char* time_label;
} ClockFFI;

typedef struct {
  char* id;
  char* label;
  char* icon_name;
  char* icon_theme_path;
  char* service_name;
  char* object_path;
} TrayItemFFI;

typedef struct {
  WorkspaceFFI* workspaces;
  size_t workspace_count;
  MediaFFI* media;
  NetworkFFI network;
  ClockFFI clock;
  TrayItemFFI* tray_items;
  size_t tray_item_count;
  double memory_usage_percent;
  double cpu_usage_cores;
} AliceSnapshotFFI;

AliceConfigFFI* alice_platform_load_config(void);
void alice_platform_free_config(AliceConfigFFI* config);
AliceSnapshotFFI* alice_platform_read_snapshot(void);
void alice_platform_free_snapshot(AliceSnapshotFFI* snapshot);
bool alice_platform_send_media_action(const char* action);
bool alice_platform_focus_workspace(const char* label);
bool alice_platform_send_tray_action(const char* service_name,
                                     const char* object_path,
                                     const char* action,
                                     int32_t x,
                                     int32_t y);
void alice_platform_clear_tray_cache(void);

#ifdef __cplusplus
}
#endif

#endif
