# Godot finds the plugin class by name (manifest meta-data) and its @UsedByGodot methods by reflection.
-keep class com.flipfold.ludozing.levelplay.** { *; }
# The LevelPlay SDK AAR brings its own consumer rules (com.ironsource.**, com.unity3d.mediation.**).
