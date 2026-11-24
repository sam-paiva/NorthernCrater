"""macOS edits to FFNx (after tools/ffnx_edit_android.py): bgfx on Metal.

Run by tools/setup_mac.sh. Idempotent: each edit checks for its own marker.
"""
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, 'external', 'FFNx', 'src')

EDITS = [
    ('renderer.cpp',
     '''    switch (renderer_backend)
    {
    case RENDERER_BACKEND_AUTO:''',
     '''#ifdef FF7_MACOS
    return bgfx::RendererType::Metal;   // FF7Recomp macOS: Metal only
#endif
    switch (renderer_backend)
    {
    case RENDERER_BACKEND_AUTO:'''),
    ('renderer.cpp',
     '''#ifdef FFNX_ANDROID
    case bgfx::RendererType::OpenGLES:   // FF7Recomp
        currentRenderer = "OpenGL ES";
        shaderSuffix = ".gles";
        break;
#endif''',
     '''#ifdef FFNX_ANDROID
    case bgfx::RendererType::OpenGLES:   // FF7Recomp
        currentRenderer = "OpenGL ES";
        shaderSuffix = ".gles";
        break;
#endif
    case bgfx::RendererType::Metal:      // FF7Recomp macOS
        currentRenderer = "Metal";
        shaderSuffix = ".mtl";
        break;'''),
    ('renderer.cpp',
     '''    if ((bgfx::getRendererType() != bgfx::RendererType::Vulkan && bgfx::getRendererType() != bgfx::RendererType::OpenGLES) || getenv("FF7_TEST_VK_TRACE"))   // FF7Recomp''',
     '''    if ((bgfx::getRendererType() != bgfx::RendererType::Vulkan && bgfx::getRendererType() != bgfx::RendererType::OpenGLES && bgfx::getRendererType() != bgfx::RendererType::Metal) || getenv("FF7_TEST_VK_TRACE"))   // FF7Recomp'''),
    ('renderer.cpp',
     '''        if (bgfx::getRendererType() != bgfx::RendererType::Vulkan && bgfx::getRendererType() != bgfx::RendererType::OpenGLES)
        {''',
     '''        if (bgfx::getRendererType() != bgfx::RendererType::Vulkan && bgfx::getRendererType() != bgfx::RendererType::OpenGLES && bgfx::getRendererType() != bgfx::RendererType::Metal)
        {'''),
]

# FFNx defines globals in headers and links with /FORCE:MULTIPLE (lld: --allow-multiple-definition);
# Apple's linker has no such option, so these become C++17 inline definitions (one shared copy).
INLINE = [
    ('input.h', 'std::vector<MouseListener*> mouseListeners;', 'inline std::vector<MouseListener*> mouseListeners;'),
    ('input.h', 'std::vector<KeyListener*> keyListeners;', 'inline std::vector<KeyListener*> keyListeners;'),
    ('widescreen.h', 'int wide_game_x = 0;', 'inline int wide_game_x = 0;'),
    ('widescreen.h', 'int wide_game_y = 0;', 'inline int wide_game_y = 0;'),
    ('widescreen.h', 'int wide_game_width = 854;', 'inline int wide_game_width = 854;'),
    ('widescreen.h', 'int wide_game_height = 480;', 'inline int wide_game_height = 480;'),
    ('ff7/world/utils.h', '    bool is_key_pressed(int', '    inline bool is_key_pressed(int'),
    ('ff7/world/utils.h', '    bool is_key_pressed_first_time(', '    inline bool is_key_pressed_first_time('),
    ('ff7/world/utils.h', '    bool is_key_released(', '    inline bool is_key_released('),
    ('ff7/field/opcode.h', '    std::array<uint32_t, 256> original_opcode_table {0};', '    inline std::array<uint32_t, 256> original_opcode_table {0};'),
    ('ff7/field/model.h', '    uint32_t ff7_kawai_current_model_id = 0xFF;', '    inline uint32_t ff7_kawai_current_model_id = 0xFF;'),
    ('ff7/field/model.h', '    std::array<external_field_model_data, MAX_FIELD_MODELS> external_model_data;', '    inline std::array<external_field_model_data, MAX_FIELD_MODELS> external_model_data;'),
    ('ff7/field/background.h', '    vector2<float>\n        field_curr_delta_world_pos,', '    inline vector2<float>\n        field_curr_delta_world_pos,'),
    ('movies.h', 'extern short movie_fps_ratio = 1;', 'inline short movie_fps_ratio = 1;'),
    ('movies.h', 'extern bool is_movie_bgfield = false;', 'inline bool is_movie_bgfield = false;'),
    ('ff8/file.h', 'uint32_t(*ff8_read_file)(uint32_t count', 'inline uint32_t(*ff8_read_file)(uint32_t count'),
    ('ff8/file.h', 'void (*ff8_close_file)(struct ff8_file* file);', 'inline void (*ff8_close_file)(struct ff8_file* file);'),
    ('../../deps/openpsf/include/openpsf/openpsf.h', 'PsfFlags operator|(PsfFlags flags, PsfFlags other) noexcept {', 'inline PsfFlags operator|(PsfFlags flags, PsfFlags other) noexcept {'),
]
EDITS += INLINE

