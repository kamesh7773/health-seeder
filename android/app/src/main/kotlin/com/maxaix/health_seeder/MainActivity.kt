package com.maxaix.health_seeder

import io.flutter.embedding.android.FlutterFragmentActivity

/**
 * `FlutterFragmentActivity`, not the default `FlutterActivity`.
 *
 * The health plugin asks Health Connect for permissions through
 * `registerForActivityResult`, and to do that it casts the host activity to
 * `androidx.activity.ComponentActivity`. `FlutterActivity` extends plain
 * `android.app.Activity`, so that cast throws the moment the plugin attaches —
 * the permission sheet never appears. The Kai apps' own MainActivity extends
 * this class for the same reason.
 */
class MainActivity : FlutterFragmentActivity()
