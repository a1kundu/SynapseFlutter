// --- Team ---
class TeamSearchResult {
  final int id;
  final String name;
  final int seatCount;
  final int memberCount;

  TeamSearchResult({
    required this.id,
    required this.name,
    required this.seatCount,
    required this.memberCount,
  });

  factory TeamSearchResult.fromJson(Map<String, dynamic> json) =>
      TeamSearchResult(
        id: json['id'],
        name: json['name'],
        seatCount: json['seatCount'],
        memberCount: json['memberCount'],
      );
}

class TeamResponse {
  final int id;
  final String name;
  final bool hasTotpSetup;

  TeamResponse({
    required this.id,
    required this.name,
    required this.hasTotpSetup,
  });

  factory TeamResponse.fromJson(Map<String, dynamic> json) => TeamResponse(
    id: json['id'],
    name: json['name'],
    hasTotpSetup: json['hasTotpSetup'] ?? false,
  );
}

// --- Seat ---
class SeatResponse {
  final int id;
  final String label;
  final int teamId;

  SeatResponse({required this.id, required this.label, required this.teamId});

  factory SeatResponse.fromJson(Map<String, dynamic> json) => SeatResponse(
    id: json['id'],
    label: json['label'],
    teamId: json['teamId'],
  );
}

// --- Reportee ---
class ReporteeResponse {
  final int id;
  final String friendlyName;
  final int teamId;
  final bool isApproved;
  final bool hasTotpSetup;

  ReporteeResponse({
    required this.id,
    required this.friendlyName,
    required this.teamId,
    required this.isApproved,
    required this.hasTotpSetup,
  });

  factory ReporteeResponse.fromJson(Map<String, dynamic> json) =>
      ReporteeResponse(
        id: json['id'],
        friendlyName: json['friendlyName'],
        teamId: json['teamId'],
        isApproved: json['isApproved'] ?? false,
        hasTotpSetup: json['hasTotpSetup'] ?? false,
      );
}

// --- Booking ---
class BookingResponse {
  final int id;
  final String date;
  final int seatId;
  final String seatLabel;
  final int reporteeId;
  final String reporteeName;
  final String status;
  final String createdAt;

  BookingResponse({
    required this.id,
    required this.date,
    required this.seatId,
    required this.seatLabel,
    required this.reporteeId,
    required this.reporteeName,
    required this.status,
    required this.createdAt,
  });

  factory BookingResponse.fromJson(Map<String, dynamic> json) =>
      BookingResponse(
        id: json['id'],
        date: json['date'],
        seatId: json['seatId'],
        seatLabel: json['seatLabel'],
        reporteeId: json['reporteeId'],
        reporteeName: json['reporteeName'],
        status: json['status'],
        createdAt: json['createdAt'],
      );
}

// --- Waitlist ---
class WaitlistInfo {
  final int bookingId;
  final int? reporteeId;
  final String reporteeName;
  final String desiredSeatLabel;
  final String waitlistedSince;

  WaitlistInfo({
    required this.bookingId,
    this.reporteeId,
    required this.reporteeName,
    required this.desiredSeatLabel,
    required this.waitlistedSince,
  });

  factory WaitlistInfo.fromJson(Map<String, dynamic> json) => WaitlistInfo(
    bookingId: json['bookingId'],
    reporteeId: json['reporteeId'],
    reporteeName: json['reporteeName'],
    desiredSeatLabel: json['desiredSeatLabel'],
    waitlistedSince: json['waitlistedSince'],
  );
}

// --- Availability ---
class AvailabilityResponse {
  final String date;
  final int totalSeats;
  final int bookedCount;
  final int availableCount;
  final int waitlistedCount;
  final List<BookingResponse> bookings;
  final List<SeatResponse> availableSeats;
  final List<WaitlistInfo> waitlist;

  AvailabilityResponse({
    required this.date,
    required this.totalSeats,
    required this.bookedCount,
    required this.availableCount,
    required this.waitlistedCount,
    required this.bookings,
    required this.availableSeats,
    required this.waitlist,
  });

  factory AvailabilityResponse.fromJson(Map<String, dynamic> json) =>
      AvailabilityResponse(
        date: json['date'],
        totalSeats: json['totalSeats'],
        bookedCount: json['bookedCount'],
        availableCount: json['availableCount'],
        waitlistedCount: json['waitlistedCount'],
        bookings: (json['bookings'] as List)
            .map((b) => BookingResponse.fromJson(b))
            .toList(),
        availableSeats: (json['availableSeats'] as List)
            .map((s) => SeatResponse.fromJson(s))
            .toList(),
        waitlist: (json['waitlist'] as List)
            .map((w) => WaitlistInfo.fromJson(w))
            .toList(),
      );
}

