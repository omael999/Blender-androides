/* SPDX-FileCopyrightText: 2026 Blender Authors
 *
 * SPDX-License-Identifier: GPL-2.0-or-later */

/** \file
 * \ingroup creator
 *
 * Android entry point.
 *
 * The Java side (`org.blender.android.BlenderActivity`, a subclass of SDL3's `SDLActivity`)
 * loads `libmain.so` and calls `SDL_main()` on its own thread. Before that it extracts the
 * read-only data files (`datafiles/`, `scripts/`, `python/`) bundled in the APK into
 * `<internal storage>/blender/<version>/`.
 *
 * Here the environment is set up so the regular desktop code paths in `appdir.cc`
 * find those files, then Blender's own `main()` is called.
 */

#ifdef BLENDER_ANDROID

#  include <android/log.h>
#  include <cstdio>
#  include <pthread.h>
#  include <cstdlib>
#  include <string>
#  include <sys/stat.h>
#  include <unistd.h>
#  include <vector>

#  include <SDL3/SDL.h>
#  include <SDL3/SDL_main.h>

#  include "BKE_blender_version.h"

#  define LOG_TAG "Blender"
#  define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#  define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

/* Defined in `creator.cc` (Blender's `main` renamed for Android). */
int blender_android_main(int argc, const char **argv);

static void ensure_dir(const std::string &path)
{
  mkdir(path.c_str(), 0700);
}

/**
 * Redirect `stdout`/`stderr` to `logcat`, otherwise Blender's console output is lost.
 */
static void *stdio_to_logcat_thread(void *arg)
{
  const int fd = *static_cast<int *>(arg);
  char buf[1024];
  ssize_t len;
  while ((len = read(fd, buf, sizeof(buf) - 1)) > 0) {
    if (buf[len - 1] == '\n') {
      len--;
    }
    buf[len] = '\0';
    __android_log_write(ANDROID_LOG_INFO, LOG_TAG, buf);
  }
  return nullptr;
}

static void stdio_to_logcat()
{
  static int pipe_fd[2];
  setvbuf(stdout, nullptr, _IOLBF, 0);
  setvbuf(stderr, nullptr, _IONBF, 0);
  if (pipe(pipe_fd) != 0) {
    return;
  }
  dup2(pipe_fd[1], STDOUT_FILENO);
  dup2(pipe_fd[1], STDERR_FILENO);
  pthread_t thread;
  if (pthread_create(&thread, nullptr, stdio_to_logcat_thread, &pipe_fd[0]) == 0) {
    pthread_detach(thread);
  }
}

int main(int argc, char *argv[])
{
  stdio_to_logcat();

  const char *internal = SDL_GetAndroidInternalStoragePath();
  if (internal == nullptr) {
    LOGE("SDL_GetAndroidInternalStoragePath failed: %s", SDL_GetError());
    return 1;
  }
  const char *cache = SDL_GetAndroidCachePath();

  const std::string root = internal;
  const std::string version = std::to_string(BLENDER_VERSION / 100) + "." +
                              std::to_string(BLENDER_VERSION % 100);
  const std::string system_dir = root + "/blender/" + version;
  const std::string user_dir = root + "/config";
  const std::string tmp_dir = cache ? std::string(cache) : root + "/tmp";

  ensure_dir(user_dir);
  ensure_dir(tmp_dir);

  /* Read by `appdir.cc`. */
  setenv("HOME", root.c_str(), 1);
  setenv("BLENDER_SYSTEM_RESOURCES", system_dir.c_str(), 1);
  setenv("BLENDER_USER_RESOURCES", user_dir.c_str(), 1);
  setenv("TMPDIR", tmp_dir.c_str(), 1);
  /* Bundled CPython (built for Android, see `build_deps_android.sh`). */
  const std::string python_home = system_dir + "/python";
  setenv("PYTHONHOME", python_home.c_str(), 1);
  setenv("PYTHONDONTWRITEBYTECODE", "1", 1);

  /* Default working directory for "Save As" etc. */
  chdir(root.c_str());

  LOGI("Blender %s starting, resources: %s", version.c_str(), system_dir.c_str());

  /* `argv[0]` is used to locate the program directory, point it inside the
   * extracted resources so relative lookups resolve there. */
  const std::string program = root + "/blender/blender";
  std::vector<const char *> args;
  args.push_back(program.c_str());
  for (int i = 1; i < argc; i++) {
    args.push_back(argv[i]);
  }
  args.push_back(nullptr);

  const int ret = blender_android_main(int(args.size()) - 1, args.data());
  LOGI("Blender exited with code %d", ret);
  return ret;
}

#endif /* BLENDER_ANDROID */
