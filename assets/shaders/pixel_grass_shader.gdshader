// NOTE: Shader automatically converted from Godot Engine 4.4.1.stable's StandardMaterial3D.

shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx, vertex_lighting;

uniform vec4 albedo : source_color;
uniform sampler2D texture_albedo : source_color, filter_nearest, repeat_enable;
uniform float alpha_scissor_threshold : hint_range(0.0, 1.0, 0.001);
uniform ivec2 albedo_texture_size;
uniform float point_size : hint_range(0.1, 128.0, 0.1);

uniform vec3 uv1_scale;
uniform vec3 uv1_offset;
uniform vec3 uv2_scale;
uniform vec3 uv2_offset;

void vertex() {
	// Shading Mode: Per Vertex

	UV = UV * uv1_scale.xy + uv1_offset.xy;

	// Billboard Mode: Enabled
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
			MAIN_CAM_INV_VIEW_MATRIX[0],
			MAIN_CAM_INV_VIEW_MATRIX[1],
			MAIN_CAM_INV_VIEW_MATRIX[2],
			MODEL_MATRIX[3]);
	//MODELVIEW_NORMAL_MATRIX = mat3(vec3(0,0,0),vec3(0,0,0),vec3(0,0,0));
	//MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
	MODELVIEW_NORMAL_MATRIX = MODELVIEW_NORMAL_MATRIX;
}

void fragment() {
	vec2 base_uv = UV;

	vec4 albedo_tex = texture(texture_albedo, base_uv);

	// Vertex Color Use as Albedo: Enabled
	albedo_tex *= COLOR;

	ALBEDO = albedo.rgb;// * albedo_tex.rgb;

	ALPHA *= albedo.a * albedo_tex.a;
	ALPHA_SCISSOR_THRESHOLD = alpha_scissor_threshold;
}



//
//
//
//// NOTE: Shader automatically converted from Godot Engine 4.4.1.stable's StandardMaterial3D.
//
//shader_type spatial;
//render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_disabled, vertex_lighting;
//
//uniform vec4 albedo : source_color;
//uniform sampler2D texture_albedo : source_color, filter_nearest, repeat_enable;
//uniform float alpha_scissor_threshold : hint_range(0.0, 1.0, 0.001);
//uniform ivec2 albedo_texture_size;
//uniform float point_size : hint_range(0.1, 128.0, 0.1);
//
//uniform vec3 uv1_scale;
//uniform vec3 uv1_offset;
//uniform vec3 uv2_scale;
//uniform vec3 uv2_offset;
//
//void vertex() {
	//// Shading Mode: Per Vertex
	//UV = UV * uv1_scale.xy + uv1_offset.xy;
//
	//// Billboard Mode: Enabled
	//MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
			//MAIN_CAM_INV_VIEW_MATRIX[0],
			//MAIN_CAM_INV_VIEW_MATRIX[1],
			//MAIN_CAM_INV_VIEW_MATRIX[2],
			//MODEL_MATRIX[3]);
	////MODELVIEW_NORMAL_MATRIX = mat3(vec3(0,0,0),vec3(0,0,0),vec3(0,0,0));
	//MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
	//
//}
//
//void fragment() {
	//
	//LIGHT_VERTEX = MODEL_MATRIX[3].xyz;
	//
	//vec2 base_uv = UV;
//
	//vec4 albedo_tex = texture(texture_albedo, base_uv);
	//ALBEDO = albedo.rgb;
//
	//ALPHA *= albedo.a * albedo_tex.a;
	//ALPHA_SCISSOR_THRESHOLD = alpha_scissor_threshold;
//}
