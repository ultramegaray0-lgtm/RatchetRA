/* rando_give core: portable logic of the randomizer's "give item" and (v3) "mission" helper.
 *
 * The game's own level-script node AddToInventoryAction gives an item by sending the actor
 * message "AddToInventoryHandle" to the local player (RiftApart.exe 3.0630.1.0, handler at
 * RVA 0x86CB90):
 *
 *     ActorList t;  GetPlayerActors(g_players /RVA 0x6747580/, &t, 0)      ; RVA 0x12AB160
 *     struct { u64 item; u32 count; } payload = { item_config_asset_id, count };
 *     SendMessage(1, *(u64 *)RVA 0x60315B8, t.ptr, t.count, &payload, 0xC)   ; RVA 0x1B7B850
 *
 * One difference, found in game (round 12): the handler's default target, GetPlayerActors(.., 0)
 * (an actor group, index 0 of the game's group table), was ignored by the game. The nodes that
 * really gave items (Nefarious City, rounds 7-8) all targeted "_Local" through their Target
 * variable. So the target is chosen per request (MB_MODE): 0 = the hero actor handle rivet_hook
 * reports, k >= 1 = actor group k - 1. The Lua script tries targets in turn and keeps the one
 * the game answers.
 *
 * This helper makes exactly that call, on the game thread, when the randomizer's Lua script
 * asks for it through a small shared "mailbox" (see MAILBOX_* below). Nothing is called or
 * patched unless every byte of the handler and of the hook site matches the expected exe.
 *
 * This file has no OS dependencies so it can be unit-tested on any machine.
 */
#ifndef RANDO_GIVE_CORE_H
#define RANDO_GIVE_CORE_H

typedef unsigned char u8;
typedef unsigned int u32;
typedef unsigned long long u64;

#define RG_MAGIC 0x31564947444E4152ULL /* "RANDGIV1" */
#define RG_VERSION 7u

/* mailbox layout (one 4 KiB page, read and written by Lua through rivet.read / rivet.write) */
#define MB_MAGIC 0x00   /* u64 RG_MAGIC */
#define MB_VERSION 0x08 /* u32 */
#define MB_STATUS 0x0C  /* u32 RG_STATUS_* */
#define MB_REQ 0x10     /* u32 request sequence, written by Lua (last) */
#define MB_DONE 0x14    /* u32 last processed sequence, written by the helper */
#define MB_ITEM 0x18    /* u64 item config asset id */
#define MB_COUNT 0x20   /* u32 */
#define MB_RESULT 0x24  /* u32 RG_RESULT_* of the last request */
#define MB_PUMPS 0x28   /* u32 heartbeat: frames the hook has run */
#define MB_TARGETS 0x2C /* u32 number of actors the last message went to */
#define MB_BASE 0x30    /* u64 exe load address (diagnostics) */
#define MB_HERO 0x38    /* u32 hero actor handle from Lua (fallback target) */
#define MB_SENT 0x3C    /* u32 messages sent so far */
#define MB_PATH 0x40    /* u32 target actually used by the last message: MB_MODE value + 1, 0 = none */
#define MB_MODE 0x44    /* u32 target for this request: 0 = hero handle (MB_HERO), k = group k - 1 */
#define RG_MAX_GROUP 64u
/* v3: mission requests (see "mission system" below) */
#define MB_KIND 0x48     /* u32 RG_KIND_* of this request; 0 = give an item, exactly as in v2 */
#define MB_SLOT 0x4C     /* u32 mission name slot: the name is at MB_NAMES + slot * RG_NAME_SIZE */
#define MB_FLAG 0x50     /* u32 StartMissionAction's flag byte (node + 0x60); 0 unless researched */
#define MB_BEFORE 0x54   /* u32 the game's own mission state before the call */
#define MB_AFTER 0x58    /* u32 ... and after it */
#define MB_RET 0x5C      /* u32 what the game's call returned (start) */
#define MB_MISSIONS 0x60 /* u32 1 = every mission-system byte matched this exe (set at start) */
#define MB_INDEX 0x64    /* u32 system 1: index in the manager's table; system 2: the mission actor's handle */
#define MB_OBJECT 0x68   /* u64 system 2: the mission component (research: its vtable) */
#define MB_SYSTEM 0x70   /* u32 which mission system answered: 1 or 2 */
#define MB_VANITY 0x74   /* u32 v5: 1 = every byte of the armor-give path matched this exe (set at start) */
#define MB_V6 0x78       /* u32 v6: which 8.0 paths matched this exe (RG_V6_*), set at start */
#define MB_CLEAR_END 0x100
/* v5: armor sources and configs (cleared at start like the block above) */
#define MB_ARMOR_ON 0x100    /* u32 written by Lua: 1 = the pieces in MB_ARMOR_TABLE are intercepted */
#define MB_ARMOR_HOOK 0x104  /* u32 RG_ARMOR_HOOK_*: is VanityGiveBundleAction's handler replaced */
#define MB_ARMOR_SEQ 0x10C   /* u32 events written to the ring so far (the helper only counts up) */
#define MB_ARMOR_CALLS 0x110 /* u32 times the game ran VanityGiveBundleAction since start */
#define MB_CONFIG_MGR 0x118  /* u64 the game's config asset manager (found by rivet_hook's own signature), 0 = not found */
#define MB_CONFIG_SIGS 0x120 /* u32 how many times that signature matched (1 expected) */
#define MB_SCENE_MGR 0x128   /* u64 v7: the game's SceneManager (rivet_hook's own SCENE_MANAGER signature), 0 = not exactly one match */
#define MB_SCENE_SIGS 0x130  /* u32 v7: how many times that signature matched (rivet_hook accepts exactly 1) */
#define MB_ARMOR_TABLE 0x180 /* u64[RG_ARMOR_MAX] bundle ids to intercept, 0 = free; the helper zeroes an entry it used */
#define RG_ARMOR_MAX 48u
#define MB_ARMOR_RING 0x300  /* RG_ARMOR_RING entries of { u64 bundle; u32 seq; u32 what }, entry = seq % RG_ARMOR_RING */
#define RG_ARMOR_RING 16u    /* 0x300..0x400; mission names start at 0x400 */
#define MB_NAMES 0x400
#define RG_NAME_SIZE 0x40u
#define RG_NAME_SLOTS 48u /* names are never overwritten by Lua: the game may keep the pointer */

enum {
	RG_STATUS_STARTING = 0,
	RG_STATUS_READY = 1,
	RG_STATUS_WRONG_EXE = 2,
	RG_STATUS_HOOK_FAILED = 3,
};

enum {
	RG_RESULT_NONE = 0,
	RG_RESULT_SENT = 1,
	RG_RESULT_NO_TARGET = 2,
	RG_RESULT_FAULT = 3,
	RG_RESULT_BAD_REQUEST = 4,
	/* v3, mission requests */
	RG_RESULT_NOT_VERIFIED = 5,    /* the mission code of this exe did not match: nothing called */
	RG_RESULT_NO_MANAGER = 6,      /* the game's mission manager does not exist (yet) */
	RG_RESULT_NOT_READY = 7,       /* the manager says it is not ready (loading, menus) */
	RG_RESULT_ALT_SYSTEM = 8,      /* the game runs its other mission path; the actions do nothing then */
	RG_RESULT_UNKNOWN_MISSION = 9, /* no mission of that name in the manager's table */
	RG_RESULT_WRONG_STATE = 10,    /* the game's action would do nothing in this state, so neither did we */
	RG_RESULT_DONE = 11,           /* the game's own calls were made; see MB_BEFORE / MB_AFTER */
	RG_RESULT_NO_SUCH_ACTION = 12, /* the game's action does nothing in this mission system */
	RG_RESULT_NOT_FOUND = 13,      /* v5: no loaded config with that asset id */
};

enum {
	RG_KIND_GIVE = 0,
	RG_KIND_MISSION_QUERY = 1,          /* read the state through the game's own function */
	RG_KIND_MISSION_MAKE_AVAILABLE = 2, /* exactly what MakeMissionAvailableAction does */
	RG_KIND_MISSION_START = 3,          /* exactly what StartMissionAction does */
	RG_KIND_MISSION_COMPLETE = 4,       /* exactly what CompleteMissionAction's "complete" input does */
	RG_KIND_MISSION_REPLAY = 5,         /* v4, system 2: exactly what ReplayMissionAction does */
	RG_KIND_VANITY_GIVE = 6,            /* v5: exactly what VanityGiveBundleAction does (one armor piece) */
	RG_KIND_CONFIG_LOOKUP = 7,          /* v5: the loaded config with asset id MB_ITEM -> MB_OBJECT (read only) */
	/* v6 (Randomizer 8.0, experimental): */
	RG_KIND_MISSION_SET_STATE = 8,      /* system 2: write state MB_FLAG (0..5) into the mission's saved state record */
	RG_KIND_LEVEL_SET = 9,              /* exactly what UnlockLevelAction does: level MB_COUNT (1..10), MB_FLAG 1 unlock / 0 lock */
	RG_KIND_LEVEL_READ = 10,            /* read the level masks (+0x30 unlocked, +0x2C, +0x20) */
	RG_KIND_TRAVEL_SET = 11,            /* exactly what SetPlanetaryTravelAction does: MB_FLAG 0/1 */
	RG_KIND_MISSION_PROBE = 12,         /* system 2: find the mission's state record (MB_OBJECT), change nothing */
};
/* v6: MB_V6 bits */
enum {
	RG_V6_STATE = 1,   /* the walk to a mission's state record matches State() byte for byte */
	RG_V6_LEVELS = 2,  /* UnlockLevelAction's handler and the bit function match */
	RG_V6_TRAVEL = 4,  /* SetPlanetaryTravelAction's handler matches */
};
/* v5: what happened when the game ran VanityGiveBundleAction (ring entry "what") */
enum {
	RG_ARMOR_INTERCEPTED = 1, /* the piece was in MB_ARMOR_TABLE: nothing given, "success" output fired */
	RG_ARMOR_GIVEN = 2,       /* not listed: given exactly as the game does, and the game said yes */
	RG_ARMOR_NOT_GIVEN = 3,   /* not listed: given as the game does, the game said no (owned already, no hero) */
};
enum {
	RG_ARMOR_HOOK_OFF = 0,     /* not tried (helper not ready) */
	RG_ARMOR_HOOK_ON = 1,      /* replaced: every run of the action goes through rg_armor_action */
	RG_ARMOR_HOOK_NO_MATCH = 2,/* this exe's armor code differs: nothing patched */
	RG_ARMOR_HOOK_BUSY = 3,    /* a thread stood inside the bytes to patch: nothing patched */
};

/* RVAs in RiftApart.exe 3.0630.1.0 (Steam), all checked by rg_verify before use */
#define RVA_ADD_TO_INVENTORY_HANDLER 0x86CB90u
#define RVA_SIGNAL_PUMP 0x12BE970u       /* the script signal queue processor, runs every frame */
#define RVA_GET_PLAYER_ACTORS 0x12AB160u
#define RVA_PLAYERS_GLOBAL 0x6747580u
#define RVA_SEND_MESSAGE 0x1B7B850u
#define RVA_ADD_TO_INVENTORY_MSG 0x60315B8u
#define HOOK_BYTES 14

/* the whole AddToInventoryAction handler, byte for byte: proves the build and every RVA above */
static const u8 RG_EXPECTED_HANDLER[0xA3] = {
	0x40, 0x53, 0x48, 0x83, 0xec, 0x50, 0x48, 0x8b, 0xd9, 0x48, 0x8d, 0x54, 0x24, 0x60, 0x48, 0x8b,
	0x49, 0x58, 0x41, 0xb8, 0x9b, 0x61, 0x17, 0x78, 0xe8, 0x63, 0x13, 0xa5, 0x00, 0x44, 0x8b, 0xc8,
	0x85, 0xc0, 0x75, 0x25, 0x45, 0x33, 0xc0, 0x48, 0x8d, 0x54, 0x24, 0x40, 0x48, 0x8d, 0x0d, 0xbd,
	0xa9, 0xed, 0x05, 0xe8, 0x98, 0xe5, 0xa3, 0x00, 0x4c, 0x8b, 0x44, 0x24, 0x40, 0x44, 0x8b, 0x4c,
	0x24, 0x48, 0x4c, 0x89, 0x44, 0x24, 0x60, 0xeb, 0x05, 0x4c, 0x8b, 0x44, 0x24, 0x60, 0x8b, 0x43,
	0x68, 0xb9, 0x01, 0x00, 0x00, 0x00, 0x48, 0x8b, 0x15, 0xcb, 0x49, 0x7c, 0x05, 0x89, 0x44, 0x24,
	0x38, 0x48, 0x8b, 0x43, 0x60, 0x48, 0x89, 0x44, 0x24, 0x30, 0x48, 0x8d, 0x44, 0x24, 0x30, 0xc7,
	0x44, 0x24, 0x28, 0x0c, 0x00, 0x00, 0x00, 0x48, 0x89, 0x44, 0x24, 0x20, 0xe8, 0x3f, 0xec, 0x30,
	0x01, 0x48, 0x8b, 0x4b, 0x58, 0xba, 0x8a, 0xbc, 0xea, 0x6e, 0xe8, 0xf1, 0x18, 0xa5, 0x00, 0x48,
	0x8b, 0x4b, 0x58, 0xba, 0x50, 0x44, 0xbf, 0x93, 0xe8, 0xe3, 0x18, 0xa5, 0x00, 0x48, 0x83, 0xc4,
	0x50, 0x5b, 0xc3,
};

