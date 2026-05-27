#include "include/pipewire_video_capture/pipewire_video_capture_plugin.h"

#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>

extern "C" {
#include <pipewire/pipewire.h>
#include <spa/param/video/format-utils.h>
#include <spa/utils/result.h>
}

#include <linux/videodev2.h>
#include <dirent.h>
#include <fcntl.h>
#include <sys/ioctl.h>
#include <unistd.h>

#include <algorithm>
#include <atomic>
#include <cstdio>
#include <cstring>
#include <mutex>
#include <thread>
#include <vector>

// ─── GObject boilerplate ──────────────────────────────────────────────────────

#define PIPEWIRE_VIDEO_CAPTURE_PLUGIN(obj)                                     \
  (G_TYPE_CHECK_INSTANCE_CAST((obj),                                           \
                              pipewire_video_capture_plugin_get_type(),        \
                              PipewireVideoCapturePlugin))

struct _PipewireVideoCapturePlugin {
  GObject parent_instance;
};

G_DEFINE_TYPE(PipewireVideoCapturePlugin, pipewire_video_capture_plugin,
              g_object_get_type())

// ─── Capture state ────────────────────────────────────────────────────────────

struct CaptureState {
  struct pw_main_loop* loop    = nullptr;
  struct pw_context*   context = nullptr;
  struct pw_core*      core    = nullptr;
  struct pw_stream*    stream  = nullptr;
  struct spa_hook      stream_listener{};

  int v4l2_fd = -1;
  int width   = 0;
  int height  = 0;

  // Scratch buffer for BGRx→YUYV conversion
  std::vector<uint8_t> yuyv_buf;

  std::atomic<bool> running{false};
  std::thread       pw_thread;
};

static CaptureState* g_capture = nullptr;
static std::mutex    g_mutex;

// ─── V4L2 helpers ─────────────────────────────────────────────────────────────

static int find_v4l2loopback_device(char* out_path, size_t path_len) {
  DIR* dir = opendir("/dev");
  if (!dir) return -1;

  struct dirent* entry;
  while ((entry = readdir(dir)) != nullptr) {
    if (strncmp(entry->d_name, "video", 5) != 0) continue;

    char path[64];
    snprintf(path, sizeof(path), "/dev/%s", entry->d_name);

    int fd = open(path, O_WRONLY | O_NONBLOCK);
    if (fd < 0) continue;

    struct v4l2_capability cap{};
    if (ioctl(fd, VIDIOC_QUERYCAP, &cap) == 0) {
      bool is_loopback =
          strstr(reinterpret_cast<char*>(cap.driver), "v4l2 loopback") ||
          strstr(reinterpret_cast<char*>(cap.driver), "v4l2loopback");
      bool has_output = (cap.device_caps  & V4L2_CAP_VIDEO_OUTPUT) ||
                        (cap.capabilities & V4L2_CAP_VIDEO_OUTPUT);

      if (is_loopback && has_output) {
        if (out_path) snprintf(out_path, path_len, "%s", path);
        closedir(dir);
        return fd;
      }
    }
    close(fd);
  }

  closedir(dir);
  return -1;
}

static bool setup_v4l2_format(int fd, int width, int height) {
  struct v4l2_format fmt{};
  fmt.type                 = V4L2_BUF_TYPE_VIDEO_OUTPUT;
  fmt.fmt.pix.width        = static_cast<uint32_t>(width);
  fmt.fmt.pix.height       = static_cast<uint32_t>(height);
  fmt.fmt.pix.pixelformat  = V4L2_PIX_FMT_YUYV;  // libwebrtc supports YUYV, not BGR32
  fmt.fmt.pix.field        = V4L2_FIELD_NONE;
  fmt.fmt.pix.bytesperline = static_cast<uint32_t>(width * 2);
  fmt.fmt.pix.sizeimage    = static_cast<uint32_t>(width * height * 2);
  fmt.fmt.pix.colorspace   = V4L2_COLORSPACE_SRGB;
  return ioctl(fd, VIDIOC_S_FMT, &fmt) == 0;
}

