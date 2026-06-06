import 'dart:async';
import 'dart:convert';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import '../models/models.dart';

class ApiService with WidgetsBindingObserver {
  final String baseUrl;
  final String _serverBase;

  /// Reactive health state
  final ValueNotifier<bool> backendDown = ValueNotifier(false);

  /// Reactive connectivity state
  final ValueNotifier<bool> noInternet = ValueNotifier(false);

  /// Emits when backend transitions from down -> up
  final StreamController<void> backendRecovered = StreamController.broadcast();

  Timer? _healthTimer;
  int _consecutiveFailures = 0;

  /// Number of consecutive failures before marking backend as down.
  static const int _failureThreshold = 2;

  /// Whether the app is currently in the background.
  bool _paused = false;

  static ApiService? _instance;

  factory ApiService({
    String baseUrl = 'https://officeaschi.azurewebsites.net/api',
  }) {
    _instance ??= ApiService._internal(baseUrl: baseUrl);
    return _instance!;
  }

  ApiService._internal({
    this.baseUrl = 'https://officeaschi.azurewebsites.net/api',
  }) : _serverBase = baseUrl.replaceAll(RegExp(r'/api$'), '') {
    WidgetsBinding.instance.addObserver(this);
    _pollHealth();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _paused = true;
      _healthTimer?.cancel();
    } else if (state == AppLifecycleState.resumed) {
      _paused = false;
      _consecutiveFailures = 0;
      _healthTimer?.cancel();
      _pollHealth();
    }
  }

  void _pollHealth() {
    _checkHealth();
    final delay = backendDown.value
        ? const Duration(seconds: 10)
        : const Duration(seconds: 30);
    _healthTimer?.cancel();
    _healthTimer = Timer(delay, _pollHealth);
  }

  Future<void> _checkHealth() async {
    if (_paused) return;

    try {
      final response = await http
          .get(Uri.parse('$_serverBase/health'))
          .timeout(const Duration(seconds: 5));
      noInternet.value = false;
      _consecutiveFailures = 0;
      final wasDown = backendDown.value;
      backendDown.value = response.statusCode != 200;
      if (wasDown && !backendDown.value) {
        backendRecovered.add(null);
      }
    } on TimeoutException {
      _consecutiveFailures++;
      if (_consecutiveFailures >= _failureThreshold) {
        backendDown.value = true;
      }
    } catch (e) {
      _consecutiveFailures++;
      if (_consecutiveFailures >= _failureThreshold) {
        final msg = e.toString().toLowerCase();
        if (msg.contains('socket') ||
            msg.contains('network') ||
            msg.contains('failed host lookup') ||
            msg.contains('xmlhttprequest') ||
            msg.contains('clientexception')) {
          noInternet.value = true;
        }
        backendDown.value = true;
      }
    }
  }

  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _healthTimer?.cancel();
    backendDown.dispose();
    noInternet.dispose();
    backendRecovered.close();
  }

  Map<String, String> _jsonHeaders() => {
    'Content-Type': 'application/json; charset=UTF-8',
  };

  Map<String, String> _totpHeaders(
    String entityType,
    int entityId,
    String code,
  ) => {..._jsonHeaders(), 'Authorization': 'TOTP $entityType:$entityId:$code'};

  // --- Teams ---
  Future<List<TeamSearchResult>> searchTeams([String? query]) async {
    var url = '$baseUrl/teams';
    if (query != null && query.isNotEmpty) {
      url += '?q=${Uri.encodeQueryComponent(query)}';
    }
    final response = await http.get(Uri.parse(url));
    if (response.statusCode == 200) {
      return (json.decode(response.body) as List)
          .map((j) => TeamSearchResult.fromJson(j))
          .toList();
    }
    throw Exception('Failed to load teams');
  }

  Future<TeamResponse> getTeam(int id) async {
    final response = await http.get(Uri.parse('$baseUrl/teams/$id'));
    if (response.statusCode == 200) {
      return TeamResponse.fromJson(json.decode(response.body));
    }
    throw Exception('Team not found');
  }

  Future<TeamResponse> createTeam(
    String? name,
    String secretKey,
    String totpCode,
  ) async {
    final response = await http.post(
      Uri.parse('$baseUrl/teams'),
      headers: _jsonHeaders(),
      body: jsonEncode({
        'name': name,
        'secretKey': secretKey,
        'totpCode': totpCode,
      }),
    );
    if (response.statusCode == 201) {
      return TeamResponse.fromJson(json.decode(response.body));
    }
    final err = json.decode(response.body);
    throw Exception(err['error'] ?? 'Failed to create team');
  }

  Future<void> deleteTeam(int id, String totpCode) async {
    final response = await http.delete(
      Uri.parse('$baseUrl/teams/$id'),
      headers: _totpHeaders('manager', id, totpCode),
    );
    if (response.statusCode != 200) {
      final err = json.decode(response.body);
      throw Exception(err['error'] ?? 'Failed to delete team');
    }
  }

  // --- Seats ---
  Future<List<SeatResponse>> listSeats(int teamId) async {
    final response = await http.get(Uri.parse('$baseUrl/teams/$teamId/seats'));
    if (response.statusCode == 200) {
      return (json.decode(response.body) as List)
          .map((j) => SeatResponse.fromJson(j))
          .toList();
    }
    throw Exception('Failed to load seats');
  }

  Future<SeatResponse> addSeat(
    int teamId,
    String label,
    String totpCode,
  ) async {
    final response = await http.post(
      Uri.parse('$baseUrl/teams/$teamId/seats'),
      headers: _totpHeaders('manager', teamId, totpCode),
      body: jsonEncode({'label': label}),
    );
    if (response.statusCode == 201) {
      return SeatResponse.fromJson(json.decode(response.body));
    }
    final err = json.decode(response.body);
    throw Exception(err['error'] ?? 'Failed to add seat');
  }

  Future<void> deleteSeat(int teamId, int seatId, String totpCode) async {
    final response = await http.delete(
      Uri.parse('$baseUrl/teams/$teamId/seats/$seatId'),
      headers: _totpHeaders('manager', teamId, totpCode),
    );
    if (response.statusCode != 200) {
      final err = json.decode(response.body);
      throw Exception(err['error'] ?? 'Failed to delete seat');
    }
  }

  // --- Reportees ---
  Future<List<ReporteeResponse>> listReportees(int teamId) async {
    final response = await http.get(
      Uri.parse('$baseUrl/teams/$teamId/reportees'),
    );
    if (response.statusCode == 200) {
      return (json.decode(response.body) as List)
          .map((j) => ReporteeResponse.fromJson(j))
          .toList();
    }
    throw Exception('Failed to load reportees');
  }

  Future<ReporteeResponse> joinTeam(
    int teamId,
    String friendlyName,
    String secretKey,
    String totpCode,
  ) async {
    final response = await http.post(
      Uri.parse('$baseUrl/teams/$teamId/reportees'),
      headers: _jsonHeaders(),
      body: jsonEncode({
        'friendlyName': friendlyName,
        'secretKey': secretKey,
        'totpCode': totpCode,
      }),
    );
    if (response.statusCode == 201) {
      return ReporteeResponse.fromJson(json.decode(response.body));
    }
    final err = json.decode(response.body);
    throw Exception(err['error'] ?? 'Failed to join team');
  }

  Future<ReporteeResponse> approveReportee(
    int teamId,
    int reporteeId,
    String totpCode,
  ) async {
    final response = await http.put(
      Uri.parse('$baseUrl/teams/$teamId/reportees/$reporteeId/approve'),
      headers: _totpHeaders('manager', teamId, totpCode),
    );
    if (response.statusCode == 200) {
      return ReporteeResponse.fromJson(json.decode(response.body));
    }
    final err = json.decode(response.body);
    throw Exception(err['error'] ?? 'Failed to approve');
  }

  Future<void> denyReportee(int teamId, int reporteeId, String totpCode) async {
    final response = await http.delete(
      Uri.parse('$baseUrl/teams/$teamId/reportees/$reporteeId/deny'),
      headers: _totpHeaders('manager', teamId, totpCode),
    );
    if (response.statusCode != 200) {
      final err = json.decode(response.body);
      throw Exception(err['error'] ?? 'Failed to deny');
    }
  }

  Future<void> removeReportee(
    int teamId,
    int reporteeId,
    String totpCode,
  ) async {
    final response = await http.delete(
      Uri.parse('$baseUrl/teams/$teamId/reportees/$reporteeId'),
      headers: _totpHeaders('manager', teamId, totpCode),
    );
    if (response.statusCode != 200) {
      final err = json.decode(response.body);
      throw Exception(err['error'] ?? 'Failed to remove');
    }
  }

  // --- Bookings ---
  Future<List<SeatOverviewResponse>> getAllSeats(String date) async {
    final response = await http.get(Uri.parse('$baseUrl/seats?date=$date'));
    if (response.statusCode == 200) {
      return (json.decode(response.body) as List)
          .map((s) => SeatOverviewResponse.fromJson(s))
          .toList();
    }
    throw Exception('Failed to load seats');
  }

  Future<AvailabilityResponse> getAvailability(int teamId, String date) async {
    final response = await http.get(
      Uri.parse('$baseUrl/bookings/availability/$teamId?date=$date'),
    );
    if (response.statusCode == 200) {
      return AvailabilityResponse.fromJson(json.decode(response.body));
    }
    throw Exception('Failed to load availability');
  }

  Future<RangeAvailabilityResponse> getAvailabilityRange(
    int teamId,
    String from,
    String to,
  ) async {
    final response = await http.get(
      Uri.parse(
        '$baseUrl/bookings/availability/$teamId/range?from=$from&to=$to',
      ),
    );
    if (response.statusCode == 200) {
      return RangeAvailabilityResponse.fromJson(json.decode(response.body));
    }
    throw Exception('Failed to load range availability');
  }

  Future<BookingResponse> bookSeat(
    int reporteeId,
    int seatId,
    String date,
    String totpCode,
  ) async {
    final response = await http.post(
      Uri.parse('$baseUrl/bookings'),
      headers: _totpHeaders('reportee', reporteeId, totpCode),
      body: jsonEncode({
        'reporteeId': reporteeId,
        'seatId': seatId,
        'date': date,
      }),
    );
    if (response.statusCode == 201) {
      return BookingResponse.fromJson(json.decode(response.body));
    }
    final err = json.decode(response.body);
    throw Exception(err['error'] ?? 'Failed to book seat');
  }

  Future<RangeBookingResponse> bookSeatRange(
    int reporteeId,
    int seatId,
    String from,
    String to,
    String totpCode,
  ) async {
    final response = await http.post(
      Uri.parse('$baseUrl/bookings/range'),
      headers: _totpHeaders('reportee', reporteeId, totpCode),
      body: jsonEncode({
        'reporteeId': reporteeId,
        'seatId': seatId,
        'from': from,
        'to': to,
      }),
    );
    if (response.statusCode == 200 || response.statusCode == 201) {
      return RangeBookingResponse.fromJson(json.decode(response.body));
    }
    final err = json.decode(response.body);
    throw Exception(err['error'] ?? 'Failed to book seat range');
  }

  Future<void> cancelBooking(
    int bookingId,
    int reporteeId,
    String totpCode,
  ) async {
    final response = await http.delete(
      Uri.parse('$baseUrl/bookings/$bookingId'),
      headers: _totpHeaders('reportee', reporteeId, totpCode),
    );
    if (response.statusCode != 200) {
      final err = json.decode(response.body);
      throw Exception(err['error'] ?? 'Failed to cancel booking');
    }
  }

  // --- TOTP ---
  Future<bool> verifyTotp(String entityType, int entityId, String code) async {
    final response = await http.post(
      Uri.parse('$baseUrl/totp/verify'),
      headers: _jsonHeaders(),
      body: jsonEncode({
        'entityType': entityType,
        'entityId': entityId,
        'code': code,
      }),
    );
    if (response.statusCode == 200) {
      return json.decode(response.body)['valid'] == true;
    }
    return false;
  }
}
