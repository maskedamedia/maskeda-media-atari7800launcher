#ifndef LIBRETRO_BRIDGE_H
#define LIBRETRO_BRIDGE_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include "libretro.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef void (RETRO_CALLCONV *lb_retro_init_fn)(void);
typedef void (RETRO_CALLCONV *lb_retro_deinit_fn)(void);
typedef unsigned (RETRO_CALLCONV *lb_retro_api_version_fn)(void);
typedef void (RETRO_CALLCONV *lb_retro_get_system_info_fn)(struct retro_system_info *);
typedef void (RETRO_CALLCONV *lb_retro_get_system_av_info_fn)(struct retro_system_av_info *);
typedef void (RETRO_CALLCONV *lb_retro_set_environment_fn)(retro_environment_t);
typedef void (RETRO_CALLCONV *lb_retro_set_video_refresh_fn)(retro_video_refresh_t);
typedef void (RETRO_CALLCONV *lb_retro_set_audio_sample_fn)(retro_audio_sample_t);
typedef void (RETRO_CALLCONV *lb_retro_set_audio_sample_batch_fn)(retro_audio_sample_batch_t);
typedef void (RETRO_CALLCONV *lb_retro_set_input_poll_fn)(retro_input_poll_t);
typedef void (RETRO_CALLCONV *lb_retro_set_input_state_fn)(retro_input_state_t);
typedef bool (RETRO_CALLCONV *lb_retro_load_game_fn)(const struct retro_game_info *);
typedef void (RETRO_CALLCONV *lb_retro_unload_game_fn)(void);
typedef void (RETRO_CALLCONV *lb_retro_run_fn)(void);
typedef void (RETRO_CALLCONV *lb_retro_reset_fn)(void);
typedef size_t (RETRO_CALLCONV *lb_retro_serialize_size_fn)(void);
typedef bool (RETRO_CALLCONV *lb_retro_serialize_fn)(void *, size_t);
typedef bool (RETRO_CALLCONV *lb_retro_unserialize_fn)(const void *, size_t);

typedef struct LBLoadedCore {
    void *handle;
    lb_retro_init_fn retro_init;
    lb_retro_deinit_fn retro_deinit;
    lb_retro_api_version_fn retro_api_version;
    lb_retro_get_system_info_fn retro_get_system_info;
    lb_retro_get_system_av_info_fn retro_get_system_av_info;
    lb_retro_set_environment_fn retro_set_environment;
    lb_retro_set_video_refresh_fn retro_set_video_refresh;
    lb_retro_set_audio_sample_fn retro_set_audio_sample;
    lb_retro_set_audio_sample_batch_fn retro_set_audio_sample_batch;
    lb_retro_set_input_poll_fn retro_set_input_poll;
    lb_retro_set_input_state_fn retro_set_input_state;
    lb_retro_load_game_fn retro_load_game;
    lb_retro_unload_game_fn retro_unload_game;
    lb_retro_run_fn retro_run;
    lb_retro_reset_fn retro_reset;
    lb_retro_serialize_size_fn retro_serialize_size;
    lb_retro_serialize_fn retro_serialize;
    lb_retro_unserialize_fn retro_unserialize;
} LBLoadedCore;

bool lb_environment_callback(unsigned cmd, void *data);
void lb_video_refresh_callback(const void *data, unsigned width, unsigned height, size_t pitch);
void lb_audio_sample_callback(int16_t left, int16_t right);
size_t lb_audio_sample_batch_callback(const int16_t *data, size_t frames);
void lb_input_poll_callback(void);
int16_t lb_input_state_callback(unsigned port, unsigned device, unsigned index, unsigned id);

int lb_core_open(const char *path, LBLoadedCore *out_core, char *error_message, size_t error_message_size);
void lb_core_close(LBLoadedCore *core);
void lb_core_set_callbacks(LBLoadedCore *core);

#ifdef __cplusplus
}
#endif

#endif
