# ── JGit on Android ──────────────────────────────────────────────────
# JGit references several Java SE / Java EE classes that are absent on
# Android.  These code-paths are never reached at runtime, so we tell
# R8 to ignore them instead of aborting the build.

# JMX monitoring (desktop-only)
-dontwarn javax.management.**

# GSSAPI / Kerberos Negotiate auth (not used on Android)
-dontwarn org.ietf.jgss.**

# ProcessHandle (Java 9+ desktop API, used by GC$PidLock)
-dontwarn java.lang.ProcessHandle

# SLF4J static binder (provided at runtime by Android logging bridge)
-dontwarn org.slf4j.impl.StaticLoggerBinder

# ── JGit internals ──────────────────────────────────────────────────
# Keep JGit service-provider configs so transport/FS detection works.
-keep class org.eclipse.jgit.** { *; }
-keepnames class org.eclipse.jgit.**
