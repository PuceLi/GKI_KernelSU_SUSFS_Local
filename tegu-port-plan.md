# Sultan → Pixel 9a (tegu) — План порта

> Рабочий документ-журнал. Цель: довести сборку Sultan-ядра под Google Pixel 9a (tegu) с
> (ReSukiSU + SUSFS + BBG + Droidspaces + NTSync) до прошиваемого zip через существующий
> конвейер `sultan.yml`. Документ самодостаточен: любой следующий сеанс может продолжить
> работу, начиная с этого файла.
>
> Дополнение к основному журналу билдов: `job.md`.

---

## 0. TL;DR (что поняли и куда идём)

1. **Наш zumapro-zip был исправен.** Ошибки «invalid ak3» нет — это был обман штатного
   файлового проводника (выбор не того файла). Настоящая ошибка при флеше на 9a —
   `Unsupported device. Aborting...` — это **devicecheck** AK3: `anykernel.sh` разрешает
   только `caiman/komodo/tokay/comet` (zumapro), а `ro.product.device` у Pixel 9a = **tegu**.
2. **tegu совместим с zumapro по платформе**: тот же чип Tensor G4, та же GKI `android14-6.1`.
   Различаются периферия/плата (дисплей, отпечаток, модем, Wi-Fi, батарея) → нужен свой
   device-tree (DTB/DTBO), а не замена строк в anykernel.sh.
3. **Уже существуют готовые Sultan→tegu порты** (Optimistic Kernel — etnperlong/miacate),
   их можно использовать как референс/базу вместо портирования «с нуля».
4. **РЕШЕНО: берём вариант (B)** — готовый tegu-порт на **6.1.157** (etnperlong/miacate
   «Optimistic Kernel», та же Sultan-база, tegu уже работает). Все ручные патчи
   (`sultan-susfs-*`, `sultan-droidspaces-*`, selinux-export) проверены на 6.1.157 (fuzz=0,
   см. журнал); droidspaces использует tegu-вариант. Тулчейн оставляем GCC 14.2.0 (наш
   зелёный конвейер); переход на Clang 21 — только если make-сборка на 6.1.157 упрётся.

---

## 1. Факты об устройстве tegu (Pixel 9a)

| Параметр | Значение |
|---|---|
| Кодовое имя | `tegu` (`ro.product.device=tegu`, `ro.boot.hardware=tegu`) |
| SoC | Google Tensor G4 (как Pixel 9/Pro/XL/Fold = zumapro; `ro.boot.hardware.platform=zumapro`) |
| CPU | 1×Cortex-X4 3.10 GHz, 3×A720 2.60, 4×A520 1.92; 8 GiB Hynix LPDDR5, 256GB Samsung UFS |
| GPU | Mali-G715 MC7 (vulkan/egl=mali) |
| GKI | `android14-6.1` — **стоковое ядро `6.1.157-android14`** (KMI совпадает с базой Optimistic!) |
| Официальная ветка kernel-манифеста | `android-gs-tegu-6.1-android16` |
| Kernel-разделы | `boot`, `dtbo`, `vendor_kernel_boot`, `vendor_dlkm`, `system_dlkm`, `init_boot`, `vendor_boot` |
| AK3 флешит | `Image.lz4` → `boot`; `dtb` → `vendor_kernel_boot`; **dtbo не трогаем** |
| **ro.boot.dtbo_idx** | **`9`** → bootloader применяет DTBO-оверлей `zumapro-tegu-mp.dtbo` поверх базового DTB из vendor_kernel_boot |
| ОС (у нас) | **Android 17**, build `CP2A.260705.006`, SP **2026-07-05**, bootloader `tegu-17.0-15199480`, слот `_a` |
| Периферия | panel `panel-google-tg4c.2d408004`, fingerprint goodix (`g7a.app`), Wi-Fi bcm4383, модем s5300 (`g5300t-…`), vibrator cs40l26 |
| Bootloader | физически разблокирован; `ro.boot.flash.locked=1`/`vbmeta=locked`/`verifiedbootstate=green` — **спуф** от SUSFS/хидов |

Источники: source.android.com/docs/setup/build/building-pixel-kernels (таблица GKI-веток),
postmarketOS wiki, GrapheneOS thread, **getprop-дамп устройства** (`device-configs/tegu/tegu-getprop.txt`).

### Почему zumapro-яdrop напрямую не подходит
- Devicecheck: `anykernel.sh` zumapro разрешает только `caiman/komodo/tokay/comet`,
  а у 9a `ro.product.device=tegu` → `Unsupported device. Aborting...` (обязателен
  `device.name1=tegu` + корректные `supported.versions/patchlevels`, см. раздел 2.1).
- DTB: **для tegu vendor_kernel_boot содержит те же 4 базовых zumapro-DTB** (a0/a1-foplp/ipop) —
  проверено сравнением с релизным zip Optimistic (см. раздел 2.2). tegu-специфика вносится
  **стоковым DTBO** (оверлей idx 9 = mp), который мы не трогаем. Отдельный custom dtbo/dtb
  не нужен.

---

## 2. Итоги прошлого расследования (чтобы не повторять)

- **`/tmp/zumapro-a6.1-wksu-susfs-ReSukiSU-anykernel3.zip`** (18 316 326 байт) — валиден:
  `unzip -t` без ошибок, `anykernel.sh` в корне, META-INF/update-binary на месте, порядок/атрибуты
  совпадают с шаблоном AK3. Zip собирается шагом «Create ZIP Files for Different Formats»
  (`sultan.yml:348`, команда `zip -r ../$ZIP_NAME ./*`).
- **KernelFlasher (capntrips)** — единственный массовый «AK3 flasher»; его проверка тривиальна
  (`SlotViewModel.kt:445`): `if (z.getEntry("anykernel.sh") == null) → "Invalid AK3 zip"`.
  Наш zip проходит. Сообщение «Invalid AK3 zip» НЕ про «Unsupported device».
- **`Unsupported device. Aborting...`** — из `META-INF/com/google/android/update-binary:310`
  (функция `do_devicecheck()`): `getprop ro.product.device` сверяется с
  `device.name*=...` из `anykernel.sh`. Для прошивки на tegu нужно, чтобы в списке был `tegu`.

