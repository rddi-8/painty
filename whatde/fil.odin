package whatde

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
    if !sdl.Init({.VIDEO}) do print_err()
    fmt.println("hell")
    if !sdl.CreateWindowAndRenderer("hmmm", WIDTH, HEIGHT, {}, &window, &renderer ) do print_err()


    main_loop: for {
        ev: sdl.Event
        for sdl.PollEvent(&ev) {
            #partial switch ev.type {
                case .QUIT:
                    break main_loop
            }
        }

        sdl.SetRenderDrawColor(renderer, 220, 100, 100, 255)
        sdl.RenderClear(renderer)

        // sdl.FlushRenderer(renderer)
        sdl.RenderPresent(renderer)
    }

    sdl.Quit()
}