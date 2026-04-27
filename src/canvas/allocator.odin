package canvas

import "core:mem"
import vmem "core:mem/virtual"

Canvas_Allocator :: struct {
    arena: vmem.Arena,
}

load_files :: proc() {
    arena: vmem.Arena
	arena_err := vmem.arena_init_growing(&arena)
	ensure(arena_err == nil)
	arena_alloc := vmem.arena_allocator(&arena)
}