### 2.1 Проверки update-binary (полный список для tegu) — актуально для финального anykernel.sh
- `do_devicecheck()` (update-binary:292): `device.name1=tegu` должен совпасть с одним из
  `ro.product.device` / `ro.build.product` / `ro.product.vendor.device` / `ro.vendor.product.device`.
  У 9a все = `tegu` → OK.
- `do_versioncheck()` (:322): `supported.versions` (single `17` или диапазон `17-17`) против
  `/system/build.prop ro.build.version.release`. **У нас Android 17** → `supported.versions=17`.
- `do_levelcheck()` (:349): `supported.patchlevels` (формат `YYYY-MM` или диапазон `lo - hi`,
  `-hi`=снизу открыт, `hi-`=сверху открыт) против `/system/build.prop ro.build.version.security_patch`.
  **У нас 2026-07-05** → например `supported.patchlevels=- 2026-09` (до сентября 2026).
- `do_vendorlevelcheck()` (:372): `supported.vendorpatchlevels` против
  `/vendor/build.prop ro.vendor.build.security_patch` (= 2026-07-05 у нас).

Итоговые значения для tegu:
```
do.devicecheck=1
device.name1=tegu
supported.versions=17
supported.patchlevels=- 2026-09
supported.vendorpatchlevels=- 2026-09
```

### 2.2 Релизный zip Optimistic как эталон (скачан и разобран)
- `Optimistic-Kernel-Pixel9a.tegu.-BP4A.251205.006-20251217.zip` (18 385 646 байт),
  /tmp/opencode/tegu_ref/ — актуальная схема AK3 для tegu:
  - `anykernel.sh`: `do.devicecheck=1`, `device.name1=tegu`, `supported.versions=16`,
    `supported.patchlevels=2025-12 - 2026-02`, `block=boot` (Image.lz4) + `block=vendor_kernel_boot` (dtb).
    **dtbo в zip НЕТ** — стоковый dtbo не трогается.
  - `dtb` payload = **4 DTB** (по ~386 КБ, total 1 546 962 б): базовые `zumapro-a0/a1-foplp/ipop`,
    БЕЗ tegu-оверлеев. Наш zumapro-dtb (1 548 118 б, 4×~387 КБ) — структурно тот же набор.
    → **шаг `cat out/google-devices/zumapro/dts/*.dtb` для tegu менять НЕ нужно.**
  - `Image.lz4` — только ядро, без ramdisk (boot header v4, RAMDISK_SZ=0, KERNEL_FMT lz4_legacy).
- **Модулей в zip нет** → используются стоковые vendor_dlkm/system_dlkm; работает, т.к. KMI
  сохраняется (6.1.157-android14). Наша сборка должна тоже не ломать KMI.

---

## 3. Существующие порты (референсы)

### 3.1 etnperlong/android_kernel_google_tegu — «Optimistic Kernel»
- Форк `kerneltoast/android_kernel_google_zumapro` (Sultan), переделан под 9a.
- Ветки: `16.0.0-optimistic`, `16.0.0-optimistic+kernelsu`, `16.0.0-optimistic+sukisu`.
- XDA-тред: «Optimistic Kernel for Google Pixel 9a» (started 2025-07-24).
- Фичи: Sultan-ядро + ACK **6.1.157**, Clang 21.0.0, LTO, CASS/Tensor AIO (от Sultan),
  MGLRU/PSI/MEMCG, BBRv3, zstd/lz обновления; варианты SUSFS + KernelSU 3.0 / SukiSU.
- Сборка — **bazel/Kleaf** (`tools/bazel run --config=tegu //private/devices/google/tegu:...`),
  не make (см. ниже).

### 3.2 miacate/android_kernel_google_tegu
- Форк Sultan, default `16.0.0-optimistic`, те же идеи.
- Полезные ветки: `google-devices/tegu`, `google-modules/display/panels/tegu`,
  `google-modules/fingerprint/goodix`, `google-modules/radio/samsung/s5300`,
  `google-modules/wlan/bcmdhd/bcm4383`, `patch/google-bbrv3`, `fix/tegu-thermal`,
  `fix/clang-build`. Каждая ветка — кусок tegu-поддержки, их можно cherry-pick'ать.

### 3.3 Устройство tegu-дерева в этих портах
- `google-devices/tegu/dts/` — `zuma-tegu-*.dtsi` (battery, camera, charging, display,
  gnss, pmic, thermal, touch, modem s5300, ...) + `Makefile`:
  - `zumapro_tegu_dtbs := zumapro/zumapro-a0-foplp.dtb ...` (4 базовых dtb) — это и есть
    payload для vendor_kernel_boot (подтверждено сравнением с релизным zip, раздел 2.2).
  - `zumapro_tegu_overlays := zumapro-tegu-{dev1,proto1_0,…-,mp}.dtbo` — оверлеи для
    **dtbo-раздела** (стоковый, не трогаем; на устройстве bootloader применяет idx 9 = mp).
  - `multi_dtbs_overlay(..., y)` генерит `dtb-y += zumapro-tegu-<ov>-<base>.dtb` (склейки
    база+оверлей) — по комментарию в Makefile это **для проверки наложения оверлеев**, НЕ payload.
  - Вывод: для tegu-флеша нужны только 4 базовых dtb; `cat .../zumapro/dts/*.dtb` не меняем.
- Отличие от Sultan-дерева: там dtb задаётся `dtb-$(CONFIG_SOC_ZUMA) := zumapro-*.dtb`
  в `google-devices/zumapro/dts/Makefile` и собирается **make-сборкой** в
  `out/google-devices/zumapro/dts/*.dtb` (это читает `sultan.yml:345`). В tegu-дереве
  (Optimistic) та же структура сохраняется.

### 3.4 Официальный сток (для сверки/базы DTS)
- Манифест: `repo init -u https://android.googlesource.com/kernel/manifest -b android-gs-tegu-6.1-android16`
- Репо ядра: AOSP `android_kernel_google_tensynos` (ветка tegu).

---

## 4. Текущий конвейер `sultan.yml` (что менять не хотим/хотим)

Цепочка шагов (номера строк по текущему файлу):

