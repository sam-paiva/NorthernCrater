// ff7_mac_main.mm - the macOS app: a Cocoa window with a CAMetalLayer for bgfx (Metal), the
// keyboard and game controllers folded into one XInput-style pad, and the lifted game on its
// own thread (ff7_boot_and_run), as src/android/ff7_android_main.cpp does on Android.
//
// The game folder is <app>/Contents/Resources/game when the app carries one, else the folder in
// FF7_GAME_DIR, else ~/Library/Application Support/FF7Recomp/game.
//
// Keyboard (the pad the game sees):
//   arrows       D-pad              Enter / K   OK (Circle)
//   Backspace/J  Cancel (Cross)     Space / I   Menu (Triangle)
//   Shift / U    Square             Q / W       L1 / R1
//   1 / 2        L2 / R2            Tab         Select     P   Start
//   L / R        L3 / R3 (L3: FFNx's shortcut mode: then W/Q speed, Enter battles, Backspace battle+)
//   Cmd+F        fullscreen         Cmd+Q       quit        Cmd+L / Select+Start held 2 s: back to the launcher
#import <Cocoa/Cocoa.h>
#import <GameController/GameController.h>
#import <QuartzCore/CAMetalLayer.h>
#import <Metal/Metal.h>
#import <CoreHaptics/CoreHaptics.h>
#include <mach/mach_time.h>
#include <atomic>
#include <algorithm>
#include <vector>
#include <sys/resource.h>
#include <chrono>
#include <thread>
#include <cstdio>
#include <cstring>
#include <mutex>
#include <string>
#include <pthread.h>
#include <unistd.h>
#include "ff7_boot.h"

namespace {

std::mutex g_lock;
CAMetalLayer *g_layer;
std::atomic<int> g_width{ 1280 }, g_height{ 960 };
std::string g_game_dir;

// keyboard -> XInput bits
std::atomic<unsigned short> g_key_buttons{ 0 };
std::atomic<unsigned char> g_key_lt{ 0 }, g_key_rt{ 0 };
std::atomic<unsigned short> g_inject{ 0 };
std::atomic<bool> g_autofire{ false };
// Back to the launcher: WM_CLOSE to the game's window (on the game thread, as the window's close
// button ends it on Windows), then a fresh instance of the app opens on the launcher.
std::atomic<bool> g_quit{ false };
std::atomic<bool> g_relaunch{ false };   // NorthernCrater: there is no launcher to come back to
std::chrono::steady_clock::time_point g_leave_held;   // Select+Start held since

enum : unsigned short {
    XI_UP = 0x0001, XI_DOWN = 0x0002, XI_LEFT = 0x0004, XI_RIGHT = 0x0008,
    XI_START = 0x0010, XI_BACK = 0x0020, XI_LTHUMB = 0x0040, XI_RTHUMB = 0x0080,
    XI_LB = 0x0100, XI_RB = 0x0200, XI_A = 0x1000, XI_B = 0x2000, XI_X = 0x4000, XI_Y = 0x8000,
};

// The keyboard: macOS virtual key codes (Carbon kVK_*) -> pad buttons. The defaults below, or
// keymap.txt beside the game folder, written by the launcher's Controls page (Views.swift
// KeymapEditor): one line per button, "name keycode keycode ...".
enum : unsigned short { KEY_L2 = 0xFFFE, KEY_R2 = 0xFFFD };
static unsigned short g_keymap[128];
static const struct { const char *name; unsigned short button; std::initializer_list<unsigned short> keys; } k_keymap_default[] = {
    {"up", XI_UP, {126}}, {"down", XI_DOWN, {125}}, {"left", XI_LEFT, {123}}, {"right", XI_RIGHT, {124}},
    {"ok", XI_B, {36, 76, 40}},           // Return, keypad Enter, K
    {"cancel", XI_A, {51, 38}},           // Backspace, J
    {"menu", XI_Y, {49, 34}},             // Space, I
    {"square", XI_X, {56, 60, 32}},       // Shift, U
    {"l1", XI_LB, {12}}, {"r1", XI_RB, {13}},      // Q, W
    {"l2", KEY_L2, {18}}, {"r2", KEY_R2, {19}},    // 1, 2
    {"select", XI_BACK, {48}},            // Tab
    {"start", XI_START, {35}},            // P
    {"l3", XI_LTHUMB, {37}},              // L: FFNx's shortcut mode
    {"r3", XI_RTHUMB, {15}},              // R
};

void load_keymap(const std::string &game_dir) {
    std::memset(g_keymap, 0, sizeof g_keymap);
    for (auto &d : k_keymap_default) for (unsigned short k : d.keys) g_keymap[k] = d.button;
    FILE *f = std::fopen((game_dir + "/../keymap.txt").c_str(), "r");
    if (!f) return;
    unsigned short m[128] = {};
    char line[256];
    int lines = 0;
    while (std::fgets(line, sizeof line, f)) {
        char name[32]; int n = 0;
        if (std::sscanf(line, "%31s%n", name, &n) != 1) continue;
        unsigned short button = 0;
        for (auto &d : k_keymap_default) if (!std::strcmp(d.name, name)) button = d.button;
        if (!button) continue;
        ++lines;
        for (char *p = line + n;;) {
            char *e; long k = std::strtol(p, &e, 10);
            if (e == p) break;
            if (k >= 0 && k < 128) m[k] = button;
            p = e;
        }
    }
    std::fclose(f);
    if (lines) { std::memcpy(g_keymap, m, sizeof m); std::fprintf(stderr, "[ff7] keymap.txt: %d buttons\n", lines); }
}

// Tests: FF7_TEST_INPUT="seconds:hexbuttons:ms,..." presses XInput buttons at those times
// (e.g. "12:2000:150" taps OK 12 s after start), as the keyboard would.
void *test_input_thread(void *arg) {
    std::string script = static_cast<const char *>(arg);
    auto t0 = std::chrono::steady_clock::now();
    size_t at = 0;
    while (at < script.size()) {
        size_t end = script.find(',', at);
        std::string item = script.substr(at, end == std::string::npos ? std::string::npos : end - at);
        at = end == std::string::npos ? script.size() : end + 1;
        double sec = 0; unsigned btn = 0, ms = 100;
        if (std::sscanf(item.c_str(), "%lf:%x:%u", &sec, &btn, &ms) < 2) continue;
        std::this_thread::sleep_until(t0 + std::chrono::milliseconds((long)(sec * 1000)));
        g_key_buttons.fetch_or((unsigned short)btn);
        std::this_thread::sleep_for(std::chrono::milliseconds(ms));
        g_key_buttons.fetch_and((unsigned short)~btn);
    }
    return nullptr;
}

void relaunch_and_quit() {
    if (g_relaunch.load()) {
        NSWorkspaceOpenConfiguration *cfg = [NSWorkspaceOpenConfiguration configuration];
        cfg.createsNewApplicationInstance = YES;
        [[NSWorkspace sharedWorkspace] openApplicationAtURL:[[NSBundle mainBundle] bundleURL] configuration:cfg
                                          completionHandler:^(NSRunningApplication *, NSError *) {
            dispatch_async(dispatch_get_main_queue(), ^{ [NSApp terminate:nil]; });
        }];
    } else {
        [NSApp terminate:nil];
    }
}

// The game ended (ExitProcess, src/hle/ff7_kernel32.c): the process ends right after, so the
// launcher is opened now, from the game thread, and waited for.
extern "C" void ff7_platform_exit(int code) {
    std::fprintf(stderr, "[ff7] game exited (%d)\n", code);
    std::fflush(stderr);
    if (!g_relaunch.load()) return;
    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    NSWorkspaceOpenConfiguration *cfg = [NSWorkspaceOpenConfiguration configuration];
    cfg.createsNewApplicationInstance = YES;
    [[NSWorkspace sharedWorkspace] openApplicationAtURL:[[NSBundle mainBundle] bundleURL] configuration:cfg
                                      completionHandler:^(NSRunningApplication *, NSError *) { dispatch_semaphore_signal(done); }];
    dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC));
}