/* first bytes of the signal pump: four position-independent instructions, exactly 14 bytes
 * (mov [rsp+8],rbx / push rdi / sub rsp,20h / mov rbx,[rcx+18h]), then the rest of its loop */
static const u8 RG_EXPECTED_PUMP[0x20] = {
	0x48, 0x89, 0x5c, 0x24, 0x08, 0x57, 0x48, 0x83, 0xec, 0x20, 0x48, 0x8b, 0x59, 0x18, 0x48, 0x8b,
	0xf9, 0x48, 0x3b, 0x59, 0x10, 0x74, 0x39, 0x48, 0x8b, 0xcb, 0xe8, 0x21, 0xce, 0xd3, 0xff, 0x48,
};

/* first bytes of the two functions that get called */
static const u8 RG_EXPECTED_GET_PLAYERS[16] = {
	0x40, 0x53, 0x48, 0x83, 0xec, 0x20, 0x48, 0x8b, 0x05, 0xd3, 0x2d, 0x23, 0x04, 0x48, 0x8b, 0xda,
};
static const u8 RG_EXPECTED_SEND[16] = {
	0x48, 0x89, 0x5c, 0x24, 0x08, 0x48, 0x89, 0x6c, 0x24, 0x18, 0x48, 0x89, 0x74, 0x24, 0x20, 0x48,
};

/* ---- v3: the mission system ------------------------------------------------------------
 * Read from your game's code (campaign_research_20261111_073336.zip, game_code_dump.json,
 * RiftApart.exe 3.0630.1.0 loaded at 0x7FF6C17E0000; the dump's AddToInventoryAction handler
 * is byte-identical to RG_EXPECTED_HANDLER, so it is the same exe this helper was made for).
 *
 * Every mission action reads its "Mission" plug (hash 0x918D9104) as a NAME STRING and uses the
 * mission manager, a global object at RVA 0x68DD510:
 *   MakeMissionAvailableAction (RVA 0x19D25F0):
 *       if (!byte[0x6925FA8] && mgr && Ready(mgr) && StateByName(mgr, name, 0) == 0)
 *           { MakeA(mgr, name, 0); MakeB(mgr, name); }
 *   StartMissionAction (RVA 0x19D28C0):
 *       if (!byte[0x6925FA8] && mgr && Ready(mgr)) mgr->vtable[0x120 / 8](mgr, name, node byte +0x60);
 *   CompleteMissionAction, input "complete" (RVA 0x19D2D20, input hash 0x06EC4BB2):
 *       if (!byte[0x6925FA8] && mgr && Ready(mgr)) { Find(mgr, &i, Hash(name));
 *           if (StateByIndex(mgr, i, 0) == 3) SetState(mgr, i, 4); }
 * (with byte[0x6925FA8] set the game takes a different path through another system; this
 * helper then refuses with RG_RESULT_ALT_SYSTEM.) Hash() is the engine's string hash, the same
 * one rivet.hash returns: CRC-32 table, start value 0xEDB88320, no final xor (RVA 0x1595870;
 * checked against MIS_INTRO, MIS_RYNO_PLANS and MIS_HAX_DEFAULT in your rivet.log research).
 * The manager's table: entries at [mgr + 0x28] (0x30 bytes each, Hash at +8), count at
 * [mgr + 0x30]; states: u32 array at [[mgr + 0x688B0]] (0 = locked, Make sets 1, Complete needs
 * 3 and sets 4). The Lua side reads that table itself (read-only); this helper only makes the
 * game's own calls, one per frame, on the game thread, like the actions do. */
#define RVA_MS_MANAGER 0x68DD510u
#define RVA_MS_ALT_FLAG 0x6925FA8u
#define RVA_MAKE_HANDLER 0x19D25F0u
#define RVA_START_HANDLER 0x19D28C0u
#define RVA_COMPLETE_HANDLER 0x19D2D20u
#define RVA_MS_READY 0x19C98B0u
#define RVA_MS_STATE_BY_NAME 0x19C7750u
#define RVA_MS_MAKE_A 0x19CA530u
#define RVA_MS_MAKE_B 0x19CC7C0u
#define RVA_MS_FIND 0x19C71A0u
#define RVA_MS_STATE_BY_INDEX 0x19C75E0u
#define RVA_MS_SET_STATE 0x19CD250u
#define MS_VT_START 0x120u
#define RG_IMAGE_SPAN 0x8000000ull /* a vtable entry must point into the exe */