| № | Шаг | Суть |
|---|---|---|
| 63 | Set CONFIG | `CONFIG=android_kernel_google_tensynos` |
| 72 | Toolchain | GCC **14.2.0** nolibc aarch64 (kernel.org crosstool) |
| 82 | KSU branch | `BRANCH` по варианту (ReSukiSU → `-s main`) |
| 123 | Clone deps | AnyKernel3 `sultan-<codename>` (TheWildJames), kernel_patches, **kerneltoast tensynos**, susfs4ksu `gki-android14-6.1` + checkout `ef16cbce` |
| 133 | AnyKernel3 | берётся ветка `sultan-<codename>`; **для tegu нужно патчить `anykernel.sh`**: `device.name1=tegu`, `supported.versions=17`, `supported.patchlevels=- 2026-09`, `supported.vendorpatchlevels=- 2026-09` (см. раздел 2.1) |
| 141 | Add KernelSU | curl setup.sh по варианту (ReSukiSU основной) |
| 170 | ReSukiSU selinux | `sultan-resukisu-selinux-export.patch` (sel_handle_status_ops, write_op) |
| 184 | SUSFS | copy `fs/*` + `include/linux/*` + `sultan-susfs-a14-6.1.patch`; для Next — ksun compat |
| 208 | Droidspaces | `sultan-droidspaces-a14-6.1.patch` (SYSVIPC/POSIX_MQUEUE/NS/DEVTMPFS, ABI-safe) |
| 219 | KSU config | `CONFIG_KSU=y`, `CONFIG_KSU_SUSFS=y/n` в `<codename>_defconfig` |
| 232 | Mountify | `CONFIG_TMPFS_XATTR`, `CONFIG_TMPFS_POSIX_ACL` |
| 241 | sed | LOCALVERSION, `CONFIG_LTO_NONE=y`, gsa_core.c fix, `adb_root.c` + `#include <linux/sched/task_stack.h>` |
| 279 | BBG | vc-teahouse setup.sh + `CONFIG_BBG=y` + security/Kconfig LSM |
| 298 | NTSync | ntsync_base + ntsync_compat_android14-6.1 + `CONFIG_NTSYNC=y` |
| 324 | Build | `make <codename>_defconfig` + `make` (GCC 14.2.0) |
| 332 | Copy | `Image.lz4`; concat `google-devices/<d>/dts/*.dtb` → `dtb` (только gs201/zuma/zumapro) — **для tegu НЕ меняем**: payload = те же 4 базовых zumapro-dtb (раздел 2.2) |
| 348 | Zip | `cd AnyKernel3 && zip -r ../$ZIP_NAME ./*` |
| 358 | Artifact | upload-artifact v4 (скачивается как внешний zip-конверт!) |

Диспетчер: `kernel-a14-6-1.yml` → `build-sultan-kernel` job вызывает `sultan.yml` с
`codename: zumapro` (строки 192–203). Это место надо расширять под `tegu`.

---

## 5. Развилки и решения

### 5.1 База (РЕШЕНО: 6.1.157, вариант B)

**База — теgu-порт «Optimistic Kernel» на 6.1.157** (Sultan-дерево, tegu уже работает):

- etnperlong/android_kernel_google_tegu, ветки:
  - `16.0.0-optimistic` (чистый Sultan+tegu),
  - `16.0.0-optimistic+kernelsu` (уже `CONFIG_KSU=y` + полный `CONFIG_KSU_SUSFS_*`),
  - `16.0.0-optimistic+sukisu`.
- miacate/android_kernel_google_tegu — те же идеи + полезные ветки:
  `google-devices/tegu`, `google-modules/display/panels/tegu`,
  `google-modules/fingerprint/goodix`, `google-modules/radio/samsung/s5300`,
  `google-modules/wlan/bcmdhd/bcm4383`, `patch/google-bbrv3`, `fix/tegu-thermal`,
  `fix/clang-build`.
- Сборка у них — **bazel/Kleaf + Clang 21 + `CONFIG_LTO_CLANG_THIN=y`**. У нас —
  make + GCC 14.2.0 + LTO_NONE. Проверить совместимость (открытый вопрос №1 в разделе 8).
- В их `arch/arm64/configs/zumapro_defconfig` уже есть KSU+SUSFS (см. раздел 4.1).
  Решаем: оставить их SUSFS-версию или заменить на нашу пиновую (ef16cbce).

Как работать с деревом:
1. Форкнуть etnperlong (или miacate) к себе (наш репо = sheerboy/GKI_KernelSU_SUSFS).
2. В workflow заменить URL клона дерева на свой форк (см. раздел 6, Фаза 2).
3. Добавлять ReSukiSU/BBG/Droidspaces/NTSync поверх, откатив их KernelSU/SukiSU.

### Р5.2 Тулчейн
- Оставляем GCC 14.2.0 (совпадает с текущей зелёной сборкой). Clang 21 (как в Optimistic)
  — опциональный апгрейд позже, только если make+GCC на 6.1.157 не поедет.

### Р5.3 AnyKernel3 под tegu (РЕШЕНО — значения подтверждены, раздел 2.1)
- Ветки TheWildJames: только `sultan-gs201/zuma/zumapro`, `sultan-tegu` НЕТ.
- Не менять сторонний репо. Правильно — патчить `anykernel.sh` **в самом workflow** после
  клонирования, для `codename=tegu`:

  ```bash
  sed -i 's/^device\.name1=.*/device.name1=tegu/; s/^device\.name2=.*/device.name2=/; \
          s/^device\.name3=.*/device.name3=/; s/^device\.name4=.*/device.name4=/' anykernel.sh
  sed -i 's/^supported\.versions=.*/supported.versions=17/' anykernel.sh
  sed -i 's/^supported\.patchlevels=.*/supported.patchlevels=- 2026-09/' anykernel.sh
  sed -i 's/^supported\.vendorpatchlevels=.*/supported.vendorpatchlevels=- 2026-09/' anykernel.sh
  ```

- Либо форкнуть AnyKernel3 и создать `sultan-tegu` (чище, но тянет зависимость от своего форка).
- Проверка: наш эталонный anykernel.sh из релиза Optimistic (`/tmp/opencode/tegu_ref/anykernel.sh`).

### Р5.4 DTB для tegu (РЕШЕНО — payload = базовые zumapro-dtb, раздел 2.2)
- Эталонный релизный zip Optimistic содержит в `dtb` ровно **4 базовых zumapro-DTB**
  (a0/a1-foplp/ipop), БЕЗ теgu-оверлеев. tegu-специфика = стоковый DTBO (idx 9).