void *game_thread(void *) {
    int rc = ff7_boot_and_run(g_game_dir.c_str());
    std::fprintf(stderr, "[ff7] game finished with %d\n", rc);
    std::fflush(stderr);
    dispatch_async(dispatch_get_main_queue(), ^{ relaunch_and_quit(); });
    return nullptr;
}

std::string find_game_dir() {
    if (const char *e = getenv("FF7_GAME_DIR")) return e;
    NSString *res = [[NSBundle mainBundle] resourcePath];
    NSString *inApp = [res stringByAppendingPathComponent:@"game"];
    if ([[NSFileManager defaultManager] fileExistsAtPath:[inApp stringByAppendingPathComponent:@"ff7_en.exe"]])
        return inApp.UTF8String;
    NSString *sup = [NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES) firstObject];
    return [[sup stringByAppendingPathComponent:@"FF7Recomp/game"] UTF8String];
}

void redirect_log(const std::string &dir) {
    std::string log = dir + "/../ff7.log";
    std::rename(log.c_str(), (dir + "/../ff7.prev.log").c_str());
    if (!getenv("FF7_LOG_STDERR")) {
        freopen(log.c_str(), "w", stderr);
        setvbuf(stderr, nullptr, _IONBF, 0);
    }
}

}  // namespace

// ---- the platform API (src/host/ff7_boot.h) ----

extern "C" void *ff7_platform_window(int *width, int *height) {
    std::lock_guard<std::mutex> lk(g_lock);
    if (width) *width = g_width;
    if (height) *height = g_height;
    return (__bridge void *)g_layer;
}