// BGRx (4 bytes/pixel) → YUYV (2 bytes/pixel) conversion.
// PipeWire ScreenCast outputs BGRx; libwebrtc's V4L2 capture supports YUYV.
static void bgrx_to_yuyv(const uint8_t* src, uint8_t* dst, int width, int height) {
  for (int y = 0; y < height; y++) {
    const uint8_t* row = src + y * width * 4;
    uint8_t*       out = dst + y * width * 2;
    for (int x = 0; x < width; x += 2) {
      int b0 = row[x*4],     g0 = row[x*4+1], r0 = row[x*4+2];
      int b1 = row[x*4+4],   g1 = row[x*4+5], r1 = row[x*4+6];
      int y0 = ((66*r0 + 129*g0 + 25*b0 + 128) >> 8) + 16;
      int y1 = ((66*r1 + 129*g1 + 25*b1 + 128) >> 8) + 16;
      int u  = ((-38*(r0+r1) - 74*(g0+g1) + 112*(b0+b1) + 512) >> 9) + 128;
      int v  = ((112*(r0+r1) - 94*(g0+g1) -  18*(b0+b1) + 512) >> 9) + 128;
      out[x*2]   = (uint8_t)std::clamp(y0, 16, 235);
      out[x*2+1] = (uint8_t)std::clamp(u,  16, 240);
      out[x*2+2] = (uint8_t)std::clamp(y1, 16, 235);
      out[x*2+3] = (uint8_t)std::clamp(v,  16, 240);
    }
  }
}

// ─── PipeWire callbacks ───────────────────────────────────────────────────────

static void on_stream_process(void* userdata) {
  auto* s = static_cast<CaptureState*>(userdata);

  struct pw_buffer* b = pw_stream_dequeue_buffer(s->stream);
  if (!b) return;

  struct spa_buffer* buf = b->buffer;
  const auto* src = static_cast<const uint8_t*>(buf->datas[0].data);
  if (src && s->v4l2_fd >= 0 && s->width > 0 && s->height > 0) {
    const size_t yuyv_size = static_cast<size_t>(s->width * s->height * 2);
    if (s->yuyv_buf.size() != yuyv_size)
      s->yuyv_buf.resize(yuyv_size);
    bgrx_to_yuyv(src, s->yuyv_buf.data(), s->width, s->height);
    ssize_t w = write(s->v4l2_fd, s->yuyv_buf.data(), yuyv_size);
    (void)w;
  }

  pw_stream_queue_buffer(s->stream, b);
}

static void on_stream_state_changed(void* userdata,
                                    enum pw_stream_state /*old*/,
                                    enum pw_stream_state state,
                                    const char* /*error*/) {
  auto* s = static_cast<CaptureState*>(userdata);
  if (state == PW_STREAM_STATE_ERROR && s->loop)
    pw_main_loop_quit(s->loop);
}

static void on_param_changed(void* userdata, uint32_t id,
                              const struct spa_pod* param) {
  auto* s = static_cast<CaptureState*>(userdata);
  if (!param || id != SPA_PARAM_Format) return;

  struct spa_video_info info{};
  if (spa_format_parse(param, &info.media_type, &info.media_subtype) < 0) return;
  if (info.media_type != SPA_MEDIA_TYPE_video ||
      info.media_subtype != SPA_MEDIA_SUBTYPE_raw)
    return;
  if (spa_format_video_raw_parse(param, &info.info.raw) < 0) return;

  s->width  = static_cast<int>(info.info.raw.size.width);
  s->height = static_cast<int>(info.info.raw.size.height);

  if (s->v4l2_fd >= 0)
    setup_v4l2_format(s->v4l2_fd, s->width, s->height);

  uint8_t pbuf[512];
  struct spa_pod_builder b = SPA_POD_BUILDER_INIT(pbuf, sizeof(pbuf));
  const struct spa_pod* params[1];
  params[0] = reinterpret_cast<const struct spa_pod*>(
      spa_pod_builder_add_object(
          &b,
          SPA_TYPE_OBJECT_ParamBuffers, SPA_PARAM_Buffers,
          SPA_PARAM_BUFFERS_buffers, SPA_POD_CHOICE_RANGE_Int(2, 1, 32),
          SPA_PARAM_BUFFERS_blocks,  SPA_POD_Int(1),
          SPA_PARAM_BUFFERS_size,    SPA_POD_Int(s->width * s->height * 4),  // source is BGRx
          SPA_PARAM_BUFFERS_stride,  SPA_POD_Int(s->width * 4)));
  pw_stream_update_params(s->stream, params, 1);
}

static const struct pw_stream_events kStreamEvents = {
    .version       = PW_VERSION_STREAM_EVENTS,
    .state_changed = on_stream_state_changed,
    .param_changed = on_param_changed,
    .process       = on_stream_process,
};

// ─── Capture lifecycle ────────────────────────────────────────────────────────

static void capture_destroy(CaptureState* s) {
  if (!s) return;
  s->running = false;
  if (s->loop) pw_main_loop_quit(s->loop);
  if (s->pw_thread.joinable()) s->pw_thread.join();
  if (s->stream)  pw_stream_destroy(s->stream);
  if (s->core)    pw_core_disconnect(s->core);
  if (s->context) pw_context_destroy(s->context);
  if (s->loop)    pw_main_loop_destroy(s->loop);
  if (s->v4l2_fd >= 0) close(s->v4l2_fd);
  delete s;
}

