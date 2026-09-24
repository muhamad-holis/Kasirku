package com.kasirku.app

// FIX: local_auth plugin requires FlutterFragmentActivity (bukan FlutterActivity)
// agar fitur Biometrik (fingerprint / Face ID) bisa berjalan.
// Error sebelumnya: "local_auth plugin requires activity to be a FragmentActivity"
import io.flutter.embedding.android.FlutterFragmentActivity

class MainActivity: FlutterFragmentActivity()
