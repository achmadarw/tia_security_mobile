#!/usr/bin/env python3
"""
Script to download MobileFaceNet TFLite model
Alternative sources for face recognition models
"""

import urllib.request
import os

# Model sources (try in order)
MODEL_SOURCES = [
    {
        'name': 'FaceNet MobileNet (Recommended)',
        'url': 'https://github.com/sirius-ai/MobileFaceNet_TF/raw/master/arch/pretrained_model/MobileFaceNet_9925_9680.ckpt.data-00000-of-00001',
        'filename': 'mobilefacenet_checkpoint.data',
        'note': 'Needs conversion to TFLite'
    },
    {
        'name': 'Alternative - Use pre-converted model',
        'url': 'https://storage.googleapis.com/mediapipe-models/face_landmarker/face_landmarker/float16/latest/face_landmarker.task',
        'filename': 'face_landmarker.task',
        'note': 'MediaPipe model'
    }
]

def download_model(url, filename):
    """Download model file"""
    print(f"Downloading {filename}...")
    print(f"From: {url}")
    
    try:
        urllib.request.urlretrieve(url, filename)
        file_size = os.path.getsize(filename) / (1024 * 1024)  # MB
        print(f"✓ Downloaded successfully: {file_size:.2f} MB")
        return True
    except Exception as e:
        print(f"✗ Failed: {e}")
        return False

def main():
    print("=" * 60)
    print("MobileFaceNet Model Downloader")
    print("=" * 60)
    
    print("\n⚠️  IMPORTANT:")
    print("The original MobileFaceNet_TF repository doesn't provide")
    print("a pre-converted TFLite model. You have 3 options:\n")
    
    print("Option 1: Manual Download (RECOMMENDED)")
    print("-" * 60)
    print("1. Visit: https://github.com/kby-ai/FaceRecognition-Flutter")
    print("2. Navigate to: android/app/src/main/assets/")
    print("3. Download: mobile_face_net.tflite")
    print("4. Save as: mobilefacenet.tflite (in this folder)\n")
    
    print("Option 2: Use Alternative Model")
    print("-" * 60)
    print("Download MediaPipe Face Landmarker (recommended for testing)")
    choice = input("Download MediaPipe model? (y/n): ").lower()
    
    if choice == 'y':
        success = download_model(
            MODEL_SOURCES[1]['url'],
            MODEL_SOURCES[1]['filename']
        )
        if success:
            print("\n✓ Model downloaded!")
            print("Note: This is a face detection model, not recognition.")
            print("You'll need to modify the code to use it.\n")
    
    print("\nOption 3: Convert TensorFlow Model to TFLite")
    print("-" * 60)
    print("1. Clone: git clone https://github.com/sirius-ai/MobileFaceNet_TF")
    print("2. Install TensorFlow: pip install tensorflow")
    print("3. Convert using TFLite Converter")
    print("4. See: CONVERSION_GUIDE.md (to be created)\n")
    
    print("=" * 60)
    print("For now, please manually download the model:")
    print("https://github.com/kby-ai/FaceRecognition-Flutter/raw/main/android/app/src/main/assets/mobile_face_net.tflite")
    print("\nSave it as: mobilefacenet.tflite")
    print("=" * 60)

if __name__ == '__main__':
    main()