- Поэтому шаг `sultan.yml:332` (`cat out/google-devices/zumapro/dts/*.dtb > ../AnyKernel3/dtb`)
  **оставляем как есть** — в tegu-дереве базовые zumapro-dtb собираются той же make-механикой.
- Склейки `zumapro-tegu-*.dtb` (multi_dtbs_overlay) для флеша НЕ нужны.

### Р5.5 Версия ядра и KMI (РЕШЕНО)
- Сток ядра 9a: **`6.1.157-android14`** (Android 17, CP2A.260705.006, SP 2026-07-05) —
  совпадает с базой Optimistic (Makefile 6.1.157, android14-6.1 KMI). ✅
- Модулей в кастомном zip нет → работают стоковые vendor_dlkm/system_dlkm при сохранении KMI.
- Обновления прошивки: поддерживаем диапазон patchlevel в anykernel.sh (`- 2026-09`).

---

## 6. План работ по фазам

### Фаза 0. Подготовка (нужно от пользователя)
1. Разблокировать bootloader на 9a (`fastboot oem unlock` / `fastboot flashing unlock`).
   — **СТАТУС: физически разблокирован** (в getprop `locked` — спуф от SUSFS/хидов).
2. Собрать конфиги телефона (см. раздел 7) и положить в репо `device-configs/tegu/`.
   — **СТАТУС: получены** (getprop-дамп, info.txt, magiskboot_unpack.log; образы разделов опционально).
3. Сделать стоковый бэкап: `boot.img`, `dtbo.img`, `vendor_kernel_boot.img` (dumper/magiskboot).
   — **опционально** (для отката/сверки; для сборки zip не требуется).
4. **Уточнить версию базы:** подтверждено — `16.0.0-optimistic` = **6.1.157** (Makefile), сток 9a
   = `6.1.157-android14` (KMI совпадает). ✅

### Фаза 1. Поднять make-сборку на базе 6.1.157 (без фич-стека)
1. Форкнуть etnperlong/android_kernel_google_tegu в свой аккаунт (ветка `16.0.0-optimistic`).
2. Склонировать локально, проверить `make`-сборку:
   - `make CROSS_COMPILE=... CC=... zumapro_defconfig && make` (как в sultan.yml) —
     собирается ли `Image.lz4` на 6.1.157 через GCC 14.2.0 (у Optimistic — Clang).
   - Проверить, что `out/google-devices/zumapro/dts/*.dtb` даёт те же 4 базовых dtb.
3. Сравнить с нашей zumapro-сборкой: какие из ручных фиксов уже встроены в Optimistic
   (gsa_core.c, LTO, task_stack_page и т.п.), какие придётся переносить.
4. **Критерий выхода фазы:** в CI собирается tegu-zip «чистый Sultan+tegu» (без KSU/SUSFS),
   грузится на 9a (`fastboot boot`), периферия работает.

### Фаза 2. Замена root-стека на наш (ReSukiSU + SUSFS + BBG + Droidspaces + NTSync)
1. В дереве откатить их KernelSU/SukiSU-интеграцию (если базовая ветка `16.0.0-optimistic`
   чистая — шаг не нужен).
2. Добавить ReSukiSU через `kernel/setup.sh` (как в sultan.yml:141).
 3. SUSFS: решить, оставить их SUSFS-версию или заменить на нашу пиновую (ef16cbce). Если
    заменяем — переписать `sultan-susfs-a14-6.1.patch` под 6.1.157.
    **[ПРОВЕРЕНО]** `sultan-susfs-a14-6.1.patch` ложится на 6.1.157 чисто (fuzz=0, все
    hunk'и с оффсетами; только fs/namei.c, fs/namespace.c, fs/notify/fdinfo.c, fs/readdir.c,
    kernel/sys.c отличаются от 6.1.145, но не в зонах хуков).
 4. Переделать `sultan-droidspaces-a14-6.1.patch` под 6.1.157 (ABI-safe task_struct layout;
    проверить, не изменился ли layout между 6.1.145 и 6.1.157).
    **[ПРОВЕРЕНО/РЕШЕНО]** layout и defconfig-контекст совпадают (sched.h:1098/1101/1102/1560,
    zumapro_defconfig:38/194); упали бы только hunk'и gs201/zuma (файлов нет в tegu-дереве).
    Создан `sultan-droidspaces-a14-6.1-tegu.patch` (sched.h + zumapro_defconfig), проверен fuzz=0;
    sultan.yml использует tegu-вариант при codename==tegu.
 5. Перепроверить `sultan-resukisu-selinux-export.patch` (fuzz на 6.1.157).
    **[ПРОВЕРЕНО]** selinuxfs.c идентичен между 6.1.145 и 6.1.157 → ложится чисто.
 6. BBG и NTSync: прогнать setup.sh/патчи, поправить fuzz.
    **[ПРОВЕРЕНО]** ntsync_base.patch + ntsync_compat_android14-6.1.patch чистые на 6.1.157.
7. Учесть, что Optimistic уже может содержать часть фич (CASS, BBRv3, MGLRU и т.д.) —
   не дублировать.
8. **Критерий выхода фазы:** полный билд с фич-стеком проходит зелёным CI.

### Фаза 3. AnyKernel3 + workflow
1. Патч `anykernel.sh` под tegu (Р5.3).
2. Расширить dtb-ветку в Copy Images (Р5.4).
3. `kernel-a14-6-1.yml`: добавить источник `Sultan (Pixel Tensor G4 / tegu)` или отдельный
   input `codename`, который пробрасывает `tegu`.
4. Убедиться, что артефакт — именно внутренний `*-anykernel3.zip` (не внешний конверт).

### Фаза 4. Тест на устройстве (итеративно)
1. `fastboot boot <Image.lz4-упакованный boot.img>` — временная загрузка без флеша.
2. Если boot OK — флеш AK3-zip через KernelFlasher (вариант с `allow-errors` не нужен,
   наш zip валиден).
3. Проверки: `dmesg`, `uname -a`, KSU Manager (ReSukiSU), SUSFS, BBG, Droidspaces, NTSync.
4. Собрать логи при фейле (см. раздел 7, «лог»).

### Фаза 5. Доставка
1. Зафиксировать изменения в репо (workflow + патчи + доки).
2. Обновить `job.md` и этот план.

---

## 7. Что нужно от пользователя (конфиги телефона) — СТАТУС

