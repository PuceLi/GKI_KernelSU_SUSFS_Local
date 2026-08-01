# GKI_SUSFS build journal

Goal: link/build the Sultan kernel (Pixel Tensor G4 / zumapro) from
`kerneltoast/android_kernel_google_tensynos` (branch `16.0.0-sultan`) with
ReSukiSU + SUSFS + Droidspaces + BBG + NTSync, and produce a flashable zip.
After that, port to Pixel 9a (`tegu`): "GKI first (for testing) + Sultan->tegu later".

## Build runs

### GKI (Original, android14-6.1) — SUCCESS
- `30695107843` (job `6.1.145-2025-09`, clang + thin LTO via Bazel) — success.

### Sultan (workflow `sultan.yml`, GCC 14.2.0-nolibc, no LTO)
- `30695419130` — cancelled
- `30695473127` — failed (toolchain checkout order)
- `30695613705` — failed (sel_handle_status_ops / ReSukiSU static exports)
- `30696237941` — failed (LTO; fixed by `52eeef9`)
- `30697198348` — failed (gsa_core.c -Werror=nonnull; fixed by `46c7f9c`)
- `30698376528` — failed at step 16 `make vmlinux`:
  - `Unexpected GOT/PLT entries detected!`
  - `Unexpected run-time procedure linkages detected!`
  - `adb_root.o: in function 'ksu_adb_root_handle_execve_manual': undefined reference to 'task_stack_page'`

## Root cause (task_stack_page)

- Chain: `current_user_stack_pointer()` -> `user_stack_pointer(current_pt_regs())`
  -> `task_pt_regs(current)` (macros in `arch/arm64/include/asm/processor.h`)
  -> `task_stack_page()` (defined in `include/linux/sched/task_stack.h`).
- ReSukiSU `kernel/feature/adb_root.c` (~line 95) uses `current_user_stack_pointer()`
  but does NOT `#include <linux/sched/task_stack.h>`.
- `sucompat.c:17` and `syscall_hook_manager.c:13` DO include it and link fine.
- Stock GKI leaks the declaration transitively; Sultan tree does not, so GCC 14
  emits an external `task_stack_page` call -> undefined ref at vmlinux link.
- Kernel 6.1 predates `-Werror=implicit-function-declaration` (added in 6.2),
  so the missing declaration was only caught at link time, not compile time.

## Fixes / commits (branch `dev`)

- `c6bdaad` — BBG (Baseband Guard)
- `cb89707` — NTSync
- `70daa4e` — checkout before toolchain unpack
- `e771293` — export selinuxfs symbols (ReSukiSU: write_op, sel_handle_status_ops)
- `52eeef9` — disable GCC LTO (LTO_NONE)
- `46c7f9c` — gsa_core.c: guard memcpy with `if (cb && dst_buf)`
- next — sultan.yml sed step: inject `#include <linux/sched/task_stack.h>`
  into `drivers/kernelsu/feature/adb_root.c` (after `<asm/ptrace.h>`)

## Next steps

1. Push the adb_root.c include fix to `dev`.
2. User re-runs the Sultan workflow.
3. If still failing on task_stack_page, check other ReSukiSU files that use
   `current_user_stack_pointer`/`task_pt_regs` (e.g. `kernel/feature/sucompat.c`
   already OK) and extend the patch.
4. After green Sultan: port to `etnperlong/android_kernel_google_tegu`
   (branch `16.0.0-optimistic`).

## Reference material

- `/tmp/opencode/job_logs5.txt` — Sultan run `30698376528` log; link errors at
  lines 6805-6808.
- `/tmp/opencode/resukisu_git/` — ReSukiSU clone
  (`kernel/feature/adb_root.c`, `kernel/feature/sucompat.c:17`,
  `kernel/hook/syscall_hook_manager.c:13`).
- `/tmp/opencode/sultan_task_stack.h`, `sultan_arm64_processor.h` — Sultan headers
  confirming the macro chain.
- `.github/workflows/sultan.yml` — step 12 "Run sed Commands" hosts the fix.
- `.github/patches/sultan/` — sultan-susfs, sultan-droidspaces,
  sultan-resukisu-selinux-export patches.
