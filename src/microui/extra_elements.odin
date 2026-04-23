package microui

import "core:math"
import "core:fmt"
import "../color"
import "../render"

slider_gradient :: proc(ctx: ^Context, value: ^Real, low, high: Real, gradient: color.Gradient, step: Real = 0.0, fmt_string: string = SLIDER_FMT, opt: Options = {.ALIGN_CENTER}) -> (res: Result_Set) {
	last := value^
	v := last
	id := get_id(ctx, uintptr(value))
	base := layout_next(ctx)

	/* handle text input mode */
	if number_textbox(ctx, &v, base, id, fmt_string) {
		return
	}

	/* handle normal mode */
	update_control(ctx, id, base, opt)

	/* handle input */
	if ctx.focus_id == id && ctx.mouse_down_bits == {.LEFT} {
		v = low + Real(ctx.mouse_pos.x - base.x) * (high - low) / Real(base.w)
		if step != 0.0 {
			v = math.floor((v + step/2) / step) * step
		}
	}
	/* clamp and store value, update res */
	v = clamp(v, low, high); value^ = v
	if last != v {
		res += {.CHANGE}
	}

	/* draw base */
	// draw_control_frame(ctx, id, base, .BASE, opt)
    draw_gradient_rect(ctx, base, gradient)
	/* draw thumb */
	w := ctx.style.thumb_size
	x := i32((v - low) * Real(base.w - w) / (high - low))
	thumb := Rect{base.x + x, base.y, w, base.h}
	draw_control_frame(ctx, id, thumb, .BUTTON, opt)
	/* draw text  */
	text_buf: [4096]byte
	draw_control_text(ctx, fmt.bprintf(text_buf[:], fmt_string, v), base, .TEXT, opt)

	return
}

icon :: proc(ctx: ^Context, id: string, icon: render.Texture_Tile, color: Color, opt: Options = {.ALIGN_CENTER}) -> (res: Result_Set) {

	id := get_id(ctx, id)
	base := layout_next(ctx)
	min := math.min(base.w, base.h)
	base.h = min
	base.w = min


	/* handle normal mode */
	update_control(ctx, id, base, opt)

	/* handle input */

	/* clamp and store value, update res */


	/* draw base */
	// draw_control_frame(ctx, id, base, .BASE, opt)
    draw_texture_rect(ctx, base, color, icon)
	

	return
}