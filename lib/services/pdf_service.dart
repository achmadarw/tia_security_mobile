import 'dart:io';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import '../config/api_config.dart';

class PdfService {
  final Dio _dio = Dio();

  /// Generate and download roster PDF from backend
  Future<Uint8List> exportRosterPdf({
    required String token,
    required String month,
    required int daysInMonth,
    required List<String> dayNames,
    required List<Map<String, dynamic>> users,
  }) async {
    try {
      print('📄 Requesting PDF export...');
      print('   Month: $month');
      print('   Days: $daysInMonth');
      print('   Users: ${users.length}');

      final response = await _dio.post(
        '${ApiConfig.baseUrl}/roster/export-pdf',
        data: {
          'month': month,
          'daysInMonth': daysInMonth,
          'dayNames': dayNames,
          'users': users,
        },
        options: Options(
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
          responseType: ResponseType.bytes, // Important: receive as bytes
          validateStatus: (status) => status! < 500,
        ),
      );

      if (response.statusCode == 200) {
        final bytes = Uint8List.fromList(response.data);
        print('✅ PDF downloaded: ${bytes.length} bytes');
        return bytes;
      } else {
        throw Exception('PDF export failed: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ PDF export error: $e');
      rethrow;
    }
  }

  /// Save PDF to Downloads folder
  Future<String> savePdfToDownloads({
    required Uint8List pdfBytes,
    required String fileName,
  }) async {
    try {
      // Request storage permission
      if (Platform.isAndroid) {
        final status = await Permission.storage.request();
        if (!status.isGranted) {
          // Try with manageExternalStorage for Android 11+
          final manageStatus = await Permission.manageExternalStorage.request();
          if (!manageStatus.isGranted) {
            throw Exception('Storage permission denied');
          }
        }
      }

      // Get Downloads directory
      Directory? directory;
      if (Platform.isAndroid) {
        directory = Directory('/storage/emulated/0/Download');
        if (!await directory.exists()) {
          directory = await getExternalStorageDirectory();
        }
      } else if (Platform.isIOS) {
        directory = await getApplicationDocumentsDirectory();
      }

      if (directory == null) {
        throw Exception('Could not find downloads directory');
      }

      // Save file
      final filePath = '${directory.path}/$fileName';
      final file = File(filePath);
      await file.writeAsBytes(pdfBytes);

      print('✅ PDF saved: $filePath');
      return filePath;
    } catch (e) {
      print('❌ Save PDF error: $e');
      rethrow;
    }
  }

  /// Share PDF file
  Future<void> sharePdf({
    required Uint8List pdfBytes,
    required String fileName,
  }) async {
    try {
      // Save to temp directory first
      final tempDir = await getTemporaryDirectory();
      final filePath = '${tempDir.path}/$fileName';
      final file = File(filePath);
      await file.writeAsBytes(pdfBytes);

      // Share using share_plus
      await Share.shareXFiles(
        [XFile(filePath)],
        text: 'Roster Schedule - $fileName',
        subject: 'Roster PDF Export',
      );

      print('✅ PDF shared: $fileName');
    } catch (e) {
      print('❌ Share PDF error: $e');
      rethrow;
    }
  }
}
