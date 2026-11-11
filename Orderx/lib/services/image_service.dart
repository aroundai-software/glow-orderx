import 'dart:io';
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ImageService {
  final SupabaseClient _supabase = Supabase.instance.client;
  final ImagePicker _picker = ImagePicker();

  // Pick and compress image
  Future<File?> pickAndCompressImage() async {
    final XFile? pickedFile = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 85,
    );

    if (pickedFile == null) return null;

    // Further compress the image
    final File file = File(pickedFile.path);
    final Uint8List imageBytes = await file.readAsBytes();

    // Decode and resize image
    img.Image? image = img.decodeImage(imageBytes);
    if (image == null) return file;

    // Resize to max 800x800 while maintaining aspect ratio
    img.Image resized = img.copyResize(
      image,
      width: image.width > image.height ? 800 : null,
      height: image.height > image.width ? 800 : null,
      interpolation: img.Interpolation.linear,
    );

    // Compress as JPEG with 75% quality
    final Uint8List compressedBytes = Uint8List.fromList(
      img.encodeJpg(resized, quality: 75),
    );

    // Write compressed image to temporary file
    final String tempPath =
        '${file.parent.path}/compressed_${DateTime.now().millisecondsSinceEpoch}.jpg';
    final File compressedFile = File(tempPath);
    await compressedFile.writeAsBytes(compressedBytes);

    return compressedFile;
  }

  // Upload image to Supabase Storage
  Future<Map<String, String>?> uploadProductImage(
      File imageFile, String productId) async {
    try {
      print('🔄 Starting upload for product: $productId');
      print('📁 File exists: ${await imageFile.exists()}');
      print('📊 File size: ${await imageFile.length()} bytes');

      final String fileName =
          'product_${productId}_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final String filePath = 'products/$fileName';

      print('🎯 Upload path: $filePath');
      print('🏪 Bucket: product-images');

      // Upload to Supabase Storage
      final String uploadResponse = await _supabase.storage
          .from('product-images')
          .upload(filePath, imageFile);

      print('✅ Upload successful: $uploadResponse');

      // Get public URL
      final String publicUrl =
          _supabase.storage.from('product-images').getPublicUrl(filePath);

      print('🌐 Public URL: $publicUrl');

      return {
        'url': publicUrl,
        'path': filePath,
      };
    } catch (e) {
      print('❌ Upload error: $e');
      print('📋 Error details: ${e.toString()}');
      if (e is StorageException) {
        print('🚨 Storage error: ${e.message}');
        print('🚨 Storage error code: ${e.statusCode}');
      }
      // Bubble up so UI can show an error instead of a misleading success
      rethrow;
    }
  }

  // Delete image from storage
  Future<bool> deleteProductImage(String imagePath) async {
    try {
      await _supabase.storage.from('product-images').remove([imagePath]);
      return true;
    } catch (e) {
      print('Error deleting image: $e');
      return false;
    }
  }

  // Get optimized image URL with transformations
  String getOptimizedImageUrl(String imageUrl, {int? width, int? height}) {
    // Supabase automatically optimizes images if you append transform parameters
    if (width != null || height != null) {
      final uri = Uri.parse(imageUrl);
      final params = <String, String>{};
      if (width != null) params['width'] = width.toString();
      if (height != null) params['height'] = height.toString();
      params['quality'] = '80';

      return uri.replace(queryParameters: params).toString();
    }
    return imageUrl;
  }
}
