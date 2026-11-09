# R8 rules for the release build (tools/android-release.sh switches R8 on in godot/android/build/build.gradle and
# points it here). Each plugin brings its own keep rules (plugins/*/consumer-rules.pro), the Google, Firebase and
# LevelPlay libraries theirs.
# The engine's Java side is called from C++ through JNI by class and method name: keep all of it.
-keep class org.godotengine.** { *; }
-keepclassmembers class * { native <methods>; }
# Line numbers in Play's crash reports (Play reads the mapping file R8 puts in the bundle).
-keepattributes SourceFile,LineNumberTable,*Annotation*,Signature,InnerClasses,EnclosingMethod
-renamesourcefileattribute SourceFile
