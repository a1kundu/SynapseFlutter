import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/api_service.dart';
import '../models/models.dart';
import '../widgets/seat_booking_card.dart';
import '../widgets/date_navigator.dart';
import '../widgets/filter_chip_bar.dart';
import '../widgets/empty_state.dart';

enum SeatFilter { all, vacant, engaged }

class SeatSearchScreen extends StatefulWidget {
  const SeatSearchScreen({super.key});

  @override
  State<SeatSearchScreen> createState() => _SeatSearchScreenState();
}

class _SeatSearchScreenState extends State<SeatSearchScreen>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  final ApiService _api = ApiService();
  final TextEditingController _searchController = TextEditingController();

  List<SeatOverviewResponse> _allSeats = [];
  bool _loading = true;
  String? _error;
  DateTime _selectedDate = DateTime.now();
  SeatFilter _activeFilter = SeatFilter.all;

  String get _dateString => DateFormat('yyyy-MM-dd').format(_selectedDate);

  List<SeatOverviewResponse> get _filteredSeats {
    var seats = _allSeats;
    final q = _searchController.text.toLowerCase().trim();
    if (q.isNotEmpty) {
      seats = seats
          .where(
            (s) =>
                s.label.toLowerCase().contains(q) ||
                s.teamName.toLowerCase().contains(q),
          )
          .toList();
    }
    switch (_activeFilter) {
      case SeatFilter.engaged:
        return seats.where((s) => s.isEngaged).toList();
      case SeatFilter.vacant:
        return seats.where((s) => !s.isEngaged).toList();
      case SeatFilter.all:
        return seats;
    }
  }

  int get _vacantCount => _allSeats.where((s) => !s.isEngaged).length;
  int get _engagedCount => _allSeats.where((s) => s.isEngaged).length;

  @override
  void initState() {
    super.initState();
    _loadSeats();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadSeats() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final seats = await _api.getAllSeats(_dateString);
      setState(() {
        _allSeats = seats;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  void _onDateChange(int delta) {
    setState(() => _selectedDate = _selectedDate.add(Duration(days: delta)));
    _loadSeats();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2024),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() => _selectedDate = picked);
      _loadSeats();
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final cs = Theme.of(context).colorScheme;
    final filtered = _filteredSeats;

    return Scaffold(
      body: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: SearchBar(
              controller: _searchController,
              hintText: 'Search by seat label or team...',
              leading: const Icon(Icons.search),
              trailing: [
                if (_searchController.text.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () {
                      _searchController.clear();
                      setState(() {});
                    },
                  ),
              ],
              onChanged: (_) => setState(() {}),
            ),
          ),
          // Date selector
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: DateSelectorRow(
              selectedDate: _selectedDate,
              onPreviousDay: () => _onDateChange(-1),
              onNextDay: () => _onDateChange(1),
              onTap: _pickDate,
            ),
          ),
          // Filter chips
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: FilterChipBar<SeatFilter>(
              items: [
                FilterChipItem(
                  label: 'All (${_allSeats.length})',
                  value: SeatFilter.all,
                ),
                FilterChipItem(
                  label: 'Vacant ($_vacantCount)',
                  value: SeatFilter.vacant,
                ),
                FilterChipItem(
                  label: 'Engaged ($_engagedCount)',
                  value: SeatFilter.engaged,
                ),
              ],
              activeFilter: _activeFilter,
              onSelected: (filter) => setState(() => _activeFilter = filter),
            ),
          ),
          const SizedBox(height: 8),
          // Content
          Expanded(
            child: RefreshIndicator(
              onRefresh: _loadSeats,
              child: _buildContent(cs, filtered),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(ColorScheme cs, List<SeatOverviewResponse> filtered) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: EmptyState(
          icon: Icons.cloud_off_rounded,
          title: _error!,
          onRetry: _loadSeats,
        ),
      );
    }

    if (filtered.isEmpty) {
      return ListView(
        children: const [
          SizedBox(height: 100),
          EmptyState(
            icon: Icons.event_seat,
            title: 'No seats found. Adjust your search or filter.',
          ),
        ],
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 80),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 300,
        childAspectRatio: 2.0,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: filtered.length,
      itemBuilder: (context, index) {
        return SeatOverviewCard(seat: filtered[index]);
      },
    );
  }
}