# The window resized (live resize, full screen): FFNx's WM_SIZE path (common.cpp) for the macOS
# window -- new output size, view offsets from scratch, framebuffers and swap chain rebuilt.
EDITS.append(('renderer.cpp',
'''        bgfxInit.swapChain.nwh = nwh;
        bgfx::reset(bgfxInit.reset, &bgfxInit.swapChain);
    }
#endif''',
'''        bgfxInit.swapChain.nwh = nwh;
        bgfx::reset(bgfxInit.reset, &bgfxInit.swapChain);
    }
#endif
#ifdef FF7_MACOS
    {   // FF7Recomp macOS: follow the window's size
        int w = 0, h = 0;
        ff7_platform_window(&w, &h);
        if (w > 0 && h > 0 && (w != (int)window_size_x || h != (int)window_size_y))
        {
            window_size_x = w;
            window_size_y = h;
            viewOffsetX = viewOffsetY = 0;
            x_offset = y_offset = 0;
            reset();
        }
    }
#endif'''))

# FF7Recomp: a 21:9 mode (aspect_ratio = 4), the way FFNx does 16:10: the widescreen viewport is
# 1138x480 (64:27, 2560x1080 and 3440x1440 screens) instead of 854x480; every widescreen patch
# reads wide_viewport_x / wide_viewport_width, so fields with room, battles, the world map and
# the menus widen with it. Fields narrower than that keep their bars, as they do at 16:9.
EDITS.extend([
('common.h',
'''	AR_WIDESCREEN_16X10,
	AR_COUNT''',
'''	AR_WIDESCREEN_16X10,
	AR_WIDESCREEN_21X9,   // FF7Recomp
	AR_COUNT'''),
('common.cpp',
'''		widescreen_enabled = (aspect_ratio == AR_WIDESCREEN_16X9 || aspect_ratio == AR_WIDESCREEN_16X10);''',
'''		widescreen_enabled = (aspect_ratio == AR_WIDESCREEN_16X9 || aspect_ratio == AR_WIDESCREEN_16X10 || aspect_ratio == AR_WIDESCREEN_21X9);'''),
('ff7/widescreen.cpp',
'''        viewport_width_plus_x_widescreen_fix = 704;
    }''',
'''        viewport_width_plus_x_widescreen_fix = 704;
    }
    else if (aspect_ratio == AR_WIDESCREEN_21X9)   // FF7Recomp
    {
        wide_viewport_x = -249;
        wide_viewport_width = 1138;
        wide_game_width = 1138;
        viewport_width_plus_x_widescreen_fix = 892;
    }'''),
('renderer.cpp',
'''        case AR_WIDESCREEN_16X10:''',
'''        case AR_WIDESCREEN_21X9:   // FF7Recomp: as 16:9, at the viewport's own ratio
            if (viewWidth * wide_game_height != viewHeight * wide_game_width)
            {
                if (viewHeight * wide_game_width > viewWidth * wide_game_height)
                {
                    viewOffsetY = (viewHeight - (viewWidth * wide_game_height) / wide_game_width) / 2;
                    viewHeight = (viewWidth * wide_game_height) / wide_game_width;
                    y_offset = viewOffsetY;
                }
                else
                {
                    viewOffsetX = (viewWidth - (viewHeight * wide_game_width) / wide_game_height) / 2;
                    viewWidth = (viewHeight * wide_game_width) / wide_game_height;
                    x_offset = viewOffsetX;
                }
            }
            break;
        case AR_WIDESCREEN_16X10:'''),
('gl/special_case.cpp',
'''16 / (aspect_ratio == AR_WIDESCREEN_16X10 ? 10.f : 9.f)''',
'''(aspect_ratio == AR_WIDESCREEN_21X9 ? (float)wide_game_width / wide_game_height : 16 / (aspect_ratio == AR_WIDESCREEN_16X10 ? 10.f : 9.f))'''),
])