/* MakeMissionAvailableAction handler, RVA 0x19D25F0 */
static const u8 RG_EXPECTED_MAKE_HANDLER[0xED] = {
	0x40, 0x53, 0x48, 0x83, 0xec, 0x30, 0x80, 0x3d, 0xab, 0x39, 0xf5, 0x04, 0x00, 0x48, 0x8b, 0xd9,
	0x0f, 0x85, 0xd1, 0x00, 0x00, 0x00, 0x80, 0x3d, 0xfa, 0x3d, 0xeb, 0x04, 0x00, 0x75, 0x36, 0x48,
	0x8b, 0x49, 0x58, 0x48, 0x8d, 0x54, 0x24, 0x28, 0x41, 0xb8, 0x04, 0x91, 0x8d, 0x91, 0xe8, 0xbd,
	0xbc, 0x8e, 0xff, 0x84, 0xc0, 0x74, 0x1e, 0x4c, 0x8b, 0x44, 0x24, 0x28, 0x48, 0x8d, 0x54, 0x24,
	0x58, 0x48, 0x8b, 0x0d, 0xd8, 0xae, 0xf0, 0x04, 0xe8, 0xb3, 0x4b, 0xff, 0xff, 0x48, 0x8b, 0xc8,
	0xe8, 0x8b, 0xc8, 0xff, 0xff, 0x48, 0x8b, 0x4b, 0x58, 0x48, 0x8d, 0x54, 0x24, 0x20, 0x41, 0xb8,
	0x04, 0x91, 0x8d, 0x91, 0xe8, 0x87, 0xbc, 0x8e, 0xff, 0x84, 0xc0, 0x74, 0x7a, 0x80, 0x3d, 0xa8,
	0xae, 0xf0, 0x04, 0x00, 0x74, 0x11, 0x48, 0x8b, 0x54, 0x24, 0x20, 0x48, 0x8d, 0x0d, 0xfe, 0xb7,
	0xc1, 0x02, 0xe8, 0xb9, 0x5f, 0xbc, 0xff, 0x48, 0x8b, 0x0d, 0x92, 0xae, 0xf0, 0x04, 0x48, 0x85,
	0xc9, 0x74, 0x46, 0xe8, 0x28, 0x72, 0xff, 0xff, 0x84, 0xc0, 0x74, 0x3d, 0x48, 0x8b, 0x54, 0x24,
	0x20, 0x45, 0x33, 0xc0, 0x48, 0x8b, 0x0d, 0x75, 0xae, 0xf0, 0x04, 0xe8, 0xb0, 0x50, 0xff, 0xff,
	0x85, 0xc0, 0x75, 0x25, 0x48, 0x8b, 0x54, 0x24, 0x20, 0x45, 0x33, 0xc0, 0x48, 0x8b, 0x0d, 0x5d,
	0xae, 0xf0, 0x04, 0xe8, 0x78, 0x7e, 0xff, 0xff, 0x48, 0x8b, 0x54, 0x24, 0x20, 0x48, 0x8b, 0x0d,
	0x4c, 0xae, 0xf0, 0x04, 0xe8, 0xf7, 0xa0, 0xff, 0xff, 0x48, 0x8b, 0x4b, 0x58, 0xba, 0x50, 0x44,
	0xbf, 0x93, 0xe8, 0x39, 0xbe, 0x8e, 0xff, 0x48, 0x83, 0xc4, 0x30, 0x5b, 0xc3,
};
/* StartMissionAction handler, RVA 0x19D28C0 */
static const u8 RG_EXPECTED_START_HANDLER[0x182] = {
	0x40, 0x57, 0x48, 0x83, 0xec, 0x40, 0x80, 0x3d, 0x3a, 0x3b, 0xeb, 0x04, 0x00, 0x48, 0x8b, 0xf9,
	0x75, 0x3f, 0x80, 0x3d, 0xcf, 0x36, 0xf5, 0x04, 0x00, 0x75, 0x36, 0x48, 0x8b, 0x49, 0x58, 0x48,
	0x8d, 0x54, 0x24, 0x20, 0x41, 0xb8, 0x04, 0x91, 0x8d, 0x91, 0xe8, 0xf1, 0xb9, 0x8e, 0xff, 0x84,
	0xc0, 0x74, 0x1e, 0x4c, 0x8b, 0x44, 0x24, 0x20, 0x48, 0x8d, 0x54, 0x24, 0x50, 0x48, 0x8b, 0x0d,
	0x0c, 0xac, 0xf0, 0x04, 0xe8, 0xe7, 0x48, 0xff, 0xff, 0x48, 0x8b, 0xc8, 0xe8, 0xbf, 0xc5, 0xff,
	0xff, 0x48, 0x8b, 0x4f, 0x58, 0x48, 0x8d, 0x54, 0x24, 0x68, 0x41, 0xb8, 0x04, 0x91, 0x8d, 0x91,
	0xe8, 0xbb, 0xb9, 0x8e, 0xff, 0x84, 0xc0, 0x0f, 0x84, 0x0f, 0x01, 0x00, 0x00, 0x80, 0x3d, 0xd8,
	0xab, 0xf0, 0x04, 0x00, 0x74, 0x11, 0x48, 0x8b, 0x54, 0x24, 0x68, 0x48, 0x8d, 0x0d, 0xce, 0xb5,
	0xc1, 0x02, 0xe8, 0xe9, 0x5c, 0xbc, 0xff, 0x80, 0x3d, 0x5a, 0x36, 0xf5, 0x04, 0x00, 0x48, 0x89,
	0x5c, 0x24, 0x58, 0x0f, 0x84, 0x9d, 0x00, 0x00, 0x00, 0x48, 0x8b, 0x4f, 0x58, 0x48, 0x8d, 0x54,
	0x24, 0x50, 0x41, 0xb8, 0x04, 0x91, 0x8d, 0x91, 0xc7, 0x44, 0x24, 0x50, 0x00, 0x00, 0x00, 0x00,
	0xe8, 0xab, 0xb9, 0x8e, 0xff, 0x84, 0xc0, 0x0f, 0x84, 0xba, 0x00, 0x00, 0x00, 0x44, 0x8b, 0x44,
	0x24, 0x50, 0x48, 0x8d, 0x54, 0x24, 0x28, 0x48, 0x8b, 0x0d, 0x02, 0x7a, 0xf1, 0x04, 0xe8, 0x1d,
	0x23, 0x07, 0x00, 0x48, 0x8b, 0x0d, 0xf6, 0x79, 0xf1, 0x04, 0x48, 0x8d, 0x54, 0x24, 0x28, 0xe8,
	0xcc, 0x24, 0x07, 0x00, 0x83, 0xf8, 0x01, 0x75, 0x42, 0x48, 0x8d, 0x4c, 0x24, 0x28, 0xe8, 0xed,
	0x33, 0x7b, 0xff, 0x48, 0x85, 0xc0, 0x74, 0x7f, 0x48, 0x8b, 0x54, 0x24, 0x30, 0x48, 0x8b, 0xc8,
	0xe8, 0x8b, 0x21, 0x7b, 0xff, 0x48, 0x8b, 0xd8, 0x48, 0x85, 0xc0, 0x74, 0x6a, 0x48, 0x8b, 0x10,
	0x48, 0x8b, 0xc8, 0xff, 0x92, 0xd0, 0x00, 0x00, 0x00, 0x84, 0xc0, 0x74, 0x5a, 0x48, 0x8b, 0x13,
	0x48, 0x8b, 0xcb, 0xff, 0x92, 0xd8, 0x00, 0x00, 0x00, 0xeb, 0x3e, 0x80, 0x3d, 0xb6, 0x35, 0xf5,
	0x04, 0x00, 0x75, 0x43, 0xeb, 0x33, 0x48, 0x8b, 0x0d, 0x13, 0xab, 0xf0, 0x04, 0x48, 0x85, 0xc9,
	0x74, 0x27, 0xe8, 0xa9, 0x6e, 0xff, 0xff, 0x84, 0xc0, 0x74, 0x1e, 0x48, 0x8b, 0x0d, 0xfe, 0xaa,
	0xf0, 0x04, 0x44, 0x0f, 0xb6, 0x47, 0x60, 0x48, 0x8b, 0x54, 0x24, 0x68, 0x48, 0x8b, 0x01, 0xff,
	0x90, 0x20, 0x01, 0x00, 0x00, 0x85, 0xc0, 0x74, 0x0e, 0x48, 0x8b, 0x4f, 0x58, 0xba, 0x50, 0x44,
	0xbf, 0x93, 0xe8, 0xd9, 0xba, 0x8e, 0xff, 0x48, 0x8b, 0x5c, 0x24, 0x58, 0x48, 0x83, 0xc4, 0x40,
	0x5f, 0xc3,
};
/* CompleteMissionAction handler, RVA 0x19D2D20 */
static const u8 RG_EXPECTED_COMPLETE_HANDLER[0x1E6] = {
	0x40, 0x55, 0x53, 0x57, 0x48, 0x8d, 0x6c, 0x24, 0xb9, 0x48, 0x81, 0xec, 0x90, 0x00, 0x00, 0x00,
	0x80, 0x3d, 0xd0, 0x36, 0xeb, 0x04, 0x00, 0x8b, 0xfa, 0x48, 0x8b, 0xd9, 0x75, 0x3c, 0x80, 0x3d,
	0x63, 0x32, 0xf5, 0x04, 0x00, 0x75, 0x33, 0x48, 0x8b, 0x49, 0x58, 0x48, 0x8d, 0x55, 0x07, 0x41,
	0xb8, 0x04, 0x91, 0x8d, 0x91, 0xe8, 0x86, 0xb5, 0x8e, 0xff, 0x84, 0xc0, 0x74, 0x1c, 0x4c, 0x8b,
	0x45, 0x07, 0x48, 0x8d, 0x55, 0x67, 0x48, 0x8b, 0x0d, 0xa3, 0xa7, 0xf0, 0x04, 0xe8, 0x7e, 0x44,
	0xff, 0xff, 0x48, 0x8b, 0xc8, 0xe8, 0x56, 0xc1, 0xff, 0xff, 0x48, 0x8b, 0x4b, 0x58, 0x48, 0x8d,
	0x55, 0x7f, 0x41, 0xb8, 0x04, 0x91, 0x8d, 0x91, 0xe8, 0x53, 0xb5, 0x8e, 0xff, 0x84, 0xc0, 0x0f,
	0x84, 0xa2, 0x02, 0x00, 0x00, 0x48, 0x8b, 0x4b, 0x58, 0x48, 0x8d, 0x53, 0x64, 0x41, 0xb8, 0x04,
	0x91, 0x8d, 0x91, 0x48, 0x89, 0xb4, 0x24, 0xb8, 0x00, 0x00, 0x00, 0xe8, 0x70, 0xb5, 0x8e, 0xff,
	0x80, 0x3d, 0x55, 0xa7, 0xf0, 0x04, 0x00, 0x74, 0x10, 0x48, 0x8b, 0x55, 0x7f, 0x48, 0x8d, 0x0d,
	0xec, 0xb1, 0xc1, 0x02, 0xe8, 0x67, 0x58, 0xbc, 0xff, 0x80, 0x3d, 0xd8, 0x31, 0xf5, 0x04, 0x00,
	0x0f, 0x84, 0xc4, 0x00, 0x00, 0x00, 0x81, 0xff, 0xdb, 0xa7, 0x8a, 0xde, 0x0f, 0x84, 0xa5, 0x00,
	0x00, 0x00, 0x44, 0x8b, 0x43, 0x64, 0x48, 0x8d, 0x55, 0x0f, 0x48, 0x8b, 0x0d, 0x9f, 0x75, 0xf1,
	0x04, 0xe8, 0xba, 0x1e, 0x07, 0x00, 0x81, 0xff, 0xb2, 0x4b, 0xec, 0x06, 0x75, 0x51, 0x48, 0x8b,
	0x0d, 0x8b, 0x75, 0xf1, 0x04, 0x48, 0x8d, 0x55, 0x0f, 0xe8, 0x62, 0x20, 0x07, 0x00, 0x83, 0xf8,
	0x03, 0x0f, 0x85, 0x0a, 0x02, 0x00, 0x00, 0x48, 0x8d, 0x4d, 0x0f, 0xe8, 0x80, 0x2f, 0x7b, 0xff,
	0x48, 0x85, 0xc0, 0x0f, 0x84, 0xf8, 0x01, 0x00, 0x00, 0x48, 0x8b, 0x55, 0x17, 0x48, 0x8b, 0xc8,
	0xe8, 0x1b, 0x1d, 0x7b, 0xff, 0x48, 0x85, 0xc0, 0x0f, 0x84, 0xe3, 0x01, 0x00, 0x00, 0x48, 0x8b,
	0x10, 0x48, 0x8b, 0xc8, 0xff, 0x92, 0xf0, 0x00, 0x00, 0x00, 0xe9, 0xd2, 0x01, 0x00, 0x00, 0x48,
	0x8d, 0x4d, 0x0f, 0xe8, 0x48, 0x2f, 0x7b, 0xff, 0x48, 0x85, 0xc0, 0x74, 0x22, 0x48, 0x8b, 0x55,
	0x17, 0x48, 0x8b, 0xc8, 0xe8, 0xe7, 0x1c, 0x7b, 0xff, 0x48, 0x85, 0xc0, 0x74, 0x11, 0x4c, 0x8b,
	0x00, 0x48, 0x8b, 0xc8, 0x0f, 0xb6, 0x53, 0x60, 0x41, 0xff, 0x90, 0xe8, 0x00, 0x00, 0x00, 0x85,
	0xff, 0x0f, 0x85, 0x9a, 0x01, 0x00, 0x00, 0x48, 0x8b, 0x4b, 0x58, 0xba, 0xc8, 0xf3, 0x6d, 0xca,
	0xe8, 0x7b, 0xb6, 0x8e, 0xff, 0xe9, 0x87, 0x01, 0x00, 0x00, 0x48, 0x8b, 0x0d, 0x6f, 0xa6, 0xf0,
	0x04, 0x48, 0x85, 0xc9, 0x0f, 0x84, 0x77, 0x01, 0x00, 0x00, 0xe8, 0x01, 0x6a, 0xff, 0xff, 0x84,
	0xc0, 0x0f, 0x84, 0x6a, 0x01, 0x00, 0x00, 0x81, 0xff, 0xb2, 0x4b, 0xec, 0x06, 0x75, 0x47, 0x44,
	0x8b, 0x43, 0x64, 0x48, 0x8d, 0x55, 0x67, 0x48, 0x8b, 0x0d, 0x42, 0xa6, 0xf0, 0x04, 0xe8, 0xcd,
	0x42, 0xff, 0xff, 0x8b, 0x55, 0x67, 0x45, 0x33, 0xc0, 0x48, 0x8b, 0x0d, 0x30, 0xa6, 0xf0, 0x04,
	0xe8, 0xfb, 0x46, 0xff, 0xff, 0x83, 0xf8, 0x03, 0x0f, 0x85, 0x33, 0x01, 0x00, 0x00, 0x8b, 0x55,
	0x67, 0x44, 0x8d, 0x40, 0x01, 0x48, 0x8b, 0x0d, 0x14, 0xa6, 0xf0, 0x04, 0xe8, 0x4f, 0xa3, 0xff,
	0xff, 0xe9, 0x1b, 0x01, 0x00, 0x00,
};
/* RVA 0x19C98B0 */
static const u8 RG_EXPECTED_MS_READY[0x10] = {
	0xe9, 0x8b, 0x6e, 0xf5, 0xff, 0xcc, 0xcc, 0xcc, 0xcc, 0xcc, 0xcc, 0xcc, 0xcc, 0xcc, 0xcc, 0xcc,
};
/* RVA 0x19C7750 */
static const u8 RG_EXPECTED_MS_STATE_BY_NAME[0x10] = {
	0x48, 0x89, 0x5c, 0x24, 0x10, 0x48, 0x89, 0x6c, 0x24, 0x18, 0x48, 0x89, 0x7c, 0x24, 0x20, 0x41,
};
/* RVA 0x19CA530 */
static const u8 RG_EXPECTED_MS_MAKE_A[0x10] = {
	0x40, 0x55, 0x56, 0x41, 0x57, 0x48, 0x81, 0xec, 0xd0, 0x04, 0x00, 0x00, 0x45, 0x0f, 0xb6, 0xf8,
};
/* RVA 0x19CC7C0 */
static const u8 RG_EXPECTED_MS_MAKE_B[0x10] = {
	0x48, 0x89, 0x74, 0x24, 0x10, 0x57, 0x48, 0x81, 0xec, 0x60, 0x04, 0x00, 0x00, 0x48, 0x8b, 0xf2,
};
/* RVA 0x19C71A0 */
static const u8 RG_EXPECTED_MS_FIND[0x10] = {
	0x4c, 0x8b, 0x59, 0x28, 0x4d, 0x85, 0xdb, 0x74, 0x2b, 0x48, 0x63, 0x41, 0x30, 0x45, 0x33, 0xc9,
};
/* RVA 0x19C75E0 */
static const u8 RG_EXPECTED_MS_STATE_BY_INDEX[0x10] = {
	0x40, 0x53, 0x57, 0x41, 0x56, 0x48, 0x83, 0xec, 0x20, 0x48, 0x63, 0xfa, 0x41, 0x0f, 0xb6, 0xd8,
};
/* RVA 0x19CD250 */
static const u8 RG_EXPECTED_MS_SET_STATE[0x10] = {
	0x48, 0x89, 0x5c, 0x24, 0x08, 0x48, 0x89, 0x74, 0x24, 0x10, 0x57, 0x48, 0x83, 0xec, 0x20, 0x41,
};


/* ---- v4: system 2, the one your game runs (round 15) ----------------------------------------
 * Round 15: the global above (RVA 0x68DD510) is NULL in your game and the byte at 0x6925FA8 is
 * set, so every mission action takes its OTHER branch. That branch (the same code in
 * StartMissionAction, SetMissionActiveAction, CompleteMissionAction, ReplayMissionAction):
 *   mgr2 = *(RVA 0x68EA390); h = Lookup(mgr2, &h, Hash(name))         ; RVA 0x1A44CB0
 *   state = State(mgr2, &h)                                             ; RVA 0x1A44E70
 *   obj = Component(Resolve(&h), h.component)                           ; RVA 0x1185DA0, 0x1184B50
 *   start:    if (state == 1 && obj->vt[0xD0](obj)) obj->vt[0xD8](obj)
 *   complete: if (state == 3) obj->vt[0xF0](obj)
 *   replay:   obj->vt[0x108](obj, node byte +0x60, 1)
 *   make available: nothing at all (the handler returns at once)
 * Missions are components on level actors; availability is the game's own business. */
#define RVA_MS2_MANAGER 0x68EA390u
#define RVA_SET_ACTIVE_HANDLER 0x1A3E100u
#define RVA_REPLAY_HANDLER 0x1A3F520u
#define RVA_MS2_LOOKUP 0x1A44CB0u
#define RVA_MS2_STATE 0x1A44E70u
#define RVA_MS2_RESOLVE 0x1185DA0u
#define RVA_MS2_COMPONENT 0x1184B50u
#define MS2_VT_CAN_START 0xD0u
#define MS2_VT_START 0xD8u
#define MS2_VT_COMPLETE 0xF0u
#define MS2_VT_REPLAY 0x108u

