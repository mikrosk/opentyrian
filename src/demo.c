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
#include "demo.h"

#include "config.h"
#include "episodes.h"
#include "file.h"
#include "keyboard.h"
#include "logging.h"
#include "mainint.h"
#include "mtrand.h"
#include "varz.h"

bool playDemo = false;
bool recordDemo = false;
bool stoppedDemo = false;

static Uint8 demoNum = 0;
static FILE *demoFile = NULL;

static Uint8 demoKeys;
static Uint16 demoKeysWait;  // FKA Varz.lastMoveWait

static const unsigned long seed = 32402394;

void beginPlayDemo(void)
{
	assert(demoFile == NULL);

	if (++demoNum > 5)
		demoNum = 1;

	char demoFilename[9];
	snprintf(demoFilename, sizeof(demoFilename), "demo.%d", demoNum);

	logDebug("Playing demo '%s'.", demoFilename);

	demoFile = dir_fopen_die(data_dir(), demoFilename, "rb");

	mt_srand(seed);

	difficultyLevel = DIFFICULTY_NORMAL;

	Uint8 temp;
	fread_u8_die(&temp, 1, demoFile);
	JE_initEpisode(temp);

	fread_die(levelName, 1, 10, demoFile);
	levelName[10] = '\0';

	fread_u8_die(&lvlFileNum, 1, demoFile);

	fread_u8_die(&player[0].items.weapon[FRONT_WEAPON].id,  1, demoFile);
	fread_u8_die(&player[0].items.weapon[REAR_WEAPON].id,   1, demoFile);
	fread_u8_die(&player[0].items.super_arcade_mode,        1, demoFile);
	fread_u8_die(&player[0].items.sidekick[LEFT_SIDEKICK],  1, demoFile);
	fread_u8_die(&player[0].items.sidekick[RIGHT_SIDEKICK], 1, demoFile);
	fread_u8_die(&player[0].items.generator,                1, demoFile);

	fread_u8_die(&player[0].items.sidekick_level,           1, demoFile);
	fread_u8_die(&player[0].items.sidekick_series,          1, demoFile);

	fread_u8_die(&initial_episode_num,                      1, demoFile);

	fread_u8_die(&player[0].items.shield,                   1, demoFile);
	fread_u8_die(&player[0].items.special,                  1, demoFile);
	fread_u8_die(&player[0].items.ship,                     1, demoFile);

	for (uint i = 0; i < 2; ++i)
		fread_u8_die(&player[0].items.weapon[i].power,      1, demoFile);

	Uint8 unused[3];
	fread_u8_die(unused, 3, demoFile);

	fread_u8_die(&levelSong, 1, demoFile);

	demoKeys = 0;

	Uint8 temp2[2] = { 0, 0 };
	fread_u8(temp2, 2, demoFile);
	demoKeysWait = (temp2[0] << 8) | temp2[1];
}

bool playDemoKeys(void)
{
	while (demoKeysWait == 0)
	{
		demoKeys = 0;
		fread_u8(&demoKeys, 1, demoFile);

		Uint8 temp2[2] = { 0, 0 };
		fread_u8(temp2, 2, demoFile);
		demoKeysWait = (temp2[0] << 8) | temp2[1];

		if (feof(demoFile))
			return false;  // no more keys
	}

	demoKeysWait--;

	if (demoKeys & (1 << KEY_SETTING_UP))
		player[0].y -= CURRENT_KEY_SPEED;
	if (demoKeys & (1 << KEY_SETTING_DOWN))
		player[0].y += CURRENT_KEY_SPEED;

	if (demoKeys & (1 << KEY_SETTING_LEFT))
		player[0].x -= CURRENT_KEY_SPEED;
	if (demoKeys & (1 << KEY_SETTING_RIGHT))
		player[0].x += CURRENT_KEY_SPEED;

	button[0] = (bool)(demoKeys & (1 << KEY_SETTING_FIRE));
	button[3] = (bool)(demoKeys & (1 << KEY_SETTING_CHANGE_FIRE));
	button[1] = (bool)(demoKeys & (1 << KEY_SETTING_LEFT_SIDEKICK));
	button[2] = (bool)(demoKeys & (1 << KEY_SETTING_RIGHT_SIDEKICK));

	return true;
}

