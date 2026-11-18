/* rando_give.dll v6: Windows layer of the randomizer's "give item" and mission helper (see rando_give_core.h).
 *
 * Loaded by rivet_hook at startup through its [renderdoc] dll_path setting (rivet_hook's only
 * way to load an extra DLL; nothing of RenderDoc is used). It:
 *   1. puts a 4 KiB mailbox page at the first free address of RG_MAILBOX_CANDIDATES (Lua finds
 *      it by reading the magic with rivet.read),
 *   2. checks every byte it relies on in RiftApart.exe; on any difference it stops there and
 *      reports RG_STATUS_WRONG_EXE (nothing is patched, nothing is ever called),
 *   3. hooks the script signal pump (RVA 0x12BE970), which the game runs once per frame on its
 *      game thread, with a 14-byte jump; other threads are suspended while the bytes change,
 *      exactly like MinHook does,
 *   4. on each pump, performs at most one give (v3: or one mission call, v5: or one armor piece
 *      or one config lookup) the mailbox asks for, inside a structured exception handler, then
 *      runs the original pump,
 *   5. v5: replaces VanityGiveBundleAction's handler (RVA 0x880720, a 0x72-byte function that
 *      is checked byte for byte) with rg_armor_action, which does the same calls except for the
 *      armor pieces Lua lists (see rando_give_core.h, "armor sources"). It is patched in the
 *      same pass as the pump, with every other thread suspended; if a thread stands inside
 *      the bytes, only the pump is patched,
 *   6. v5: finds the game's config asset manager with rivet_hook's own signature (read only).
 *   7. v6 (Randomizer 8.0): checks three more paths and reports them in MB_V6: a mission's saved
 *      state record (read, or written for the hub's "force available" experiment), the level
 *      mask UnlockLevelAction changes, and the byte SetPlanetaryTravelAction sets. Nothing is
 *      patched for them; they run inside the pump like every other request.
 * The DLL pins itself, so rivet_hook's FreeLibrary at exit cannot unload code that is hooked.
 *
 * Built without the CRT or the Windows SDK (clang --target=x86_64-pc-windows-msvc + lld-link,
 * import libraries from .def files), see build.sh.
 */
#include "rando_give_core.h"

typedef void *HANDLE;
typedef int BOOL;
typedef unsigned long DWORD;
typedef unsigned short WORD;
typedef unsigned long long SIZE_T;

#define WINAPI __stdcall
#define IMPORT __declspec(dllimport)

IMPORT void *WINAPI VirtualAlloc(void *address, SIZE_T size, DWORD type, DWORD protect);
IMPORT BOOL WINAPI VirtualProtect(void *address, SIZE_T size, DWORD protect, DWORD *old);
IMPORT BOOL WINAPI FlushInstructionCache(HANDLE process, const void *address, SIZE_T size);
IMPORT HANDLE WINAPI GetCurrentProcess(void);
IMPORT DWORD WINAPI GetCurrentProcessId(void);
IMPORT DWORD WINAPI GetCurrentThreadId(void);
IMPORT void *WINAPI GetModuleHandleA(const char *name);
IMPORT BOOL WINAPI GetModuleHandleExA(DWORD flags, const char *name, void **module);
IMPORT HANDLE WINAPI CreateToolhelp32Snapshot(DWORD flags, DWORD pid);
IMPORT BOOL WINAPI Thread32First(HANDLE snapshot, void *entry);
IMPORT BOOL WINAPI Thread32Next(HANDLE snapshot, void *entry);
IMPORT HANDLE WINAPI OpenThread(DWORD access, BOOL inherit, DWORD id);
IMPORT DWORD WINAPI SuspendThread(HANDLE thread);
IMPORT DWORD WINAPI ResumeThread(HANDLE thread);
IMPORT BOOL WINAPI GetThreadContext(HANDLE thread, void *context);
IMPORT BOOL WINAPI SetThreadContext(HANDLE thread, const void *context);
IMPORT BOOL WINAPI CloseHandle(HANDLE handle);

#define MEM_COMMIT 0x1000
#define MEM_RESERVE 0x2000
#define PAGE_READWRITE 0x04
#define PAGE_EXECUTE_READ 0x20
#define PAGE_EXECUTE_READWRITE 0x40
#define TH32CS_SNAPTHREAD 0x4
#define THREAD_ACCESS 0x001A /* SUSPEND_RESUME | GET_CONTEXT | SET_CONTEXT */
#define CONTEXT_CONTROL 0x100001
#define GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS 0x4
#define GET_MODULE_HANDLE_EX_FLAG_PIN 0x1
#define INVALID_HANDLE ((HANDLE)(long long)-1)

