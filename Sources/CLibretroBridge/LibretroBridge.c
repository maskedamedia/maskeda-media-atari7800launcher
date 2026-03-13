#include "LibretroBridge.h"

#include <dlfcn.h>
#include <stdarg.h>
#include <stdio.h>
#include <string.h>

static void lb_write_error(char *buffer, size_t buffer_size, const char *format, ...) {
    va_list args;
    if (!buffer || buffer_size == 0) {
        return;
    }

    va_start(args, format);
    vsnprintf(buffer, buffer_size, format, args);
    va_end(args);
}

static void *lb_load_symbol(void *handle, const char *symbol) {
    dlerror();
    return dlsym(handle, symbol);
}

#define LB_RESOLVE(core_handle, field, symbol_name, type_name, error_message, error_size) \
    do { \
        void *symbol = lb_load_symbol((core_handle), (symbol_name)); \
        if (!symbol) { \
            lb_write_error((error_message), (error_size), "missing required symbol: %s", (symbol_name)); \
            return -2; \
        } \
        out_core->field = (type_name)symbol; \
    } while (0)

int lb_core_open(const char *path, LBLoadedCore *out_core, char *error_message, size_t error_message_size) {
    void *handle;

    if (!path || !out_core) {
        lb_write_error(error_message, error_message_size, "invalid arguments to lb_core_open");
        return -1;
    }

    memset(out_core, 0, sizeof(*out_core));
    handle = dlopen(path, RTLD_NOW | RTLD_LOCAL);
    if (!handle) {
        lb_write_error(error_message, error_message_size, "dlopen failed: %s", dlerror());
        return -1;
    }

    out_core->handle = handle;
    LB_RESOLVE(handle, retro_init, "retro_init", lb_retro_init_fn, error_message, error_message_size);
    LB_RESOLVE(handle, retro_deinit, "retro_deinit", lb_retro_deinit_fn, error_message, error_message_size);
    LB_RESOLVE(handle, retro_api_version, "retro_api_version", lb_retro_api_version_fn, error_message, error_message_size);
    LB_RESOLVE(handle, retro_get_system_info, "retro_get_system_info", lb_retro_get_system_info_fn, error_message, error_message_size);
    LB_RESOLVE(handle, retro_get_system_av_info, "retro_get_system_av_info", lb_retro_get_system_av_info_fn, error_message, error_message_size);
    LB_RESOLVE(handle, retro_set_environment, "retro_set_environment", lb_retro_set_environment_fn, error_message, error_message_size);
    LB_RESOLVE(handle, retro_set_video_refresh, "retro_set_video_refresh", lb_retro_set_video_refresh_fn, error_message, error_message_size);
    LB_RESOLVE(handle, retro_set_audio_sample, "retro_set_audio_sample", lb_retro_set_audio_sample_fn, error_message, error_message_size);
    LB_RESOLVE(handle, retro_set_audio_sample_batch, "retro_set_audio_sample_batch", lb_retro_set_audio_sample_batch_fn, error_message, error_message_size);
    LB_RESOLVE(handle, retro_set_input_poll, "retro_set_input_poll", lb_retro_set_input_poll_fn, error_message, error_message_size);
    LB_RESOLVE(handle, retro_set_input_state, "retro_set_input_state", lb_retro_set_input_state_fn, error_message, error_message_size);
    LB_RESOLVE(handle, retro_load_game, "retro_load_game", lb_retro_load_game_fn, error_message, error_message_size);
    LB_RESOLVE(handle, retro_unload_game, "retro_unload_game", lb_retro_unload_game_fn, error_message, error_message_size);
    LB_RESOLVE(handle, retro_run, "retro_run", lb_retro_run_fn, error_message, error_message_size);
    LB_RESOLVE(handle, retro_reset, "retro_reset", lb_retro_reset_fn, error_message, error_message_size);
    LB_RESOLVE(handle, retro_serialize_size, "retro_serialize_size", lb_retro_serialize_size_fn, error_message, error_message_size);
    LB_RESOLVE(handle, retro_serialize, "retro_serialize", lb_retro_serialize_fn, error_message, error_message_size);
    LB_RESOLVE(handle, retro_unserialize, "retro_unserialize", lb_retro_unserialize_fn, error_message, error_message_size);

    return 0;
}

void lb_core_close(LBLoadedCore *core) {
    if (!core || !core->handle) {
        return;
    }

    dlclose(core->handle);
    memset(core, 0, sizeof(*core));
}

void lb_core_set_callbacks(LBLoadedCore *core) {
    if (!core) {
        return;
    }

    core->retro_set_environment(lb_environment_callback);
    core->retro_set_video_refresh(lb_video_refresh_callback);
    core->retro_set_audio_sample(lb_audio_sample_callback);
    core->retro_set_audio_sample_batch(lb_audio_sample_batch_callback);
    core->retro_set_input_poll(lb_input_poll_callback);
    core->retro_set_input_state(lb_input_state_callback);
}
