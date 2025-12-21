# 📥 Download Face Recognition Model

## ⚠️ Important Note

Repository **MobileFaceNet_TF** tidak menyediakan file `.tflite` yang siap pakai. Repository tersebut hanya berisi kode training untuk TensorFlow.

## ✅ Recommended Solution - Manual Download

### Option 1: Pre-converted Model (EASIEST)

Download dari repository yang sudah convert ke TFLite:

**Source:** https://github.com/kby-ai/FaceRecognition-Flutter

**Steps:**

1. **Klik link berikut untuk download langsung:**

    ```
    https://github.com/kby-ai/FaceRecognition-Flutter/raw/main/android/app/src/main/assets/mobile_face_net.tflite
    ```

2. **Simpan file sebagai:** `mobilefacenet.tflite`

3. **Letakkan di folder:** `d:\WORKSPACE\PROJECT\TIA\mobile\assets\models\`

4. **Verifikasi ukuran file:** ~3-5 MB

### Option 2: Alternative Models

Jika Option 1 gagal, gunakan model alternatif:

#### A. FaceNet 512D (From TFHub)

**Not directly available as .tflite - needs conversion**

#### B. InsightFace ArcFace

Repository: https://github.com/deepinsight/insightface

Download pre-trained model (ONNX format), then convert to TFLite.

#### C. Use Google ML Kit (No model needed)

**Recommended for testing:**

Google ML Kit sudah include face detection, tapi untuk face recognition kita tetap butuh embedding model.

---

## 🔧 Alternative - Convert Yourself

### Step 1: Clone Repository

```bash
cd d:\WORKSPACE\PROJECT\TIA\mobile\assets\models
git clone https://github.com/sirius-ai/MobileFaceNet_TF
```

### Step 2: Download Checkpoint

Repository memiliki pretrained checkpoint di:

```
arch/pretrained_model/MobileFaceNet_9925_9680.ckpt
```

### Step 3: Convert to TFLite

**Install dependencies:**

```bash
pip install tensorflow opencv-python numpy
```

**Create conversion script:** `convert_to_tflite.py`

```python
import tensorflow as tf
import os

# Load TensorFlow model
model_dir = 'arch/pretrained_model'
checkpoint = 'MobileFaceNet_9925_9680.ckpt'

# Create frozen graph
# ... (requires complex TF conversion)

# Convert to TFLite
converter = tf.lite.TFLiteConverter.from_frozen_graph(
    graph_def_file='frozen_model.pb',
    input_arrays=['input'],
    output_arrays=['embeddings']
)

tflite_model = converter.convert()

# Save TFLite model
with open('mobilefacenet.tflite', 'wb') as f:
    f.write(tflite_model)

print("✓ Conversion complete!")
```

**⚠️ Warning:** Proses ini rumit dan butuh expertise di TensorFlow.

---

## 🎯 QUICKEST SOLUTION (Recommended)

### Using PowerShell (Windows):

```powershell
cd "d:\WORKSPACE\PROJECT\TIA\mobile\assets\models"

# Download from alternative source
Invoke-WebRequest -Uri "https://github.com/kby-ai/FaceRecognition-Flutter/raw/main/android/app/src/main/assets/mobile_face_net.tflite" -OutFile "mobilefacenet.tflite"

# Verify
Get-ChildItem mobilefacenet.tflite
```

### Using Browser:

1. **Open link:** https://github.com/kby-ai/FaceRecognition-Flutter/blob/main/android/app/src/main/assets/mobile_face_net.tflite

2. **Click "Download"** button (top right)

3. **Save to:** `d:\WORKSPACE\PROJECT\TIA\mobile\assets\models\mobilefacenet.tflite`

---

## 📊 Model Specifications

Once downloaded, your model should have:

-   **File name:** `mobilefacenet.tflite`
-   **Size:** ~3-5 MB (3,000,000 - 5,000,000 bytes)
-   **Input:** 112x112x3 RGB image
-   **Output:** 512-dimensional embedding (float32 array)
-   **Accuracy:** ~99% on LFW benchmark

---

## ✓ Verification

After download, verify dengan command:

```powershell
cd "d:\WORKSPACE\PROJECT\TIA\mobile\assets\models"
Get-ChildItem mobilefacenet.tflite | Select-Object Name, Length
```

Expected output:

```
Name                 Length
----                 ------
mobilefacenet.tflite 4123456  (approximate)
```

---

## 🐛 Troubleshooting

### File not found after download?

Check these locations:

-   Downloads folder: `C:\Users\<YourName>\Downloads\`
-   Move it to: `d:\WORKSPACE\PROJECT\TIA\mobile\assets\models\`

### Download fails?

Try alternative methods:

1. Use browser download (most reliable)
2. Use download manager (IDM, Free Download Manager)
3. Try different network/VPN

### Model too large or too small?

Verify file integrity:

-   Should be 3-5 MB
-   If much smaller (<1MB): incomplete download
-   If much larger (>10MB): wrong model

---

## 📚 Additional Resources

-   **MobileFaceNet Paper:** https://arxiv.org/abs/1804.07573
-   **TFLite Guide:** https://www.tensorflow.org/lite/guide
-   **Face Recognition Guide:** See `FACE_RECOGNITION_GUIDE.md`

---

## 🆘 Need Help?

Jika semua cara di atas gagal:

1. Check `PHASE2_IMPLEMENTATION.md` untuk alternative models
2. Contact: Create issue di repository
3. Use Google ML Kit only (detection, not full recognition)

---

**Last Updated:** December 20, 2024

**Status:** Waiting for manual model download

**Next Step:** Download model, then test with `flutter run`