/* SetMissionActiveAction handler, RVA 0x1A3E100 (system 2's start, the same as StartMissionAction's) */
static const u8 RG_EXPECTED_SET_ACTIVE_HANDLER[0xDD] = {
	0x48, 0x89, 0x5c, 0x24, 0x10, 0x57, 0x48, 0x83, 0xec, 0x40, 0x48, 0x8b, 0xf9, 0x48, 0x8d, 0x54,
	0x24, 0x50, 0x48, 0x8b, 0x49, 0x58, 0x33, 0xdb, 0x41, 0xb8, 0x60, 0x0e, 0xc3, 0xa5, 0x89, 0x5c,
	0x24, 0x50, 0xe8, 0xf9, 0x01, 0x88, 0xff, 0x84, 0xc0, 0x0f, 0x84, 0x95, 0x00, 0x00, 0x00, 0x44,
	0x8b, 0x44, 0x24, 0x50, 0x45, 0x85, 0xc0, 0x0f, 0x84, 0x87, 0x00, 0x00, 0x00, 0x48, 0x8b, 0x0d,
	0x4c, 0xc2, 0xea, 0x04, 0x48, 0x85, 0xc9, 0x74, 0x7b, 0x48, 0x8d, 0x54, 0x24, 0x20, 0xe8, 0x5d,
	0x6b, 0x00, 0x00, 0x48, 0x8b, 0x0d, 0x36, 0xc2, 0xea, 0x04, 0x48, 0x8d, 0x54, 0x24, 0x20, 0xe8,
	0x0c, 0x6d, 0x00, 0x00, 0x83, 0xf8, 0x01, 0x75, 0x42, 0x48, 0x8d, 0x4c, 0x24, 0x20, 0xe8, 0x2d,
	0x7c, 0x74, 0xff, 0x48, 0x85, 0xc0, 0x74, 0x5a, 0x48, 0x8b, 0x54, 0x24, 0x28, 0x48, 0x8b, 0xc8,
	0xe8, 0xcb, 0x69, 0x74, 0xff, 0x48, 0x8b, 0xd8, 0x48, 0x85, 0xc0, 0x74, 0x45, 0x48, 0x8b, 0x10,
	0x48, 0x8b, 0xc8, 0xff, 0x92, 0xd0, 0x00, 0x00, 0x00, 0x84, 0xc0, 0x74, 0x35, 0x48, 0x8b, 0x13,
	0x48, 0x8b, 0xcb, 0xff, 0x92, 0xd8, 0x00, 0x00, 0x00, 0xeb, 0x19, 0x48, 0x8b, 0x4f, 0x58, 0x48,
	0x8d, 0x54, 0x24, 0x68, 0x41, 0xb8, 0x60, 0x0e, 0xc3, 0xa5, 0x48, 0x89, 0x5c, 0x24, 0x68, 0xe8,
	0x1c, 0x01, 0x88, 0xff, 0x48, 0x8b, 0x4f, 0x58, 0xba, 0xf6, 0x63, 0x1c, 0x4b, 0xe8, 0x3e, 0x03,
	0x88, 0xff, 0x48, 0x8b, 0x5c, 0x24, 0x58, 0x48, 0x83, 0xc4, 0x40, 0x5f, 0xc3,
};
/* ReplayMissionAction handler, RVA 0x1A3F520 */
static const u8 RG_EXPECTED_REPLAY_HANDLER[0xB3] = {
	0x40, 0x53, 0x48, 0x83, 0xec, 0x40, 0x48, 0x8b, 0xd9, 0xc7, 0x44, 0x24, 0x50, 0x00, 0x00, 0x00,
	0x00, 0x48, 0x8b, 0x49, 0x58, 0x48, 0x8d, 0x54, 0x24, 0x50, 0x41, 0xb8, 0x60, 0x0e, 0xc3, 0xa5,
	0xe8, 0xdb, 0xed, 0x87, 0xff, 0x84, 0xc0, 0x74, 0x76, 0x44, 0x8b, 0x44, 0x24, 0x50, 0x45, 0x85,
	0xc0, 0x74, 0x6c, 0x48, 0x8b, 0x0d, 0x36, 0xae, 0xea, 0x04, 0x48, 0x85, 0xc9, 0x74, 0x60, 0x48,
	0x8d, 0x54, 0x24, 0x20, 0xe8, 0x47, 0x57, 0x00, 0x00, 0x48, 0x8d, 0x4c, 0x24, 0x20, 0xe8, 0x2d,
	0x68, 0x74, 0xff, 0x48, 0x85, 0xc0, 0x74, 0x47, 0x48, 0x8b, 0x54, 0x24, 0x28, 0x48, 0x8b, 0xc8,
	0xe8, 0xcb, 0x55, 0x74, 0xff, 0x48, 0x85, 0xc0, 0x74, 0x35, 0x4c, 0x8b, 0x08, 0x41, 0xb0, 0x01,
	0x0f, 0xb6, 0x53, 0x60, 0x48, 0x8b, 0xc8, 0x41, 0xff, 0x91, 0x08, 0x01, 0x00, 0x00, 0x84, 0xc0,
	0x75, 0x1d, 0x48, 0x8b, 0x4b, 0x58, 0x48, 0x8d, 0x54, 0x24, 0x68, 0x41, 0xb8, 0x60, 0x0e, 0xc3,
	0xa5, 0x48, 0xc7, 0x44, 0x24, 0x68, 0x00, 0x00, 0x00, 0x00, 0xe8, 0x21, 0xed, 0x87, 0xff, 0x48,
	0x8b, 0x4b, 0x58, 0xba, 0xd1, 0xb7, 0x38, 0x22, 0xe8, 0x43, 0xef, 0x87, 0xff, 0x48, 0x83, 0xc4,
	0x40, 0x5b, 0xc3,
};
/* RVA 0x1A44CB0 */
static const u8 RG_EXPECTED_MS2_LOOKUP[0x10] = {
	0x48, 0x89, 0x5c, 0x24, 0x08, 0x48, 0x89, 0x74, 0x24, 0x10, 0x57, 0x48, 0x83, 0xec, 0x20, 0x33,
};
/* RVA 0x1A44E70 */
static const u8 RG_EXPECTED_MS2_STATE[0x10] = {
	0x48, 0x89, 0x5c, 0x24, 0x10, 0x56, 0x48, 0x83, 0xec, 0x20, 0x48, 0x8b, 0xf1, 0x48, 0x8b, 0xda,
};
/* RVA 0x1185DA0 */
static const u8 RG_EXPECTED_MS2_RESOLVE[0x10] = {
	0x8b, 0x11, 0x44, 0x8b, 0xc2, 0x41, 0xc1, 0xe8, 0x14, 0x48, 0x8d, 0x0d, 0xd0, 0xe8, 0x19, 0x04,
};
/* RVA 0x1184B50 */
static const u8 RG_EXPECTED_MS2_COMPONENT[0x10] = {
	0x48, 0x83, 0xec, 0x28, 0x48, 0x83, 0xc1, 0x48, 0xe8, 0xd3, 0x82, 0x42, 0x00, 0x48, 0x85, 0xc0,
};

/* ---- v6 (Randomizer 8.0): the hub campaign's experimental levers ----------------------------
 * 1. A mission's saved state. State() (RVA 0x1A44E70, both dumps byte-identical over 0x91 bytes)
 *    reads it like this:
 *        id  = obj->vt[0x38](obj)                      ; obj = Component(Resolve(&h), h.component)
 *        key = *(u64 *)(**(u8 ***)(obj + 8) + 8)
 *        t   = TableFind(mgr2 + 0x1B0, key)            ; RVA 0x1BDAFD0 (rel32 call inside State)
 *        e   = EntryFind(t, id)                        ; RVA 0x1BDB000 (rel32 call inside State)
 *        state = *(u32 *)(*(u8 **)(e + 0x28) + 0x30)
 *    The helper walks the same way (every byte of that path is checked, the two calls are pinned
 *    by their rel32 operands) and, for RG_KIND_MISSION_SET_STATE, writes MB_FLAG there. It only
 *    writes when its walk reads exactly what the game's State() returns. Whether the mission
 *    system ACTS on such a write (loads the mission's overlays, lets it start) is unknown: it is
 *    the 8.0 experiment ("force available"). The record looks like MissionSaveDataShared
 *    (MissionState: 0 Inactive, 1 Available, 2 Active, 3 Complete Cleaning, 4 Complete Finished,
 *    5 Failed - the DDL enum; the event MissionStateChangedEvent reports the same numbers).
 * 2. The level mask. UnlockLevelAction (handler RVA 0x89DA00) takes a level 1..10 and calls
 *    SetBit(&g_levels /RVA 0x5161238/, level, on) (RVA 0x89C1E0): bit `level` of the u32 at
 *    +0x30. IsLevelUnlockedAction tests that bit (RVA 0x89C140). What the bits mean (the ship's
 *    planet menu?) is unknown; 8.0 reads them on every planet change and logs them.
 * 3. Planetary travel. SetPlanetaryTravelAction (RVA 0x607500) stores one byte at RVA 0x5FFD3C0.
 */
#define RVA_MS2_TABLE_FIND 0x1BDAFD0u
#define RVA_MS2_ENTRY_FIND 0x1BDB000u
#define MS2_VT_NODE_ID 0x38u
#define MS2_SAVE_TABLE 0x1B0u
#define MS2_ENTRY_RECORD 0x28u
#define MS2_RECORD_STATE 0x30u
#define RG_MISSION_STATE_MAX 5u
#define RVA_LEVEL_SET_BIT 0x89C1E0u
#define RVA_IS_LEVEL_UNLOCKED 0x89C140u
#define RVA_UNLOCK_LEVEL_HANDLER 0x89DA00u
#define RVA_LEVELS_GLOBAL 0x5161238u
#define LEVELS_UNLOCKED 0x30u
#define LEVELS_OTHER 0x2Cu
#define LEVELS_CURRENT 0x20u
#define RVA_PLANETARY_TRAVEL_HANDLER 0x607500u
#define RVA_PLANETARY_TRAVEL_BYTE 0x5FFD3C0u

/* RVA 0x1A44E70: State(), up to and including the read of the state (both dumps) */
static const u8 RG_EXPECTED_MS2_STATE_WALK[0x91] = {
	0x48, 0x89, 0x5c, 0x24, 0x10, 0x56, 0x48, 0x83, 0xec, 0x20, 0x48, 0x8b, 0xf1, 0x48, 0x8b, 0xda,
	0x48, 0x8b, 0xca, 0xe8, 0x18, 0x0f, 0x74, 0xff, 0x48, 0x85, 0xc0, 0x0f, 0x84, 0x8d, 0x00, 0x00,
	0x00, 0x48, 0x8b, 0x53, 0x08, 0x48, 0x8b, 0xc8, 0xe8, 0xb3, 0xfc, 0x73, 0xff, 0x48, 0x8b, 0xd0,
	0x48, 0x85, 0xc0, 0x74, 0x79, 0x48, 0x8b, 0x40, 0x08, 0x48, 0x89, 0x7c, 0x24, 0x30, 0x48, 0x8b,
	0x08, 0x48, 0x8b, 0x02, 0x48, 0x8b, 0x59, 0x08, 0x48, 0x8b, 0xca, 0xff, 0x50, 0x38, 0x48, 0x8b,
	0xd3, 0x48, 0x8d, 0x8e, 0xb0, 0x01, 0x00, 0x00, 0x8b, 0xf8, 0x48, 0xb8, 0x00, 0x00, 0x00, 0x00,
	0xff, 0xff, 0xff, 0xff, 0x48, 0x23, 0xd0, 0x8b, 0xc3, 0x48, 0x0b, 0xd0, 0xe8, 0xef, 0x60, 0x19,
	0x00, 0x48, 0x85, 0xc0, 0x74, 0x26, 0x8b, 0xd7, 0x48, 0x8b, 0xc8, 0xe8, 0x10, 0x61, 0x19, 0x00,
	0x48, 0x85, 0xc0, 0x74, 0x17, 0x48, 0x8b, 0x40, 0x28, 0x48, 0x8b, 0x7c, 0x24, 0x30, 0x8b, 0x40,
	0x30,
};
/* RVA 0x89C1E0: SetBit(levels, level, on) */
static const u8 RG_EXPECTED_LEVEL_SET[0x25] = {
	0x4c, 0x8b, 0xc9, 0xb8, 0x01, 0x00, 0x00, 0x00, 0x8b, 0xca, 0xd3, 0xe0, 0x41, 0x8b, 0x51, 0x30,
	0x45, 0x84, 0xc0, 0x74, 0x07, 0x0b, 0xd0, 0x41, 0x89, 0x51, 0x30, 0xc3, 0xf7, 0xd0, 0x23, 0xc2,
	0x41, 0x89, 0x41, 0x30, 0xc3,
};
/* RVA 0x89C140: IsLevelUnlocked(levels, level) */
static const u8 RG_EXPECTED_IS_LEVEL_UNLOCKED[0xA] = {
	0x8b, 0x41, 0x30, 0x0f, 0xa3, 0xd0, 0x0f, 0x92, 0xc0, 0xc3,
};
/* RVA 0x89DA00: UnlockLevelAction's handler (its two lea operands name RVA 0x5161238) */
static const u8 RG_EXPECTED_UNLOCK_LEVEL_HANDLER[0xCC] = {
	0x48, 0x89, 0x5c, 0x24, 0x10, 0x57, 0x48, 0x83, 0xec, 0x20, 0x8b, 0xfa, 0x48, 0x8b, 0xd9, 0x48,
	0x8b, 0x49, 0x58, 0x48, 0x8d, 0x54, 0x24, 0x30, 0x41, 0xb8, 0xe1, 0x55, 0x04, 0xe3, 0xe8, 0xdd,
	0x07, 0xa2, 0x00, 0x84, 0xc0, 0x74, 0x3e, 0xf3, 0x0f, 0x10, 0x4c, 0x24, 0x30, 0xf3, 0x44, 0x0f,
	0x2c, 0xc1, 0x41, 0x81, 0xf8, 0x00, 0x00, 0x00, 0x80, 0x74, 0x21, 0x66, 0x41, 0x0f, 0x6e, 0xc0,
	0x0f, 0x5b, 0xc0, 0x0f, 0x2e, 0xc1, 0x74, 0x14, 0x0f, 0x14, 0xc9, 0x0f, 0x50, 0xc1, 0x83, 0xe0,
	0x01, 0x44, 0x2b, 0xc0, 0x66, 0x41, 0x0f, 0x6e, 0xc8, 0x0f, 0x5b, 0xc9, 0xf3, 0x0f, 0x2c, 0xd1,
	0x89, 0x53, 0x60, 0xeb, 0x03, 0x8b, 0x53, 0x60, 0x8d, 0x42, 0xff, 0x83, 0xf8, 0x09, 0x77, 0x43,
	0x81, 0xff, 0x88, 0xfe, 0x9c, 0x54, 0x74, 0x1e, 0x81, 0xff, 0xbe, 0x5b, 0x1f, 0xb7, 0x75, 0x33,
	0x45, 0x33, 0xc0, 0x48, 0x8d, 0x0d, 0xae, 0x37, 0x8c, 0x04, 0xe8, 0x51, 0xe7, 0xff, 0xff, 0xba,
	0x4b, 0x70, 0xe3, 0x56, 0xeb, 0x14, 0x41, 0xb0, 0x01, 0x48, 0x8d, 0x0d, 0x98, 0x37, 0x8c, 0x04,
	0xe8, 0x3b, 0xe7, 0xff, 0xff, 0xba, 0xcc, 0xf3, 0xeb, 0x91, 0x48, 0x8b, 0x4b, 0x58, 0xe8, 0x5d,
	0x0a, 0xa2, 0x00, 0x48, 0x8b, 0x4b, 0x58, 0xba, 0x50, 0x44, 0xbf, 0x93, 0xe8, 0x4f, 0x0a, 0xa2,
	0x00, 0x48, 0x8b, 0x5c, 0x24, 0x38, 0x48, 0x83, 0xc4, 0x20, 0x5f, 0xc3,
};
/* RVA 0x607500: SetPlanetaryTravelAction's handler (its byte operands name RVA 0x5FFD3C0) */
static const u8 RG_EXPECTED_PLANETARY_TRAVEL_HANDLER[0x4B] = {
	0x40, 0x53, 0x48, 0x83, 0xec, 0x20, 0x48, 0x8b, 0xd9, 0x48, 0x8d, 0x54, 0x24, 0x30, 0x48, 0x8b,
	0x49, 0x58, 0x41, 0xb8, 0xf5, 0x94, 0x24, 0x04, 0xe8, 0x43, 0x6a, 0xcb, 0x00, 0x44, 0x0f, 0xb6,
	0x05, 0x9b, 0x5e, 0x9f, 0x05, 0x84, 0xc0, 0x0f, 0xb6, 0x54, 0x24, 0x30, 0x44, 0x0f, 0x45, 0xc2,
	0xba, 0x5e, 0xe1, 0xf2, 0x3e, 0x44, 0x88, 0x05, 0x84, 0x5e, 0x9f, 0x05, 0x48, 0x8b, 0x4b, 0x58,
	0xe8, 0xcb, 0x6f, 0xcb, 0x00, 0x48, 0x83, 0xc4, 0x20, 0x5b, 0xc3,
};
typedef u32 (*rg_ms2_node_id_fn)(void *obj);
typedef void *(*rg_ms2_table_find_fn)(void *table, u64 key);
typedef void *(*rg_ms2_entry_find_fn)(void *table, u32 id);
typedef void (*rg_level_set_fn)(void *levels, u32 level, u8 on);