# 21:9 fields: the camera clamp's half extension (53 = 107 / 2 at 16:9) follows the viewport, and a
# field wide enough for 16:9 but not for 21:9 still extends -- centred, as far as its background
# goes -- instead of dropping to 4:3.
EDITS.append(('ff7/field/background.cpp', 'std::min(53, cameraRangeSize / 2 - 160)',
              'std::min(aspect_ratio == AR_WIDESCREEN_21X9 ? abs(wide_viewport_x) / 2 : 53, cameraRangeSize / 2 - 160)', 'all'))
EDITS.append(('ff7/widescreen.cpp',
'''    if(camera_range.right - camera_range.left >= game_width / 2 + abs(wide_viewport_x))''',
'''    if(camera_range.right - camera_range.left >= game_width / 2 + (aspect_ratio == AR_WIDESCREEN_21X9 ? 107 : abs(wide_viewport_x)))   // FF7Recomp: 21:9'''))

# 21:9 world map: the clouds-and-sky quad is +-256 (enough for 16:9's half width of 213); at
# 21:9 the half width is 284, so it follows the skybox's own margin (width / 4 + 20).
EDITS.append(('ff7/widescreen.cpp',
'''    patch_code_short(ff7_externals.world_submit_draw_clouds_and_meteor_7547A6 + 0x132, -256);
    patch_code_int(ff7_externals.world_submit_draw_clouds_and_meteor_7547A6 + 0x144, 256);
    patch_code_byte(ff7_externals.world_submit_draw_clouds_and_meteor_7547A6 + 0x15C, 0);
    patch_code_short(ff7_externals.world_submit_draw_clouds_and_meteor_7547A6 + 0x16D, 256);''',
'''    const int clouds_half = aspect_ratio == AR_WIDESCREEN_21X9 ? wide_viewport_width / 4 + 20 : 256;   // FF7Recomp: 21:9
    patch_code_short(ff7_externals.world_submit_draw_clouds_and_meteor_7547A6 + 0x132, -clouds_half);
    patch_code_int(ff7_externals.world_submit_draw_clouds_and_meteor_7547A6 + 0x144, clouds_half);
    patch_code_byte(ff7_externals.world_submit_draw_clouds_and_meteor_7547A6 + 0x15C, 0);
    patch_code_short(ff7_externals.world_submit_draw_clouds_and_meteor_7547A6 + 0x16D, clouds_half);'''))

# The widescreen code patches (ff7_widescreen_hook_init, at driver start) bake values like the
# skybox's width / 4 + 20 into the game's code before Widescreen::init sets the 21:9 viewport:
# set it here first.
EDITS.append(('ff7/widescreen.cpp',
'''void ff7_widescreen_hook_init() {
    // Field fix''',
'''void ff7_widescreen_hook_init() {
    if (aspect_ratio == AR_WIDESCREEN_21X9)   // FF7Recomp: as Widescreen::init, before the patches below
    {
        wide_viewport_x = -249;
        wide_viewport_width = 1138;
        wide_game_width = 1138;
        viewport_width_plus_x_widescreen_fix = 892;
    }
    // Field fix'''))

# Snowboard minigame: FFNx hooks the game's thiscall 0x732159 with a __fastcall (this in ecx, edx
# unused). __fastcall is empty here and the override reads every parameter off the guest stack, so
# `this` and `edx` ate the first two stack arguments and `matrix` received obj_type (the game
# closed as the board run started: a fault reading guest address 2). `this` is in the guest ecx.
EDITS.append(('ff7/minigames.cpp',
'void __fastcall ff7_snowboard_parse_model_vertices(snowboard_this* _this, void* edx, const matrix *matrix, int current_obj, int obj_type, int unk)\n{',
'void __fastcall ff7_snowboard_parse_model_vertices(const matrix *matrix, int current_obj, int obj_type, int unk)\n{\n  snowboard_this* _this = (snowboard_this*)GPTR(g_ecx);   // thiscall: this is in ecx'))