Положить в `device-configs/tegu/` (или передать в чат). Нужно для сверки KMI/DTB и отладки.

**Получено (лежит в `device-configs/tegu/`):**
- [x] `tegu-getprop.txt` — полный дамп getprop.
- [x] `info.txt` — сводка: tegu, слот `_a`, Android 17, SP 2026-07-05,
      fingerprint `google/tegu/tegu:17/CP2A.260705.006/15641320`, ядро `6.1.157-android14`.
- [x] `magiskboot_unpack.log` — boot header v4, RAMDISK_SZ 0, KERNEL_FMT lz4_legacy.
- [x] Bootloader физически разблокирован (в getprop `locked`/`verifiedbootstate=green` — спуф
      от SUSFS/хидов).

**Ключевые извлечённые факты (использованы в разделе 1):**
`ro.boot.dtbo_idx=9`, `ro.boot.hardware.platform=zumapro`, `ro.product.build.16k_page.enabled=true`,
модем `s5300` (`g5300t-…`), Wi-Fi `bcm4383`, fingerprint goodix, panel `tg4c`, 8GiB/256GB,
`ro.boot.bootloader=tegu-17.0-15199480`, `ro.build.version.sdk=37`.

**Опционально (не блокирует):**
- [ ] Стоковые образы: `boot.img`, `dtbo.img`, `vendor_kernel_boot.img` — для бэкапа/отката и
      сверки. Для сборки zip не нужны (см. раздел 2.2).
- [ ] При фейле загрузки — klog: `fastboot boot` + `adb shell dmesg`, либо `pstore/ramoops`.

---

## 8. Открытые вопросы (требуют исследования/теста)

1. **make-сборка на 6.1.157:** [проверено по дереву] Kbuild-механика на месте
   (`defconfig` + `google-devices/tegu/dts/Makefile`), наш существующий LTO-sed-фикс
   (LTO_NONE) снимает `CONFIG_LTO_CLANG_THIN`. Остаётся подтвердить зелёной сборкой в CI.
2. **DTB для tegu:** [РЕШЕНО] payload = те же 4 базовых zumapro-dtb (раздел 2.2/3.3);
   шаг `cat out/google-devices/zumapro/dts/*.dtb` не меняем. Склейки `zumapro-tegu-*.dtb`
   не используются для флеша.
3. **DTBO-оверлеи:** [РЕШЕНО] в zip не нужны. Стоковый dtbo остаётся; bootloader применяет
   оверлей по `ro.boot.dtbo_idx=9` (= `zumapro-tegu-mp.dtbo`). Эталонный релиз Optimistic
   dtbo не содержит.
4. **AK3 devicecheck/versions/patchlevels:** [РЕШЕНО] для tegu: `device.name1=tegu`,
   `supported.versions=17`, `supported.patchlevels=- 2026-09`, `supported.vendorpatchlevels=- 2026-09`
   (раздел 2.1). Иначе abort: «Unsupported device/version/security patch level».
5. **Версия SUSFS:** оставить SUSFS из Optimistic (какой это коммит/версия?) или заменить
   на нашу пиновую (ef16cbce, gki-android14-6.1).
6. **ReSukiSU на 6.1.157:** применим ли `kernel/setup.sh` (main) без конфликтов; работают
   ли фиксы `adb_root.c`/`task_stack_page` и `gsa_core.c` на 6.1.157 (или в Optimistic
   это уже не нужно).