// --- Merged seat view for UI ---
class SeatView {
  final int seatId;
  final String label;
  final String status; // 'booked' or 'available'
  final String personName;
  final BookingResponse? booking;

  SeatView({
    required this.seatId,
    required this.label,
    required this.status,
    this.personName = '',
    this.booking,
  });
}

// --- Range Availability ---
class DateAvailabilitySummary {
  final String date;
  final int totalSeats;
  final int bookedCount;
  final int availableCount;
  final int waitlistedCount;

  DateAvailabilitySummary({
    required this.date,
    required this.totalSeats,
    required this.bookedCount,
    required this.availableCount,
    required this.waitlistedCount,
  });

  factory DateAvailabilitySummary.fromJson(Map<String, dynamic> json) =>
      DateAvailabilitySummary(
        date: json['date'],
        totalSeats: json['totalSeats'],
        bookedCount: json['bookedCount'],
        availableCount: json['availableCount'],
        waitlistedCount: json['waitlistedCount'],
      );
}

class RangeAvailabilityResponse {
  final int teamId;
  final String from;
  final String to;
  final List<DateAvailabilitySummary> days;

  RangeAvailabilityResponse({
    required this.teamId,
    required this.from,
    required this.to,
    required this.days,
  });

  factory RangeAvailabilityResponse.fromJson(Map<String, dynamic> json) =>
      RangeAvailabilityResponse(
        teamId: json['teamId'],
        from: json['from'],
        to: json['to'],
        days: (json['days'] as List)
            .map((d) => DateAvailabilitySummary.fromJson(d))
            .toList(),
      );
}

// --- Range Booking ---
class RangeBookingResult {
  final String date;
  final bool success;
  final String status;
  final int? bookingId;
  final String? error;

  RangeBookingResult({
    required this.date,
    required this.success,
    required this.status,
    this.bookingId,
    this.error,
  });

  factory RangeBookingResult.fromJson(Map<String, dynamic> json) =>
      RangeBookingResult(
        date: json['date'],
        success: json['success'],
        status: json['status'],
        bookingId: json['bookingId'],
        error: json['error'],
      );
}

class RangeBookingResponse {
  final int seatId;
  final String seatLabel;
  final int reporteeId;
  final String reporteeName;
  final String from;
  final String to;
  final int confirmedCount;
  final int waitlistedCount;
  final int failedCount;
  final List<RangeBookingResult> results;

  RangeBookingResponse({
    required this.seatId,
    required this.seatLabel,
    required this.reporteeId,
    required this.reporteeName,
    required this.from,
    required this.to,
    required this.confirmedCount,
    required this.waitlistedCount,
    required this.failedCount,
    required this.results,
  });

  factory RangeBookingResponse.fromJson(Map<String, dynamic> json) =>
      RangeBookingResponse(
        seatId: json['seatId'],
        seatLabel: json['seatLabel'],
        reporteeId: json['reporteeId'],
        reporteeName: json['reporteeName'],
        from: json['from'],
        to: json['to'],
        confirmedCount: json['confirmedCount'],
        waitlistedCount: json['waitlistedCount'],
        failedCount: json['failedCount'],
        results: (json['results'] as List)
            .map((r) => RangeBookingResult.fromJson(r))
            .toList(),
      );
}

// --- All Seats Overview ---
class SeatOverviewBooking {
  final int reporteeId;
  final String reporteeName;
  final int bookingId;
  final String status;
  final String createdAt;

  SeatOverviewBooking({
    required this.reporteeId,
    required this.reporteeName,
    required this.bookingId,
    required this.status,
    required this.createdAt,
  });

  factory SeatOverviewBooking.fromJson(Map<String, dynamic> json) =>
      SeatOverviewBooking(
        reporteeId: json['reporteeId'],
        reporteeName: json['reporteeName'],
        bookingId: json['bookingId'],
        status: json['status'],
        createdAt: json['createdAt'],
      );
}

class SeatOverviewResponse {
  final int id;
  final String label;
  final int teamId;
  final String teamName;
  final bool isEngaged;
  final SeatOverviewBooking? engagedBy;

  SeatOverviewResponse({
    required this.id,
    required this.label,
    required this.teamId,
    required this.teamName,
    required this.isEngaged,
    this.engagedBy,
  });

  factory SeatOverviewResponse.fromJson(Map<String, dynamic> json) =>
      SeatOverviewResponse(
        id: json['id'],
        label: json['label'],
        teamId: json['teamId'],
        teamName: json['teamName'],
        isEngaged: json['isEngaged'] ?? false,
        engagedBy: json['engagedBy'] != null
            ? SeatOverviewBooking.fromJson(json['engagedBy'])
            : null,
      );
}