void endPlayDemo(void)
{
	fclose(demoFile);
	demoFile = NULL;
}

void beginRecordDemo(void)
{
	assert(demoFile == NULL);

	char newDemoFilename[12];
	for (Uint8 newDemoNum = 1; ; ++newDemoNum)
	{
		snprintf(newDemoFilename, sizeof(newDemoFilename), "demorec.%d", newDemoNum);

		if (!dir_file_exists(get_user_directory(), newDemoFilename))
			break;

		if (newDemoNum == UINT8_MAX)
		{
			logFatal("No more demo recording files can be created.");
			exit(EXIT_FAILURE);
		}
	}

	logDebug("Recording demo '%s'.", newDemoFilename);

	demoFile = dir_fopen_die(get_user_directory(), newDemoFilename, "wb");

	mt_srand(seed);

	difficultyLevel = DIFFICULTY_NORMAL;

	fwrite_u8_die(&episodeNum, 1, demoFile);

	// Pad string buffer with NULs.
	for (size_t i = 1; i < 10; ++i)
		if (levelName[i - 1] == '\0')
			levelName[i] = '\0';
	fwrite_u8_die((Uint8 *)levelName, 10, demoFile);

	fwrite_u8_die(&lvlFileNum, 1, demoFile);

	fwrite_u8_die(&player[0].items.weapon[FRONT_WEAPON].id,  1, demoFile);
	fwrite_u8_die(&player[0].items.weapon[REAR_WEAPON].id,   1, demoFile);
	fwrite_u8_die(&player[0].items.super_arcade_mode,        1, demoFile);
	fwrite_u8_die(&player[0].items.sidekick[LEFT_SIDEKICK],  1, demoFile);
	fwrite_u8_die(&player[0].items.sidekick[RIGHT_SIDEKICK], 1, demoFile);
	fwrite_u8_die(&player[0].items.generator,                1, demoFile);

	fwrite_u8_die(&player[0].items.sidekick_level,           1, demoFile);
	fwrite_u8_die(&player[0].items.sidekick_series,          1, demoFile);

	fwrite_u8_die(&initial_episode_num,                      1, demoFile);

	fwrite_u8_die(&player[0].items.shield,                   1, demoFile);
	fwrite_u8_die(&player[0].items.special,                  1, demoFile);
	fwrite_u8_die(&player[0].items.ship,                     1, demoFile);

	for (uint i = 0; i < 2; ++i)
		fwrite_u8_die(&player[0].items.weapon[i].power,      1, demoFile);

	Uint8 unused[3] = { 0, 0, 0 };
	fwrite_u8_die(unused, 3, demoFile);

	fwrite_u8_die(&levelSong, 1, demoFile);

	demoKeys = 0;
	demoKeysWait = 0;
}

void recordDemoKeys(void)
{
	Uint8 oldDemoKeys = demoKeys;

	demoKeys = 0;
	for (size_t i = 0; i < 8; ++i)
		demoKeys |= keysactive[keySettings[i]] << i;

	if (demoKeys != oldDemoKeys || demoKeysWait == UINT16_MAX)
	{
		Uint8 temp2[2] = { demoKeysWait >> 8, demoKeysWait };
		fwrite_u8(temp2, 2, demoFile);
		fwrite_u8(&demoKeys, 1, demoFile);

		demoKeysWait = 0;
	}

	demoKeysWait++;
}

void endRecordDemo(void)
{
	Uint8 temp2[2] = { demoKeysWait >> 8, demoKeysWait };
	fwrite_u8(temp2, 2, demoFile);

	fclose(demoFile);
	demoFile = NULL;
}
