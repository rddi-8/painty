package colors

GradientPoint :: struct {
    color: Color,
    position: f32,
}

Gradient :: struct {
    points: []GradientPoint
}