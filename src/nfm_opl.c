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
#include "nfm_opl.h"

#if defined(WITH_NFM)

#include "logging.h"
#include "opentyr.h"

#include <nfmcore.h>

#include <mint/osbind.h>
#include <mint/ostruct.h>

#include <stdlib.h>
#include <string.h>

typedef struct
{
	const char *id;
	const char *name;
	eFmDriverType type;
	eChipModel chip;
	bool opl2AudioBoard;
	bool supervisor;
} Device;

// OPLL, FMST and the OPL3 Express are left out: the first two are not OPL
// compatible and the last one cannot be written from an interrupt.
// NFM_OPL_DEFAULT_DEVICE refers to an index in this table.
static const Device devices[] =
{
	{ "nfm2",      "NokturnFM2",    FMD_OPLCART,               CM_OPL2, false, false },
	{ "nfm3",      "NokturnFM3",    FMD_OPLCART,               CM_OPL3, false, false },
	// VME allows user access but not sure about other _ISA adapters
	{ "isasb",     "SB (ISA)",      FMD_ISA_SB,                CM_OPL3, false, true  },
	{ "opl2lpt",   "OPL2LPT",       FMD_OPL2LPT,               CM_OPL2, false, true  },
	{ "opl3lpt",   "OPL3LPT",       FMD_OPL3LPT,               CM_OPL3, false, true  },
	{ "opl2audio", "OPL2 Audio",    FMD_CE_OPL2AUDIO_LPT_SPI,  CM_OPL2, true,  true  },
	{ "opl3duo",   "OPL3 Duo!",     FMD_CE_OPL3DUO_LPT_SPI,    CM_OPL3, false, true  },
	{ "null",      "NatFeats",      FMD_NULL,                  CM_OPL3, false, false },
};

bool nfm_opl_active = false;

static sFmInterface iface;
static const Device *activeDevice;

// 2457600 Hz / 200 / 177 = 69.42 Hz
#define TIMER_B_CTRL_DIV200 7
#define TIMER_B_DATA        177
#define TIMER_B_VECTOR      (0x120 / 4)
#define MFP_IERA            ((volatile uint8_t *)0xfffffa07)
#define MFP_ISRA            ((volatile uint8_t *)0xfffffa0f)

static void (*tickCallback)(void);
static void (*oldTimerBVector)(void);
// Set while tickCallback() runs in supervisor mode from the interrupt.
static volatile bool inTimerB = false;

static __attribute__((interrupt)) void timerBInterrupt(void)
{
	// With OPL2 write delays a tick can take ~1 ms. Clearing the in-service
	// bit and lowering the IPL lets the keyboard and audio interrupts through
	// meanwhile; disabling Timer B prevents re-entrancy and drops requests
	// arriving during the tick instead of letting them pile up.
	*MFP_IERA &= (uint8_t)~(1 << 0);
	*MFP_ISRA = (uint8_t)~(1 << 0);
	__asm__ volatile ("move.w #0x2500,%%sr" ::: "memory");

	inTimerB = true;

	tickCallback();

	inTimerB = false;

	*MFP_IERA |= (1 << 0);
}

static void *enterSuper(void)
{
	if (!activeDevice->supervisor || Super(SUP_INQUIRE))
		return NULL;
	return (void *)Super(SUP_SET);
}

static void leaveSuper(void *oldStack)
{
	if (oldStack != NULL)
		SuperToUser(oldStack);
}

size_t nfm_opl_device_count(void)
{
	return COUNTOF(devices);
}

const char *nfm_opl_device_id(size_t device)
{
	return devices[device].id;
}

const char *nfm_opl_device_name(size_t device)
{
	return devices[device].name;
}

bool nfm_opl_init(size_t index, void (*tick)(void))
{
	if (nfm_opl_active || index >= COUNTOF(devices))
		return false;

	const Device *device = &devices[index];

	if (nfInit(NULL, NULL) < 0)
	{
		logError("nFM: initialization failed");
		return false;
	}

	sOplInterfaceConfiguration config =
	{
		.deviceType = device->type,
		.soundchip = device->chip,
		.operationMode = CO_OPL2,
		.setup = CC_SINGLE,
		.dualChipEmulationEnabled = false,
	};

	iface = nfCreateInterface(config);
	activeDevice = device;

	sInterfaceInitData params;
	memset(&params, 0, sizeof(params));
	params.uCeAudioBoardSettings.isOpl2AudioBoard = device->opl2AudioBoard;

	void *oldStack = enterSuper();
	const int32_t result = nfInitialiseInterface(&iface, &params);
	if (result < 0)
		nfDestroyInterface(&iface);
	leaveSuper(oldStack);

	if (result < 0)
	{
		logError("nFM: failed to initialize '%s'", device->name);
		nfDeinit();
		return false;
	}

	logInfo("nFM: using '%s'", nfGetDriverName(&iface));

	nfm_opl_active = true;

	tickCallback = tick;
	oldTimerBVector = Setexc(TIMER_B_VECTOR, VEC_INQUIRE);
	Xbtimer(XB_TIMERB, TIMER_B_CTRL_DIV200, TIMER_B_DATA, timerBInterrupt);
	Jenabint(MFP_TIMERB);

	// Leaving the timer running after exit would crash the system.
	static bool atexitRegistered = false;
	if (!atexitRegistered)
		atexitRegistered = atexit(nfm_opl_deinit) == 0;

	return true;
}

void nfm_opl_deinit(void)
{
	if (!nfm_opl_active)
		return;

	Jdisint(MFP_TIMERB);
	Xbtimer(XB_TIMERB, 0, 0, oldTimerBVector);
	Jdisint(MFP_TIMERB);

	nfm_opl_active = false;

	void *oldStack = enterSuper();
	nfReset(&iface);
	nfDestroyInterface(&iface);
	leaveSuper(oldStack);

	nfDeinit();
}

void nfm_opl_reset(void)
{
	void *oldStack = enterSuper();
	nfReset(&iface);
	leaveSuper(oldStack);
}

void nfm_opl_write(uint8_t reg, uint8_t val)
{
	const sOplRegisterWrite write = { .port = 0, .reg = reg, .value = val };

	if (inTimerB)
	{
		iface.write(&write);
	}
	else
	{
		void *oldStack = enterSuper();
		iface.write(&write);
		leaveSuper(oldStack);
	}
}

#endif /* WITH_NFM */
