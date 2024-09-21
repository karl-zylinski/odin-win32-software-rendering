package game

import "base:runtime"
import "core:fmt"
import "core:math"
import "core:math/linalg"
import "core:slice"
import "core:time"
import "core:log"
import "core:image/png"
import "core:image"
import win "core:sys/windows"

_ :: fmt
_ :: png

Vec2 :: [2]f32
Color :: [4]u8

// Rectangle with position, width and height
Rect :: struct {
	x, y, w, h: f32,
}

// Single bit texture: data is just an array of booleans saying if there is
// color or not there.
Texture :: struct {
	data: []bool,
	w: int,
	h: int,
}

Key :: enum {
	None,
	Left,
	Right,
	Up,
	Down,
}

Player :: struct {
	anim_texture: Texture,
	anim_frame: int,
	anim_timer: f32,
	pos: Vec2,
	flip_x: bool,
}

// The size of the bitmap we will use for drawing. Will be scaled up to window.
SCREEN_WIDTH :: 320
SCREEN_HEIGHT :: 180

player: Player

// State of held keys
key_down: [Key]bool

// 2 color palette (1 bit graphics)
PALETTE :: [2]Color {
	{ 41, 61, 49, 255 },
	{ 241, 167, 189, 255 },
}

screen_buffer_bitmap_handle: win.HBITMAP

// This is the pixels for the screen. 0 means first color of PALETTE and 1 means
// second color of PALETTE. Higher numbers mean nothing.
screen_buffer: []u8

run := true

main :: proc() {
	context.logger = log.create_console_logger()

	// Make program respect DPI scaling.
	win.SetProcessDPIAware()

	// The handle of this executable. Some Windows API functions use it to
	// identify the running program.
	instance := win.HINSTANCE(win.GetModuleHandleW(nil))
	assert(instance != nil, "Failed to fetch current instance")

	// Create a new type of window with the type name `window_class_name`,
	// `win_proc` is the procedure that is run when the window is sent messages.
	window_class_name := win.L("SoftwareRenderingExample")
	window_class := win.WNDCLASSW {
		lpfnWndProc = win_proc,
		lpszClassName = window_class_name,
		hInstance = instance,
	}
	class := win.RegisterClassW(&window_class)
	assert(class != 0, "Class creation failed")

	// Create window, note that we reuse the class name to make this window
	// a window of that type. Other than that we mostly provide a window title,
	// a window size and a position. WS_OVERLAPPEDWINDOW makes this "normal
	// looking window" and WS_VISIBLE makes the window not hidden. See
	// https://learn.microsoft.com/en-us/windows/win32/winmsg/window-styles for
	// all styles.
	hwnd := win.CreateWindowW(window_class_name,
		win.L("Software Rendering"),
		win.WS_OVERLAPPEDWINDOW | win.WS_VISIBLE,
		100, 100, 1280, 720,
		nil, nil, instance, nil)
	assert(hwnd != nil, "Window creation Failed")

	// In case the window doesn't end up in the foreground for some reason.
	win.SetForegroundWindow(hwnd)

	// Load texture for player, it's a 2 frame animation.
	player_anim_texture, player_anim_texture_ok := load_texture("walk_animation.png")

	if !player_anim_texture_ok {
		fmt.println("Failed to walk_animation.png")
		return
	}

	player = {
		pos = {40, 40},
		anim_texture = player_anim_texture,
	}

	// Use built in Odin high resolution timer for tracking frame time.
	prev_time := time.tick_now()

	for	run {
		// Calculate frame time: the time from previous to current frame
		dt := f32(time.duration_seconds(time.tick_lap_time(&prev_time)))

		tick(dt)

		// This will make WM_PAINT run in the message loop, see wnd_proc
		win.InvalidateRect(hwnd, nil, false)

		pump()

		// Anything on temp allocator is valid until end of frame.
		free_all(context.temp_allocator)
	}

	delete_texture(player.anim_texture)
}

