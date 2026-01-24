import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tia_mobile/config/api_config.dart';
import '../models/block.dart';

class BlockService {
  // Railway deployment URL
  // static const String baseUrl =
  //     'https://tiasecuritybackend-production.up.railway.app';

  // Cache for token to avoid repeated SharedPreferences access
  String? _cachedToken;

  // Get auth token from SharedPreferences with caching
  // Block Management is for Community App (admin), so use 'access_token'
  Future<String> _getToken() async {
    if (_cachedToken != null) {
      print('[BlockService] Using cached token');
      return _cachedToken!;
    }

    final prefs = await SharedPreferences.getInstance();

    // Use 'access_token' for Community App (admin users)
    // NOT 'security_access_token' (for security guards)
    _cachedToken = prefs.getString('access_token');

    if (_cachedToken == null || _cachedToken!.isEmpty) {
      print('[BlockService] ❌ No access_token found in SharedPreferences');
      print('[BlockService] Available keys: ${prefs.getKeys()}');
      throw Exception(
          'No auth token found. Please login as admin from Community App.');
    }

    // Log first and last 10 chars for debugging
    final tokenPreview = _cachedToken!.length > 20
        ? '${_cachedToken!.substring(0, 10)}...${_cachedToken!.substring(_cachedToken!.length - 10)}'
        : _cachedToken!;
    print('[BlockService] ✅ Token found: $tokenPreview');

    return _cachedToken!;
  }

  // Clear cached token (call on logout)
  void clearCache() {
    _cachedToken = null;
  }

  // Get all blocks with optional status filter
  Future<List<Block>> getBlocks({String? status}) async {
    try {
      final token = await _getToken();
      final url = status != null
          ? Uri.parse('${ApiConfig.serverUrl}/api/blocks?status=$status')
          : Uri.parse('${ApiConfig.serverUrl}/api/blocks');

      print('[BlockService] Fetching blocks from: $url');

      final response = await http.get(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      print('[BlockService] Response status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final responseBody = response.body;
        print('[BlockService] Response body type: ${responseBody.runtimeType}');

        final jsonData = json.decode(responseBody);
        print('[BlockService] Parsed JSON type: ${jsonData.runtimeType}');

        // Backend returns array directly, not wrapped in {blocks: [...]}
        List<dynamic> blocksJson;
        if (jsonData is List) {
          blocksJson = jsonData;
          print('[BlockService] Response is direct array');
        } else if (jsonData is Map && jsonData.containsKey('blocks')) {
          blocksJson = jsonData['blocks'] ?? [];
          print('[BlockService] Response has blocks wrapper');
        } else {
          print('[BlockService] ⚠️ Unexpected response format: $jsonData');
          blocksJson = [];
        }

        final blocks = blocksJson.map((json) => Block.fromJson(json)).toList();
        print('[BlockService] Fetched ${blocks.length} blocks');

        return blocks;
      } else {
        final errorBody = response.body;
        print('[BlockService] Error response: $errorBody');
        throw Exception(
            'Failed to fetch blocks: ${response.statusCode} - $errorBody');
      }
    } catch (e) {
      print('[BlockService] Exception in getBlocks: $e');
      rethrow;
    }
  }

  // Get single block by ID
  Future<Block> getBlock(int id) async {
    try {
      final token = await _getToken();
      final url = Uri.parse('${ApiConfig.serverUrl}/api/blocks/$id');

      print('[BlockService] Fetching block $id from: $url');

      final response = await http.get(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final jsonData = json.decode(response.body);
        final block = Block.fromJson(jsonData['block']);
        print('[BlockService] Fetched block: ${block.name}');

        return block;
      } else {
        throw Exception('Failed to fetch block: ${response.statusCode}');
      }
    } catch (e) {
      print('[BlockService] Exception in getBlock: $e');
      rethrow;
    }
  }

  // Create new block
  Future<Block> createBlock(Block block) async {
    try {
      final token = await _getToken();
      final url = Uri.parse('${ApiConfig.serverUrl}/api/blocks');

      print('[BlockService] Creating block: ${block.name}');
      print('[BlockService] Coordinates: ${block.coordinatesText}');

      final body = json.encode(block.toJson());
      print('[BlockService] Request body: $body');

      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: body,
      );

      print('[BlockService] Create response status: ${response.statusCode}');
      print('[BlockService] Create response body: ${response.body}');

      if (response.statusCode == 201 || response.statusCode == 200) {
        final jsonData = json.decode(response.body);
        final createdBlock = Block.fromJson(jsonData['block']);
        print('[BlockService] Block created successfully: ${createdBlock.id}');

        return createdBlock;
      } else {
        final errorBody = response.body;
        throw Exception(
            'Failed to create block: ${response.statusCode} - $errorBody');
      }
    } catch (e) {
      print('[BlockService] Exception in createBlock: $e');
      rethrow;
    }
  }

  // Update existing block
  Future<Block> updateBlock(int id, Block block) async {
    try {
      final token = await _getToken();
      final url = Uri.parse('${ApiConfig.serverUrl}/api/blocks/$id');

      print('[BlockService] Updating block $id: ${block.name}');
      print('[BlockService] New coordinates: ${block.coordinatesText}');

      final body = json.encode(block.toJson());
      print('[BlockService] Update request body: $body');

      final response = await http.put(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: body,
      );

      print('[BlockService] Update response status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final jsonData = json.decode(response.body);
        final updatedBlock = Block.fromJson(jsonData['block']);
        print('[BlockService] Block updated successfully');

        return updatedBlock;
      } else {
        final errorBody = response.body;
        throw Exception(
            'Failed to update block: ${response.statusCode} - $errorBody');
      }
    } catch (e) {
      print('[BlockService] Exception in updateBlock: $e');
      rethrow;
    }
  }

  // Delete block
  Future<void> deleteBlock(int id) async {
    try {
      final token = await _getToken();
      final url = Uri.parse('${ApiConfig.serverUrl}/api/blocks/$id');

      print('[BlockService] Deleting block $id');

      final response = await http.delete(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      print('[BlockService] Delete response status: ${response.statusCode}');

      if (response.statusCode == 200) {
        print('[BlockService] Block deleted successfully');
      } else {
        final errorBody = response.body;
        throw Exception(
            'Failed to delete block: ${response.statusCode} - $errorBody');
      }
    } catch (e) {
      print('[BlockService] Exception in deleteBlock: $e');
      rethrow;
    }
  }

  // Toggle block status (active/inactive)
  Future<Block> toggleBlockStatus(Block block) async {
    final newStatus = block.isActive ? 'inactive' : 'active';
    print('[BlockService] Toggling block ${block.id} status to: $newStatus');

    final updatedBlock = block.copyWith(status: newStatus);
    return await updateBlock(block.id!, updatedBlock);
  }
}