// The frame limiter's sleep (FFNx ff7/misc.cpp, tools/ffnx_edit_mac.py): to an absolute deadline,
// which macOS keeps far closer than a nanosleep.
void ff7r_sleep_us(long long us) {
    static mach_timebase_info_data_t tb;
    if (!tb.denom) mach_timebase_info(&tb);
    const uint64_t ticks = (uint64_t)us * 1000ull * tb.denom / tb.numer;
    mach_wait_until(mach_absolute_time() + ticks);
}

// FF7_HITCH=1: what the game thread does in a slow frame. A thread samples the game thread's
// stack (frame pointers) every millisecond; a frame over 40 ms prints its samples, grouped by
// the function each one is in and by the deepest named caller from FFNx / the HLE / the
// system (the lifted game's functions have no names here), so a hitch shows what it waited on.
#include <mach/mach.h>
#include <dlfcn.h>
static mach_port_t g_game_mach;
struct hitch_sample { uint64_t t; uintptr_t pc[16]; int n; };
static hitch_sample g_hs[4096];
static std::atomic<unsigned> g_hs_n{0};
static std::atomic<uint64_t> g_hitch_from{0}, g_hitch_to{0};
static uint64_t now_ticks() { return mach_absolute_time(); }
static void *hitch_self() {   // the app's own binary (its name has changed before)
    static void *base = [] { Dl_info d; return dladdr((void *)&now_ticks, &d) ? d.dli_fbase : nullptr; }();
    return base;
}
static void *hitch_thread(void *) {
    for (;;) {
        ff7r_sleep_us(1000);
        if (!g_game_mach) continue;
        // a slow frame to report
        if (uint64_t to = g_hitch_to.exchange(0)) {
            const uint64_t from = g_hitch_from.load();
            std::vector<std::pair<std::string, int>> leaf, mid;
            auto add = [](std::vector<std::pair<std::string, int>> &v, const std::string &k) {
                for (auto &e : v) if (e.first == k) { e.second++; return; }
                v.push_back({k, 1});
            };
            int total = 0;
            const unsigned end = g_hs_n.load();
            for (unsigned i = end > 4096 ? end - 4096 : 0; i < end; i++) {
                const hitch_sample &h = g_hs[i % 4096];
                if (h.t < from || h.t > to) continue;
                total++;
                Dl_info di;
                // the leaf as an offset in the app's binary (atos -o FF7Recomp -l 0x100000000 <addr>),
                // dladdr only knows exported names
                char top[32] = "?";
                if (h.n && dladdr((void *)h.pc[0], &di) && di.dli_fbase == hitch_self())
                    std::snprintf(top, sizeof top, "0x%llx", (unsigned long long)(h.pc[0] - (uintptr_t)di.dli_fbase + 0x100000000ull) & ~0xFFull);
                else if (h.n && dladdr((void *)h.pc[0], &di) && di.dli_sname) std::snprintf(top, sizeof top, "%.31s", di.dli_sname);
                add(leaf, top);
                // the first named frame that is ours (FFNx, HLE) rather than the system's
                std::string ours = "?";
                for (int k = 0; k < h.n; k++) {
                    if (!dladdr((void *)h.pc[k], &di) || !di.dli_sname || !di.dli_fname) continue;
                    if (di.dli_fbase == hitch_self()) { ours = di.dli_sname; if (ours.rfind("sub_", 0) != 0 && ours.rfind("f_", 0) != 0) break; }
                }
                add(mid, ours);
            }
            auto top = [](std::vector<std::pair<std::string, int>> &v) {
                std::sort(v.begin(), v.end(), [](auto &a, auto &b) { return a.second > b.second; });
                std::string o;
                for (size_t k = 0; k < v.size() && k < 6; k++) o += " " + v[k].first.substr(0, 60) + ":" + std::to_string(v[k].second);
                return o;
            };
            std::fprintf(stderr, "[hitch]   %d samples; in:%s\n[hitch]   under:%s\n", total, top(leaf).c_str(), top(mid).c_str());
            continue;
        }
        if (thread_suspend(g_game_mach) != KERN_SUCCESS) continue;
#if defined(__arm64__)
        arm_thread_state64_t st; mach_msg_type_number_t cnt = ARM_THREAD_STATE64_COUNT;
        const thread_state_flavor_t flavor = ARM_THREAD_STATE64;
#else
        x86_thread_state64_t st; mach_msg_type_number_t cnt = x86_THREAD_STATE64_COUNT;
        const thread_state_flavor_t flavor = x86_THREAD_STATE64;
#endif
        hitch_sample &h = g_hs[g_hs_n.load() % 4096];
        h.n = 0; h.t = now_ticks();
        if (thread_get_state(g_game_mach, flavor, (thread_state_t)&st, &cnt) == KERN_SUCCESS) {
#if defined(__arm64__)
            h.pc[h.n++] = (uintptr_t)arm_thread_state64_get_pc(st);
            uintptr_t fp = (uintptr_t)arm_thread_state64_get_fp(st);
#else
            h.pc[h.n++] = st.__rip;
            uintptr_t fp = st.__rbp;
#endif
            while (h.n < 16 && fp && (fp & 7) == 0) {
                uintptr_t pair[2]; vm_size_t got = 0;   // read safely: a frame may not be one
                if (vm_read_overwrite(mach_task_self(), fp, sizeof pair, (vm_address_t)pair, &got) != KERN_SUCCESS || got != sizeof pair) break;
                uintptr_t ret = pair[1], next = pair[0];
                if (!ret || next <= fp) break;
                h.pc[h.n++] = ret; fp = next;
            }
        }
        thread_resume(g_game_mach);
        g_hs_n.fetch_add(1);
    }
    return nullptr;
}
static void hitch_frame() {
    static const bool on = getenv("FF7_HITCH") != nullptr;
    if (!on) return;
    static uint64_t last;
    static mach_timebase_info_data_t tb;
    if (!tb.denom) {
        mach_timebase_info(&tb);
        g_game_mach = mach_thread_self();
        pthread_t t; pthread_create(&t, nullptr, hitch_thread, nullptr); pthread_detach(t);
    }
    const uint64_t now = now_ticks();
    if (last) {
        const double ms = (double)(now - last) * tb.numer / tb.denom / 1e6;
        if (ms > 40) {
            std::fprintf(stderr, "[hitch] frame %.0f ms\n", ms);
            g_hitch_from.store(last); g_hitch_to.store(now);
        }
    }
    last = now;
}

