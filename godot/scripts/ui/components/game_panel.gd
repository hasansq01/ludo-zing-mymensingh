class_name GamePanel
extends PanelContainer
## A rounded panel drawn by one small shader, for the game look (the Shop's cards, banner, tiles and price buttons):
## a radial or vertical gradient face (three stops, or four with c3 / mid2), a border, a darker 3D lip under it (and a
## second, darker one under that: lip2) and optional light rays (count, width, reach, turn). Children lay out like any
## PanelContainer (content margins: `pad`, plus the lips at the bottom). Nothing redraws unless a property changes;
## the shader runs on the GPU.
##   var p := GamePanel.radial(Color("#fff3b0"), Color("#ffbf3c"), Color("#c9690a"))
##   p.border = 3.0; p.border_color = Color("#ffe08a"); p.lip = 5.0; p.lip_color = Color("#7a3e08")

const SHADER := """shader_type canvas_item;
uniform vec2 size = vec2(100.0, 100.0);
uniform float radius = 16.0;
uniform float radius_bottom = -1.0;   // < 0: the same as radius
uniform float border = 0.0;
uniform float lip = 0.0;
uniform float lip2 = 0.0;             // a second lip under the first (CSS: inset lip + an outer 0 Npx 0 shadow)
uniform int mode = 0;                 // 0 radial, 1 vertical
uniform vec4 c0 : source_color = vec4(1.0);
uniform vec4 c1 : source_color = vec4(0.8);
uniform vec4 c2 : source_color = vec4(0.5);
uniform vec4 c3 : source_color = vec4(0.5);
uniform float mid = 0.4;              // where c1 sits along the gradient
uniform float mid2 = 1.0;             // where c2 sits (1: a three-stop gradient, c3 unused)
uniform vec2 center = vec2(0.5, 0.4); // radial centre (face UV)
uniform vec2 reach = vec2(0.7, 0.6);  // radial radii (face UV)
uniform vec4 border_color : source_color = vec4(0.0);
uniform vec4 lip_color : source_color = vec4(0.0);
uniform vec4 lip2_color : source_color = vec4(0.0);
uniform float rays = 0.0;             // ray strength (0 = none)
uniform vec2 ray_center = vec2(0.25, 0.25);
uniform float ray_count = 16.0;
uniform float ray_width = 0.4;        // the lit share of each ray period
uniform float ray_reach = 0.0;        // px: rays end at this distance from ray_center (0: they don't)
uniform float ray_angle = 0.0;        // radians: turns the rays

float sd_box(vec2 p, vec2 b, float r) {
	vec2 q = abs(p) - b + r;
	return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

void fragment() {
	vec4 tint = COLOR;                    // modulate / self_modulate (and any parent fade) arrive here
	vec2 px = UV * size;
	vec2 face_size = vec2(size.x, max(1.0, size.y - lip - lip2));
	vec2 lip_size = vec2(size.x, max(1.0, size.y - lip2));
	float rb = radius_bottom < 0.0 ? radius : radius_bottom;
	float d_all = sd_box(px - size * 0.5, size * 0.5, px.y > size.y * 0.5 ? rb : radius);
	float d_face = sd_box(px - face_size * 0.5, face_size * 0.5, px.y > face_size.y * 0.5 ? rb : radius);
	float d_lip = sd_box(px - lip_size * 0.5, lip_size * 0.5, px.y > lip_size.y * 0.5 ? rb : radius);
	float a = clamp(0.5 - d_all, 0.0, 1.0);
	vec2 uv = px / face_size;
	float t = mode == 0 ? length((uv - center) / reach) : uv.y;
	t = clamp(t, 0.0, 1.0);
	vec4 col = t < mid ? mix(c0, c1, t / mid) : (t < mid2 ? mix(c1, c2, (t - mid) / max(mid2 - mid, 0.0001)) : mix(c2, c3, (t - mid2) / max(1.0 - mid2, 0.0001)));
	if (rays > 0.0) {
		vec2 rp = (uv - ray_center) * face_size;
		float ang = (atan(rp.y, rp.x) + ray_angle) / 6.2831853 * ray_count;
		float f = fract(ang);
		float aa = fwidth(ang) * 0.75;
		float stripe = smoothstep(-aa, aa, f) * (1.0 - smoothstep(ray_width - aa, ray_width + aa, f));
		if (ray_reach > 0.0) {
			stripe *= 1.0 - smoothstep(ray_reach - 1.0, ray_reach + 1.0, length(rp));
		}
		col.rgb = mix(col.rgb, vec3(1.0), stripe * rays);
	}
	if (border > 0.0) {
		col = mix(col, border_color, clamp(d_face + border + 0.5, 0.0, 1.0));
	}
	if (lip > 0.0) {
		col = mix(col, lip_color, clamp(d_face + 0.5, 0.0, 1.0));
	}
	if (lip2 > 0.0) {
		col = mix(col, lip2_color, clamp(d_lip + 0.5, 0.0, 1.0));
	}
	COLOR = vec4(col.rgb, col.a * a) * tint;
}"""

