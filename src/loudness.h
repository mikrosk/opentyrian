/* 
 * OpenTyrian: A modern cross-platform port of Tyrian
 * Copyright (C) The OpenTyrian Development Team
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License
 * as published by the Free Software Foundation; either version 2
 * of the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
 */
#ifndef LOUDNESS_H
#define LOUDNESS_H

#include "opentyr.h"

#if defined(TARGET_ATARI)
#define OUTPUT_QUALITY 1  // 11.025 kHz
#define OUTPUT_CHANNELS 2  // Falcon and FireBee have no 16-bit mono
#else
#define OUTPUT_QUALITY 4  // 44.1 kHz
#define OUTPUT_CHANNELS 1
#endif

extern int audioSampleRate;

extern unsigned int song_playing;

extern bool audio_disabled, music_disabled, samples_disabled;

// Device that plays the music: 0 is the DOSBox OPL emulator, the others are OPL
// hardware devices.
extern size_t music_device;

bool init_audio(void);
void deinit_audio(void);

size_t music_device_count(void);
const char *music_device_id(size_t device);    // for the command line and config
const char *music_device_name(size_t device);  // for the setup menu
bool find_music_device(const char *id, size_t *device);
void set_music_device(size_t device);

void play_song(unsigned int song_num);
void restart_song(void);
void stop_song(void);
void fade_song(void);

void set_volume(Uint8 musicVolume, Uint8 sampleVolume);

void multiSamplePlay(const Sint16 *samples, size_t sampleCount, Uint8 chan, Uint8 vol);

#endif /* LOUDNESS_H */