// FF7_PERF=1: every 10 s, frames per second, the slowest frames and the process's CPU use.
static void perf_frame() {
    static const bool on = getenv("FF7_PERF") != nullptr;
    if (!on) return;
    using clk = std::chrono::steady_clock;
    static clk::time_point last, window;
    static std::vector<double> ms;
    static rusage ru0;
    const auto now = clk::now();
    if (last.time_since_epoch().count()) ms.push_back(std::chrono::duration<double, std::milli>(now - last).count());
    else { window = now; getrusage(RUSAGE_SELF, &ru0); }
    last = now;
    const double secs = std::chrono::duration<double>(now - window).count();
    if (secs < 10 || ms.empty()) return;
    rusage ru; getrusage(RUSAGE_SELF, &ru);
    auto tv = [](timeval t) { return t.tv_sec + t.tv_usec / 1e6; };
    const double cpu = (tv(ru.ru_utime) - tv(ru0.ru_utime) + tv(ru.ru_stime) - tv(ru0.ru_stime)) / secs * 100;
    std::vector<double> s = ms; std::sort(s.begin(), s.end());
    const double p99 = s[(size_t)(s.size() * 0.99)], worst = s.back();
    int over = 0; for (double m : ms) over += m > 25.0;
    std::fprintf(stderr, "[perf] %.1f fps, frame p99 %.1f ms, worst %.1f ms, %d frame(s) over 25 ms, cpu %.0f%%\n",
                 ms.size() / secs, p99, worst, over, cpu);
    ms.clear(); window = now; ru0 = ru;
}

extern "C" void *ff7_platform_frame_window(void) {
    perf_frame();
    hitch_frame();
    std::lock_guard<std::mutex> lk(g_lock);
    return (__bridge void *)g_layer;
}

extern "C" void *ff7_platform_companion_window(int *width, int *height) {
    if (width) *width = 0;
    if (height) *height = 0;
    return nullptr;
}

extern "C" int ff7_platform_keyboard_state(unsigned char keys[256]) {
    std::memset(keys, 0, 256);   // the keyboard drives the pad (see the top of this file)
    return 0;
}

static short axis(float v) {
    float c = v * 32767.0f;
    return (short)(c > 32767.0f ? 32767 : c < -32768.0f ? -32768 : c);
}

extern "C" void hle_post_message(uint32_t hwnd, uint32_t message, uint32_t wParam, uint32_t lParam);
extern "C" uint32_t hle_first_hwnd(void);

// The launcher, from the game: the menu, the window's close button, or Select+Start held 2 s.
void request_back_to_launcher() {
    if (g_quit.exchange(true)) return;
    std::fprintf(stderr, "[ff7] back to the launcher\n");
    // a game that does not end within a few seconds is left anyway
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{ relaunch_and_quit(); });
}

// The achievements panel over the game (src/mac/launcher/GameOverlay.swift): F1 or Select+Triangle
// opens and closes it; while it is open the game gets no input, up / down scroll it and
// cross / circle close it.
// NorthernCrater: the panel itself lived in the removed launcher; these do nothing now.
static void ff7_overlay_set_achievements(int) {}
static void ff7_overlay_scroll(int) {}
static void ff7_achievements_window(void) {}
static std::atomic<bool> g_ach_open{false};
void set_achievements_panel(bool open) {
    g_ach_open.store(open);
    dispatch_async(dispatch_get_main_queue(), ^{ ff7_overlay_set_achievements(open ? 1 : 0); });
}

// FF7_SWAP_AB=1 (the app's "swap confirm and cancel"): the controller's A and B buttons trade places.
static bool swap_confirm_cancel() {
    static const bool on = getenv("FF7_SWAP_AB") && atoi(getenv("FF7_SWAP_AB")) != 0;
    return on;
}

