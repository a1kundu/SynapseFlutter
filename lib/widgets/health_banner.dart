import 'package:flutter/material.dart';
import '../services/api_service.dart';

/// Banner displayed at the top of the app when the backend is unreachable
/// or internet connectivity is lost.
class HealthBanner extends StatelessWidget {
  final ApiService api;
  const HealthBanner({super.key, required this.api});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([api.backendDown, api.noInternet]),
      builder: (context, _) {
        if (!api.backendDown.value) return const SizedBox.shrink();
        final isNoInternet = api.noInternet.value;
        final cs = Theme.of(context).colorScheme;
        return Material(
          child: Container(
            width: double.infinity,
            padding: EdgeInsets.only(
              top: MediaQuery.of(context).padding.top + 8,
              bottom: 8,
              left: 16,
              right: 16,
            ),
            color: cs.errorContainer,
            child: Row(
              children: [
                Icon(
                  isNoInternet ? Icons.wifi_off : Icons.cloud_off,
                  size: 18,
                  color: cs.onErrorContainer,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    isNoInternet
                        ? 'No internet connection'
                        : 'Backend server is unavailable',
                    style: TextStyle(
                      color: cs.onErrorContainer,
                      fontWeight: FontWeight.w500,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
