# Simple painty program

Digital painting program written in Odin with SDL3. Project used for me to learn Odin, SDL and stuff.
Focusing on straighforward user experience with specific painting workflows.

### Dependencies
- [Odin compiler](https://odin-lang.org)
- [SDL3](https://wiki.libsdl.org/SDL3/FrontPage) (bundled in Odin's standard library)
- [SDL_Shadercross](https://github.com/libsdl-org/SDL_shadercross)
- [lcms2](https://github.com/mm2/Little-CMS) required to generate color LUT from monitor ICC profile
- [glslc](https://github.com/google/shaderc) to compile shaders to SPIR-V

### How to build (Windows)
When using VS Code the included task.json should work provided odin and glslc is in your PATH.
For convenience the required .dll are included in the [build/win](build/win) folder.