EDITS.append(('ff7/defs.h',
'void __fastcall ff7_snowboard_parse_model_vertices(snowboard_this* _this, void* edx, const matrix *matrix, int current_obj, int obj_type, int unk);',
'void __fastcall ff7_snowboard_parse_model_vertices(const matrix *matrix, int current_obj, int obj_type, int unk);'))

# The frame limiter's sleep: macOS wakes a nanosleep late (timer coalescing), so every frame ran
# long (57 FPS at 60). The Mac host sleeps to an absolute deadline with mach_wait_until.
EDITS.append(('ff7/misc.cpp',
'''		if (left_us > 500.0) std::this_thread::sleep_for(std::chrono::microseconds((long long)(left_us - 250.0)));''',
'''#ifdef FF7_MACOS
		extern void ff7r_sleep_us(long long us);   // FF7Recomp macOS: src/mac/ff7_mac_main.mm
		if (left_us > 500.0) ff7r_sleep_us((long long)(left_us - 250.0));
#else
		if (left_us > 500.0) std::this_thread::sleep_for(std::chrono::microseconds((long long)(left_us - 250.0)));
#endif'''))

# ...and the next deadline is the last one plus a frame, not "now": a wake-up that is still a
# little late then costs that frame only, instead of every frame running long (57 FPS at 60).
EDITS.append(('ff7/misc.cpp',
'''	while (gametime > last_gametime && qpc_diff_time(&gametime, &last_gametime, nullptr) < frame_time);
#endif

	last_gametime = gametime;''',
'''	while (gametime > last_gametime && qpc_diff_time(&gametime, &last_gametime, nullptr) < frame_time);
#endif

#ifdef FF7_MACOS
	if (gametime > last_gametime && (double)qpc_diff_time(&gametime, &last_gametime, nullptr) < 2 * frame_time)
		last_gametime += (time_t)frame_time;   // FF7Recomp macOS: steady deadlines
	else
#endif
	last_gametime = gametime;'''))


# Scene changes (entering a battle): mod PNGs were decoded by bimg's lodepng, about twice as slow
# as libpng (FFNx's own loadPng, already used for other PNGs): PNGs now go through libpng.
EDITS.append(('image/image.cpp',
'''bimg::ImageContainer *loadImageContainer(bx::AllocatorI *allocator, const char *filename, bimg::TextureFormat::Enum targetFormat)
{
    FILE* file = fopen(filename, "rb");''',
'''bimg::ImageContainer *loadImageContainer(bx::AllocatorI *allocator, const char *filename, bimg::TextureFormat::Enum targetFormat)
{
#ifdef FF7_MACOS
    // FF7Recomp: PNGs through libpng (faster than bimg's lodepng); anything else, or a PNG libpng
    // cannot read, as before
    if (const size_t n = strlen(filename); n > 4 && _stricmp(filename + n - 4, ".png") == 0)
        if (bimg::ImageContainer *png = loadPng(allocator, filename, targetFormat)) return png;
#endif
    FILE* file = fopen(filename, "rb");'''))