/* the CRT-free compiler may still emit calls to these */
void *memset(void *dst, int c, SIZE_T n) {
	u8 *d = (u8 *)dst;
	while (n--) *d++ = (u8)c;
	return dst;
}
void *memcpy(void *dst, const void *src, SIZE_T n) {
	u8 *d = (u8 *)dst;
	const u8 *s = (const u8 *)src;
	while (n--) *d++ = *s++;
	return dst;
}
int _fltused = 0;

typedef struct {
	DWORD dwSize, cntUsage, th32ThreadID, th32OwnerProcessID;
	long tpBasePri, tpDeltaPri;
	DWORD dwFlags;
} THREADENTRY32;

/* x64 CONTEXT: 0x4D0 bytes, 16-byte aligned; ContextFlags at 0x30, Rip at 0xF8 */
typedef struct __declspec(align(16)) {
	u8 raw[0x4D0];
} CONTEXT64;
#define CTX_FLAGS(c) (*(DWORD *)((c)->raw + 0x30))
#define CTX_RIP(c) (*(u64 *)((c)->raw + 0xF8))

/* fixed addresses Lua probes for the mailbox (first one VirtualAlloc grants wins) */
static const u64 RG_MAILBOX_CANDIDATES[] = {
	0x00007FEF00000000ULL, 0x00007FEE00000000ULL, 0x00007FED00000000ULL, 0x0000000B00000000ULL,
};

static rg_state g_state;
static u8 *g_trampoline;
typedef void (*pump_fn)(void *queue, void *a2, void *a3, void *a4);
static volatile pump_fn g_original_pump;

static u32 guarded_give(rg_state *s, u64 item, u32 count, u32 hero, u32 mode, u32 *targets_out, u32 *path_out) {
	u32 result;
	__try {
		result = rg_give(s, item, count, hero, mode, targets_out, path_out);
	} __except (1) {
		result = RG_RESULT_FAULT;
	}
	return result;
}

static u32 guarded_mission(rg_state *s, u32 kind, const char *name, u32 flag, u32 *before, u32 *after, u32 *ret, u32 *index, u64 *object, u32 *system) {
	u32 result;
	__try {
		result = rg_mission(s, kind, name, flag, before, after, ret, index, object, system);
	} __except (1) {
		result = RG_RESULT_FAULT;
	}
	return result;
}
static u32 guarded_vanity(rg_state *s, u64 bundle, u32 *ret) {
	u32 result;
	__try {
		result = rg_vanity(s, bundle, ret);
	} __except (1) {
		result = RG_RESULT_FAULT;
	}
	return result;
}
static u32 guarded_lookup(rg_state *s, u64 id, u64 *object) {
	u32 result;
	__try {
		result = rg_config_lookup(s, id, object);
	} __except (1) {
		*object = 0;
		result = RG_RESULT_FAULT;
	}
	return result;
}
static u32 guarded_level(rg_state *s, u32 kind, u32 flag, u32 level, u32 *before, u32 *after, u32 *ret, u32 *index) {
	u32 result;
	__try {
		result = rg_level(s, kind, flag, level, before, after, ret, index);
	} __except (1) {
		result = RG_RESULT_FAULT;
	}
	return result;
}
static void detour_pump(void *queue, void *a2, void *a3, void *a4) {
	__try {
		rg_pump(&g_state, guarded_give, guarded_mission, guarded_vanity, guarded_lookup, guarded_level);
	} __except (1) {
	}
	g_original_pump(queue, a2, a3, a4);
}

/* v5: VanityGiveBundleAction's handler, replaced. Same arguments as the game's handler (the
 * node, the input plug, which it ignores); same result (the output plug function's). */
static u8 detour_vanity_action(u8 *node, u32 input) {
	u32 plug = RG_PLUG_FAILURE;
	u8 r = 0;
	(void)input;
	__try {
		plug = rg_armor_decide(&g_state, node);
	} __except (1) {
		plug = RG_PLUG_FAILURE;
	}
	__try {
		r = g_state.fire(*(void **)(node + 0x58), plug);
	} __except (1) {
		r = 0;
	}
	return r;
}

static int patch(u8 *at, u64 to) {
	DWORD old = 0;
	if (!VirtualProtect(at, HOOK_BYTES, PAGE_EXECUTE_READWRITE, &old)) {
		return 0;
	}
	rg_write_jump(at, to);
	VirtualProtect(at, HOOK_BYTES, old, &old);
	FlushInstructionCache(GetCurrentProcess(), at, HOOK_BYTES);
	return 1;
}