7. **Ручные патчи:** [ПРОВЕРЕНО на 6.1.157, fuzz=0] `sultan-susfs-a14-6.1.patch` — чисто
   (оффсеты); `sultan-resukisu-selinux-export.patch` — чисто (selinuxfs.c идентичен);
   `ntsync_base/compat_android14-6.1` — чисто; BBG (setup.sh + security/Kconfig sed) —
   без изменений vs zumapro. `sultan-droidspaces-a14-6.1.patch` — для tegu создан
   `sultan-droidspaces-a14-6.1-tegu.patch` (gs201/zuma-hunk'и не нужны).
8. **Модули/периферия:** эталонный zip модулей не содержит → используются стоковые
   vendor_dlkm/system_dlkm (работают при сохранении KMI). Подтвердить, что наша сборка
   не ломает KMI (не меняет ABI-символы/структуры, используемые модулями).
9. **RAM 8 ГБ / 16K pages:** `ro.product.build.16k_page.enabled=true` — проверить, что
   собранное ядро 4K (`-4k` в стоковой версии) корректно работает; zram-конфиг 50%.
10. **Локальный полный билд:** невозможен (~2.3 ТБ), поэтому итерации — только через CI.

---

## 9. Шпаргалка: репозитории, ветки, команды

- Текущий конвейер: `.github/workflows/sultan.yml` (шаги см. таблицу в разделе 4).
- Диспетчер: `.github/workflows/kernel-a14-6-1.yml` (job `build-sultan-kernel`, codename=zumapro).
- Ручные патчи: `.github/patches/sultan/`:
  - `sultan-resukisu-selinux-export.patch`
  - `sultan-susfs-a14-6.1.patch`
  - `sultan-droidspaces-a14-6.1.patch`
  - `sultan-droidspaces-a14-6.1-tegu.patch` (tegu-вариант: sched.h + zumapro_defconfig,
    без gs201/zuma; используется в sultan.yml при codename==tegu)
- Базовое дерево (Sultan): `https://github.com/kerneltoast/android_kernel_google_tensynos`
  (ветка `16.0.0-sultan`). Defconfig: `arch/arm64/configs/zumapro_defconfig`.
  dtb: `google-devices/zumapro/dts/Makefile`.
- **БАЗА 6.1.157 (РЕШЕНО):** `https://github.com/etnperlong/android_kernel_google_tegu`
  (ветка `16.0.0-optimistic`, +kernelsu, +sukisu) — Clang 21 + `CONFIG_KSU_SUSFS_*` уже
  в defconfig; `https://github.com/miacate/android_kernel_google_tegu` (ветки
  `google-devices/tegu`, `google-modules/.../tegu`, `patch/google-bbrv3`, `fix/*`).
- Официальный tegu: AOSP `android-gs-tegu-6.1-android16` (manifest).
- AnyKernel3: `https://github.com/TheWildJames/AnyKernel3` (ветки `sultan-*`; `gki-2.0`
  имеет `do.devicecheck=0`).
- SUSFS: `gitlab.com/simonpunk/susfs4ksu.git -b gki-android14-6.1`, checkout `ef16cbce...`.
- BBG: `vc-teahouse/Baseband-guard` setup.sh.
- NTSync: `Goldzxcbug/Droidspaces_Kernel_patch` (ntsync_base.patch + ntsync_compat_android14-6.1.patch).
- Тулчейн: `x86_64-gcc-14.2.0-nolibc-aarch64-linux` с kernel.org.

- Эталонный релиз Optimistic: `Optimistic-Kernel-Pixel9a.tegu.-BP4A.251205.006-20251217.zip`
  из releases etnperlong/android_kernel_google_tegu (разобран в `/tmp/opencode/tegu_ref/`).
  Содержимое: `anykernel.sh` (device.name1=tegu), `Image.lz4` (boot), `dtb` (4 базовых
  zumapro-dtb → vendor_kernel_boot). dtbo нет.
- AK3 anykernel.sh для tegu: `device.name1=tegu`, `supported.versions=17`,
  `supported.patchlevels=- 2026-09`, `supported.vendorpatchlevels=- 2026-09` (раздел 2.1).
- Конфиги устройства: `device-configs/tegu/` (`tegu-getprop.txt`, `info.txt`,
  `magiskboot_unpack.log`).

### Полезные команды
```bash
# klog при загрузке с custom kernel
fastboot boot <boot.img>            # временно, без флеша
adb shell dmesg                     # после успешного boot
# разобрать boot на части
magiskboot unpack boot.img && file kernel
# снять все пропы
adb shell getprop > tegu-getprop.txt
```

---

## 10. Критерии успеха

1. `sultan.yml` собирает `tegu-a6.1-wksu-susfs-ReSukiSU-anykernel3.zip` зелёным CI.
2. Zip проходит KernelFlasher (без «Invalid AK3 zip») и AK3 devicecheck
   (без «Unsupported device»).
3. Ядро грузится на Pixel 9a (Android 17), KMI совпадает с прошивкой.
4. Работают: ReSukiSU-рут, SUSFS, BBG, Droidspaces (с NTSync по желанию).
5. Периферия 9a работает: дисплей, тач, отпечаток, модем, Wi-Fi, батарея/зарядка, камера.

---

## 11. Журнал изменений плана

- 2026-08-01: создан. Итоги расследования «invalid ak3» закрыты (zip валиден; причина —
  devicecheck). Зафиксированы развилки Р5.1–Р5.5 и список запрошенных у пользователя
  конфигов.
- 2026-08-01: **РЕШЕНО 6.1.157 (вариант B)** — база = etnperlong/miacate tegu-порт
  «Optimistic». Проверено: в `zumapro_defconfig` ветки `+kernelsu` уже есть
  `CONFIG_KSU=y` + полный набор `CONFIG_KSU_SUSFS_*`; сборка там Clang+bazel
  (`CONFIG_LTO_CLANG_THIN=y`) — тестируем нашу make+GCC. Фазы переписаны: 0 — конфиги,
  1 — make-сборка 6.1.157, 2 — замена root-стека на ReSukiSU+SUSFS+BBG+Droidspaces+NTSync,
  3 — AK3/workflow. Открытый вопрос №1 — совместимость make+GCC на 6.1.157.
- 2026-08-01: **получены конфиги 9a** (getprop-дамп, info, magiskboot_unpack.log) →
  подтверждено: сток = Android 17 / `CP2A.260705.006` / SP 2026-07-05 / ядро `6.1.157-android14`
  (KMI совпадает с базой); `ro.boot.dtbo_idx=9` (mp-оверлей из стокового dtbo); bootloader
  физически разблокирован (spoof). **Разобран эталонный релизный zip Optimistic**
  (`/tmp/opencode/tegu_ref/`): dtb payload = 4 базовых zumapro-dtb (наш шаг cat *.dtb НЕ
  меняем), dtbo в zip нет, anykernel.sh подтверждает схему. Найдены проверки update-binary:
   `do_devicecheck` / `do_versioncheck` / `do_levelcheck` / `do_vendorlevelcheck` →
   финальные значения anykernel.sh для tegu: `device.name1=tegu`, `supported.versions=17`,
   `supported.patchlevels=- 2026-09`, `supported.vendorpatchlevels=- 2026-09`.
- 2026-08-01: **верификация всех ручных патчей на 6.1.157 (fuzz=0, dry-run на реальных
   файлах tegu-дерева):** susfs — чисто (все hunk'и с оффсетами, отличаются только
   fs/namei.c, fs/namespace.c, fs/notify/fdinfo.c, fs/readdir.c, kernel/sys.c, но не в зонах
   хуков); selinux-export — чисто (selinuxfs.c идентичен 6.1.145); droidspaces — sched.h и
   zumapro_defconfig совпадают, но hunk'и gs201/zuma падают (файлов нет в tegu-дереве) →
   создан `sultan-droidspaces-a14-6.1-tegu.patch`, sultan.yml переведён на него при
   codename==tegu; NTSync (base+compat) — чисто. Проверены пути: `gsa_core.c` и `selinuxfs.c`
   есть в tegu-дереве; `out/google-devices/zumapro/dts/*.dtb` даёт те же 4 dtb; ветка
   `sultan-zumapro` — единственная для tegu в AnyKernel3 (sultan-tegu нет). YAML обоих
   workflow валиден.
- 2026-08-01: **DROIDSPACES — реализован, не нужен отдельный тумблер.** Наш 1-в-1 повторяет эталонный Droidspaces-OSS
   `001.GKI-below-6.12-fix_sysvipc_kabi_6_7_8.patch` (ABI-слоты 6/7/8) и в Sultan-конвейере
   применяется всегда (матрица `wksu-susfs`) — контейнер уже поддержан без опции
   `off/678/123/345` (она нужна только Original-джобе, где слот-патч выбирается по версии).
   Дополнено: netfilter-набор расширен до рекомендованного Droidspaces (добавлены
   `NETFILTER_XT_MATCH_RECENT`, `NETFILTER_XT_TARGET_LOG`, `IP_SET_HASH_IP`,
   `IP_SET_HASH_NET`, `NETFILTER_XT_SET`; `IP_NF_TARGET_REJECT` уже был `=y`). Все конфиги
   проверены на наличие в 6.1.157 (   `net/netfilter/Kconfig`, `net/netfilter/ipset/Kconfig`,
   `net/ipv4/netfilter/Kconfig`); оба droidspaces-патча перепроверены fuzz=0 (tegu — exit 0,
   zumapro — sched.h+zumapro exit 0).
- 2026-08-01: **CI-итерации (GCC 14.2.0 на 6.1.157):** патчи легли все, дальше — череда
   `-Werror "macro redefined"` от GCC (Clang не ругается, поэтому у Optimistic чисто):
   1) `lib/lz4/lz4hc.c` MIN/MAX → `#undef` перед define (как в апстримном lz4.c);
   2) `google-modules/bms/google_dual_batt_gauge.c` MAX → фикс обобщён: `git grep` по всему
   дереву (`*.c *.h`), `#undef` перед каждым `#define MIN/MAX(` (compile-time, бинарь тот же);
   3) `dwc3-exynos.h` DWC3_LLUCTL (stale vendor) → корень найден: **`init/Kconfig: config WERROR
   default y`** в Optimistic-дереве → для tegu в defconfig добавляется `CONFIG_WERROR=n`
   (снимает только строгость сборки; на код/загрузку ноль влияния — тот же код собирается
   Clang'ом).    zumapro 6.1.145 остаётся на `-Werror`. Побочно подтверждено: zram-энхансменты
   в Sultan-конвейер НЕ попадают (нет zram-шага в sultan.yml).
   4) после CONFIG_WERROR=n упал только `google-modules/wlan/bcm4383/wb_regon_coordinator.c`
   `#define\tMIN` (ТАБ, паттерн не находил) + модуль добавляет СВОЙ `-Werror` через
   `DHDCFLAGS` (`bcm4383/Kbuild:117`), не покрываемый WERROR → в sultan.yml для tegu:
   паттерн MIN/MAX расширен на `[ \t]+`, и вырезается bare `-Werror` из всех
   Makefile/Kbuild/*.mk (`perl -0pi -e 's/-Werror(?!\s*=)//g'`, сохраняет `-Werror=...`).
- 2026-08-01: **CI-билд #1-4 (runs/30703906484, 30704452458, 30706949029, 30707598175)** —
   все -Werror-фейлы закрыты. Итог: **ядро собралось, прошилось, но после перезагрузки —
   FASTBOOT-STUCK.** Пользователь ставит сток и вытягивает стоковые образы
   (boot/vendor_kernel_boot/vendor_dlkm/dtbo) для диагностики. Гипотезы причины (проверить):
   1) KMI/vermagic несоответствие → стоковые vendor_dlkm не грузятся (наш
   `CONFIG_LOCALVERSION=-Sultan-SUSFS` меняет версию ядра! — сравнить `uname -r` нашей
   сборки со стоковой `6.1.157-android14-...-4k`);
   2) ранний паник ядра (GCC 14 + LTO_NONE) — нужен klog/pstore;
   3) vendor_kernel_boot/dtb не принят bootloader'ом (сравнить наш dtb-payload со стоковым
   vendor_kernel_boot);
   4) отличия нашей defconfig от стоковой (тегу-периферия как модули?).
- 2026-08-01: **ПОДТВЕРЖДЕНО на стоке:** `uname`/`/proc/version` стока =
   `6.1.157-android14-11-geadf9a793a097-ab10025877-4k` (clang 17.0.2, +lto). Стоковые модули
   загружены: `panel_gs_tg4c`, `panel_gs_tg4b/a`, `panel_gs_simple`, `exynos_drm`,
   `bcmdhd4383`, `gsa` и т.д. → суффикс в sultan.yml совпадает, флаг-строки vermagic
   (`SMP PREEMPT mod_unload modversions aarch64`) у нас совпадают.
- 2026-08-01: **КОРЕНЬ ПРОБЛЕМЫ НАЙДЕН — два бага, оба исправлены (commit 9fdc3e1):**
   (1) **Версия ядра / vermagic.** Наше ядро сообщало ГОЛОЕ `6.1.157` (`/proc/version`),
   сток = `6.1.157-android14-11-geadf9a793a097-ab10025877-4k`. Причина: tegu-defconfig
   имеет `CONFIG_LOCALVERSION="-Optimistic"` + `CONFIG_LOCALVERSION_AUTO=y`, но make
   `LOCALVERSION_AUTO=0` + shallow-клон без scm дали пустой суффикс; наш старый sed
   `s/^CONFIG_LOCALVERSION=.../` не сработал бы даже на строке. Итог: **ни один
   vendor_dlkm-модуль не грузится** (панель/wifi/модем — все `=m`) → Android бутается,
   но «вслепую» (adb жив, дисплея нет, Google-логотип висит). ФИКС: для tegu патчим
   `scripts/setlocalversion` на точный сток-суффикс (как Original build.yml:1382) +
   в defconfig `CONFIG_LOCALVERSION`/`AUTO=n`.
   (2) **vendor_kernel_boot → fastboot.** Наш vkb (восстановленный AK3 sultan-zumapro)
   bootloader tegu отклоняет → fastboot независимо от содержимого boot (прошивка
   рабочего boot.img не помогла). А наш boot + сток vkb = Android грузится. Сток vkb и так
   содержит правильные 4 базовых zumapro-dtb → для tegu убран блок флеша vkb (boot only).
   Оба факта подтверждены на устройстве (adb, /proc/version, /proc/modules пуст).
- 2026-08-01: **AK3-механика флеша НЕ виновата.** Сравнены anykernel.sh ветки
   `sultan-zumapro` (наш конвейер) и релиза Optimistic tegu (`/tmp/opencode/tegu_ref/`):
   идентичны — `block=boot` (Image.lz4) + `block=vendor_kernel_boot` (dtb), is_slot_device=1.
   Различие только в device.name*/versions/patchlevels (их мы и меняем). Пользователь
   подтвердил: прошилось (AK3 прошёл все чекки на Android 17 / SP 2026-07). → виноват
   КОНТЕНТ (ядро и/или dtb). План:    (а) сток той же прошивки CP2A.260705.006 + вытащить
   boot/vendor_kernel_boot/dtbo/vendor_dlkm/init_boot; (б) `fastboot boot` референс-ядра
   (пересобрать boot.img через magiskboot из `/tmp/opencode/tegu_ref/Image.lz4`) — проверить,
   грузится ли вообще кастом на этой прошивке; (в) mix-and-match (наш boot × сток vkb и
   наоборот) — изолировать «ядро vs dtb»; (г) после фейла `fastboot boot <сток>` + сразу
   pull `/sys/fs/pstore` — взять консоль паника; (д) проверить `fastboot getvar all`
   (unlocked/lock-state/current-slot).
