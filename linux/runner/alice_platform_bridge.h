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

#ifdef __cplusplus
}
#endif

#endif
