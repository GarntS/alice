#ifndef FLUTTER_ALICE_APPLICATION_H_
#define FLUTTER_ALICE_APPLICATION_H_

#include <gtk/gtk.h>

G_DECLARE_FINAL_TYPE(AliceApplication,
                     alice_application,
                     ALICE,
                     APPLICATION,
                     GtkApplication)

/**
 * alice_application_new:
 *
 * Creates a new Flutter-based application.
 *
 * Returns: a new #AliceApplication.
 */
AliceApplication* alice_application_new();

#endif  // FLUTTER_ALICE_APPLICATION_H_
