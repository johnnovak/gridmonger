nim c --gc:arc --deepcopy:on --hint[Performance]:off \
    -D:nvgGL3 -D:glfwStaticLib \
    --app:gui \
    -r src/main

