# Blender para Android (port no oficial)

Port de Blender (código oficial, `main` 5.4 alpha) a Android **arm64-v8a**, Android 10+ (API 29).

## Arquitectura

| Capa | Desktop | Android (este port) |
|---|---|---|
| Ventanas / entrada | X11, Wayland, Win32, Cocoa | **GHOST SDL3** (backend que ya existe en Blender) |
| GPU | OpenGL 4.3 / Vulkan / Metal | **Vulkan** (Android no tiene OpenGL de escritorio) |
| Ejecutable | `blender` | **`libmain.so`**, cargada por `SDLActivity` → `SDL_main()` |
| Datos (`scripts/`, `datafiles/`, Python) | junto al binario | en el APK (`assets/`), se extraen al primer arranque |
| Python | CPython incluido | CPython 3.13 compilado para Android (PEP 738) |

```
SetupActivity (Java)  -> extrae assets/blender/5.4 a /data/data/org.blender.android/files/blender/5.4
BlenderActivity       -> SDLActivity: carga libSDL3.so + libmain.so, crea la superficie Vulkan
SDL_main (C++)        -> creator_android.cc: HOME, BLENDER_SYSTEM_RESOURCES, PYTHONHOME, stdout→logcat
main() de Blender     -> creator.cc sin cambios (renombrado a blender_android_main)
```

## Archivos del port

- `build_files/cmake/platform/platform_android.cmake`: plataforma Android (reutiliza `platform_unix.cmake`).
- `build_files/cmake/config/blender_android.cmake`: preset de opciones (fase 1).
- `build_files/build_environment/android/build_deps_android.sh`: compila las 25 dependencias con el NDK,
  usando las mismas versiones que fija `versions.cmake`.
- `source/creator/creator_android.cc`: punto de entrada `SDL_main`.
- `build_files/android/`: proyecto Gradle (APK) y `build_android.sh`.
- Cambios mínimos en: `CMakeLists.txt`, `platform_unix.cmake`, `source/creator/CMakeLists.txt`,
  `creator.cc`, `gpu/vulkan/vk_backend.cc` (geometry shaders opcionales en móvil).

## Compilar

Requisitos (Linux x86_64 o macOS): Android SDK + NDK r29 (libc++ 19+ para `std::atomic_ref`), CMake ≥ 3.24, Ninja, Meson, Python 3.13,
JDK 17+, Gradle 8.9+ (o Android Studio), ~40 GB libres y bastante tiempo (las dependencias tardan horas).

```bash
export ANDROID_HOME=~/Android/Sdk
export ANDROID_NDK_HOME=$ANDROID_HOME/ndk/<versión r29>

./build_files/android/build_android.sh               # deps + Blender + APK (debug)
./build_files/android/build_android.sh --skip-deps   # recompilar solo Blender + APK

adb install -r build_files/android/app/build/outputs/apk/debug/app-debug.apk
adb logcat -s Blender BlenderSetup SDL
```

Para ver las versiones de dependencias: `build_deps_android.sh versions`.

## Requisitos del dispositivo

El backend Vulkan de Blender exige: Vulkan 1.1+, `VK_KHR_dynamic_rendering`, `timeline_semaphore`,
`buffer_device_address`, `depth_stencil_resolve`, `create_renderpass2`,
`separate_depth_stencil_layouts`, y las características `dualSrcBlend`, `imageCubeArray`,
`fragmentStoresAndAtomics`, `drawIndirectFirstInstance`.

- **Adreno 7xx/8xx (Snapdragon 8 Gen 1 en adelante)**: el candidato más probable.
- **Mali / Immortalis**: suelen fallar por `dualSrcBlend` (la comprobación de geometry shaders ya
  se omite en Android).
- **Xclipse (Exynos, RDNA)**: buen soporte de extensiones, por probar.

## Estado y hoja de ruta

**Fase 1 — base (este commit)**: integración de plataforma, punto de entrada, APK, dependencias.
Sin compilar todavía en un NDK real: es de esperar una ronda de correcciones de compilación/enlace.

**Fase 2**: audio (SDL audio + Audaspace), OpenSubdiv, OpenColorIO completo, selector de archivos
con Storage Access Framework, teclado en pantalla (SDL_StartTextInput), gestos táctiles
(pellizcar = zoom, dos dedos = orbitar) mapeados a eventos de trackpad de GHOST.

**Fase 3**: Cycles en CPU (NEON vía sse2neon), interfaz adaptada a táctil (escala de UI, keymap).

## Limitaciones conocidas

- Interfaz de escritorio: usable con ratón/teclado o tablet con lápiz; con el dedo es incómoda.
- Sin OpenGL: todo depende de que el driver Vulkan del móvil cumpla los requisitos de arriba.
- Sin Cycles en la fase 1; EEVEE y Workbench sí.
- No es un producto oficial de la Blender Foundation. Licencia: GPL-2.0-or-later, como Blender.
