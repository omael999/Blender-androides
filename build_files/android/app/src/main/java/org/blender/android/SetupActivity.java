/* SPDX-FileCopyrightText: 2026 Blender Authors
 *
 * SPDX-License-Identifier: GPL-2.0-or-later */

package org.blender.android;

import android.app.Activity;
import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageInfo;
import android.content.res.AssetManager;
import android.graphics.Color;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.util.Log;
import android.view.Gravity;
import android.widget.TextView;

import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;

/**
 * Launcher activity: on first run (or after an update) extracts Blender's read-only data files
 * from the APK assets to {@code <filesDir>/blender/<version>/}, where the native code expects
 * them ({@code BLENDER_SYSTEM_RESOURCES}), then starts {@link BlenderActivity}.
 *
 * Blender reads its scripts, fonts, startup.blend and the Python standard library with plain
 * POSIX file I/O, so they cannot stay inside the compressed APK.
 */
public class SetupActivity extends Activity {
    private static final String TAG = "BlenderSetup";
    private static final String STAMP = ".extracted";

    private TextView status;
    private final Handler ui = new Handler(Looper.getMainLooper());
    private int filesDone = 0;

    static File resourcesDir(Context ctx) {
        return new File(ctx.getFilesDir(), "blender/" + BuildConfig.BLENDER_VERSION);
    }

    private static String stampValue(Context ctx) {
        try {
            PackageInfo info = ctx.getPackageManager().getPackageInfo(ctx.getPackageName(), 0);
            return info.getLongVersionCode() + ":" + info.lastUpdateTime;
        }
        catch (Exception e) {
            return "unknown";
        }
    }

    static boolean isExtracted(Context ctx) {
        File stamp = new File(resourcesDir(ctx), STAMP);
        try {
            return stamp.exists() &&
                   new String(Files.readAllBytes(stamp.toPath()), StandardCharsets.UTF_8)
                       .equals(stampValue(ctx));
        }
        catch (IOException e) {
            return false;
        }
    }

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        if (isExtracted(this)) {
            launchBlender();
            return;
        }

        status = new TextView(this);
        status.setGravity(Gravity.CENTER);
        status.setTextColor(Color.WHITE);
        status.setBackgroundColor(Color.rgb(35, 35, 35));
        status.setTextSize(18);
        status.setText(R.string.setup_preparing);
        setContentView(status);

        new Thread(this::extractAll, "blender-extract").start();
    }

    private void extractAll() {
        File dest = resourcesDir(this);
        try {
            deleteRecursive(dest);
            copyAssetDir(getAssets(), "blender/" + BuildConfig.BLENDER_VERSION, dest);
            try (OutputStream os = new FileOutputStream(new File(dest, STAMP))) {
                os.write(stampValue(this).getBytes(StandardCharsets.UTF_8));
            }
            ui.post(this::launchBlender);
        }
        catch (IOException e) {
            Log.e(TAG, "Extraction failed", e);
            ui.post(() -> status.setText(getString(R.string.setup_failed, e.getMessage())));
        }
    }

    private void copyAssetDir(AssetManager am, String assetPath, File dest) throws IOException {
        String[] children = am.list(assetPath);
        if (children == null || children.length == 0) {
            /* A file (AssetManager reports files as empty directories). */
            copyAssetFile(am, assetPath, dest);
            return;
        }
        if (!dest.isDirectory() && !dest.mkdirs()) {
            throw new IOException("Cannot create " + dest);
        }
        for (String child : children) {
            copyAssetDir(am, assetPath + "/" + child, new File(dest, child));
        }
    }

    private void copyAssetFile(AssetManager am, String assetPath, File dest) throws IOException {
        File parent = dest.getParentFile();
        if (parent != null && !parent.isDirectory()) {
            parent.mkdirs();
        }
        try (InputStream in = am.open(assetPath, AssetManager.ACCESS_STREAMING);
             OutputStream os = new FileOutputStream(dest)) {
            byte[] buf = new byte[1 << 16];
            int n;
            while ((n = in.read(buf)) > 0) {
                os.write(buf, 0, n);
            }
        }
        catch (IOException e) {
            /* Empty directories have no file to open, keep them as directories. */
            if (am.list(assetPath) == null) {
                throw e;
            }
            dest.mkdirs();
            return;
        }
        if (++filesDone % 200 == 0) {
            final int done = filesDone;
            ui.post(() -> status.setText(getString(R.string.setup_progress, done)));
        }
    }

    private static void deleteRecursive(File f) {
        File[] children = f.listFiles();
        if (children != null) {
            for (File c : children) {
                deleteRecursive(c);
            }
        }
        f.delete();
    }

    private void launchBlender() {
        Intent intent = new Intent(this, BlenderActivity.class);
        Intent source = getIntent();
        if (source != null) {
            intent.setAction(source.getAction());
            intent.setData(source.getData());
        }
        startActivity(intent);
        finish();
    }
}