tick :: proc(dt: f32) {
	movement: Vec2

	if key_down[.Left] {
		movement.x -= 1
		player.flip_x = true
	}

	if key_down[.Right] {
		movement.x += 1
		player.flip_x = false
	}

	if key_down[.Up] {
		movement.y -= 1
	}

	if key_down[.Down] {
		movement.y += 1
	}

	// Normalize input so you don't walk faster when walking diagonally.
	movement = linalg.normalize0(movement)

	if movement.x != 0 {
		// If player moves, then update animation. It's just a timer that hops
		// between two frames.

		player.anim_timer -= dt
		if player.anim_timer <= 0 {
			player.anim_frame += 1

			if player.anim_frame > 1 {
				player.anim_frame = 0
			}

			player.anim_timer = 0.1
		}
	}

	player.pos += movement * 60 * dt
}

// Runs Windows message pump. The DispatchMessageW call will run `wnd_proc` if
// the message belongs to this window. `wnd_proc` as specified in the
// `window_class` in `main`.
pump :: proc() {
	msg: win.MSG

	// Use PeekMessage instead of GetMessage to not block and wait for message.
	// This makes it so that our main game loop continues and we can draw frames
	// although no messages occur.
	for win.PeekMessageW(&msg, nil, 0, 0, win.PM_REMOVE) {
		if (msg.message == win.WM_QUIT) {
			run = false
			break
		}

		win.DispatchMessageW(&msg)
	}
}

draw :: proc(hwnd: win.HWND) {
	// This clears the screen.
	slice.zero(screen_buffer)
	
	draw_rect({20, 56, 200, 8})

	// Draw player
	{
		// The rectangle in the animation image to use.
		anim_frame_rect := Rect {
			x = f32(8*player.anim_frame),
			y = 0,
			w = 8,
			h = 16,
		}

		draw_texture(player.anim_texture, anim_frame_rect, player.pos, player.flip_x)	
	}
	
	// Begin painting of window. This gives a hdc: A device context handle,
	// which is a handle we can use to instruct the Windows API to draw stuff
	// for us.
	ps: win.PAINTSTRUCT
	dc := win.BeginPaint(hwnd, &ps)

	// Make make dc into an in-memory DC we can draw into. Then select the
	// our screen buffer bitmap, so we can draw it to the screen.
	bitmap_dc := win.CreateCompatibleDC(dc)
	old_bitmap_handle := win.SelectObject(bitmap_dc, win.HGDIOBJ(screen_buffer_bitmap_handle))

	// Get size of window
	client_rect: win.RECT
	win.GetClientRect(hwnd, &client_rect)
	width := client_rect.right - client_rect.left
	height := client_rect.bottom - client_rect.top

	// Draw bitmap onto window. Note that this is stretched to size of window.
	win.StretchBlt(dc, 0, 0, width, height, bitmap_dc, 0, 0, SCREEN_WIDTH, SCREEN_HEIGHT, win.SRCCOPY)

	// Delete the temporary bitmap DC
	win.SelectObject(bitmap_dc, old_bitmap_handle)
	win.DeleteDC(bitmap_dc)

	// This must happen if `BeginPaint` has happened.
	win.EndPaint(hwnd, &ps)
}