/* suspends every other thread, moves any that stand inside the pump's 14 bytes to the
 * trampoline, writes the jump(s), resumes. Returns 1 when the pump is hooked. v5: the armor
 * handler (vanity, may be 0) is patched in the same pass unless a thread stands inside it. */
#define MAX_THREADS 4096
static int install_hook(u8 *pump, u8 *vanity) {
	/* not on the stack: a 32 KiB frame would need the CRT's stack probe */
	HANDLE *threads = (HANDLE *)VirtualAlloc(0, MAX_THREADS * sizeof(HANDLE), MEM_RESERVE | MEM_COMMIT, PAGE_READWRITE);
	int n = 0, ok = 1;
	DWORD me = GetCurrentThreadId(), pid = GetCurrentProcessId();
	HANDLE snap = CreateToolhelp32Snapshot(TH32CS_SNAPTHREAD, 0);
	THREADENTRY32 te;
	if (!threads || snap == INVALID_HANDLE) {
		if (snap != INVALID_HANDLE) CloseHandle(snap);
		return 0;
	}
	te.dwSize = sizeof te;
	if (Thread32First(snap, &te)) {
		do {
			if (te.th32OwnerProcessID == pid && te.th32ThreadID != me) {
				if (n >= MAX_THREADS) {
					ok = 0; /* never patch with a thread left running */
					break;
				}
				HANDLE t = OpenThread(THREAD_ACCESS, 0, te.th32ThreadID);
				if (t) {
					if (SuspendThread(t) != (DWORD)-1) {
						threads[n++] = t;
					} else {
						CloseHandle(t);
					}
				}
			}
			te.dwSize = sizeof te;
		} while (Thread32Next(snap, &te));
	}
	CloseHandle(snap);

	for (int i = 0; i < n && ok; ++i) {
		CONTEXT64 ctx;
		memset(&ctx, 0, sizeof ctx);
		CTX_FLAGS(&ctx) = CONTEXT_CONTROL;
		if (GetThreadContext(threads[i], &ctx)) {
			u64 rip = CTX_RIP(&ctx);
			if (vanity && rip >= (u64)vanity && rip < (u64)vanity + HOOK_BYTES) {
				vanity = 0; /* never patched under a running thread */
				RG_U32(g_state.mailbox, MB_ARMOR_HOOK) = RG_ARMOR_HOOK_BUSY;
			}
			if (rip >= (u64)pump && rip < (u64)pump + HOOK_BYTES) {
				u32 off = (u32)(rip - (u64)pump);
				if (!rg_is_boundary(off)) {
					ok = 0;
				} else {
					CTX_RIP(&ctx) = (u64)g_trampoline + off;
					ok = SetThreadContext(threads[i], &ctx) ? 1 : 0;
				}
			}
		}
	}

	if (ok) {
		ok = patch(pump, (u64)&detour_pump);
	}
	if (ok && vanity) {
		RG_U32(g_state.mailbox, MB_ARMOR_HOOK) = patch(vanity, (u64)&detour_vanity_action) ? RG_ARMOR_HOOK_ON : RG_ARMOR_HOOK_OFF;
	}

	for (int i = 0; i < n; ++i) {
		ResumeThread(threads[i]);
		CloseHandle(threads[i]);
	}
	return ok;
}

/* every executable section of the exe (PE headers as loaded), scanned for rivet_hook's
 * config-manager signature */
static void find_config_manager(u8 *base) {
	u32 total = 0;
	__try {
		u8 *nt = base + *(u32 *)(base + 0x3C);
		WORD sections = *(WORD *)(nt + 6), opt = *(WORD *)(nt + 20);
		u8 *sec = nt + 24 + opt;
		if (*(u32 *)nt != 0x00004550u) { /* "PE\0\0" */
			return;
		}
		for (WORD i = 0; i < sections; ++i, sec += 40) {
			u32 vsize = *(u32 *)(sec + 8), rva = *(u32 *)(sec + 12), flags = *(u32 *)(sec + 36);
			u32 m = 0;
			u8 *found;
			if (!(flags & 0x20000000u)) { /* IMAGE_SCN_MEM_EXECUTE */
				continue;
			}
			found = rg_find_config_manager(base + rva, vsize, &m);
			if (found && !g_state.config_mgr) {
				g_state.config_mgr = found;
			}
			total += m;
		}
	} __except (1) {
		g_state.config_mgr = 0;
	}
	RG_U64(g_state.mailbox, MB_CONFIG_MGR) = (u64)g_state.config_mgr;
	RG_U32(g_state.mailbox, MB_CONFIG_SIGS) = total;
}

/* v7: the SceneManager, by rivet_hook's own signature over the exe's code sections; published only
 * when it matched exactly once */