# The game's own textures, converted to 32-bit when a scene loads (the battle's models and
# effects): per pixel, FFNx divided by each channel's maximum (16-bit) or reread the palette
# through the format struct. Now a table: the palette once per image (256 entries), and 16-bit
# formats through a 64K-entry table kept for the last few formats.
EDITS.append(('common.cpp',
'''void convert_image_data(const unsigned char *image_data, uint32_t *converted_image_data, uint32_t w, uint32_t h, struct texture_format *tex_format, uint32_t invert_alpha, uint32_t color_key, uint32_t palette_offset, uint32_t reference_alpha)
{
	uint32_t i, j, o = 0, c = 0;
''',
'''#ifdef FF7_MACOS
static uint32_t ff7r_convert_one(uint32_t pixel, const struct texture_format *tex_format, uint32_t invert_alpha, uint32_t color_key)
{
	if((color_key == 1 && (pixel & ~tex_format->alpha_mask) == 0) || (color_key == 3 && pixel == 0)) return 0;
	uint32_t color = tex_format->blue_max > 0 ? ((((pixel & tex_format->blue_mask) >> tex_format->blue_shift) * 255) / tex_format->blue_max) : 0;
	color |= (tex_format->green_max > 0 ? ((((pixel & tex_format->green_mask) >> tex_format->green_shift) * 255) / tex_format->green_max) : 0) << 8;
	color |= (tex_format->red_max > 0 ? ((((pixel & tex_format->red_mask) >> tex_format->red_shift) * 255) / tex_format->red_max) : 0) << 16;
	if(invert_alpha && pixel != 0x8000) color |= (tex_format->alpha_max > 0 ? (255 - ((((pixel & tex_format->alpha_mask) >> tex_format->alpha_shift) * 255) / tex_format->alpha_max)) : 255) << 24;
	else color |= (tex_format->alpha_max > 0 ? ((((pixel & tex_format->alpha_mask) >> tex_format->alpha_shift) * 255) / tex_format->alpha_max) : 255) << 24;
	return color;
}

// FF7Recomp: the fast paths (same results as the loops below)
static bool ff7r_convert_fast(const unsigned char *image_data, uint32_t *out, uint32_t n, struct texture_format *tex_format, uint32_t invert_alpha, uint32_t color_key, uint32_t palette_offset, uint32_t reference_alpha)
{
	if(tex_format->bytesperpixel == 1 && tex_format->use_palette)
	{
		uint8_t top = 0;
		for(uint32_t k = 0; k < n; k++) if(image_data[k] > top) top = image_data[k];
		if(top > tex_format->palette_size) return false;   // the loop below reports it
		uint32_t lut[256];
		const uint32_t *pal = tex_format->palette_data;
		for(uint32_t k = 0; k <= top; k++)
		{
			if(color_key && k == 0) { lut[k] = 0; continue; }
			uint32_t color = pal[palette_offset + k];
			if(BGRA_A(color) == 0xFE) color = (color & 0xFFFFFF) | reference_alpha;
			lut[k] = color;
		}
		for(uint32_t k = 0; k < n; k++) out[k] = lut[image_data[k]];
		return true;
	}
	if(tex_format->bytesperpixel == 2 && !tex_format->use_palette)
	{
		struct cached { uint32_t key[14]; uint32_t *lut; };
		static cached cache[6];
		static int next;
		const uint32_t key[14] = { tex_format->blue_mask, tex_format->green_mask, tex_format->red_mask, tex_format->alpha_mask,
			tex_format->blue_shift, tex_format->green_shift, tex_format->red_shift, tex_format->alpha_shift,
			tex_format->blue_max, tex_format->green_max, tex_format->red_max, tex_format->alpha_max, invert_alpha, color_key };
		uint32_t *lut = nullptr;
		for(auto &e : cache) if(e.lut && memcmp(e.key, key, sizeof key) == 0) { lut = e.lut; break; }
		if(!lut)
		{
			if(n < 16384) return false;   // a small image: the table would cost more than it saves
			cached &e = cache[next]; next = (next + 1) % 6;
			if(!e.lut) e.lut = (uint32_t *)malloc(65536 * sizeof(uint32_t));
			if(!e.lut) return false;
			for(uint32_t p = 0; p < 65536; p++) e.lut[p] = ff7r_convert_one(p, tex_format, invert_alpha, color_key);
			memcpy(e.key, key, sizeof key);
			lut = e.lut;
		}
		const uint16_t *src = (const uint16_t *)image_data;
		for(uint32_t k = 0; k < n; k++) out[k] = lut[src[k]];
		return true;
	}
	return false;
}
#endif

void convert_image_data(const unsigned char *image_data, uint32_t *converted_image_data, uint32_t w, uint32_t h, struct texture_format *tex_format, uint32_t invert_alpha, uint32_t color_key, uint32_t palette_offset, uint32_t reference_alpha)
{
	uint32_t i, j, o = 0, c = 0;
#ifdef FF7_MACOS
	if(!ff8 && ff7r_convert_fast(image_data, converted_image_data, w * h, tex_format, invert_alpha, color_key, palette_offset, reference_alpha)) return;
#endif
'''))