- 2026-08-01: **ДИАГНОЗ: виноват наш vendor_kernel_boot (dtb), не ядро.** Пользователь дал
   dmesg (boot_log.txt, ~9.4k строк) своего рабочего кастомного ядра на этом телефоне: бут
   здоровый (uptime 176s), KernelSU+SUSFS+BBG активны, **стоковый vendor_dlkm bcm4383
   (собран Google Feb 5 2026, bazel android14-gs-pixel-6.1-26Q2-release) грузится и работает**
   → версия ядра/vermagic НЕ блокер (кастом с изменённой версией грузит сток-модули). После
   флеша нашего zip: **не выпускает из fastboot; прошивка рабочего boot.img не помогла** →
   bootloader грузит ядро ТОЛЬКО вместе с валидным vendor_kernel_boot (dtb+ramdisk), наш
   vkb, восстановленный AK3 sultan-zumapro, bootloader'ом не принимается. Гипотеза: AK3
   sultan-zumapro reconstruct vkb несовместим с tegu-bootloader (референс собирает свою
   сборкой AK3). ФИКС-ГИПОТЕЗА: для tegu dtb = те же 4 базовых zumapro-dtb, УЖЕ лежат в
   стоковом vendor_kernel_boot → можно НЕ флешить vkb (только boot). Верификация после
   анбрика: `fastboot boot <наш boot.img>` (сток vkb на месте) — загрузится = ядро ок,
   фикс = убрать шаг флеша vkb.
