import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import test from "node:test";

const projectRoot = join(dirname(fileURLToPath(import.meta.url)), "..");
const androidResources = join(projectRoot, "native/android-xr/app/src/main/res");

test("Android 12 system splash hands off without showing the OpenStream mark twice", async () => {
  const [styles, blankIcon, colors] = await Promise.all([
    readFile(join(androidResources, "values-v31/styles.xml"), "utf8"),
    readFile(join(androidResources, "drawable/openstream_splash_blank.xml"), "utf8"),
    readFile(join(androidResources, "values/colors.xml"), "utf8"),
  ]);

  assert.match(styles, /android:windowSplashScreenAnimatedIcon[^<]*@drawable\/openstream_splash_blank/);
  assert.match(styles, /android:windowSplashScreenBackground[^<]*@color\/openstream_launch_background/);
  assert.match(styles, /android:windowSplashScreenAnimationDuration[^<]*>0</);
  assert.doesNotMatch(styles, /@mipmap\/ic_launcher|openstream_launcher_foreground/);
  assert.match(blankIcon, /@android:color\/transparent/);
  assert.match(colors, /name="openstream_launch_background">#020406</);
});
