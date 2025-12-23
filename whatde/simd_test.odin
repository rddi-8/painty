package whatde

import "core:testing"
import "core:fmt"
import "base:intrinsics"
import "core:simd"

@(test)
test1 :: proc() {
    v1: simd.u16x16
    v2: simd.u16x16

    v1000: simd.u16x16 = 100

    v2 = simd.indices(simd.u16x16) * v1000
    v1 = v2
    

    v3 := v1 * v2
    fmt.println(v3)
}