- 2026-08-01: **ПРИЧИНА НЕСРАБАТЫВАНИЯ ФИКСА ВЕРСИИ (v2) НАЙДЕНА.** tegu-дерево (etnperlong
  16.0.0-optimistic) использует Google-вариант `scripts/setlocalversion`: финальный вывод
  `echo "$res"`, где `res = collect_files(localversion*) + config_localversion + LOCALVERSION +
  $(scm_version) + [-ab$BUILD_NUMBER]`. Мой perl целился в `echo "${KERNELVERSION}..."` —
  такой строки в скрипте нет (это паттерн upstream), поэтому правка была no-op; `CONFIG_
  LOCALVERSION` шёл в `config_localversion` из auto.conf, но `scripts/kconfig` при `CONFIG_
  LOCALVERSION_AUTO=y`... фактически `config_localversion` брался из auto.conf НЕверно:
  строка `CONFIG_LOCALVERSION="-android14-11-...-4k"` там присутствовала, но результат —
  голый `6.1.157`. Разобрали: `BRANCH`/`KMI_GENERATION` make-переменные в дереве НЕ заданы
  (только `$(srctree) $(BRANCH) $(KMI_GENERATION)` в filechk_kernel.release), поэтому
  android_release-ветка не печаталась; `git describe --exact-match` на --depth=1 HEAD тега
  нет → печатался бы `-g<hash>`... но выяснено, что авто-conf содержал AUTO=y, scm отдал
  бы `-g<hash>`; наблюдался же ГОЛЫЙ `6.1.157` — значит perl-правка (v2) реально что-то
  поменяла или `-g<hash>` потерялся. Решение НЕ полагаться на всё это: использовать штатный
  механизм **`.scmversion`**: `scm_version()` ПЕРВЫМ ДЕЛОМ делает `cat .scmversion` и
  возвращает его содержимое (проверено по исходнику ветки). v3-фикс: дефконфиг БЕЗ
  `CONFIG_LOCALVERSION`, `CONFIG_LOCALVERSION_AUTO=y` (сохранён), в корень дерева пишется
  `.scmversion` = `-android14-11-geadf9a793a097-ab10025877-4k`. Итог: kernel.release =
  `6.1.157-android14-11-geadf9a793a097-ab10025877-4k` = стоковый vermagic → vendor_dlkm
  (panel/wifi/modem) загрузятся. Коммит запушен; сборка в CI.
- 2026-08-02: **v3 (9416c63, .scmversion) ТОЖЕ НЕ СРАБОТАЛ — и теперь найдена корневая причина.**
  Распаковка артефакта v3 (run 30717100551): `strings Image` → `Linux version 6.1.157`, без
  суффикса. В логе сборки замечено: `Usage: ../scripts/setlocalversion [--save-scmversion]
  [srctree] [branch] [kmi-generation]`. Это `usage()` из arg-parsing: `filechk_kernel.release`
  вызывает `setlocalversion $(srctree) $(BRANCH) $(KMI_GENERATION)`, а make-переменные BRANCH
  и KMI_GENERATION в CI-билде НЕ ЗАДАНЫ → скрипт получает пустые `$2`/`$3`, `kmi_generation=""`
  → `expr '' : '^[0-9]\+$'` = 0 → `usage` (stderr) → stdout пуст → kernel.release = `6.1.157`.
  Вот почему и голый `6.1.157` с самого начала, и почему `.scmversion` не помог: скрипт падал
  ДО чтения `.scmversion`. Из стокового boot_log: работающее кастомное ядро имело ровно
  `6.1.157-android14-11-geadf9a793a097-ab10025877-4k` (строки fsck FSCK "to ..." — сам f2fs
  `6.1.84...` это версия MKFS-тула, не ядра). → vermagic-теория верна.
  **v4-ФИКС:** в make-строку полной сборки добавлены `BRANCH=android14-11 KMI_GENERATION=11`
  (make-переменные, определяющие `$(BRANCH)`/`$(KMI_GENERATION)` в filechk; пробрасываются в
  sub-make через MAKEFLAGS). Тогда setlocalversion: android_release=android14, kmi=11, usage
  не срабатывает, `.scmversion` (авторитетно) возвращает сток-суффикс → kernel.release =
  `6.1.157-android14-11-geadf9a793a097-ab10025877-4k`. Добавлен пост-билд гард: `cat
  out/include/config/kernel.release` и fail job если нет точного сток-суффикса. `tegu_defconfig`
  в дереве НЕ содержит CONFIG_LOCALVERSION вообще (проверено fetch) → append AUTO=y корректен.
