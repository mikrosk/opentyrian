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
#ifndef NFM_OPL_H
#define NFM_OPL_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

// OPL2/OPL3 hardware access through the nFM library
// (https://framagit.org/nokturnal/nfm)

extern bool nfm_opl_active;

// Devices that can be passed to nfm_opl_init(); the set depends on the drivers
// the nFM library was built with.
#define NFM_OPL_DEFAULT_DEVICE 1  // NokturnFM3
size_t nfm_opl_device_count(void);
const char *nfm_opl_device_id(size_t device);    // for the command line and config
const char *nfm_opl_device_name(size_t device);  // for the setup menu

// Starts calling tick() from a timer interrupt at ~69.5 Hz.
bool nfm_opl_init(size_t device, void (*tick)(void));
void nfm_opl_deinit(void);

void nfm_opl_reset(void);
void nfm_opl_write(uint8_t reg, uint8_t val);

#endif /* NFM_OPL_H */