extern "C" int ff7_platform_pad_state(unsigned index, ff7_pad_state *out) {
    if (index != 0) return 0;
    static bool quit_sent;
    if (g_quit.load() && !quit_sent) {
        quit_sent = true;
        if (uint32_t hwnd = hle_first_hwnd()) hle_post_message(hwnd, 0x0010u /* WM_CLOSE */, 0, 0);
    }
    std::memset(out, 0, sizeof *out);
    out->buttons = g_key_buttons.load() | g_inject.load();
    out->left_trigger = g_key_lt.load();
    out->right_trigger = g_key_rt.load();
    @autoreleasepool {
        for (GCController *c in [GCController controllers]) {
            GCExtendedGamepad *g = c.extendedGamepad;
            if (!g) continue;
            unsigned short b = 0;
            if (g.dpad.up.pressed) b |= XI_UP;
            if (g.dpad.down.pressed) b |= XI_DOWN;
            if (g.dpad.left.pressed) b |= XI_LEFT;
            if (g.dpad.right.pressed) b |= XI_RIGHT;
            if (g.buttonA.pressed) b |= XI_A;
            if (g.buttonB.pressed) b |= XI_B;
            if (swap_confirm_cancel()) {          // NorthernCrater: FF7_SWAP_AB=1 exchanges A and B on the controller
                const unsigned short had_a = b & XI_A, had_b = b & XI_B;
                b = (unsigned short)((b & ~(XI_A | XI_B)) | (had_a ? XI_B : 0) | (had_b ? XI_A : 0));
            }
            if (g.buttonX.pressed) b |= XI_X;
            if (g.buttonY.pressed) b |= XI_Y;
            if (g.leftShoulder.pressed) b |= XI_LB;
            if (g.rightShoulder.pressed) b |= XI_RB;
            if (g.buttonMenu.pressed) b |= XI_START;
            if (g.buttonOptions && g.buttonOptions.pressed) b |= XI_BACK;
            if (g.leftThumbstickButton && g.leftThumbstickButton.pressed) b |= XI_LTHUMB;
            if (g.rightThumbstickButton && g.rightThumbstickButton.pressed) b |= XI_RTHUMB;
            out->buttons |= b;
            unsigned char lt = (unsigned char)(g.leftTrigger.value * 255.0f);
            unsigned char rt = (unsigned char)(g.rightTrigger.value * 255.0f);
            if (lt > out->left_trigger) out->left_trigger = lt;
            if (rt > out->right_trigger) out->right_trigger = rt;
            out->lx = axis(g.leftThumbstick.xAxis.value);
            out->ly = axis(g.leftThumbstick.yAxis.value);
            out->rx = axis(g.rightThumbstick.xAxis.value);
            out->ry = axis(g.rightThumbstick.yAxis.value);
            break;
        }
    }
    // the achievements panel
    static unsigned short prev, held_at_close;
    const unsigned short now_b = out->buttons, pressed = now_b & ~prev;
    prev = now_b;
    held_at_close &= now_b;                               // released since the panel closed
    if ((now_b & (XI_BACK | XI_Y)) == (XI_BACK | XI_Y) && (pressed & (XI_BACK | XI_Y))) {
        set_achievements_panel(!g_ach_open.load());
        if (!g_ach_open.load()) held_at_close = now_b;
    } else if (g_ach_open.load()) {
        if (pressed & XI_UP) dispatch_async(dispatch_get_main_queue(), ^{ ff7_overlay_scroll(-1); });
        if (pressed & XI_DOWN) dispatch_async(dispatch_get_main_queue(), ^{ ff7_overlay_scroll(1); });
        if (pressed & (XI_A | XI_B)) { set_achievements_panel(false); held_at_close = now_b; }
    }
    if (g_ach_open.load()) {
        std::memset(out, 0, sizeof *out);                 // the game waits
        return 1;
    }
    out->buttons &= (unsigned short)~held_at_close;       // the button that closed it is not a game press

    // Select+Start held 2 s: back to the launcher
    const auto now = std::chrono::steady_clock::now();
    if ((out->buttons & (XI_BACK | XI_START)) == (XI_BACK | XI_START)) {
        if (g_leave_held == std::chrono::steady_clock::time_point{}) g_leave_held = now;
        else if (now - g_leave_held > std::chrono::seconds(2)) {
            g_leave_held = {};
            dispatch_async(dispatch_get_main_queue(), ^{ request_back_to_launcher(); });
        }
    } else {
        g_leave_held = {};
    }
    return 1;
}

extern "C" void ff7_platform_pad_rumble(unsigned, unsigned short, unsigned short) {}
// Rumble (src/ffnx_port/rumble.cpp: hits, falls, field shakes): the first controller's haptics.
// amplitude 1..255 for ms, 0 stops. Called on the game thread; played on a serial queue.
static dispatch_queue_t g_rumble_q;
static CHHapticEngine *g_haptics API_AVAILABLE(macos(11.0));
static id<CHHapticPatternPlayer> g_rumble_player API_AVAILABLE(macos(11.0));
static GCController *g_haptics_pad;

