#ifndef ALICE_LAYER_SHELL_BRIDGE_H_
#define ALICE_LAYER_SHELL_BRIDGE_H_

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
  bool layer_shell_supported;
} AliceLayerShellCapabilitiesFFI;

typedef struct {
  uint32_t width;
  uint32_t height;
  bool anchor_top;
  bool anchor_left;
  bool anchor_right;
} AliceSurfacePlacementFFI;

AliceLayerShellCapabilitiesFFI alice_layer_shell_detect_capabilities(void);
AliceSurfacePlacementFFI alice_layer_shell_bar_placement(void);
AliceSurfacePlacementFFI alice_layer_shell_panel_placement(void);

#ifdef __cplusplus
}
#endif

#endif