static var _shader: Shader

var mode := 0:                      ## 0 radial, 1 vertical
	set(v): mode = v; _apply()
var c0 := Color.WHITE:
	set(v): c0 = v; _apply()
var c1 := Color(0.8, 0.8, 0.8):
	set(v): c1 = v; _apply()
var c2 := Color(0.5, 0.5, 0.5):
	set(v): c2 = v; _apply()
var c3 := Color(0.5, 0.5, 0.5):     ## the fourth stop (used when mid2 < 1)
	set(v): c3 = v; _apply()
var mid2 := 1.0:
	set(v): mid2 = v; _apply()
var mid := 0.4:
	set(v): mid = v; _apply()
var center := Vector2(0.5, 0.4):
	set(v): center = v; _apply()
var reach := Vector2(0.7, 0.6):
	set(v): reach = v; _apply()
var radius := 16.0:
	set(v): radius = v; _apply()
var radius_bottom := -1.0:          ## the bottom corners' radius (< 0: radius); 0 = square (a podium block)
	set(v): radius_bottom = v; _apply()
var border := 0.0:
	set(v): border = v; _apply()
var border_color := Color.TRANSPARENT:
	set(v): border_color = v; _apply()
var lip := 0.0:
	set(v): lip = v; _relayout()
var lip_color := Color.TRANSPARENT:
	set(v): lip_color = v; _apply()
var lip2 := 0.0:                    ## a second, outer lip under `lip`
	set(v): lip2 = v; _relayout()
var lip2_color := Color.TRANSPARENT:
	set(v): lip2_color = v; _apply()
var rays := 0.0:
	set(v): rays = v; _apply()
var ray_center := Vector2(0.25, 0.25):
	set(v): ray_center = v; _apply()
var ray_count := 16.0:
	set(v): ray_count = v; _apply()
var ray_width := 0.4:               ## the lit share of each ray period
	set(v): ray_width = v; _apply()
var ray_reach := 0.0:               ## px from ray_center where the rays end (0: no end)
	set(v): ray_reach = v; _apply()
var ray_angle := 0.0:               ## radians: tween it to turn the rays (one uniform, no relayout)
	set(v):
		ray_angle = v
		if _mat:
			_mat.set_shader_parameter("ray_angle", v)
var pad := 0.0:
	set(v): pad = v; _relayout()

var _mat: ShaderMaterial


static func radial(glow: Color, face: Color, deep: Color) -> GamePanel:
	var p := GamePanel.new()
	p.c0 = glow; p.c1 = face; p.c2 = deep
	return p

static func vertical(top: Color, bottom: Color) -> GamePanel:
	var p := GamePanel.new()
	p.mode = 1
	p.c0 = top; p.c1 = top.lerp(bottom, 0.5); p.c2 = bottom
	p.mid = 0.5
	return p


func _init() -> void:
	if _shader == null:
		_shader = Shader.new()
		_shader.code = SHADER
	_mat = ShaderMaterial.new()
	_mat.shader = _shader
	material = _mat
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(_apply)
	_relayout()


## A panel sized before it enters the tree (anchors / offsets set on a detached node) gets no `resized` there: give
## the shader its size on entering.
func _enter_tree() -> void:
	_apply()


func _relayout() -> void:
	var st := StyleBoxEmpty.new()
	st.content_margin_left = pad
	st.content_margin_right = pad
	st.content_margin_top = pad
	st.content_margin_bottom = pad + lip + lip2
	add_theme_stylebox_override("panel", st)
	_apply()


func _apply() -> void:
	if _mat == null:
		return
	_mat.set_shader_parameter("size", size)
	_mat.set_shader_parameter("radius", radius)
	_mat.set_shader_parameter("radius_bottom", radius_bottom)
	_mat.set_shader_parameter("border", border)
	_mat.set_shader_parameter("lip", lip)
	_mat.set_shader_parameter("lip2", lip2)
	_mat.set_shader_parameter("lip2_color", lip2_color)
	_mat.set_shader_parameter("c3", c3)
	_mat.set_shader_parameter("mid2", mid2)
	_mat.set_shader_parameter("ray_count", ray_count)
	_mat.set_shader_parameter("ray_width", ray_width)
	_mat.set_shader_parameter("ray_reach", ray_reach)
	_mat.set_shader_parameter("ray_angle", ray_angle)
	_mat.set_shader_parameter("mode", mode)
	_mat.set_shader_parameter("c0", c0)
	_mat.set_shader_parameter("c1", c1)
	_mat.set_shader_parameter("c2", c2)
	_mat.set_shader_parameter("mid", mid)
	_mat.set_shader_parameter("center", center)
	_mat.set_shader_parameter("reach", reach)
	_mat.set_shader_parameter("border_color", border_color)
	_mat.set_shader_parameter("lip_color", lip_color)
	_mat.set_shader_parameter("rays", rays)
	_mat.set_shader_parameter("ray_center", ray_center)
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color.WHITE)