static void find_scene_manager(u8 *base) {
	u32 total = 0;
	u8 *first = 0;
	__try {
		u8 *nt = base + *(u32 *)(base + 0x3C);
		WORD sections = *(WORD *)(nt + 6), opt = *(WORD *)(nt + 20);
		u8 *sec = nt + 24 + opt;
		if (*(u32 *)nt != 0x00004550u) { /* "PE\0\0" */
			return;
		}
		for (WORD i = 0; i < sections; ++i, sec += 40) {
			u32 vsize = *(u32 *)(sec + 8), rva = *(u32 *)(sec + 12), flags = *(u32 *)(sec + 36);
			u32 m = 0;
			u8 *found;
			if (!(flags & 0x20000000u)) { /* IMAGE_SCN_MEM_EXECUTE */
				continue;
			}
			found = rg_find_scene_manager(base + rva, vsize, &m);
			if (found && !first) {
				first = found;
			}
			total += m;
		}
	} __except (1) {
		first = 0;
	}
	RG_U64(g_state.mailbox, MB_SCENE_MGR) = (total == 1) ? (u64)first : 0;
	RG_U32(g_state.mailbox, MB_SCENE_SIGS) = total;
}

static void start(void *module) {
	volatile u8 *mb = 0;
	u8 *base = (u8 *)GetModuleHandleA(0);
	void *pinned = 0;

	for (u32 i = 0; i < sizeof RG_MAILBOX_CANDIDATES / sizeof RG_MAILBOX_CANDIDATES[0] && !mb; ++i) {
		mb = (volatile u8 *)VirtualAlloc((void *)RG_MAILBOX_CANDIDATES[i], 0x1000, MEM_RESERVE | MEM_COMMIT, PAGE_READWRITE);
	}
	if (!mb || !base) {
		return; /* Lua finds no mailbox and keeps using the Nefarious City route */
	}
	g_state.base = base;
	g_state.mailbox = mb;
	rg_mailbox_init(mb, base);

	if (!rg_verify(base)) {
		RG_U32(mb, MB_STATUS) = RG_STATUS_WRONG_EXE;
		return;
	}
	rg_resolve(&g_state);

	/* v3: mission requests only when every mission-system byte matches too; items work either way */
	if (rg_verify_missions(base)) {
		rg_resolve_missions(&g_state);
		RG_U32(mb, MB_MISSIONS) = 1;
	}
	/* v5: armor pieces only when VanityGiveBundleAction's path matches byte for byte */
	if (rg_verify_vanity(base)) {
		rg_resolve_vanity(&g_state);
		RG_U32(mb, MB_VANITY) = 1;
	} else {
		RG_U32(mb, MB_ARMOR_HOOK) = RG_ARMOR_HOOK_NO_MATCH;
	}
	/* v6 (8.0): mission state records, the level mask and planetary travel, each only on a match */
	RG_U32(mb, MB_V6) = rg_verify_v6(&g_state);
	/* v5: the config manager, by signature over the exe's code sections */
	find_config_manager(base);
	/* v7: the SceneManager (read only; Lua reads the script variables through it) */
	find_scene_manager(base);

	/* never unloaded: rivet_hook frees "renderdoc" at exit while the game may still run */
	GetModuleHandleExA(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS | GET_MODULE_HANDLE_EX_FLAG_PIN, (const char *)&start, &pinned);
	(void)module;

	g_trampoline = (u8 *)VirtualAlloc(0, 0x1000, MEM_RESERVE | MEM_COMMIT, PAGE_EXECUTE_READWRITE);
	if (!g_trampoline) {
		RG_U32(mb, MB_STATUS) = RG_STATUS_HOOK_FAILED;
		return;
	}
	rg_build_trampoline(g_trampoline, base + RVA_SIGNAL_PUMP);
	g_original_pump = (pump_fn)g_trampoline;
	{
		DWORD old = 0;
		VirtualProtect(g_trampoline, 0x1000, PAGE_EXECUTE_READ, &old);
		FlushInstructionCache(GetCurrentProcess(), g_trampoline, 0x1000);
	}
	/* READY before the jump goes in: the first pump already sees a consistent mailbox */
	RG_U32(mb, MB_STATUS) = RG_STATUS_READY;
	if (!install_hook(base + RVA_SIGNAL_PUMP, g_state.vanity_ok ? base + RVA_VANITY_GIVE_HANDLER : 0)) {
		RG_U32(mb, MB_STATUS) = RG_STATUS_HOOK_FAILED;
	}
}

BOOL WINAPI DllMain(void *module, DWORD reason, void *reserved) {
	(void)reserved;
	if (reason == 1 /* DLL_PROCESS_ATTACH */) {
		start(module);
	}
	return 1;
}