win_proc :: proc "stdcall" (hwnd: win.HWND, msg: win.UINT, wparam: win.WPARAM, lparam: win.LPARAM) -> win.LRESULT {
	context = runtime.default_context()
	switch(msg) {
	case win.WM_DESTROY:
		// This makes the WM_QUIT message happen, which will set run = false
		win.PostQuitMessage(0)
		return 0

	case win.WM_KEYDOWN:
		switch wparam {
		case win.VK_LEFT:
			key_down[.Left] = true

		case win.VK_RIGHT:
			key_down[.Right] = true

		case win.VK_UP:
			key_down[.Up] = true

		case win.VK_DOWN:
			key_down[.Down] = true
		}
		return 0

	case win.WM_KEYUP:
		switch wparam {
		case win.VK_LEFT:
			key_down[.Left] = false

		case win.VK_RIGHT:
			key_down[.Right] = false

		case win.VK_UP:
			key_down[.Up] = false

		case win.VK_DOWN:
			key_down[.Down] = false
		}
		return 0

	case win.WM_PAINT:
		draw(hwnd)
		return 0

	case win.WM_CREATE:
		dc := win.GetDC(hwnd)

		// Create bitmap for drawing into.

		// There is a BITMAPINFO in windows API, but to make it easier to
		// specify our palette we make our own.
		Bitmap_Info :: struct {
			bmiHeader: win.BITMAPINFOHEADER,
			bmiColors: [len(PALETTE)]Color,
		}

		bitmap_info := Bitmap_Info {
			bmiHeader = win.BITMAPINFOHEADER {
				biSize        = size_of(win.BITMAPINFOHEADER),
				biWidth       = SCREEN_WIDTH,
				biHeight      = -SCREEN_HEIGHT, // Minus for top-down
				biPlanes      = 1,
				biBitCount    = 8, // We are actually doing 1 bit graphics, but 8 bit is minimum bitmap size.
				biCompression = win.BI_RGB,
				biClrUsed     = len(PALETTE), // Palette contains 2 colors. This tells it how big the bmiColors in the palette actually is.
			},
			bmiColors = PALETTE,
		}

		// buf will contain our pixels, of the size we specify in bitmap_info
		buf: [^]u8
		screen_buffer_bitmap_handle = win.CreateDIBSection(dc, cast(^win.BITMAPINFO)&bitmap_info, win.DIB_RGB_COLORS, &buf, nil, 0)

		// Make a slice we can use for drawing onto the screen
		screen_buffer = slice.from_ptr(buf, SCREEN_WIDTH*SCREEN_HEIGHT)

		win.ReleaseDC(hwnd, dc)

		return 0
	}

	return win.DefWindowProcW(hwnd, msg, wparam, lparam)
}

// Draw rectangle onto screen by looping over pixels in the rect and setting
// pixels on screen.
draw_rect :: proc(r: Rect) {
	for x in r.x..<r.x+r.w {
		for y in r.y..<r.y+r.h {
			idx := int(math.floor(y) * SCREEN_WIDTH) + int(math.floor(x))
			if idx >= 0 && idx < len(screen_buffer) {
				// 1 means the second color in PALETTE
				screen_buffer[idx] = 1
			}
		}
	}
}

// Draws texture `t` on screen. `src` is the rectangle inside `t` to pick stuff
// from. `pos` is where on screen to draw it. `flip_x` flips the texture.
draw_texture :: proc(t: Texture, src: Rect, pos: Vec2, flip_x: bool) {
	for x in 0..<src.w {
		for y in 0..<src.h {
			sx := x + src.x
			sy := y + src.y
			src_idx := floor_to_int(sy) * t.w + (flip_x ? floor_to_int(src.w - x + src.x) - 1 : floor_to_int(sx))
			
			if src_idx >= 0 && src_idx < len(t.data) && t.data[src_idx] {
				xx := floor_to_int(pos.x) + floor_to_int(x)
				yy := floor_to_int(pos.y) + floor_to_int(y)

				idx := yy * SCREEN_WIDTH + xx

				if idx >= 0 && idx < len(screen_buffer) {
					// 1 means the second color in PALETTE
					screen_buffer[idx] = 1
				}
			}
		}
	}
}

floor_to_int :: proc(v: f32) -> int {
	return int(math.floor(v))
}

// Loads an iomage with a specific filename and makes it into a `Texture` struct
load_texture :: proc(filename: string) -> (Texture, bool) {
	img, img_err := image.load_from_file(filename, allocator = context.temp_allocator)

	if img_err != nil {
		log.error(img_err)
		return {}, false
	}

	if img.channels != 4 || img.depth != 8 {
		// This is just because of my hack below to figure out the palette color.
		log.error("Only images with 4 channels and 8 bits per channel are supported.")	
		return {}, false
	}

	tex := Texture {
		data = make([]bool, img.width*img.height),
		w = img.width,
		h = img.height,
	}

	// This is a hack to convert from RGBA texture to single bit texture. We
	// loop over pixels and only look at alpha value. If alpha is larger than
	// 100, then the pixel is set, otherwise it is not.
	for pi in 0..<img.width*img.height {
		i := pi*4 + 1
		tex.data[pi] = img.pixels.buf[i] > 100
	}

	return tex, true
}

delete_texture :: proc(t: Texture) {
	delete(t.data)
}