# 21:9 battles: the mods' battle windows are laid out for 16:9, so at 21:9 the status window
# (party HP/MP, bars) sits 142 px in from the right edge. The launcher's setting (boosters.txt
# battlehud) keeps it there (the default: less to look across), or moves it halfway or all the way out. Every 2D quad of the battle window band
# (y 330 and down, as companion_render.cpp's band) that lies right of x 320 is drawn 142 px
# further right: the whole status group moves together, while the command window and its lists
# (which end left of 300) and anything above the band (the 3D battle, damage numbers, the
# action name) stay. A copy of the vertices is moved, never the game's own. A layout whose
# window spans x 320 (the game's own UI without mods) is left as it is.
EDITS.append(('gl/gl.cpp', '#include <algorithm>\n#include <unordered_map>', '#include <algorithm>\n#include <chrono>\n#include <unordered_map>'))
EDITS.append(('gl/gl.cpp',
'''	// should never happen, broken 3rd-party models cause this
	if(!count) return;
''',
'''	// should never happen, broken 3rd-party models cause this
	if(!count) return;

#ifdef FF7_MACOS
	// FF7Recomp: at 21:9 the battle status windows to the right edge
	static std::vector<struct nvertex> ff7r_moved;
	extern bool ff7r_replaying_deferred;   // a deferred draw comes back here: moved already
	extern int ff7r_battle_hud;            // 0 as 16:9 has it, 1 halfway, 2 at the edge (Settings, boosters.txt)
	const float ff7r_shift = ff7r_battle_hud == 2 ? 142.0f : ff7r_battle_hud == 1 ? 71.0f : 0.0f;
	if (!ff8 && ff7r_shift > 0 && !ff7r_replaying_deferred && aspect_ratio == AR_WIDESCREEN_21X9 && vertextype == TLVERTEX && mode == MODE_BATTLE && vertexcount && vertexcount % 4 == 0)
	{
		bool band = true;
		for (uint32_t k = 0; k < vertexcount && band; k++) band = vertices[k]._.y >= 330.0f;
		// a band window across x 320 (the game's own status window, a wide list): this layout is
		// not split in two groups, so nothing is moved while one has been seen in the last 0.4 s
		static std::chrono::steady_clock::time_point ff7r_whole_until;
		const auto ff7r_now = std::chrono::steady_clock::now();
		if (band)
			for (uint32_t q = 0; q < vertexcount; q += 4)
			{
				const float x0 = std::min(std::min(vertices[q]._.x, vertices[q + 1]._.x), std::min(vertices[q + 2]._.x, vertices[q + 3]._.x));
				const float x1 = std::max(std::max(vertices[q]._.x, vertices[q + 1]._.x), std::max(vertices[q + 2]._.x, vertices[q + 3]._.x));
				const float y0 = std::min(std::min(vertices[q]._.y, vertices[q + 1]._.y), std::min(vertices[q + 2]._.y, vertices[q + 3]._.y));
				const float y1 = std::max(std::max(vertices[q]._.y, vertices[q + 1]._.y), std::max(vertices[q + 2]._.y, vertices[q + 3]._.y));
				// a line (no height; the status rows' underlines) does not count
				if (x0 < 310.0f && x1 > 330.0f && y1 - y0 > 2.0f) ff7r_whole_until = ff7r_now + std::chrono::milliseconds(400);
			}
		if (ff7r_now < ff7r_whole_until) band = false;
		bool any = false;
		if (band)
			for (uint32_t q = 0; q < vertexcount && !any; q += 4)
				any = std::min(std::min(vertices[q]._.x, vertices[q + 1]._.x), std::min(vertices[q + 2]._.x, vertices[q + 3]._.x)) >= 320.0f;
		if (any)
		{
			ff7r_moved.assign(vertices, vertices + vertexcount);
			for (uint32_t q = 0; q < vertexcount; q += 4)
				if (std::min(std::min(vertices[q]._.x, vertices[q + 1]._.x), std::min(vertices[q + 2]._.x, vertices[q + 3]._.x)) >= 320.0f)
					for (uint32_t k = q; k < q + 4; k++) ff7r_moved[k]._.x += ff7r_shift;
			vertices = ff7r_moved.data();
		}
	}
#endif
'''))


EDITS.append(('gl/deferred.cpp',
'''			gl_load_state(&deferred_draws[i].state);
			gl_draw_indexed_primitive(deferred_draws[i].primitivetype,''',
'''			gl_load_state(&deferred_draws[i].state);
#ifdef FF7_MACOS
			struct ff7r_replay { ff7r_replay() { ff7r_replaying_deferred = true; } ~ff7r_replay() { ff7r_replaying_deferred = false; } } ff7r_replay_guard;
#endif
			gl_draw_indexed_primitive(deferred_draws[i].primitivetype,'''))
EDITS.append(('gl/deferred.cpp',
'''		gl_draw_indexed_primitive(deferred_sorted_draws[next].deferred_draw.primitivetype,''',
'''#ifdef FF7_MACOS
		struct ff7r_replay { ff7r_replay() { ff7r_replaying_deferred = true; } ~ff7r_replay() { ff7r_replaying_deferred = false; } } ff7r_replay_guard;
#endif
		gl_draw_indexed_primitive(deferred_sorted_draws[next].deferred_draw.primitivetype,'''))