extern "C" void ff7_platform_rumble(int amplitude, int ms) {
    if (@available(macOS 11.0, *)) {
        static dispatch_once_t once;
        dispatch_once(&once, ^{ g_rumble_q = dispatch_queue_create("ff7.rumble", DISPATCH_QUEUE_SERIAL); });
        dispatch_async(g_rumble_q, ^{
            @autoreleasepool {
                GCController *pad = nil;
                for (GCController *c in [GCController controllers]) if (c.haptics) { pad = c; break; }
                if (pad != g_haptics_pad) {
                    [g_haptics stopWithCompletionHandler:nil];
                    g_haptics = pad ? [pad.haptics createEngineWithLocality:GCHapticsLocalityDefault] : nil;
                    g_haptics_pad = pad;
                    g_rumble_player = nil;
                    if (g_haptics) {
                        g_haptics.playsHapticsOnly = YES;
                        g_haptics.resetHandler = ^{ [g_haptics startAndReturnError:nil]; };
                        NSError *e = nil;
                        if (![g_haptics startAndReturnError:&e]) { std::fprintf(stderr, "[rumble] haptics: %s\n", e.localizedDescription.UTF8String); g_haptics = nil; }
                        else std::fprintf(stderr, "[rumble] controller: %s\n", pad.vendorName.UTF8String ?: "?");
                    }
                }
                if (!g_haptics) return;
                [g_rumble_player stopAtTime:CHHapticTimeImmediate error:nil];
                g_rumble_player = nil;
                if (amplitude <= 0 || ms <= 0) return;
                float k = amplitude / 255.0f;
                CHHapticEvent *ev = [[CHHapticEvent alloc]
                    initWithEventType:CHHapticEventTypeHapticContinuous
                           parameters:@[ [[CHHapticEventParameter alloc] initWithParameterID:CHHapticEventParameterIDHapticIntensity value:k],
                                         [[CHHapticEventParameter alloc] initWithParameterID:CHHapticEventParameterIDHapticSharpness value:0.4f] ]
                         relativeTime:0 duration:ms / 1000.0];
                NSError *e = nil;
                CHHapticPattern *pat = [[CHHapticPattern alloc] initWithEvents:@[ ev ] parameters:@[] error:&e];
                if (!pat) return;
                g_rumble_player = [g_haptics createPlayerWithPattern:pat error:&e];
                [g_rumble_player startAtTime:CHHapticTimeImmediate error:&e];
            }
        });
    }
}
extern "C" void ff7_platform_pad_autofire(int on) { g_autofire.store(on != 0); }
extern "C" void ff7_platform_pad_inject(unsigned short buttons) { g_inject.store(buttons); }
extern "C" int ff7_platform_pad_buttons(void) { return g_key_buttons.load(); }

// ---- Cocoa ----

@interface FF7View : NSView
@end

@implementation FF7View
- (BOOL)wantsUpdateLayer { return YES; }
- (CALayer *)makeBackingLayer {
    CAMetalLayer *l = [CAMetalLayer layer];
    l.device = MTLCreateSystemDefaultDevice();
    l.pixelFormat = MTLPixelFormatBGRA8Unorm;
    return l;
}
- (BOOL)acceptsFirstResponder { return YES; }
- (void)setKey:(NSEvent *)e down:(BOOL)down {
    unsigned short kc = e.keyCode;
    [self setKeyCode:e.keyCode down:down];
}
- (void)setKeyCode:(unsigned short)kc down:(BOOL)down {
    unsigned short b = kc < 128 ? g_keymap[kc] : 0;
    if (b == KEY_L2) { g_key_lt.store(down ? 255 : 0); return; }
    if (b == KEY_R2) { g_key_rt.store(down ? 255 : 0); return; }
    if (!b) return;
    if (down) g_key_buttons.fetch_or(b);
    else g_key_buttons.fetch_and((unsigned short)~b);
}
- (void)keyDown:(NSEvent *)e {
    if (e.modifierFlags & NSEventModifierFlagCommand) { [super keyDown:e]; return; }
    if (e.keyCode == 122 && !e.isARepeat) { set_achievements_panel(!g_ach_open.load()); return; }   // F1
    if (e.keyCode == 53 && g_ach_open.load()) { set_achievements_panel(false); return; }            // Escape
    [self setKey:e down:YES];
}
- (void)keyUp:(NSEvent *)e { [self setKey:e down:NO]; }
- (void)flagsChanged:(NSEvent *)e {
    // a modifier key mapped to a button (Shift is square by default)
    NSEventModifierFlags flag = 0;
    switch (e.keyCode) {
    case 56: case 60: flag = NSEventModifierFlagShift; break;
    case 59: case 62: flag = NSEventModifierFlagControl; break;
    case 58: case 61: flag = NSEventModifierFlagOption; break;
    case 57: flag = NSEventModifierFlagCapsLock; break;
    default: return;
    }
    [self setKeyCode:e.keyCode down:(e.modifierFlags & flag) != 0];
}
- (void)updateDrawableSize {
    CAMetalLayer *l = (CAMetalLayer *)self.layer;
    CGFloat s = self.window.backingScaleFactor;
    l.contentsScale = s;
    CGSize sz = CGSizeMake(self.bounds.size.width * s, self.bounds.size.height * s);
    l.drawableSize = sz;
    g_width = (int)sz.width;
    g_height = (int)sz.height;
}
- (void)setFrameSize:(NSSize)n { [super setFrameSize:n]; [self updateDrawableSize]; }
- (void)viewDidChangeBackingProperties { [super viewDidChangeBackingProperties]; [self updateDrawableSize]; }
@end

