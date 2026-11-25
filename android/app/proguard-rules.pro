# ML Kit Text Recognition (opsiyonel script sınıfları)
-keep class com.google.mlkit.vision.text.** { *; }
-dontwarn com.google.mlkit.vision.text.**

# TensorFlow Lite / tflite_flutter (GPU delegate opsiyonel sınıfları)
-keep class org.tensorflow.lite.** { *; }
-dontwarn org.tensorflow.lite.**