// ─── Method channel ───────────────────────────────────────────────────────────

static void method_call_cb(FlMethodChannel* /*channel*/,
                            FlMethodCall* call,
                            gpointer /*user_data*/) {
  const gchar* method = fl_method_call_get_name(call);

  if (strcmp(method, "initialize") == 0) {
    FlValue* args = fl_method_call_get_args(call);
    if (!args || fl_value_get_type(args) != FL_VALUE_TYPE_MAP) {
      fl_method_call_respond(
          call,
          FL_METHOD_RESPONSE(fl_method_error_response_new(
              "BAD_ARGS", "Expected map argument", nullptr)),
          nullptr);
      return;
    }

    FlValue* v_fd   = fl_value_lookup_string(args, "fd");
    FlValue* v_node = fl_value_lookup_string(args, "nodeId");
    FlValue* v_w    = fl_value_lookup_string(args, "width");
    FlValue* v_h    = fl_value_lookup_string(args, "height");

    if (!v_fd || !v_node || !v_w || !v_h) {
      fl_method_call_respond(
          call,
          FL_METHOD_RESPONSE(fl_method_error_response_new(
              "BAD_ARGS", "Missing fd/nodeId/width/height", nullptr)),
          nullptr);
      return;
    }

    // Dart passes the raw fd from OpenPipeWireRemote. Dup it so Dart's GC can
    // close the original without racing pw_context_connect_fd taking ownership.
    int dart_fd = static_cast<int>(fl_value_get_int(v_fd));
    int pw_fd   = dup(dart_fd);
    if (pw_fd < 0) {
      fl_method_call_respond(
          call,
          FL_METHOD_RESPONSE(fl_method_error_response_new(
              "PW_FD", "dup(pipewire_fd) failed", nullptr)),
          nullptr);
      return;
    }

    int node_id = static_cast<int>(fl_value_get_int(v_node));
    int width   = static_cast<int>(fl_value_get_int(v_w));
    int height  = static_cast<int>(fl_value_get_int(v_h));

    std::lock_guard<std::mutex> lock(g_mutex);

    capture_destroy(g_capture);
    g_capture = nullptr;

    // Find a v4l2loopback OUTPUT device
    char dev_path[64]{};
    int v4l2_fd = find_v4l2loopback_device(dev_path, sizeof(dev_path));
    if (v4l2_fd < 0) {
      close(pw_fd);
      fl_method_call_respond(
          call,
          FL_METHOD_RESPONSE(fl_method_error_response_new(
              "NO_V4L2",
              "No v4l2loopback device found. "
              "Run: sudo modprobe v4l2loopback",
              nullptr)),
          nullptr);
      return;
    }

    if (!setup_v4l2_format(v4l2_fd, width, height)) {
      close(pw_fd);
      close(v4l2_fd);
      fl_method_call_respond(
          call,
          FL_METHOD_RESPONSE(fl_method_error_response_new(
              "V4L2_FMT", "VIDIOC_S_FMT failed", nullptr)),
          nullptr);
      return;
    }

    pw_init(nullptr, nullptr);

    auto* s      = new CaptureState();
    s->v4l2_fd   = v4l2_fd;
    s->width     = width;
    s->height    = height;

    // Write a solid red YUYV frame so we can confirm getUserMedia opens the loopback.
    // YUYV for red (R=235,G=16,B=16): Y=81, U=90, V=240 approx
    {
      const size_t sz = static_cast<size_t>(width * height * 2);
      std::vector<uint8_t> red(sz);
      for (size_t i = 0; i < sz; i += 4) {
        red[i]   = 81;   // Y0
        red[i+1] = 90;   // U
        red[i+2] = 81;   // Y1
        red[i+3] = 240;  // V
      }
      write(v4l2_fd, red.data(), sz);
    }

    s->loop = pw_main_loop_new(nullptr);
    if (!s->loop) {
      close(pw_fd);
      capture_destroy(s);
      fl_method_call_respond(
          call,
          FL_METHOD_RESPONSE(fl_method_error_response_new(
              "PW_INIT", "pw_main_loop_new failed", nullptr)),
          nullptr);
      return;
    }

    s->context = pw_context_new(pw_main_loop_get_loop(s->loop), nullptr, 0);
    if (!s->context) {
      close(pw_fd);
      capture_destroy(s);
      fl_method_call_respond(
          call,
          FL_METHOD_RESPONSE(fl_method_error_response_new(
              "PW_INIT", "pw_context_new failed", nullptr)),
          nullptr);
      return;
    }

    // pw_context_connect_fd takes ownership of pw_fd in all cases
    s->core = pw_context_connect_fd(s->context, pw_fd, nullptr, 0);
    if (!s->core) {
      capture_destroy(s);
      fl_method_call_respond(
          call,
          FL_METHOD_RESPONSE(fl_method_error_response_new(
              "PW_CONNECT", "pw_context_connect_fd failed", nullptr)),
          nullptr);
      return;
    }

    struct pw_properties* props = pw_properties_new(
        PW_KEY_MEDIA_TYPE,     "Video",
        PW_KEY_MEDIA_CATEGORY, "Capture",
        PW_KEY_MEDIA_ROLE,     "Screen",
        nullptr);
    s->stream = pw_stream_new(s->core, "afk-screen", props);
    if (!s->stream) {
      capture_destroy(s);
      fl_method_call_respond(
          call,
          FL_METHOD_RESPONSE(fl_method_error_response_new(
              "PW_STREAM", "pw_stream_new failed", nullptr)),
          nullptr);
      return;
    }

    pw_stream_add_listener(s->stream, &s->stream_listener, &kStreamEvents, s);

    // Request BGRx — 4 bytes/pixel, matches V4L2_PIX_FMT_BGR32
    uint8_t pbuf[512];
    struct spa_pod_builder b = SPA_POD_BUILDER_INIT(pbuf, sizeof(pbuf));
    struct spa_video_info_raw raw_info{};
    raw_info.format          = SPA_VIDEO_FORMAT_BGRx;
    raw_info.size.width      = static_cast<uint32_t>(width);
    raw_info.size.height     = static_cast<uint32_t>(height);
    raw_info.framerate.num   = 30;
    raw_info.framerate.denom = 1;
    const struct spa_pod* params[1];
    params[0] = spa_format_video_raw_build(&b, SPA_PARAM_EnumFormat, &raw_info);

    int ret = pw_stream_connect(
        s->stream,
        PW_DIRECTION_INPUT,
        static_cast<uint32_t>(node_id),
        static_cast<enum pw_stream_flags>(PW_STREAM_FLAG_AUTOCONNECT |
                                          PW_STREAM_FLAG_MAP_BUFFERS),
        params, 1);
    if (ret < 0) {
      capture_destroy(s);
      fl_method_call_respond(
          call,
          FL_METHOD_RESPONSE(fl_method_error_response_new(
              "PW_STREAM", "pw_stream_connect failed", nullptr)),
          nullptr);
      return;
    }

    s->running   = true;
    s->pw_thread = std::thread([s]() {
      pw_main_loop_run(s->loop);
      s->running = false;
    });

    g_capture = s;

    g_autoptr(FlValue) result_val = fl_value_new_string(dev_path);
    fl_method_call_respond(
        call,
        FL_METHOD_RESPONSE(fl_method_success_response_new(result_val)),
        nullptr);

  } else if (strcmp(method, "dispose") == 0) {
    std::lock_guard<std::mutex> lock(g_mutex);
    capture_destroy(g_capture);
    g_capture = nullptr;
    fl_method_call_respond(
        call,
        FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr)),
        nullptr);

  } else {
    fl_method_call_respond(
        call,
        FL_METHOD_RESPONSE(fl_method_not_implemented_response_new()),
        nullptr);
  }
}

// ─── GObject boilerplate ──────────────────────────────────────────────────────

static void pipewire_video_capture_plugin_dispose(GObject* object) {
  G_OBJECT_CLASS(pipewire_video_capture_plugin_parent_class)->dispose(object);
}

static void pipewire_video_capture_plugin_class_init(
    PipewireVideoCapturePluginClass* klass) {
  G_OBJECT_CLASS(klass)->dispose = pipewire_video_capture_plugin_dispose;
}

static void pipewire_video_capture_plugin_init(
    PipewireVideoCapturePlugin* /*self*/) {}

void pipewire_video_capture_plugin_register_with_registrar(
    FlPluginRegistrar* registrar) {
  PipewireVideoCapturePlugin* plugin = PIPEWIRE_VIDEO_CAPTURE_PLUGIN(
      g_object_new(pipewire_video_capture_plugin_get_type(), nullptr));

  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  g_autoptr(FlMethodChannel) channel = fl_method_channel_new(
      fl_plugin_registrar_get_messenger(registrar),
      "pipewire_video_capture",
      FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(channel, method_call_cb,
                                            g_object_ref(plugin),
                                            g_object_unref);

  g_object_unref(plugin);
}