@interface FF7AppDelegate : NSObject <NSApplicationDelegate, NSWindowDelegate>
@property(strong) NSWindow *window;
@property(strong) id<NSObject> gameActivity;   // no App Nap while the game runs
@end

static void ff7_overlay_attach(void *) {}   // the launcher's booster icons / achievement banner overlay

@implementation FF7AppDelegate
- (void)applicationDidFinishLaunching:(NSNotification *)n {
    // NorthernCrater: no launcher; the game starts at once. FF7_QUICKBOOT=newgame|continue|resume skips
    // the title screen, FF7_ASPECT picks the screen shape (below).
    [self startGameAspect:(getenv("FF7_ASPECT") ? atoi(getenv("FF7_ASPECT")) : 0) fullscreen:NO];
    [NSApp activateIgnoringOtherApps:YES];
}
// aspect: FFNx aspect_ratio (0 4:3, 1 stretched, 2 16:9, 3 16:10, 4 21:9)
- (void)startGameAspect:(int)aspect fullscreen:(BOOL)fullscreen {
    [self startGameAspect:aspect fullscreen:fullscreen screen:nil];
}
// screen: the display to play on (an AirPlay display macOS uses as a separate display, a TV, a
// second monitor), by name; nil or not found: the main display.
- (void)startGameAspect:(int)aspect fullscreen:(BOOL)fullscreen screen:(NSString *)screenName {
    if (self.window) return;
    NSScreen *target = nil;
    for (NSScreen *sc in [NSScreen screens]) if (screenName.length && [sc.localizedName isEqualToString:screenName]) target = sc;
    NSRect r = aspect == 2 ? NSMakeRect(0, 0, 1600, 900) : aspect == 3 ? NSMakeRect(0, 0, 1440, 900)
             : aspect == 4 ? NSMakeRect(0, 0, 1707, 720) : NSMakeRect(0, 0, 1280, 960);   // 4: 21:9 (64:27)
    self.window = [[NSWindow alloc] initWithContentRect:r
                                              styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                                                        NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable
                                                backing:NSBackingStoreBuffered defer:NO];
    self.window.title = @"FINAL FANTASY VII";
    self.window.delegate = self;
    if (aspect != 1) self.window.contentAspectRatio = r.size;   // stretched: any shape
    FF7View *v = [[FF7View alloc] initWithFrame:r];
    v.wantsLayer = YES;
    self.window.contentView = v;
    if (target) {
        NSRect vf = target.visibleFrame;
        NSRect wf = [self.window frameRectForContentRect:r];
        if (wf.size.width > vf.size.width || wf.size.height > vf.size.height) {
            CGFloat k = MIN(vf.size.width / wf.size.width, vf.size.height / wf.size.height) * 0.9;
            [self.window setContentSize:NSMakeSize(r.size.width * k, r.size.height * k)];
            wf = self.window.frame;
        }
        [self.window setFrameOrigin:NSMakePoint(NSMidX(vf) - wf.size.width / 2, NSMidY(vf) - wf.size.height / 2)];
    } else {
        [self.window center];
    }
    [self.window makeKeyAndOrderFront:nil];
    [self.window makeFirstResponder:v];
    [v updateDrawableSize];
    ff7_overlay_attach((__bridge void *)v);   // booster icons, achievement banner
    {
        std::lock_guard<std::mutex> lk(g_lock);
        g_layer = (CAMetalLayer *)v.layer;
    }
    [NSApp activateIgnoringOtherApps:YES];

    g_game_dir = find_game_dir();
    redirect_log(g_game_dir);
    load_keymap(g_game_dir);
    std::fprintf(stderr, "[ff7] macOS: game folder %s, window %dx%d\n", g_game_dir.c_str(), g_width.load(), g_height.load());
    pthread_attr_t a;
    pthread_attr_init(&a);
    pthread_attr_setstacksize(&a, 64u << 20);   // the lifted game's host stack
    // User-interactive QoS: the frame limiter's sleeps wake on time (a default-QoS thread's
    // timers get ~2.5 ms of coalescing leeway: 52 FPS instead of 60)
    pthread_attr_set_qos_class_np(&a, QOS_CLASS_USER_INTERACTIVE, 0);
    pthread_t t;
    // The frame limiter sleeps to the frame's deadline: App Nap's timer coalescing (the window in
    // the background, another app in front) made every sleep run long, 52 FPS instead of 60.
    self.gameActivity = [[NSProcessInfo processInfo]
        beginActivityWithOptions:NSActivityUserInitiatedAllowingIdleSystemSleep | NSActivityLatencyCritical
                          reason:@"FINAL FANTASY VII is running"];
    pthread_create(&t, &a, game_thread, nullptr);
    pthread_detach(t);
    if (const char *ti = getenv("FF7_TEST_INPUT")) { pthread_t ti_t; pthread_create(&ti_t, nullptr, test_input_thread, (void *)ti); pthread_detach(ti_t); }
    if (fullscreen) [self.window toggleFullScreen:nil];
}
- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)s { return YES; }
- (BOOL)windowShouldClose:(NSWindow *)w {
    if (w != self.window) return YES;
    request_back_to_launcher();                       // the game ends and the app quits
    return NO;
}
- (void)backToLauncher:(id)sender { if (self.window) request_back_to_launcher(); }
- (void)showAchievements:(id)sender { ff7_achievements_window(); }
// About: Good JOE made it; the projects it is built on
- (void)showAbout:(id)sender {
    NSMutableParagraphStyle *ps = [NSMutableParagraphStyle new];
    ps.alignment = NSTextAlignmentCenter;
    NSDictionary *a = @{ NSFontAttributeName: [NSFont systemFontOfSize:11], NSParagraphStyleAttributeName: ps,
                         NSForegroundColorAttributeName: NSColor.secondaryLabelColor };
    const bool thai = [[[NSUserDefaults standardUserDefaults] stringForKey:@"uiLanguage"] isEqualToString:@"th"];
    NSString *t = thai
        ? @"สร้างบน GJ Materia โดย Good JOE — github.com/goodjoeth\n\n"
           "FINAL FANTASY VII (เวอร์ชัน Steam) บน Mac แบบ native\n"
           "ต้องใช้ไฟล์เกมของคุณเอง ไม่เกี่ยวข้องกับ Square Enix\n\n"
           "สร้างบน FF7Recomp, FFNx, pcrecomp, bgfx, 7th Heaven และม็อดของชุมชน Qhimm / Tsunamods (GPL v3)"
        : @"Based on GJ Materia by Good JOE — github.com/goodjoeth\n\n"
           "FINAL FANTASY VII (the Steam release), native on the Mac\n"
           "Needs your own game files. Not affiliated with Square Enix.\n\n"
           "Built on FF7Recomp, FFNx, pcrecomp, bgfx, 7th Heaven and the Qhimm / Tsunamods mods (GPL v3)";
    [NSApp orderFrontStandardAboutPanelWithOptions:@{
        NSAboutPanelOptionApplicationName: @"NorthernCrater Engine",
        NSAboutPanelOptionCredits: [[NSAttributedString alloc] initWithString:t attributes:a] }];
    [NSApp activateIgnoringOtherApps:YES];
}
- (void)quitApp:(id)sender { [NSApp terminate:nil]; }
@end

