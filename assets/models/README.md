# Face Recognition Models

## Required Model File

Download the FaceNet MobileNet model and place it in this directory.

### Model: MobileFaceNet TFLite

**Download Link:** https://github.com/sirius-ai/MobileFaceNet_TF

**File Name:** `mobilefacenet.tflite`

**File Size:** ~3-5 MB

**Output:** 512-dimensional face embedding

### Alternative Models

You can also use:

1. **FaceNet (Inception ResNet v1)**

    - More accurate but larger (~100MB)
    - Link: https://github.com/nyoki-mtl/keras-facenet

2. **ArcFace MobileFaceNet**
    - Good balance of speed and accuracy (~4MB)
    - Link: https://github.com/deepinsight/insightface

### Installation

```bash
# Download to this folder
cd mobile/assets/models
wget https://github.com/sirius-ai/MobileFaceNet_TF/releases/download/v1.0/mobilefacenet.tflite
```

Or manually download and place `mobilefacenet.tflite` in this directory.

### Model Info

-   **Input:** 112x112x3 RGB image
-   **Output:** 512-dimensional embedding vector
-   **Format:** TensorFlow Lite (.tflite)
-   **Quantization:** Float32
