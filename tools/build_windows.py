"""Build the Windows app (dist/windows/AWXCEND/AWXCEND.exe) and prove camera tracking works in it.

    py tools/build_windows.py

Uses `flet pack` (PyInstaller), so no Visual Studio is needed. After building it runs the packaged
exe with --selfcheck, which loads MediaPipe + the pose model + OpenCV exactly as the camera screen does.
"""
import os
import pathlib
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
# Big packages that happen to be installed but the app never loads (checked: importing the camera
# pipeline pulls in matplotlib - MediaPipe needs it - but none of these).
EXCLUDE = ["torch", "torchvision", "torchaudio", "tensorflow", "jax", "jaxlib", "IPython", "pandas",
           "scipy", "sklearn", "notebook", "jupyter", "tkinter", "sympy", "numba"]

# `flet pack` deletes ./build before it starts, which would also wipe an Android build in build/apk.
# So it runs from its own work folder, .pack/, and writes only to dist/windows (which it also clears).
WORK = ROOT / ".pack"
WORK.mkdir(exist_ok=True)
cmd = ["flet", "pack", "../src/main.py", "--name", "AWXCEND", "--icon", "../src/assets/icon.ico", "--onedir",
       "--distpath", "../dist/windows", "--add-data", "../src/assets:assets", "--product-name", "AWXCEND",
       "--file-description", "AWXCEND fitness", "--product-version", "0.1.0", "--company-name", "AWXCEND group",
       # MediaPipe loads its engine (libmediapipe.dll) at runtime, which PyInstaller can't see by itself.
       # collect-all would drag in PyTorch via MediaPipe's training tools, so only binaries + data.
       "--pyinstaller-build-args=--collect-binaries=mediapipe",
       "--pyinstaller-build-args=--collect-data=mediapipe",
       *[f"--pyinstaller-build-args=--exclude-module={m}" for m in EXCLUDE], "-y"]

print("Building (a few minutes)...")
if subprocess.run(cmd, cwd=WORK, env={**os.environ, "PYTHONUTF8": "1"}).returncode:
    sys.exit("Build failed - see the output above.")

exe = ROOT / "dist" / "windows" / "AWXCEND" / "AWXCEND.exe"
result = pathlib.Path(tempfile.gettempdir()) / "awxcend_selfcheck.txt"
result.unlink(missing_ok=True)
subprocess.run([str(exe), "--selfcheck", str(result)], timeout=180)
outcome = result.read_text(encoding="utf-8").strip() if result.exists() else "FAILED: no result written"
print(f"Self-check: {outcome}")
if not outcome.startswith("ok"):
    sys.exit("The packaged app can't run camera tracking - don't ship this build.")
print(f"Ready: {exe}  (zip the whole dist/windows/AWXCEND folder to share it)")
