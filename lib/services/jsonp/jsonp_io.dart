import 'package:http/http.dart' as http;

/// 네이티브에서는 CORS가 없으므로 그냥 GET 한다.
/// [callbackParam]은 웹 구현과 시그니처를 맞추기 위해 받기만 하고 쓰지 않는다.
Future<String> fetchJsonp(Uri uri, {String callbackParam = 'callback'}) async {
  final response = await http.get(uri);
  if (response.statusCode != 200) {
    throw Exception('요청 실패 (${response.statusCode})');
  }
  return response.body;
}
