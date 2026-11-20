# The optional Fingerly artifacts are compileOnly in this plugin and present at
# run time only when the host app adds them to its own dependencies. Without
# these rules R8 refuses every minified release build of an app that does not.
-dontwarn io.fingerly.sdk.appchecks.**
-dontwarn io.fingerly.sdk.playintegrity.**