static void build_menu(void) {
    NSMenu *bar = [NSMenu new];
    NSMenuItem *appItem = [NSMenuItem new];
    [bar addItem:appItem];
    NSMenu *app = [NSMenu new];
    [app addItemWithTitle:@"About NorthernCrater Engine" action:@selector(showAbout:) keyEquivalent:@""];
    [app addItem:[NSMenuItem separatorItem]];
    [app addItemWithTitle:@"Toggle Full Screen" action:@selector(toggleFullScreen:) keyEquivalent:@"f"];
    [app addItem:[NSMenuItem separatorItem]];
    [app addItemWithTitle:@"Close Game" action:@selector(backToLauncher:) keyEquivalent:@"l"];
    [app addItemWithTitle:@"Quit NorthernCrater Engine" action:@selector(quitApp:) keyEquivalent:@"q"];
    appItem.submenu = app;
    NSApp.mainMenu = bar;
}

int main(int argc, const char **argv) {
    (void)argc; (void)argv;
    @autoreleasepool {
        [NSApplication sharedApplication];
        [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
        build_menu();
        FF7AppDelegate *d = [FF7AppDelegate new];
        NSApp.delegate = d;
        [NSApp run];
    }
    return 0;
}

// The launcher's Play (src/mac/launcher/Views.swift).
extern "C" void ff7_mac_start_game(int aspect, int fullscreen, const char *screen) {
    [(FF7AppDelegate *)NSApp.delegate startGameAspect:aspect fullscreen:fullscreen != 0
                                               screen:screen && *screen ? [NSString stringWithUTF8String:screen] : nil];
}

// patches/bgfx/0004 keeps a Vulkan start-up trace; there is no Vulkan renderer here.
extern "C" const char *ff7_bgfx_vk_trace() { return "(Metal)\n"; }