/* ---- v5: armor (round 16) ----------------------------------------------------------------
 * VanityGiveBundleAction's handler (RVA 0x880720, both code dumps, byte-identical):
 *     actor = ResolveHandle(&g_hero_handle /RVA 0x6003E88/)                ; RVA 0xF1A520
 *     mgr   = actor->word[0x88] > 0 ? FindComponentA(actor + 0x80, &VanityInventoryManager)
 *                                   : FindComponentB(actor + 0x58, &VanityInventoryManager)
 *                                     ; RVA 0xFFB860 / 0xFFCA00, type info at RVA 0x6032570
 *     ok    = GiveBundle(mgr, node->bundle /+0x60/, 0)                       ; RVA 0x87B4C0
 *     fire output ok ? 0xCD6C8C3D : 0x329EA4F1
 * The helper makes the same three calls with the bundle from the mailbox (MB_ITEM) and reports
 * GiveBundle's answer in MB_RET (1 = the piece was added). The Lua side asks rivet.vanity_owns
 * first, which also proves the bundle's config is loaded (rivet_hook's own check). */
#define RVA_VANITY_GIVE_HANDLER 0x880720u
#define RVA_RESOLVE_HANDLE 0xF1A520u
#define RVA_FIND_COMPONENT_A 0xFFB860u
#define RVA_FIND_COMPONENT_B 0xFFCA00u
#define RVA_VANITY_GIVE_BUNDLE 0x87B4C0u
#define RVA_HERO_HANDLE 0x6003E88u
#define RVA_VANITY_MANAGER_TYPE 0x6032570u

static const u8 RG_EXPECTED_VANITY_GIVE_HANDLER[0x72] = {
	0x40, 0x53, 0x48, 0x83, 0xec, 0x20, 0x48, 0x8b, 0xd9, 0x48, 0x8d, 0x0d, 0x58, 0x37, 0x78, 0x05,
	0xe8, 0xeb, 0x9d, 0x69, 0x00, 0x48, 0x85, 0xc0, 0x74, 0x45, 0x66, 0x83, 0xb8, 0x88, 0x00, 0x00,
	0x00, 0x00, 0x48, 0x8d, 0x15, 0x27, 0x1e, 0x7b, 0x05, 0x76, 0x0e, 0x48, 0x8d, 0x88, 0x80, 0x00,
	0x00, 0x00, 0xe8, 0x09, 0xb1, 0x77, 0x00, 0xeb, 0x09, 0x48, 0x8d, 0x48, 0x58, 0xe8, 0x9e, 0xc2,
	0x77, 0x00, 0x48, 0x85, 0xc0, 0x74, 0x18, 0x48, 0x8b, 0x53, 0x60, 0x45, 0x33, 0xc0, 0x48, 0x8b,
	0xc8, 0xe8, 0x4a, 0xad, 0xff, 0xff, 0xba, 0x3d, 0x8c, 0x6c, 0xcd, 0x84, 0xc0, 0x75, 0x05, 0xba,
	0xf1, 0xa4, 0x9e, 0x32, 0x48, 0x8b, 0x4b, 0x58, 0x48, 0x83, 0xc4, 0x20, 0x5b, 0xe9, 0x7e, 0xdd,
	0xa3, 0x00,
};
/* RVA 0xF1A520 */
static const u8 RG_EXPECTED_RESOLVE_HANDLE[0x10] = {
	0x44, 0x8b, 0x01, 0x41, 0x8b, 0xd0, 0xc1, 0xea, 0x14, 0x81, 0xe2, 0xff, 0x07, 0x00, 0x00, 0x74,
};
/* RVA 0xFFB860 */
static const u8 RG_EXPECTED_FIND_COMPONENT_A[0x10] = {
	0x44, 0x0f, 0xb7, 0x49, 0x08, 0x4c, 0x8b, 0xc2, 0x4c, 0x8b, 0x11, 0x41, 0xff, 0xc9, 0x49, 0xc1,
};
/* RVA 0xFFCA00 */
static const u8 RG_EXPECTED_FIND_COMPONENT_B[0x10] = {
	0x48, 0x89, 0x5c, 0x24, 0x08, 0x57, 0x48, 0x83, 0xec, 0x20, 0x48, 0x8b, 0xda, 0x48, 0x8b, 0xf9,
};
/* RVA 0x87B4C0 */
static const u8 RG_EXPECTED_VANITY_GIVE_BUNDLE[0x10] = {
	0x44, 0x88, 0x44, 0x24, 0x18, 0x48, 0x89, 0x54, 0x24, 0x10, 0x53, 0x55, 0x56, 0x57, 0x41, 0x54,
};

/* the function every script action tail-calls to fire an output plug (RVA 0x12BE510): it uses
 * rcx (the node's script context, node + 0x58) and edx (the plug hash) only, returns a bool */
#define RVA_FIRE_OUTPUT 0x12BE510u
#define RG_PLUG_SUCCESS 0xCD6C8C3Du
#define RG_PLUG_FAILURE 0x329EA4F1u
static const u8 RG_EXPECTED_FIRE_OUTPUT[0x10] = {
	0x40, 0x55, 0x56, 0x41, 0x57, 0x48, 0x83, 0xec, 0x30, 0x48, 0x8b, 0xf1, 0x8b, 0xea, 0x48, 0x83,
};
typedef u8 (*rg_fire_fn)(void *context, u32 plug);

/* v5 configs: rivet_hook finds the game's config asset manager through VanityInventory::HasBundle
 * (rivet_hook src/signature.hpp VANITY_HAS_BUNDLE, rel32 at +0x22; src/configs.cpp for the
 * layout below). The helper finds it the same way, and only reads it. */
static const u8 RG_CONFIG_SIGNATURE[26] = {
	0x40, 0x55, 0x56, 0x41, 0x56, 0x41, 0x57, 0x48, 0x83, 0xEC, 0x28, 0x41, 0x8B, 0xF0, 0x4C, 0x8B,
	0xF1, 0x41, 0x83, 0xF8, 0x04, 0x75, 0x03, 0x8B, 0x71, 0x48,
};
#define RG_CONFIG_REL 0x22u
#define CFG_ENTRIES 0x40u /* entry array */
#define CFG_STRIDE 0x48u  /* u64 bytes per entry */
#define CFG_MAX 0x68u     /* i32 entries allocated */
#define CFG_ENTRY_STATE 0x0u
#define CFG_ENTRY_ID 0x8u
#define CFG_ENTRY_OBJECT 0x30u
#define CFG_STATE_LOADED 4u

typedef void *(*rg_resolve_handle_fn)(const u32 *handle);
typedef void *(*rg_find_component_fn)(void *list, const void *type);
typedef u8 (*rg_vanity_give_fn)(void *manager, u64 bundle, u8 flag);

typedef struct {
	u32 handle;
	u32 pad0;
	u64 component;
	u32 hash;
	u32 pad1;
} rg_ms2_handle;
typedef void *(*rg_ms2_lookup_fn)(void *mgr, rg_ms2_handle *out, u32 hash);
typedef u32 (*rg_ms2_state_fn)(void *mgr, rg_ms2_handle *h);
typedef void *(*rg_ms2_resolve_fn)(rg_ms2_handle *h);
typedef void *(*rg_ms2_component_fn)(void *entity, u64 component);
typedef u8 (*rg_ms2_can_start_fn)(void *obj);
typedef void (*rg_ms2_act_fn)(void *obj);
typedef u8 (*rg_ms2_replay_fn)(void *obj, u8 flag, u8 one);

typedef u8 (*rg_ms_ready_fn)(void *mgr);
typedef u32 (*rg_ms_state_by_name_fn)(void *mgr, const char *name, u8 flag);
typedef void (*rg_ms_make_a_fn)(void *mgr, const char *name, u8 flag);
typedef void (*rg_ms_make_b_fn)(void *mgr, const char *name);
typedef int *(*rg_ms_find_fn)(void *mgr, int *out, u32 hash);
typedef u32 (*rg_ms_state_by_index_fn)(void *mgr, int index, u8 flag);
typedef void (*rg_ms_set_state_fn)(void *mgr, int index, u32 state);
typedef int (*rg_ms_start_fn)(void *mgr, const char *name, u8 flag);

typedef struct {
	void *ptr;
	u32 count;
	u32 pad;
} rg_actor_list;

typedef void *(*rg_get_players_fn)(void *players, rg_actor_list *out, u32 index);
typedef void (*rg_send_fn)(u32 mode, u64 message, void *targets, u32 count, void *payload, u32 size);

typedef struct {
	u8 *base;              /* exe load address */
	volatile u8 *mailbox;  /* the shared page */
	rg_get_players_fn get_players;
	rg_send_fn send;
	void *players;
	u64 *message;
	/* v3 */
	int missions_ok;
	void **ms_manager;
	volatile u8 *ms_alt_flag;
	rg_ms_ready_fn ms_ready;
	rg_ms_state_by_name_fn ms_state_by_name;
	rg_ms_make_a_fn ms_make_a;
	rg_ms_make_b_fn ms_make_b;
	rg_ms_find_fn ms_find;
	rg_ms_state_by_index_fn ms_state_by_index;
	rg_ms_set_state_fn ms_set_state;
	/* v4, system 2 */
	void **ms2_manager;
	rg_ms2_lookup_fn ms2_lookup;
	rg_ms2_state_fn ms2_state;
	rg_ms2_resolve_fn ms2_resolve;
	rg_ms2_component_fn ms2_component;
	/* v5, armor */
	int vanity_ok;
	rg_resolve_handle_fn resolve_handle;
	rg_find_component_fn find_component_a;
	rg_find_component_fn find_component_b;
	rg_vanity_give_fn vanity_give;
	rg_fire_fn fire;
	/* v5, configs */
	u8 *config_mgr;
	/* v6 */
	int state_ok;
	rg_ms2_table_find_fn ms2_table_find;
	rg_ms2_entry_find_fn ms2_entry_find;
	int levels_ok;
	rg_level_set_fn level_set;
	u8 *levels;
	int travel_ok;
	volatile u8 *travel_byte;
} rg_state;

