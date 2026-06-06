import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';
import '../models/models.dart';
import '../utils/clipboard_otp_mixin.dart';
import '../utils/snackbar_service.dart';
import '../widgets/seat_booking_card.dart';
import '../widgets/date_navigator.dart';
import '../widgets/availability_stats.dart';
import '../widgets/waitlist_card.dart';
import '../widgets/manage_seats_card.dart';
import '../widgets/pending_approvals_card.dart';
import '../widgets/member_list_card.dart';
import '../widgets/danger_zone_card.dart';
import '../widgets/range_availability_card.dart';
import '../widgets/range_booking_result_card.dart';
import '../dialogs/totp_prompt_dialog.dart';
import '../dialogs/join_team_dialog.dart';
import '../dialogs/book_seat_dialog.dart';
import '../dialogs/range_book_dialog.dart';

class TeamDetailScreen extends StatefulWidget {
  final int teamId;
  const TeamDetailScreen({super.key, required this.teamId});

  @override
  State<TeamDetailScreen> createState() => _TeamDetailScreenState();
}

class _TeamDetailScreenState extends State<TeamDetailScreen>
    with
        SingleTickerProviderStateMixin,
        WidgetsBindingObserver,
        ClipboardOtpMixin {
  final ApiService _api = ApiService();
  late TabController _tabController;

  TeamResponse? _team;
  List<SeatResponse> _seats = [];
  List<ReporteeResponse> _reportees = [];
  AvailabilityResponse? _availability;
  AvailabilityResponse?
  _lastAvailability; // kept during refresh for flicker-free UI
  bool _loading = true;
  bool _availabilityLoading = false;
  bool _notFound = false;
  String? _availabilityError;
  DateTime _selectedDate = DateTime.now();
  final TextEditingController _seatLabelCtrl = TextEditingController();
  int? _currentReporteeId;
  late final StreamSubscription _recoverySub;

  // Range availability state
  bool _showRangeView = false;
  RangeAvailabilityResponse? _rangeAvailability;
  bool _rangeLoading = false;
  DateTime _rangeFrom = DateTime.now();
  DateTime _rangeTo = DateTime.now().add(const Duration(days: 13));
  RangeBookingResponse? _lastRangeBookResult;

  List<ReporteeResponse> get _approvedReportees =>
      _reportees.where((r) => r.isApproved).toList();
  List<ReporteeResponse> get _pendingReportees =>
      _reportees.where((r) => !r.isApproved).toList();

  List<SeatView> get _allSeats {
    final booked = (_availability?.bookings ?? []).map(
      (b) => SeatView(
        seatId: b.seatId,
        label: b.seatLabel,
        status: 'booked',
        personName: b.reporteeName,
        booking: b,
      ),
    );
    final available = (_availability?.availableSeats ?? []).map(
      (s) => SeatView(seatId: s.id, label: s.label, status: 'available'),
    );
    return [...booked, ...available];
  }

  String get _dateString => DateFormat('yyyy-MM-dd').format(_selectedDate);
  bool get _isToday =>
      DateFormat('yyyy-MM-dd').format(_selectedDate) ==
      DateFormat('yyyy-MM-dd').format(DateTime.now());

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    initClipboardOtp();
    _tabController = TabController(length: 2, vsync: this);
    _loadCurrentReporteeId();
    _loadAll();
    _recoverySub = _api.backendRecovered.stream.listen((_) => _loadAll());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    handleLifecycleForOtp(state);
  }

  Future<void> _loadCurrentReporteeId() async {
    final prefs = await SharedPreferences.getInstance();
    final savedId = prefs.getInt('reportee_${widget.teamId}');
    if (savedId != null && mounted) {
      setState(() => _currentReporteeId = savedId);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    disposeClipboardOtp();
    _recoverySub.cancel();
    _tabController.dispose();
    _seatLabelCtrl.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Data loading
  // ---------------------------------------------------------------------------

  Future<void> _loadAll() async {
    setState(() {
      _loading = true;
      _notFound = false;
    });
    try {
      final results = await Future.wait([
        _api.getTeam(widget.teamId),
        _api.listSeats(widget.teamId),
        _api.listReportees(widget.teamId),
      ]);
      setState(() {
        _team = results[0] as TeamResponse;
        _seats = results[1] as List<SeatResponse>;
        _reportees = results[2] as List<ReporteeResponse>;
      });
      await _loadAvailability();
    } catch (e) {
      setState(() {
        _notFound = true;
        _loading = false;
      });
    }
  }

  Future<void> _loadAvailability() async {
    setState(() {
      _availabilityLoading = true;
      _availabilityError = null;
      // Keep _lastAvailability so waitlist card doesn't flicker away
      if (_availability != null) _lastAvailability = _availability;
      _availability = null;
    });
    try {
      final avail = await _api.getAvailability(widget.teamId, _dateString);
      setState(() {
        _availability = avail;
        _lastAvailability = avail;
        _availabilityLoading = false;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _availabilityLoading = false;
        _loading = false;
        _availabilityError = _api.noInternet.value
            ? 'No internet connection'
            : 'Unable to load availability';
      });
    }
  }

  // ---------------------------------------------------------------------------
  // Date navigation
  // ---------------------------------------------------------------------------

  void _goToPreviousDay() {
    setState(
      () => _selectedDate = _selectedDate.subtract(const Duration(days: 1)),
    );
    _loadAvailability();
  }

  void _goToNextDay() {
    setState(() => _selectedDate = _selectedDate.add(const Duration(days: 1)));
    _loadAvailability();
  }

  void _goToToday() {
    setState(() => _selectedDate = DateTime.now());
    _loadAvailability();
  }

  // ---------------------------------------------------------------------------
  // Actions (business logic delegated to dialogs / api)
  // ---------------------------------------------------------------------------

  Future<String?> _promptTotp(
    String title, {
    String? entityName,
    String? reason,
  }) async {
    final result = await showTotpPromptDialog(
      context,
      title: title,
      entityName: entityName,
      reason: reason,
      clipboardOtp: clipboardOtp,
      pasteClipboardCode: pasteClipboardCode,
      launchAuthenticator: launchAuthenticator,
    );
    resetClipboardOtp();
    return result;
  }

  void _openBookDialog(int seatId, String seatLabel) async {
    final bookedIds = (_availability?.bookings ?? [])
        .map((b) => b.reporteeId)
        .toSet();
    final availableReportees = _approvedReportees
        .where((r) => !bookedIds.contains(r.id))
        .toList();

    final success = await showBookSeatDialog(
      context,
      seatId: seatId,
      seatLabel: seatLabel,
      selectedDate: _selectedDate,
      availableReportees: availableReportees,
      currentReporteeId: _currentReporteeId,
      clipboardOtp: clipboardOtp,
      pasteClipboardCode: pasteClipboardCode,
      launchAuthenticator: launchAuthenticator,
    );
    resetClipboardOtp();
    if (success == true) _loadAvailability();
  }

  void _cancelBooking(BookingResponse booking) async {
    final confirmed = await showConfirmActionDialog(
      context,
      title: 'Cancel Booking',
      message:
          'Cancel booking for ${booking.reporteeName} on ${booking.seatLabel}?',
      confirmLabel: 'Yes, cancel',
      cancelLabel: 'No',
      isDestructive: true,
    );
    if (confirmed != true) return;
    final code = await _promptTotp(
      'Cancel Booking',
      entityName: booking.reporteeName,
      reason: 'Cancel booking',
    );
    if (code == null || code.isEmpty) return;
    try {
      await _api.cancelBooking(booking.id, booking.reporteeId, code);
      _loadAvailability();
      if (mounted) {
        showRootSnackBar(const SnackBar(content: Text('Booking cancelled')));
      }
    } catch (e) {
      if (mounted) {
        showRootSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  void _waitlistSeat(int seatId, String seatLabel) async {
    final bookedIds = (_availability?.bookings ?? [])
        .map((b) => b.reporteeId)
        .toSet();
    final availableReportees = _approvedReportees
        .where((r) => !bookedIds.contains(r.id))
        .toList();

    final success = await showBookSeatDialog(
      context,
      seatId: seatId,
      seatLabel: seatLabel,
      selectedDate: _selectedDate,
      availableReportees: availableReportees,
      currentReporteeId: _currentReporteeId,
      clipboardOtp: clipboardOtp,
      pasteClipboardCode: pasteClipboardCode,
      launchAuthenticator: launchAuthenticator,
    );
    resetClipboardOtp();
    if (success == true) {
      _loadAvailability();
      if (mounted) {
        showRootSnackBar(SnackBar(content: Text('Waitlisted for $seatLabel')));
      }
    }
  }

  void _cancelWaitlist(WaitlistInfo w) async {
    final confirmed = await showConfirmActionDialog(
      context,
      title: 'Cancel Waitlist',
      message:
          'Remove ${w.reporteeName} from the waitlist for ${w.desiredSeatLabel}?',
      confirmLabel: 'Yes, cancel',
      cancelLabel: 'No',
      isDestructive: true,
    );
    if (confirmed != true) return;

    // Resolve reporteeId — may be null in model, fall back to name lookup
    final reporteeId =
        w.reporteeId ??
        _reportees
            .where((r) => r.friendlyName == w.reporteeName)
            .map((r) => r.id)
            .firstOrNull;
    if (reporteeId == null) {
      if (mounted) {
        showRootSnackBar(
          const SnackBar(content: Text('Cannot identify reportee')),
        );
      }
      return;
    }

    final code = await _promptTotp(
      'Cancel Waitlist',
      entityName: w.reporteeName,
      reason: 'Cancel waitlist entry',
    );
    if (code == null || code.isEmpty) return;
    try {
      await _api.cancelBooking(w.bookingId, reporteeId, code);
      _loadAvailability();
      if (mounted) {
        showRootSnackBar(
          SnackBar(
            content: Text(
              'Removed ${w.reporteeName} from waitlist for ${w.desiredSeatLabel}',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        showRootSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  void _addSeat() async {
    final label = _seatLabelCtrl.text.trim();
    if (label.isEmpty) return;
    final code = await _promptTotp(
      'Add Seat',
      entityName: _team?.name ?? '',
      reason: 'Add seat',
    );
    if (code == null || code.isEmpty) return;
    try {
      await _api.addSeat(widget.teamId, label, code);
      _seatLabelCtrl.clear();
      _loadAll();
      if (mounted) {
        showRootSnackBar(SnackBar(content: Text('Seat "$label" added')));
      }
    } catch (e) {
      if (mounted) {
        showRootSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  void _deleteSeat(SeatResponse seat) async {
    final code = await _promptTotp(
      'Delete Seat',
      entityName: _team?.name ?? '',
      reason: 'Delete seat',
    );
    if (code == null || code.isEmpty) return;
    try {
      await _api.deleteSeat(widget.teamId, seat.id, code);
      _loadAll();
      if (mounted) {
        showRootSnackBar(
          SnackBar(content: Text('Seat "${seat.label}" deleted')),
        );
      }
    } catch (e) {
      if (mounted) {
        showRootSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  void _approveReportee(int reporteeId) async {
    final code = await _promptTotp(
      'Approve Member',
      entityName: _team?.name ?? '',
      reason: 'Approve member',
    );
    if (code == null || code.isEmpty) return;
    try {
      await _api.approveReportee(widget.teamId, reporteeId, code);
      _loadAll();
      if (mounted) {
        showRootSnackBar(const SnackBar(content: Text('Member approved')));
      }
    } catch (e) {
      if (mounted) {
        showRootSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  void _denyReportee(ReporteeResponse r) async {
    final confirmed = await showConfirmActionDialog(
      context,
      title: 'Deny Join Request',
      message: 'Deny ${r.friendlyName} from joining?',
      confirmLabel: 'Deny',
      isDestructive: true,
    );
    if (confirmed != true) return;
    final code = await _promptTotp(
      'Deny Join Request',
      entityName: _team?.name ?? '',
      reason: 'Deny join request',
    );
    if (code == null || code.isEmpty) return;
    try {
      await _api.denyReportee(widget.teamId, r.id, code);
      _loadAll();
      if (mounted) {
        showRootSnackBar(SnackBar(content: Text('Denied ${r.friendlyName}')));
      }
    } catch (e) {
      if (mounted) {
        showRootSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  void _removeReportee(ReporteeResponse r) async {
    final confirmed = await showConfirmActionDialog(
      context,
      title: 'Remove Member',
      message: 'Remove ${r.friendlyName} and all their bookings?',
      confirmLabel: 'Remove',
      isDestructive: true,
    );
    if (confirmed != true) return;
    final code = await _promptTotp(
      'Remove Member',
      entityName: _team?.name ?? '',
      reason: 'Remove member',
    );
    if (code == null || code.isEmpty) return;
    try {
      await _api.removeReportee(widget.teamId, r.id, code);
      _loadAll();
      if (mounted) {
        showRootSnackBar(SnackBar(content: Text('Removed ${r.friendlyName}')));
      }
    } catch (e) {
      if (mounted) {
        showRootSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  void _deleteTeam() async {
    final confirmed = await showConfirmActionDialog(
      context,
      title: 'Delete Team',
      message:
          'Delete "${_team?.name}" and all its data? This cannot be undone.',
      confirmLabel: 'Delete',
      isDestructive: true,
    );
    if (confirmed != true) return;
    final code = await _promptTotp(
      'Delete Team',
      entityName: _team?.name ?? '',
      reason: 'Delete team',
    );
    if (code == null || code.isEmpty) return;
    try {
      await _api.deleteTeam(widget.teamId, code);
      if (mounted) {
        showRootSnackBar(const SnackBar(content: Text('Team deleted')));
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        showRootSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  void _openJoinDialog() async {
    final reporteeId = await showJoinTeamDialog(
      context,
      teamId: widget.teamId,
      teamName: _team?.name,
      clipboardOtp: clipboardOtp,
      pasteClipboardCode: pasteClipboardCode,
      launchAuthenticatorWithUri: launchAuthenticatorWithUri,
    );
    resetClipboardOtp();
    if (reporteeId != null) {
      _currentReporteeId = reporteeId;
      _loadAll();
      if (mounted) {
        showRootSnackBar(
          const SnackBar(
            content: Text('Join request sent! Awaiting manager approval.'),
          ),
        );
      }
    }
  }

  void _copyTeamUrl() {
    Clipboard.setData(
      ClipboardData(
        text: 'https://officeaschi.azurewebsites.net/team/${widget.teamId}',
      ),
    );
    showRootSnackBar(const SnackBar(content: Text('Team link copied!')));
  }

  // ---------------------------------------------------------------------------
  // Range view & booking
  // ---------------------------------------------------------------------------

  void _toggleRangeView() {
    setState(() => _showRangeView = !_showRangeView);
    if (_showRangeView && _rangeAvailability == null) {
      _loadRangeAvailability();
    }
  }

  Future<void> _loadRangeAvailability() async {
    setState(() => _rangeLoading = true);
    try {
      final fromStr = DateFormat('yyyy-MM-dd').format(_rangeFrom);
      final toStr = DateFormat('yyyy-MM-dd').format(_rangeTo);
      final result = await _api.getAvailabilityRange(
        widget.teamId,
        fromStr,
        toStr,
      );
      if (mounted) {
        setState(() {
          _rangeAvailability = result;
          _rangeLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _rangeLoading = false);
        showRootSnackBar(
          SnackBar(content: Text('Failed to load range availability: $e')),
        );
      }
    }
  }

  void _onRangeChanged(DateTime from, DateTime to) {
    setState(() {
      _rangeFrom = from;
      _rangeTo = to;
    });
    _loadRangeAvailability();
  }

  void _jumpToDate(String dateStr) {
    setState(() {
      _selectedDate = DateTime.parse(dateStr);
    });
    _loadAvailability();
  }

  void _openRangeBookDialog() async {
    final result = await showRangeBookDialog(
      context,
      seats: _seats,
      availableReportees: _approvedReportees,
      currentReporteeId: _currentReporteeId,
      defaultDate: _selectedDate,
      clipboardOtp: clipboardOtp,
      pasteClipboardCode: pasteClipboardCode,
      launchAuthenticator: launchAuthenticator,
    );
    resetClipboardOtp();
    if (result != null && mounted) {
      setState(() => _lastRangeBookResult = result);
      _loadAvailability();
      if (_showRangeView) _loadRangeAvailability();
    }
  }

  void _dismissRangeResult() {
    setState(() => _lastRangeBookResult = null);
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    if (_notFound) {
      return Scaffold(
        appBar: AppBar(title: const Text('Team Not Found')),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 64),
              const SizedBox(height: 16),
              const Text('Team not found', style: TextStyle(fontSize: 20)),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.arrow_back),
                label: const Text('Back to Teams'),
              ),
            ],
          ),
        ),
      );
    }

    final cs = Theme.of(context).colorScheme;
    final pendingCount = _pendingReportees.length;
    return Scaffold(
      appBar: AppBar(
        title: Text(_team?.name ?? 'Loading...'),
        actions: _team == null
            ? null
            : [
                IconButton(
                  icon: const Icon(Icons.share),
                  onPressed: _copyTeamUrl,
                  tooltip: 'Copy team link',
                  style: IconButton.styleFrom(
                    backgroundColor: cs.primaryContainer,
                    foregroundColor: cs.onPrimaryContainer,
                  ),
                ),
                const SizedBox(width: 6),
                IconButton(
                  icon: const Icon(Icons.person_add),
                  onPressed: _openJoinDialog,
                  tooltip: 'Join team',
                  style: IconButton.styleFrom(
                    backgroundColor: cs.primaryContainer,
                    foregroundColor: cs.onPrimaryContainer,
                  ),
                ),
                const SizedBox(width: 8),
              ],
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            const Tab(text: 'Bookings', icon: Icon(Icons.calendar_today)),
            Tab(
              text: 'Manage',
              icon: Badge(
                isLabelVisible: pendingCount > 0,
                label: Text('$pendingCount'),
                child: const Icon(Icons.settings),
              ),
            ),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [_buildBookingsTab(), _buildManageTab()],
            ),
    );
  }

  // ---------------------------------------------------------------------------
  // Bookings Tab
  // ---------------------------------------------------------------------------

  Widget _buildBookingsTab() {
    // Use _lastAvailability during refresh so waitlist/all-booked don't flicker
    final displayAvail = _availability ?? _lastAvailability;
    final allBooked =
        (displayAvail?.availableCount ?? 1) == 0 &&
        (displayAvail?.totalSeats ?? 0) > 0;
    final waitlist = displayAvail?.waitlist ?? [];
    final cs = Theme.of(context).colorScheme;

    return RefreshIndicator(
      onRefresh: _loadAvailability,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Range action buttons
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 500),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _toggleRangeView,
                          icon: Icon(
                            _showRangeView
                                ? Icons.calendar_today
                                : Icons.date_range,
                            size: 18,
                          ),
                          label: Text(
                            _showRangeView ? 'Hide Range' : 'Range View',
                          ),
                          style: OutlinedButton.styleFrom(
                            side: _showRangeView
                                ? BorderSide(color: cs.primary, width: 1.5)
                                : null,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _openRangeBookDialog,
                          icon: const Icon(Icons.calendar_month, size: 18),
                          label: const Text('Book Range'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              // Range availability card — kept alive, collapsed when hidden
              ClipRect(
                child: AnimatedAlign(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeInOut,
                  alignment: Alignment.topCenter,
                  heightFactor: _showRangeView ? 1.0 : 0.0,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: RangeAvailabilityCard(
                      rangeAvailability: _rangeAvailability,
                      loading: _rangeLoading,
                      rangeFrom: _rangeFrom,
                      rangeTo: _rangeTo,
                      selectedDate: _selectedDate,
                      onRangeChanged: _onRangeChanged,
                      onJumpToDate: _jumpToDate,
                    ),
                  ),
                ),
              ),
              // Range booking result card
              if (_lastRangeBookResult != null) ...[
                RangeBookingResultCard(
                  result: _lastRangeBookResult!,
                  onDismiss: _dismissRangeResult,
                ),
                const SizedBox(height: 12),
              ],
              DateNavigator(
                selectedDate: _selectedDate,
                onPreviousDay: _goToPreviousDay,
                onNextDay: _goToNextDay,
                onToday: _isToday ? null : _goToToday,
                onDatePicked: (picked) {
                  setState(() => _selectedDate = picked);
                  _loadAvailability();
                },
              ),
              const SizedBox(height: 16),
              AvailabilityStats(availability: displayAvail),
              const SizedBox(height: 12),
              _availabilityLoading
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(32),
                        child: CircularProgressIndicator(),
                      ),
                    )
                  : _availabilityError != null
                  ? _buildAvailabilityError()
                  : _buildSeatGrid(),
              // "All Seats Booked — join waitlist" section
              if (!_availabilityLoading &&
                  _availabilityError == null &&
                  allBooked &&
                  (displayAvail?.bookings ?? []).isNotEmpty) ...[
                const SizedBox(height: 16),
                AllSeatsBookedCard(
                  bookedSeats: displayAvail!.bookings,
                  onWaitlist: _waitlistSeat,
                ),
              ],
              // Current waitlist entries
              if (waitlist.isNotEmpty) ...[
                const SizedBox(height: 16),
                WaitlistCard(waitlist: waitlist, onCancel: _cancelWaitlist),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAvailabilityError() {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cs.errorContainer,
              shape: BoxShape.circle,
            ),
            child: Icon(
              _api.noInternet.value
                  ? Icons.wifi_off_rounded
                  : Icons.cloud_off_rounded,
              size: 36,
              color: cs.onErrorContainer,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            _availabilityError!,
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            'Tap retry to reload bookings for this date.',
            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _loadAvailability,
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Widget _buildSeatGrid() {
    final seats = _allSeats;
    if (seats.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            'No seats configured yet. Go to Manage tab to add seats.',
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = constraints.maxWidth > 800
            ? 4
            : constraints.maxWidth > 500
            ? 3
            : constraints.maxWidth > 350
            ? 2
            : 1;
        final aspectRatio = crossAxisCount == 1 ? 3.5 : 1.8;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: aspectRatio,
          ),
          itemCount: seats.length,
          itemBuilder: (context, index) {
            final seat = seats[index];
            return SeatBookingCard(
              seat: seat,
              onBook: () => _openBookDialog(seat.seatId, seat.label),
              onCancel: seat.booking != null
                  ? () => _cancelBooking(seat.booking!)
                  : null,
            );
          },
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Manage Tab
  // ---------------------------------------------------------------------------

  Widget _buildManageTab() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > 800;
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 12),
              children: [
                if (isWide)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          children: [
                            ManageSeatsCard(
                              seats: _seats,
                              seatLabelController: _seatLabelCtrl,
                              onDeleteSeat: _deleteSeat,
                              onAddSeat: _addSeat,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          children: [
                            if (_pendingReportees.isNotEmpty) ...[
                              PendingApprovalsCard(
                                pendingMembers: _pendingReportees,
                                onApprove: _approveReportee,
                                onDeny: _denyReportee,
                              ),
                              const SizedBox(height: 12),
                            ],
                            MemberListCard(
                              members: _approvedReportees,
                              onRemove: _removeReportee,
                            ),
                          ],
                        ),
                      ),
                    ],
                  )
                else ...[
                  ManageSeatsCard(
                    seats: _seats,
                    seatLabelController: _seatLabelCtrl,
                    onDeleteSeat: _deleteSeat,
                    onAddSeat: _addSeat,
                  ),
                  const SizedBox(height: 12),
                  if (_pendingReportees.isNotEmpty) ...[
                    PendingApprovalsCard(
                      pendingMembers: _pendingReportees,
                      onApprove: _approveReportee,
                      onDeny: _denyReportee,
                    ),
                    const SizedBox(height: 12),
                  ],
                  MemberListCard(
                    members: _approvedReportees,
                    onRemove: _removeReportee,
                  ),
                ],
                const SizedBox(height: 12),
                DangerZoneCard(
                  title: 'Delete this team',
                  subtitle: 'Removes all seats, members, and bookings.',
                  onAction: _deleteTeam,
                ),
                const SizedBox(height: 32),
              ],
            ),
          ),
        );
      },
    );
  }
}
