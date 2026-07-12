-keep class de.tobiaskneidl.** { *; }
-keepclassmembers class * {
    @android.webkit.JavascriptInterface <methods>;
}
-keep class rust.** { *; }
-keep class com.tauri.** { *; }