static int rg_bytes_equal(const u8 *a, const u8 *b, u32 n) {
	for (u32 i = 0; i < n; ++i) {
		if (a[i] != b[i]) {
			return 0;
		}
	}
	return 1;
}

#define RG_U32(mb, off) (*(volatile u32 *)((mb) + (off)))
#define RG_U64(mb, off) (*(volatile u64 *)((mb) + (off)))

/* 1 when the exe is exactly the build this helper was made for */
static int rg_verify(const u8 *base) {
	return rg_bytes_equal(base + RVA_ADD_TO_INVENTORY_HANDLER, RG_EXPECTED_HANDLER, sizeof RG_EXPECTED_HANDLER) &&
	       rg_bytes_equal(base + RVA_SIGNAL_PUMP, RG_EXPECTED_PUMP, sizeof RG_EXPECTED_PUMP) &&
	       rg_bytes_equal(base + RVA_GET_PLAYER_ACTORS, RG_EXPECTED_GET_PLAYERS, sizeof RG_EXPECTED_GET_PLAYERS) &&
	       rg_bytes_equal(base + RVA_SEND_MESSAGE, RG_EXPECTED_SEND, sizeof RG_EXPECTED_SEND);
}

/* 1 when every byte of the mission handlers and of the functions they call matches */
static int rg_verify_missions(const u8 *base) {
	return rg_bytes_equal(base + RVA_MAKE_HANDLER, RG_EXPECTED_MAKE_HANDLER, sizeof RG_EXPECTED_MAKE_HANDLER) &&
	       rg_bytes_equal(base + RVA_START_HANDLER, RG_EXPECTED_START_HANDLER, sizeof RG_EXPECTED_START_HANDLER) &&
	       rg_bytes_equal(base + RVA_COMPLETE_HANDLER, RG_EXPECTED_COMPLETE_HANDLER, sizeof RG_EXPECTED_COMPLETE_HANDLER) &&
	       rg_bytes_equal(base + RVA_MS_READY, RG_EXPECTED_MS_READY, sizeof RG_EXPECTED_MS_READY) &&
	       rg_bytes_equal(base + RVA_MS_STATE_BY_NAME, RG_EXPECTED_MS_STATE_BY_NAME, sizeof RG_EXPECTED_MS_STATE_BY_NAME) &&
	       rg_bytes_equal(base + RVA_MS_MAKE_A, RG_EXPECTED_MS_MAKE_A, sizeof RG_EXPECTED_MS_MAKE_A) &&
	       rg_bytes_equal(base + RVA_MS_MAKE_B, RG_EXPECTED_MS_MAKE_B, sizeof RG_EXPECTED_MS_MAKE_B) &&
	       rg_bytes_equal(base + RVA_MS_FIND, RG_EXPECTED_MS_FIND, sizeof RG_EXPECTED_MS_FIND) &&
	       rg_bytes_equal(base + RVA_MS_STATE_BY_INDEX, RG_EXPECTED_MS_STATE_BY_INDEX, sizeof RG_EXPECTED_MS_STATE_BY_INDEX) &&
	       rg_bytes_equal(base + RVA_MS_SET_STATE, RG_EXPECTED_MS_SET_STATE, sizeof RG_EXPECTED_MS_SET_STATE) &&
	       rg_bytes_equal(base + RVA_SET_ACTIVE_HANDLER, RG_EXPECTED_SET_ACTIVE_HANDLER, sizeof RG_EXPECTED_SET_ACTIVE_HANDLER) &&
	       rg_bytes_equal(base + RVA_REPLAY_HANDLER, RG_EXPECTED_REPLAY_HANDLER, sizeof RG_EXPECTED_REPLAY_HANDLER) &&
	       rg_bytes_equal(base + RVA_MS2_LOOKUP, RG_EXPECTED_MS2_LOOKUP, sizeof RG_EXPECTED_MS2_LOOKUP) &&
	       rg_bytes_equal(base + RVA_MS2_STATE, RG_EXPECTED_MS2_STATE, sizeof RG_EXPECTED_MS2_STATE) &&
	       rg_bytes_equal(base + RVA_MS2_RESOLVE, RG_EXPECTED_MS2_RESOLVE, sizeof RG_EXPECTED_MS2_RESOLVE) &&
	       rg_bytes_equal(base + RVA_MS2_COMPONENT, RG_EXPECTED_MS2_COMPONENT, sizeof RG_EXPECTED_MS2_COMPONENT);
}

static void rg_resolve_missions(rg_state *s) {
	s->ms_manager = (void **)(s->base + RVA_MS_MANAGER);
	s->ms_alt_flag = s->base + RVA_MS_ALT_FLAG;
	s->ms_ready = (rg_ms_ready_fn)(s->base + RVA_MS_READY);
	s->ms_state_by_name = (rg_ms_state_by_name_fn)(s->base + RVA_MS_STATE_BY_NAME);
	s->ms_make_a = (rg_ms_make_a_fn)(s->base + RVA_MS_MAKE_A);
	s->ms_make_b = (rg_ms_make_b_fn)(s->base + RVA_MS_MAKE_B);
	s->ms_find = (rg_ms_find_fn)(s->base + RVA_MS_FIND);
	s->ms_state_by_index = (rg_ms_state_by_index_fn)(s->base + RVA_MS_STATE_BY_INDEX);
	s->ms_set_state = (rg_ms_set_state_fn)(s->base + RVA_MS_SET_STATE);
	s->ms2_manager = (void **)(s->base + RVA_MS2_MANAGER);
	s->ms2_lookup = (rg_ms2_lookup_fn)(s->base + RVA_MS2_LOOKUP);
	s->ms2_state = (rg_ms2_state_fn)(s->base + RVA_MS2_STATE);
	s->ms2_resolve = (rg_ms2_resolve_fn)(s->base + RVA_MS2_RESOLVE);
	s->ms2_component = (rg_ms2_component_fn)(s->base + RVA_MS2_COMPONENT);
	s->missions_ok = 1;
}

/* v5: 1 when every byte of VanityGiveBundleAction's handler and the first bytes of the four
 * functions it calls match. The handler's RIP-relative operands encode the hero handle global
 * and the VanityInventoryManager type, so matching them proves those two addresses too. */
static int rg_verify_vanity(const u8 *base) {
	return rg_bytes_equal(base + RVA_VANITY_GIVE_HANDLER, RG_EXPECTED_VANITY_GIVE_HANDLER, sizeof RG_EXPECTED_VANITY_GIVE_HANDLER) &&
	       rg_bytes_equal(base + RVA_RESOLVE_HANDLE, RG_EXPECTED_RESOLVE_HANDLE, sizeof RG_EXPECTED_RESOLVE_HANDLE) &&
	       rg_bytes_equal(base + RVA_FIND_COMPONENT_A, RG_EXPECTED_FIND_COMPONENT_A, sizeof RG_EXPECTED_FIND_COMPONENT_A) &&
	       rg_bytes_equal(base + RVA_FIND_COMPONENT_B, RG_EXPECTED_FIND_COMPONENT_B, sizeof RG_EXPECTED_FIND_COMPONENT_B) &&
	       rg_bytes_equal(base + RVA_VANITY_GIVE_BUNDLE, RG_EXPECTED_VANITY_GIVE_BUNDLE, sizeof RG_EXPECTED_VANITY_GIVE_BUNDLE) &&
	       rg_bytes_equal(base + RVA_FIRE_OUTPUT, RG_EXPECTED_FIRE_OUTPUT, sizeof RG_EXPECTED_FIRE_OUTPUT);
}

static void rg_resolve_vanity(rg_state *s) {
	s->resolve_handle = (rg_resolve_handle_fn)(s->base + RVA_RESOLVE_HANDLE);
	s->find_component_a = (rg_find_component_fn)(s->base + RVA_FIND_COMPONENT_A);
	s->find_component_b = (rg_find_component_fn)(s->base + RVA_FIND_COMPONENT_B);
	s->vanity_give = (rg_vanity_give_fn)(s->base + RVA_VANITY_GIVE_BUNDLE);
	s->fire = (rg_fire_fn)(s->base + RVA_FIRE_OUTPUT);
	s->vanity_ok = 1;
}

/* v6: which of the 8.0 paths match this exe (RG_V6_* bits); resolves the ones that do. The
 * state walk needs the v4 mission path too (Lookup, Resolve, Component). */
static u32 rg_verify_v6(rg_state *s) {
	const u8 *base = s->base;
	u32 bits = 0;
	if (s->missions_ok && rg_bytes_equal(base + RVA_MS2_STATE, RG_EXPECTED_MS2_STATE_WALK, sizeof RG_EXPECTED_MS2_STATE_WALK)) {
		s->ms2_table_find = (rg_ms2_table_find_fn)(s->base + RVA_MS2_TABLE_FIND);
		s->ms2_entry_find = (rg_ms2_entry_find_fn)(s->base + RVA_MS2_ENTRY_FIND);
		s->state_ok = 1;
		bits |= RG_V6_STATE;
	}
	if (rg_bytes_equal(base + RVA_UNLOCK_LEVEL_HANDLER, RG_EXPECTED_UNLOCK_LEVEL_HANDLER, sizeof RG_EXPECTED_UNLOCK_LEVEL_HANDLER) &&
	    rg_bytes_equal(base + RVA_LEVEL_SET_BIT, RG_EXPECTED_LEVEL_SET, sizeof RG_EXPECTED_LEVEL_SET) &&
	    rg_bytes_equal(base + RVA_IS_LEVEL_UNLOCKED, RG_EXPECTED_IS_LEVEL_UNLOCKED, sizeof RG_EXPECTED_IS_LEVEL_UNLOCKED)) {
		s->level_set = (rg_level_set_fn)(s->base + RVA_LEVEL_SET_BIT);
		s->levels = s->base + RVA_LEVELS_GLOBAL;
		s->levels_ok = 1;
		bits |= RG_V6_LEVELS;
	}
	if (rg_bytes_equal(base + RVA_PLANETARY_TRAVEL_HANDLER, RG_EXPECTED_PLANETARY_TRAVEL_HANDLER, sizeof RG_EXPECTED_PLANETARY_TRAVEL_HANDLER)) {
		s->travel_byte = s->base + RVA_PLANETARY_TRAVEL_BYTE;
		s->travel_ok = 1;
		bits |= RG_V6_TRAVEL;
	}
	return bits;
}

static void *rg_vt_entry(rg_state *s, void *obj, u32 offset);
/* v6: where State() reads this mission's state, walked exactly as State() walks; 0 if any step
 * finds nothing */
static volatile u32 *rg_ms2_state_slot(rg_state *s, void *mgr2, void *obj) {
	rg_ms2_node_id_fn node_id = (rg_ms2_node_id_fn)rg_vt_entry(s, obj, MS2_VT_NODE_ID);
	u8 *p1, *p2, *t, *e, *rec;
	u32 id;
	if (!node_id) {
		return 0;
	}
	p1 = *(u8 **)((u8 *)obj + 8);
	if (!p1) {
		return 0;
	}
	p2 = *(u8 **)p1;
	if (!p2) {
		return 0;
	}
	id = node_id(obj);
	t = (u8 *)s->ms2_table_find((u8 *)mgr2 + MS2_SAVE_TABLE, *(u64 *)(p2 + 8));
	if (!t) {
		return 0;
	}
	e = (u8 *)s->ms2_entry_find(t, id);
	if (!e) {
		return 0;
	}
	rec = *(u8 **)(e + MS2_ENTRY_RECORD);
	if (!rec) {
		return 0;
	}
	return (volatile u32 *)(rec + MS2_RECORD_STATE);
}

/* v6: the level mask and planetary travel, exactly as the two actions change them.
 * before/after: the unlocked mask (+0x30) or the travel byte; ret: the mask at +0x2C; index: +0x20 */
