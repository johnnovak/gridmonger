nim c -d:release --stacktrace=on --linetrace=on --gc:arc --deepcopy:on --hint[Performance]:off --app:gui -D:nvgGL3 -D:glfwStaticLib -r %1 %2 %3 %4 %5 src/main
