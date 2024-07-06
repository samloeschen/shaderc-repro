const std = @import("std");
const builtin = @import("builtin");
const zglfw = @import("zglfw");
const zbgfx = @import("zbgfx");
const bgfx = zbgfx.bgfx;

const WIDTH = 640;
const HEIGHT = 480;

var bgfx_clbs = zbgfx.callbacks.CCallbackInterfaceT{
    .vtable = &zbgfx.callbacks.DefaultZigCallbackVTable.toVtbl(),
};

pub fn main() !void {
    try zglfw.init();
    defer zglfw.terminate();

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    zglfw.windowHintTyped(.client_api, .no_api);
    var glfw_window_handle = try zglfw.Window.create(WIDTH, HEIGHT, "shaderc repro", null);
    glfw_window_handle.setSizeLimits(400, 400, -1, -1);
    const framebufferSize = glfw_window_handle.getFramebufferSize();

    var bgfx_init: bgfx.Init = undefined;
    bgfx.initCtor(&bgfx_init);
    bgfx_init.resolution.width = @intCast(framebufferSize[0]);
    bgfx_init.resolution.height = @intCast(framebufferSize[1]);
    bgfx_init.platformData.ndt = null;
    bgfx_init.debug = true;
    bgfx_init.callback = &bgfx_clbs;

    bgfx_init.platformData.ndt = null;
    switch (builtin.target.os.tag) {
        .linux => {
            bgfx_init.platformData.type = bgfx.NativeWindowHandleType.Default;
            bgfx_init.platformData.nwh = @ptrFromInt(zglfw.getX11Window(glfw_window_handle));
            bgfx_init.platformData.ndt = zglfw.getX11Display();
        },
        .windows => {
            bgfx_init.platformData.nwh = zglfw.getWin32Window(glfw_window_handle);
        },
        else => |v| if (v.isDarwin()) {
            bgfx_init.platformData.nwh = zglfw.getCocoaWindow(glfw_window_handle);
        } else undefined,
    }

    _ = bgfx.renderFrame(0);

    if (!bgfx.init(&bgfx_init)) std.process.exit(1);
    defer bgfx.shutdown();

    bgfx.reset(@intCast(framebufferSize[0]), @intCast(framebufferSize[1]), bgfx.ResetFlags_None, .RGBA8);
    bgfx.setViewClear(0, bgfx.ClearFlags_Color | bgfx.ClearFlags_Depth, 0x303030ff, 1.0, 0);

    std.debug.print("setting up paths\n", .{});

    const real_path = try std.fs.cwd().realpathAlloc(allocator, ".");
    defer allocator.free(real_path);

    const shaders_path = try std.fs.path.join(allocator, &.{ real_path, "shaders" });
    defer allocator.free(shaders_path);

    const include_path_a = try std.fs.path.joinZ(allocator, &.{ real_path, "shaders", "include_a" });
    defer allocator.free(include_path_a);

    const include_path_b = try std.fs.path.joinZ(allocator, &.{ real_path, "shaders", "include_b" });
    defer allocator.free(include_path_b);

    const fs_path = try std.fs.path.join(allocator, &.{ real_path, "shaders/fs.fragment" });
    defer allocator.free(fs_path);
    const fs_data = try readFileFromShaderDirs(allocator, fs_path);
    defer allocator.free(fs_data);

    const varying_path = try std.fs.path.join(allocator, &.{ real_path, "shaders/v.varyings" });
    defer allocator.free(varying_path);
    const varying_data = try readFileFromShaderDirs(allocator, varying_path);
    defer allocator.free(varying_data);

    var fs_shader_options = zbgfx.shaderc.createDefaultOptionsForRenderer(bgfx.getRendererType());
    fs_shader_options.shaderType = .fragment;

    // for compilation to succeed, just use include_path_a
    var includes = [_][:0]const u8{ include_path_a, include_path_b };

    fs_shader_options.includeDirs = &includes;

    std.debug.print("compiling test shader\n", .{});

    const fs_shader = try zbgfx.shaderc.compileShader(allocator, varying_data, fs_data, fs_shader_options);
    defer allocator.free(fs_shader);

    std.debug.print("successfully compiled shader!\n", .{});

    while (!glfw_window_handle.shouldClose()) {
        zglfw.pollEvents();
        bgfx.setViewRect(0, 0, 0, @intCast(framebufferSize[0]), @intCast(framebufferSize[1]));
        bgfx.touch(0);
        bgfx.dbgTextClear(0, false);

        _ = bgfx.frame(false);
    }
}

fn readFileFromShaderDirs(allocator: std.mem.Allocator, path: []const u8) ![:0]u8 {
    const f = try std.fs.openFileAbsolute(path, .{});
    defer f.close();
    const max_size = (try f.getEndPos()) + 1;
    var data = std.ArrayList(u8).init(allocator);
    try f.reader().readAllArrayList(&data, max_size);
    return try data.toOwnedSliceSentinel(0);
}
