package whatde

import "core:log"
import sdl "vendor:sdl3"
import "core:fmt"

WIDTH :: 600
HEIGHT :: 400

renderer: ^sdl.Renderer
window: ^sdl.Window

print_err :: proc() {
    fmt.printfln("SDL Error: {}", sdl.GetError())
}

main :: proc() {
    // context.logger = log.create_console_logger()

    // ok := sdl.Init({.VIDEO}); assert(ok)
    // window := sdl.CreateWindow("hmmm", WIDTH, HEIGHT, {})

    // gpu := sdl.CreateGPUDevice({.SPIRV}, true, nil); assert(gpu != nil)
    // assert(1 == 3)


    // main_loop: for {
    //     ev: sdl.Event
    //     for sdl.PollEvent(&ev) {
    //         #partial switch ev.type {
    //             case .QUIT:
    //                 break main_loop
    //         }
    //     }

        
    // }

    // sdl.Quit()
    test1()
}