static u32 rg_level(rg_state *s, u32 kind, u32 flag, u32 level, u32 *before, u32 *after, u32 *ret, u32 *index) {
	*before = *after = *ret = *index = 0xFFFFFFFFu;
	if (kind == RG_KIND_TRAVEL_SET) {
		if (!s->travel_ok) {
			return RG_RESULT_NOT_VERIFIED;
		}
		if (flag > 1) {
			return RG_RESULT_BAD_REQUEST;
		}
		*before = *s->travel_byte;
		*s->travel_byte = (u8)flag;
		*after = *s->travel_byte;
		return RG_RESULT_DONE;
	}
	if (!s->levels_ok) {
		return RG_RESULT_NOT_VERIFIED;
	}
	*before = *(volatile u32 *)(s->levels + LEVELS_UNLOCKED);
	*ret = *(volatile u32 *)(s->levels + LEVELS_OTHER);
	*index = *(volatile u32 *)(s->levels + LEVELS_CURRENT);
	if (kind == RG_KIND_LEVEL_SET) {
		if (level < 1 || level > 10 || flag > 1) {
			*after = *before;
			return RG_RESULT_BAD_REQUEST;
		}
		s->level_set(s->levels, level, (u8)flag);
	} else if (kind != RG_KIND_LEVEL_READ) {
		return RG_RESULT_BAD_REQUEST;
	}
	*after = *(volatile u32 *)(s->levels + LEVELS_UNLOCKED);
	return RG_RESULT_DONE;
}

/* one armor piece, call for call what VanityGiveBundleAction's handler does. *ret = GiveBundle's
 * answer (1: added, 0: not added, for example already owned). */
static u32 rg_vanity(rg_state *s, u64 bundle, u32 *ret) {
	u8 *actor;
	void *mgr;
	*ret = 0xFFFFFFFFu;
	if (!s->vanity_ok) {
		return RG_RESULT_NOT_VERIFIED;
	}
	if (bundle == 0) {
		return RG_RESULT_BAD_REQUEST;
	}
	actor = (u8 *)s->resolve_handle((const u32 *)(s->base + RVA_HERO_HANDLE));
	if (actor == 0) {
		return RG_RESULT_NO_TARGET;
	}
	if (*(volatile unsigned short *)(actor + 0x88) > 0) {
		mgr = s->find_component_a(actor + 0x80, s->base + RVA_VANITY_MANAGER_TYPE);
	} else {
		mgr = s->find_component_b(actor + 0x58, s->base + RVA_VANITY_MANAGER_TYPE);
	}
	if (mgr == 0) {
		return RG_RESULT_NO_TARGET;
	}
	*ret = (u32)s->vanity_give(mgr, bundle, 0);
	return RG_RESULT_DONE;
}

/* ---- v5: armor sources ----------------------------------------------------------------------
 * The helper replaces VanityGiveBundleAction's handler (RVA 0x880720) with rg_armor_action. It
 * does what the handler does (the three calls of rg_vanity, then the output plug), except for a
 * piece Lua listed in MB_ARMOR_TABLE while MB_ARMOR_ON = 1: that piece is not given, the entry
 * is cleared (one interception per listing) and the "success" output fires, so the level
 * script goes on as if the piece had been handed over. Lua then gives that armor source's
 * randomizer item. Every run is written to the ring, so Lua sees each one. */
static int rg_armor_find(volatile u8 *mb, u64 bundle) {
	if (bundle == 0 || RG_U32(mb, MB_ARMOR_ON) != 1) {
		return -1;
	}
	for (u32 i = 0; i < RG_ARMOR_MAX; ++i) {
		if (RG_U64(mb, MB_ARMOR_TABLE + 8 * i) == bundle) {
			return (int)i;
		}
	}
	return -1;
}

static void rg_armor_note(volatile u8 *mb, u64 bundle, u32 what) {
	u32 seq = RG_U32(mb, MB_ARMOR_SEQ) + 1;
	u32 at = MB_ARMOR_RING + 16 * (seq % RG_ARMOR_RING);
	RG_U64(mb, at) = bundle;
	RG_U32(mb, at + 12) = what;
	RG_U32(mb, at + 8) = seq;
	RG_U32(mb, MB_ARMOR_SEQ) = seq; /* last */
}

/* decides and gives; returns the plug to fire. Faults are caught by the platform layer. */
static u32 rg_armor_decide(rg_state *s, const u8 *node) {
	volatile u8 *mb = s->mailbox;
	u64 bundle = *(const u64 *)(node + 0x60);
	int at;
	u32 ret = 0, result;
	RG_U32(mb, MB_ARMOR_CALLS) = RG_U32(mb, MB_ARMOR_CALLS) + 1;
	at = rg_armor_find(mb, bundle);
	if (at >= 0) {
		RG_U64(mb, MB_ARMOR_TABLE + 8 * (u32)at) = 0;
		rg_armor_note(mb, bundle, RG_ARMOR_INTERCEPTED);
		return RG_PLUG_SUCCESS;
	}
	result = rg_vanity(s, bundle, &ret);
	if (result == RG_RESULT_DONE && ret != 0) {
		rg_armor_note(mb, bundle, RG_ARMOR_GIVEN);
		return RG_PLUG_SUCCESS;
	}
	rg_armor_note(mb, bundle, RG_ARMOR_NOT_GIVEN);
	return RG_PLUG_FAILURE;
}

/* ---- v5: config lookup ------------------------------------------------------------------------
 * the loaded config with this asset id, walked exactly like rivet_hook's configs::find */
static u32 rg_config_lookup(rg_state *s, u64 id, u64 *object) {
	u8 *mgr = s->config_mgr, *array;
	u64 stride;
	int count;
	*object = 0;
	if (mgr == 0) {
		return RG_RESULT_NOT_VERIFIED;
	}
	if (id == 0) {
		return RG_RESULT_BAD_REQUEST;
	}
	array = *(u8 **)(mgr + CFG_ENTRIES);
	stride = *(u64 *)(mgr + CFG_STRIDE);
	count = *(int *)(mgr + CFG_MAX);
	if (array == 0 || stride < CFG_ENTRY_OBJECT + 8 || stride > 0x1000 || count <= 0 || count > (1 << 16)) {
		return RG_RESULT_NOT_READY;
	}
	for (int i = 0; i < count; ++i) {
		u8 *entry = array + stride * (u64)i;
		if (*(u64 *)(entry + CFG_ENTRY_ID) == id && entry[CFG_ENTRY_STATE] == CFG_STATE_LOADED) {
			u64 obj = *(u64 *)(entry + CFG_ENTRY_OBJECT);
			if (obj != 0) {
				*object = obj;
				return RG_RESULT_DONE;
			}
		}
	}
	return RG_RESULT_NOT_FOUND;
}

/* the config manager: the first place RG_CONFIG_SIGNATURE matches in [code, code + size), plus
 * its rel32. *matches counts every match (rivet_hook takes the first one too). */
static u8 *rg_find_config_manager(const u8 *code, u64 size, u32 *matches) {
	u8 *found = 0;
	*matches = 0;
	if (size < sizeof RG_CONFIG_SIGNATURE + 4) {
		return 0;
	}
	for (u64 i = 0; i + sizeof RG_CONFIG_SIGNATURE <= size && i + RG_CONFIG_REL + 4 <= size; ++i) {
		if (code[i] != RG_CONFIG_SIGNATURE[0] || !rg_bytes_equal(code + i, RG_CONFIG_SIGNATURE, sizeof RG_CONFIG_SIGNATURE)) {
			continue;
		}
		*matches += 1;
		if (!found) {
			int rel = *(const int *)(code + i + RG_CONFIG_REL);
			found = (u8 *)(code + i + RG_CONFIG_REL + 4) + rel;
		}
	}
	return found;
}

/* v7 (dev 10.21): the SceneManager, found exactly as rivet_hook finds it (src/signature.hpp
 * SCENE_MANAGER "48 8D 0D ?? ?? ?? ?? E8 ?? ?? ?? ?? 48 63 75", SCENE_MANAGER_ADDRESS 3: the rel32 of a
 * lea rcx, [rip + x]; src/overlay_core.cpp load_rel_var). rivet_hook's find_address takes it only when the
 * signature matches exactly once (limit 1), and your game's rivet.script_node answers (round 31 log), so
 * it does match once there. The helper only reads the address and publishes it; Lua reads the script
 * variables through it (SceneManager +0x75A0 scriptVars, +0x75BC scriptVarMax: rivet_hook
 * src/game/scene_manager.hpp). */
static const u8 RG_SCENE_SIGNATURE[15] = {
	0x48, 0x8D, 0x0D, 0x00, 0x00, 0x00, 0x00, 0xE8, 0x00, 0x00, 0x00, 0x00, 0x48, 0x63, 0x75,
};
static const u8 RG_SCENE_MASK[15] = { /* 1 = the byte must match, 0 = ?? */
	1, 1, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 1, 1,
};
#define RG_SCENE_REL 3u

/* the first place RG_SCENE_SIGNATURE matches in [code, code + size) and its rel32 target; *matches
 * counts every match, so the caller can refuse anything but exactly one (as rivet_hook does) */
static u8 *rg_find_scene_manager(const u8 *code, u64 size, u32 *matches) {
	u8 *found = 0;
	*matches = 0;
	if (size < sizeof RG_SCENE_SIGNATURE) {
		return 0;
	}
	for (u64 i = 0; i + sizeof RG_SCENE_SIGNATURE <= size; ++i) {
		u32 k = 0;
		if (code[i] != RG_SCENE_SIGNATURE[0]) {
			continue;
		}
		for (k = 0; k < sizeof RG_SCENE_SIGNATURE; ++k) {
			if (RG_SCENE_MASK[k] && code[i + k] != RG_SCENE_SIGNATURE[k]) {
				break;
			}
		}
		if (k != sizeof RG_SCENE_SIGNATURE) {
			continue;
		}
		*matches += 1;
		if (!found) {
			int rel = *(const int *)(code + i + RG_SCENE_REL);
			found = (u8 *)(code + i + RG_SCENE_REL + 4) + rel;
		}
	}
	return found;
}

/* the engine's string hash (see above) */
static u32 rg_hash(const char *text) {
	u32 c = 0xEDB88320u;
	for (const u8 *p = (const u8 *)text; *p; ++p) {
		u32 x = (c ^ *p) & 0xFFu;
		for (int k = 0; k < 8; ++k) {
			x = (x & 1u) ? (x >> 1) ^ 0xEDB88320u : x >> 1;
		}
		c = (c >> 8) ^ x;
	}
	return c;
}

/* a name slot is usable when it holds 1..63 printable characters and a terminating zero */
static const char *rg_slot_name(volatile u8 *mb, u32 slot) {
	const volatile u8 *p;
	u32 i;
	if (slot >= RG_NAME_SLOTS) {
		return 0;
	}
	p = mb + MB_NAMES + slot * RG_NAME_SIZE;
	for (i = 0; i < RG_NAME_SIZE; ++i) {
		if (p[i] == 0) {
			break;
		}
		if (p[i] < 0x21 || p[i] > 0x7E) {
			return 0;
		}
	}
	if (i == 0 || i == RG_NAME_SIZE) {
		return 0;
	}
	return (const char *)p;
}

/* a vtable entry is only called when it points into the exe */
static void *rg_vt_entry(rg_state *s, void *obj, u32 offset) {
	u64 fn = (*(u64 **)obj)[offset / 8];
	if (fn < (u64)s->base || fn >= (u64)s->base + RG_IMAGE_SPAN) {
		return 0;
	}
	return (void *)fn;
}

/* system 2 (the byte at 0x6925FA8 set): the actions' other branch, call for call */
static u32 rg_mission2(rg_state *s, u32 kind, const char *name, u32 flag, u32 *before, u32 *after, u32 *ret, u32 *index, u64 *object) {
	rg_ms2_handle h;
	void *mgr2 = s->ms2_manager ? *s->ms2_manager : 0, *ent, *obj;
	h.handle = h.pad0 = h.hash = h.pad1 = 0;
	h.component = 0;
	if (mgr2 == 0) {
		return RG_RESULT_NO_MANAGER;
	}
	s->ms2_lookup(mgr2, &h, rg_hash(name));
	*index = h.handle;
	if (h.handle == 0 && h.component == 0) {
		return RG_RESULT_UNKNOWN_MISSION;
	}
	*before = s->ms2_state(mgr2, &h);
	ent = s->ms2_resolve(&h);
	obj = ent ? s->ms2_component(ent, h.component) : 0;
	if (obj == 0) {
		return RG_RESULT_UNKNOWN_MISSION;
	}
	*object = (u64)obj;
	if (kind == RG_KIND_MISSION_SET_STATE || kind == RG_KIND_MISSION_PROBE) {
		volatile u32 *slot;
		if (!s->state_ok) {
			*after = *before;
			return RG_RESULT_NOT_VERIFIED;
		}
		slot = rg_ms2_state_slot(s, mgr2, obj);
		if (slot == 0) {
			*after = *before;
			return RG_RESULT_NOT_FOUND;
		}
		*object = (u64)slot;
		/* the walk must read exactly what the game's own State() read */
		if (*slot != *before) {
			*after = *before;
			return RG_RESULT_NOT_VERIFIED;
		}
		if (kind == RG_KIND_MISSION_SET_STATE) {
			if (flag > RG_MISSION_STATE_MAX) {
				*after = *before;
				return RG_RESULT_BAD_REQUEST;
			}
			*slot = flag;
		}
		*after = s->ms2_state(mgr2, &h);
		return RG_RESULT_DONE;
	}
	if (kind == RG_KIND_MISSION_MAKE_AVAILABLE) {
		*after = *before;
		return RG_RESULT_NO_SUCH_ACTION;
	}
	if (kind == RG_KIND_MISSION_START) {
		rg_ms2_can_start_fn can = (rg_ms2_can_start_fn)rg_vt_entry(s, obj, MS2_VT_CAN_START);
		rg_ms2_act_fn act = (rg_ms2_act_fn)rg_vt_entry(s, obj, MS2_VT_START);
		if (!can || !act) {
			return RG_RESULT_NOT_VERIFIED;
		}
		if (*before != 1) {
			*after = *before;
			return RG_RESULT_WRONG_STATE;
		}
		*ret = can(obj);
		if (!*ret) {
			*after = *before;
			return RG_RESULT_WRONG_STATE;
		}
		act(obj);
	} else if (kind == RG_KIND_MISSION_COMPLETE) {
		rg_ms2_act_fn act = (rg_ms2_act_fn)rg_vt_entry(s, obj, MS2_VT_COMPLETE);
		if (!act) {
			return RG_RESULT_NOT_VERIFIED;
		}
		if (*before != 3) {
			*after = *before;
			return RG_RESULT_WRONG_STATE;
		}
		act(obj);
	} else if (kind == RG_KIND_MISSION_REPLAY) {
		rg_ms2_replay_fn replay = (rg_ms2_replay_fn)rg_vt_entry(s, obj, MS2_VT_REPLAY);
		if (!replay) {
			return RG_RESULT_NOT_VERIFIED;
		}
		*ret = replay(obj, (u8)flag, 1);
	}
	*after = s->ms2_state(mgr2, &h);
	return RG_RESULT_DONE;
}

