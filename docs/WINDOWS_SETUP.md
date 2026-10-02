# Run Mudhkir on your Android phone from Windows

**تشغيل التطبيق على جوالك من ويندوز.** Three steps. It takes about 30–45 minutes the first time, mostly downloads.

## Step 1: Run the setup script (once)

1. Download the script: open
   https://github.com/AbdulrahmanB-25/Mudhkir_App/blob/claude/keen-wright-nbm6cv/tools/windows/setup.ps1
   and click **Download raw file**. Or clone the repo if you already have Git.
2. Open the Start menu, type **PowerShell**, open it, and run (change the path if your Downloads folder is elsewhere):

   ```powershell
   powershell -ExecutionPolicy Bypass -File "$env:USERPROFILE\Downloads\setup.ps1"
   ```

The script installs and configures everything: Git, Android Studio, Flutter 3.47.6, the Android SDK and its licenses. It also downloads the project to `C:\Users\<you>\Mudhkir_App`.

Two moments need you:

- **Android Studio opens for its first-time wizard** (يفتح Android Studio لأول مرة):
  1. *Do not import settings* → **Next** → **Standard** → **Next**.
  2. Accept all licenses → **Finish**. Wait until the downloads are done.
  3. On the Welcome screen click **Plugins**, search **Flutter**, click **Install** (Dart installs with it), then **Restart IDE**.
  4. Close Android Studio and press **Enter** in PowerShell.
- **The script asks for your Supabase key.** Just press **Enter**: the app already has the mudhkir project built in. Only paste a key if you want to use a different Supabase project.

It ends by printing `flutter doctor`. Everything except "Visual Studio", "Chrome" and "Xcode" should be ✓; you don't need those three for Android.

## Step 2: Prepare your phone (once)

**تفعيل وضع المطوّر وتصحيح USB:**

1. **Settings → About phone** → tap **Build number** 7 times until it says *"You are now a developer"*.
   - Samsung: *Settings → About phone → Software information → Build number*.
   - Xiaomi: *Settings → About phone → MIUI/HyperOS version*, tapped 7 times.
2. **Settings → System → Developer options** → turn on **USB debugging**.
   - Xiaomi also needs **Install via USB** and **USB debugging (Security settings)** turned on.
3. Connect the phone with a USB cable that carries **data** (some cables only charge).
4. On the phone, tap **Allow** in the *"Allow USB debugging?"* box. Tick *Always allow from this computer*.
5. In PowerShell, run `flutter devices`. Your phone should appear in the list.

## Step 3: Run the app

**Option A: double-click.** Open `Mudhkir_App\tools\windows\` and double-click **run-on-phone.bat**.

**Option B: Android Studio** (lets you see logs and use hot reload):

1. Open Android Studio → **Open** → choose the `Mudhkir_App` folder → *Trust Project*.
2. If a banner says *"Flutter SDK path not configured"*, set it to `C:\src\flutter`.
3. On the top toolbar, pick your **phone** in the device dropdown and **Mudhkir** (or `main.dart`, either works) in the configuration dropdown.
4. Press the green **▶ Run**. The first build takes 5–10 minutes; after that it's quicker. Press **⚡ Hot reload** after editing code.

When the app opens on your phone:

- Allow **notifications**, and allow **Alarms & reminders** when it asks.
- Recommended: *Settings → Apps → Mudhkir → Battery → Unrestricted*, so alarms ring on time. This matters most on Samsung and Xiaomi.

## If something goes wrong

| Problem | Fix |
|---|---|
| `flutter devices` doesn't show the phone | Try another cable or USB port. Pull down the notification shade, tap the USB notice and choose **File transfer**. Revoke USB debugging authorisations in Developer options and reconnect. Some brands need their USB driver (Samsung: "Samsung USB Driver for Mobile Phones"). |
| `'flutter' is not recognized` | Close and reopen PowerShell or Android Studio so it picks up the new PATH. Or use `C:\src\flutter\bin\flutter.bat`. |
| `Android license status unknown` | Run `flutter doctor --android-licenses` and answer `y` to each question. |
| Build stuck at "Running Gradle task" | The first build downloads Gradle and its libraries (about 1 GB). Wait; check the Wi-Fi. |
| `INSTALL_FAILED_USER_RESTRICTED` (Xiaomi) | Turn on **Install via USB** in Developer options and sign in to a Mi account. |
| Sign-up says to check your email, but no email arrives | In the Supabase dashboard → *Authentication* → *Sign In / Providers* → *Email*, turn off **Confirm email** while testing. The free plan sends only a few emails per hour. |

Still stuck? Copy the red error text and send it to me.