EDITS.append(('gl/deferred.cpp',
'''uint32_t gl_defer_draw(''',
'''#ifdef FF7_MACOS
bool ff7r_replaying_deferred;   // gl.cpp: the 21:9 battle window move is not made twice
#endif
uint32_t gl_defer_draw('''))

# The battle swirl (and anything drawn from a copy of the frame) was upside down: FFNx's vertex
# shaders flip a framebuffer texture's V for OpenGL's bottom-left origin, and skip it only for
# HLSL and SPIR-V. Metal's origin is top-left as theirs, so it is skipped there too.
for _vs in ('../misc/FFNx.vert', '../misc/FFNx.lighting.vert'):
    EDITS.append((_vs,
'''    #if BGFX_SHADER_LANGUAGE_SPIRV
    #else''',
'''    #if BGFX_SHADER_LANGUAGE_SPIRV || BGFX_SHADER_LANGUAGE_METAL   // FF7Recomp: Metal's origin is top-left too
    #else'''))

# The offset build (Apple arm64, FF7_OFFSET_MEMORY): FFNx keeps ~550 of the game's addresses as
# raw pointers (ff7_data.h: ff7_externals.x = (T *)get_absolute_value(...)). Each becomes a
# pointer into guest memory through GPTR (recomp_types.h; the same number in the flat builds).
import re as _re
_EXT_PTR = _re.compile(r'^(\s*(?:ff7|common)_externals\.\w+(?:\[[^\]]*\])?\s*=\s*\((?:const\s+)?[A-Za-z_][\w<>: ]*\s*\*+\s*\))\s*(?!GPTR\()(.+?);(\s*(?://.*)?)$')
def guest_pointer_pass():
    total = 0
    for name in ('ff7_data.h', 'externals_102_us.h', 'externals_102_fr.h', 'externals_102_de.h', 'externals_102_sp.h'):
        total += guest_pointer_file(os.path.join(SRC, name))
    return total


def guest_pointer_file(p):
    lines = open(p, encoding='utf-8', errors='surrogateescape').read().split('\n')
    out, n = [], 0
    for l in lines:
        m = _EXT_PTR.match(l)
        # two fields computed from fields that are already pointers into game memory
        if m and ('field_file_buffer)' in l or '(char *)ff7_externals.word_CC16E8' in l): m = None
        if m:
            l = f'{m.group(1)}GPTR({m.group(2)});{m.group(3)}'
            n += 1
        out.append(l)
    if n:
        open(p, 'w', encoding='utf-8', errors='surrogateescape').write('\n'.join(out))
    return n


def main():
    n = guest_pointer_pass()
    if n: print(f'ffnx_edit_mac: {n} game addresses in ff7_data.h / externals_102_*.h made guest pointers')
    for name, old, new, *how in EDITS:
        p = os.path.normpath(os.path.join(SRC, name))
        old, new = old.replace('\\n', '\n'), new.replace('\\n', '\n')
        s = open(p, encoding='utf-8', errors='surrogateescape').read()
        if new in s:
            continue
        if old not in s:
            sys.exit(f'ffnx_edit_mac: anchor not found in {name}:\n{old[:120]}')
        s = s.replace(old, new) if how == ['all'] else s.replace(old, new, 1)
        open(p, 'w', encoding='utf-8', errors='surrogateescape').write(s)
        n += 1
    print(f'ffnx_edit_mac: {n} edits applied')
    # the offset build's casts (tools/ffnx_offset_fix.py made the list from the compiler's warnings)
    import json
    off = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'ffnx_offset_edits.json')
    if os.path.exists(off):
        k = 0
        for name, old, new in json.load(open(off, encoding='utf-8')):
            p = os.path.join(SRC, name)
            s = open(p, encoding='utf-8', errors='surrogateescape').read()
            if new in s and old not in s:
                continue
            if old not in s:
                sys.exit(f'ffnx_edit_mac: offset-build line not found in {name}:\n{old.strip()[:120]}')
            s = s.replace(old, new)
            open(p, 'w', encoding='utf-8', errors='surrogateescape').write(s)
            k += 1
        print(f'ffnx_edit_mac: {k} offset-build cast edits applied')


if __name__ == '__main__':
    main()