/* one mission request: the same calls, with the same checks, as the game's own action */
static u32 rg_mission(rg_state *s, u32 kind, const char *name, u32 flag, u32 *before, u32 *after, u32 *ret, u32 *index, u64 *object, u32 *system) {
	void *mgr;
	int i = -1;
	*before = *after = *ret = *index = 0xFFFFFFFFu;
	*object = 0;
	*system = 0;
	if (!s->missions_ok) {
		return RG_RESULT_NOT_VERIFIED;
	}
	if (name == 0) {
		return RG_RESULT_BAD_REQUEST;
	}
	if (kind == RG_KIND_MISSION_SET_STATE || kind == RG_KIND_MISSION_PROBE) {
		if (kind == RG_KIND_MISSION_SET_STATE ? flag > RG_MISSION_STATE_MAX : flag != 0) {
			return RG_RESULT_BAD_REQUEST;
		}
	} else if (kind < RG_KIND_MISSION_QUERY || kind > RG_KIND_MISSION_REPLAY || flag > 1) {
		return RG_RESULT_BAD_REQUEST;
	}
	if (*s->ms_alt_flag != 0) {
		*system = 2;
		return rg_mission2(s, kind, name, flag, before, after, ret, index, object);
	}
	*system = 1;
	if (kind == RG_KIND_MISSION_SET_STATE || kind == RG_KIND_MISSION_PROBE) {
		return RG_RESULT_NO_SUCH_ACTION; /* v6 knows system 2's records only */
	}
	if (kind == RG_KIND_MISSION_REPLAY) {
		return RG_RESULT_NO_SUCH_ACTION;
	}
	mgr = *s->ms_manager;
	if (mgr == 0) {
		return RG_RESULT_NO_MANAGER;
	}
	if (!s->ms_ready(mgr)) {
		return RG_RESULT_NOT_READY;
	}
	s->ms_find(mgr, &i, rg_hash(name));
	*index = (u32)i;
	if (i == -1) {
		return RG_RESULT_UNKNOWN_MISSION;
	}
	*before = s->ms_state_by_name(mgr, name, 0);
	if (kind == RG_KIND_MISSION_MAKE_AVAILABLE) {
		if (*before != 0) {
			*after = *before;
			return RG_RESULT_WRONG_STATE;
		}
		s->ms_make_a(mgr, name, 0);
		s->ms_make_b(mgr, name);
	} else if (kind == RG_KIND_MISSION_START) {
		u64 fn = (*(u64 **)mgr)[MS_VT_START / 8];
		if (fn < (u64)s->base || fn >= (u64)s->base + RG_IMAGE_SPAN) {
			return RG_RESULT_NOT_VERIFIED;
		}
		*ret = (u32)((rg_ms_start_fn)fn)(mgr, name, (u8)flag);
	} else if (kind == RG_KIND_MISSION_COMPLETE) {
		u32 st = s->ms_state_by_index(mgr, i, 0);
		if (st != 3) {
			*after = *before;
			return RG_RESULT_WRONG_STATE;
		}
		s->ms_set_state(mgr, i, 4);
	}
	*after = s->ms_state_by_name(mgr, name, 0);
	return RG_RESULT_DONE;
}

static void rg_resolve(rg_state *s) {
	s->get_players = (rg_get_players_fn)(s->base + RVA_GET_PLAYER_ACTORS);
	s->send = (rg_send_fn)(s->base + RVA_SEND_MESSAGE);
	s->players = s->base + RVA_PLAYERS_GLOBAL;
	s->message = (u64 *)(s->base + RVA_ADD_TO_INVENTORY_MSG);
}

static void rg_mailbox_init(volatile u8 *mb, const u8 *base) {
	for (u32 i = 0; i < MB_NAMES; ++i) { /* v5: the armor block below the names too */
		mb[i] = 0;
	}
	RG_U32(mb, MB_VERSION) = RG_VERSION;
	RG_U32(mb, MB_STATUS) = RG_STATUS_STARTING;
	RG_U64(mb, MB_BASE) = (u64)base;
	RG_U64(mb, MB_MAGIC) = RG_MAGIC; /* last: Lua trusts the page once the magic is there */
}

/* v5: counts up to this (currency: bolts and Raritanium are items given with a count) */
#define RG_MAX_COUNT 100000u
/* the give itself, exactly like AddToInventoryAction's handler. Returns an RG_RESULT_* and the
 * number of actors the message went to. Faults are caught by the caller (platform layer). */
static u32 rg_give(rg_state *s, u64 item, u32 count, u32 hero, u32 mode, u32 *targets_out, u32 *path_out) {
	struct {
		u64 item;
		u32 count;
	} payload;
	rg_actor_list t;
	u32 hero_list[1];

	*path_out = 0;
	*targets_out = 0;
	if (item == 0 || count == 0 || count > RG_MAX_COUNT || mode > RG_MAX_GROUP) {
		return RG_RESULT_BAD_REQUEST;
	}
	payload.item = item;
	payload.count = count;
	t.ptr = 0;
	t.count = 0;
	t.pad = 0;
	if (mode == 0) {
		if (hero == 0) {
			return RG_RESULT_NO_TARGET;
		}
		hero_list[0] = hero;
		t.ptr = hero_list;
		t.count = 1;
	} else {
		s->get_players(s->players, &t, mode - 1);
		if (t.ptr == 0 || t.count == 0) {
			return RG_RESULT_NO_TARGET;
		}
	}
	*path_out = mode + 1;
	*targets_out = t.count;
	s->send(1, *s->message, t.ptr, t.count, &payload, 0xC);
	return RG_RESULT_SENT;
}

/* one request at most per frame. The platform layer wraps both calls in an exception handler. */
typedef u32 (*rg_guarded_give_fn)(rg_state *s, u64 item, u32 count, u32 hero, u32 mode, u32 *targets_out, u32 *path_out);
typedef u32 (*rg_guarded_mission_fn)(rg_state *s, u32 kind, const char *name, u32 flag, u32 *before, u32 *after, u32 *ret, u32 *index, u64 *object, u32 *system);
typedef u32 (*rg_guarded_vanity_fn)(rg_state *s, u64 bundle, u32 *ret);
typedef u32 (*rg_guarded_lookup_fn)(rg_state *s, u64 id, u64 *object);
typedef u32 (*rg_guarded_level_fn)(rg_state *s, u32 kind, u32 flag, u32 level, u32 *before, u32 *after, u32 *ret, u32 *index);

static void rg_pump(rg_state *s, rg_guarded_give_fn give, rg_guarded_mission_fn mission, rg_guarded_vanity_fn vanity,
                    rg_guarded_lookup_fn lookup, rg_guarded_level_fn level) {
	volatile u8 *mb = s->mailbox;
	u32 req, targets = 0, path = 0, result, kind;
	RG_U32(mb, MB_PUMPS) = RG_U32(mb, MB_PUMPS) + 1;
	if (RG_U32(mb, MB_STATUS) != RG_STATUS_READY) {
		return;
	}
	req = RG_U32(mb, MB_REQ);
	if (req == RG_U32(mb, MB_DONE)) {
		return;
	}
	kind = RG_U32(mb, MB_KIND);
	if (kind == RG_KIND_VANITY_GIVE) {
		u32 ret = 0xFFFFFFFFu;
		result = vanity(s, RG_U64(mb, MB_ITEM), &ret);
		RG_U32(mb, MB_RESULT) = result;
		RG_U32(mb, MB_RET) = ret;
		RG_U32(mb, MB_DONE) = req; /* last */
		return;
	}
	if (kind == RG_KIND_CONFIG_LOOKUP) {
		u64 object = 0;
		result = lookup(s, RG_U64(mb, MB_ITEM), &object);
		RG_U32(mb, MB_RESULT) = result;
		RG_U64(mb, MB_OBJECT) = object;
		RG_U32(mb, MB_DONE) = req; /* last */
		return;
	}
	if (kind == RG_KIND_LEVEL_SET || kind == RG_KIND_LEVEL_READ || kind == RG_KIND_TRAVEL_SET) {
		u32 before = 0xFFFFFFFFu, after = 0xFFFFFFFFu, ret = 0xFFFFFFFFu, index = 0xFFFFFFFFu;
		result = level(s, kind, RG_U32(mb, MB_FLAG), RG_U32(mb, MB_COUNT), &before, &after, &ret, &index);
		RG_U32(mb, MB_RESULT) = result;
		RG_U32(mb, MB_BEFORE) = before;
		RG_U32(mb, MB_AFTER) = after;
		RG_U32(mb, MB_RET) = ret;
		RG_U32(mb, MB_INDEX) = index;
		RG_U64(mb, MB_OBJECT) = 0;
		RG_U32(mb, MB_SYSTEM) = 0;
		RG_U32(mb, MB_DONE) = req; /* last */
		return;
	}
	if (kind != RG_KIND_GIVE) {
		u32 before = 0xFFFFFFFFu, after = 0xFFFFFFFFu, ret = 0xFFFFFFFFu, index = 0xFFFFFFFFu, system = 0;
		u64 object = 0;
		result = mission(s, kind, rg_slot_name(mb, RG_U32(mb, MB_SLOT)), RG_U32(mb, MB_FLAG), &before, &after, &ret, &index, &object, &system);
		RG_U32(mb, MB_RESULT) = result;
		RG_U32(mb, MB_BEFORE) = before;
		RG_U32(mb, MB_AFTER) = after;
		RG_U32(mb, MB_RET) = ret;
		RG_U32(mb, MB_INDEX) = index;
		RG_U64(mb, MB_OBJECT) = object;
		RG_U32(mb, MB_SYSTEM) = system;
		RG_U32(mb, MB_DONE) = req; /* last */
		return;
	}
	result = give(s, RG_U64(mb, MB_ITEM), RG_U32(mb, MB_COUNT), RG_U32(mb, MB_HERO), RG_U32(mb, MB_MODE), &targets, &path);
	RG_U32(mb, MB_RESULT) = result;
	RG_U32(mb, MB_TARGETS) = targets;
	RG_U32(mb, MB_PATH) = path;
	if (result == RG_RESULT_SENT) {
		RG_U32(mb, MB_SENT) = RG_U32(mb, MB_SENT) + 1;
	}
	RG_U32(mb, MB_DONE) = req; /* last: Lua reads the result once DONE == REQ */
}

/* the 14-byte absolute jump written over the pump's first instructions, and the trampoline
 * (the original 14 bytes followed by a jump back to pump + 14) */
static void rg_write_jump(u8 *at, u64 to) {
	at[0] = 0xFF;
	at[1] = 0x25;
	at[2] = at[3] = at[4] = at[5] = 0x00;
	for (int i = 0; i < 8; ++i) {
		at[6 + i] = (u8)(to >> (8 * i));
	}
}

static void rg_build_trampoline(u8 *tramp, const u8 *pump) {
	for (int i = 0; i < HOOK_BYTES; ++i) {
		tramp[i] = pump[i];
	}
	rg_write_jump(tramp + HOOK_BYTES, (u64)(pump + HOOK_BYTES));
}

/* instruction boundaries inside the patched bytes, for moving a suspended thread's RIP */
static int rg_is_boundary(u32 offset) {
	return offset == 0 || offset == 5 || offset == 6 || offset == 10;
}

#endif
