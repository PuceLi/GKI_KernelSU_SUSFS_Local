# BBRv3 patch — source & base compatibility notes

## Where the patch comes from

| field | value |
|---|---|
| repo | `TheWildJames/kernel_patches` (the "kernel_patches" submodule used by `WildKernels/GKI_KernelSU_SUSFS`) |
| path | `common/bbrv3/0001-net-tcp-backport-BBRv3-to-android14-6.1.patch` |
| author | `fatalcoder524` |
| introducing commit | `3a75d65` — "Add Full KABI compliant stable BBRv3 patches with required backports" |
| wired into WildKernels | `5442bb7` ("Split networking action into networking-config, bbrv3, and cifs sub-actions"), `e5a1cca` ("fix(bbrv3): add patches dir with BBRv3 backport patches"), `3daf87b`, `e5d06da` ("add @fatalcoder524 bbrv3") |

Content: full BBRv3 backport to android14-6.1 GKI common —
`net/ipv4/tcp_bbr3.c` (new, 2364 lines), `net/ipv4/tcp_plb.c` (new, 122 lines),
plus KABI/KMI-compliant hookups across 16 files (tcp.h, tcp_rate.c, tcp_input.c,
tcp_output.c, tcp_cong.c, tcp_minisocks.c, tcp_ipv4.c, sysctl_net_ipv4.c,
inet_diag.h, rtnetlink.h, Kconfig, Makefile).

Config enabled by the WildKernels bbrv3 action (gki_defconfig):
`CONFIG_TCP_CONG_ADVANCED=y`, `CONFIG_TCP_CONG_BBR3=y`.
The default TCP stack (DEFAULT_TCP_CONG, CONFIG_DEFAULT_BBR) is left untouched.

## Base compatibility check (2026-08-11)

Tested with `patch -p1 --dry-run --fuzz=0` on a fresh sparse clone of
`etnperlong/android_kernel_google_tegu` (default branch `16.0.0-optimistic`,
`SUBLEVEL = 157` → 6.1.157).

| file | result |
|---|---|
| include/linux/tcp.h | 1/1 hunk FAILED |
| include/net/tcp.h | 10/11 hunks FAILED |
| include/uapi/linux/inet_diag.h | 1/1 FAILED |
| include/uapi/linux/rtnetlink.h | 1/1 FAILED |
| net/ipv4/Kconfig | 1/3 FAILED |
| net/ipv4/Makefile | 1/2 FAILED |
| net/ipv4/sysctl_net_ipv4.c | 1/3 FAILED |
| net/ipv4/tcp.c | already applied (reversed match) |
| net/ipv4/tcp_cong.c | already applied (reversed match) |
| net/ipv4/tcp_input.c | 2/12 FAILED |
| net/ipv4/tcp_ipv4.c | 1/2 FAILED |
| net/ipv4/tcp_minisocks.c | already applied (reversed match) |
| net/ipv4/tcp_output.c | 6/6 hunks FAILED (Sultan rewrote tcp_output.c) |
| net/ipv4/tcp_plb.c | file already present in tree |
| net/ipv4/tcp_rate.c | 3/4 hunks FAILED |

### Conclusion

The Sultan tegu (and zumapro, same Sultan base / 6.1.157) tree has diverged from
the GKI `android14-6.1` common tree: Sultan already backported PLB
(`net/ipv4/tcp_plb.c` present, `tcp_plb.o` in Makefile) plus related TCP work,
and fully rewrote `tcp_output.c`. The upstream BBRv3 patch does **not** apply.

Therefore, on the Sultan/tegu path `use_bbrv3` is treated as a **documented
no-op**: the workflow logs a warning and skips the patch rather than failing the
build. BBRv3 remains fully supported on the "Original (GKI common)" / build.yml
path, where the patch applies cleanly.
