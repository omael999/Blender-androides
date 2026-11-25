/* SPDX-FileCopyrightText: 2026 Blender Authors
 *
 * SPDX-License-Identifier: GPL-2.0-or-later */

package org.blender.android;

import android.content.Intent;
import android.net.Uri;
import android.util.Log;

import org.libsdl.app.SDLActivity;

import java.io.File;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.io.OutputStream;

/**
 * Hosts Blender. SDL3 creates the Vulkan surface and forwards input (touch, mouse, keyboard,
 * stylus) to GHOST's SDL backend; Blender itself runs in {@code SDL_main()} from
 * {@code libmain.so} (see {@code source/creator/creator_android.cc}).
 *
 * Only {@link SetupActivity} starts this activity (it is not exported), after the data files
 * have been extracted, so they are always present when {@code SDL_main()} runs.
 */
public class BlenderActivity extends SDLActivity {
    private static final String TAG = "Blender";

    @Override
    protected String[] getLibraries() {
        /* SDL3 is built as a shared library by build_deps_android.sh, Blender is libmain.so. */
        return new String[] {"SDL3", "main"};
    }

    @Override
    protected String[] getArguments() {
        /* A .blend opened from a file manager is passed as Blender's file argument. */
        String path = blendFileFromIntent(getIntent());
        return path != null ? new String[] {path} : new String[0];
    }

    /**
     * Resolve a VIEW intent to a real path Blender's C code can open. {@code content://} URIs are
     * copied into the cache directory since Blender reads files with POSIX I/O.
     */
    private String blendFileFromIntent(Intent intent) {
        if (intent == null || !Intent.ACTION_VIEW.equals(intent.getAction())) {
            return null;
        }
        Uri uri = intent.getData();
        if (uri == null) {
            return null;
        }
        if ("file".equals(uri.getScheme())) {
            return uri.getPath();
        }
        try {
            String name = uri.getLastPathSegment();
            if (name == null || !name.endsWith(".blend")) {
                name = "opened.blend";
            }
            name = new File(name).getName();
            File out = new File(getCacheDir(), name);
            try (InputStream in = getContentResolver().openInputStream(uri);
                 OutputStream os = new FileOutputStream(out)) {
                byte[] buf = new byte[1 << 16];
                int n;
                while ((n = in.read(buf)) > 0) {
                    os.write(buf, 0, n);
                }
            }
            return out.getAbsolutePath();
        }
        catch (Exception e) {
            Log.e(TAG, "Unable to open " + uri, e);
            return null;
        }
    }
}
