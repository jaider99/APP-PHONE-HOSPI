import 'package:flutter/foundation.dart';
import 'package:hospi_dash/core/services/supabase_service.dart';
import 'package:hospi_dash/features/sales/data/models/sales_models.dart';

/// Service for generating AI-powered insights about sales performance.
/// Uses a server-side Edge Function — API keys are never on the client.
/// Falls back to rule-based insights if the Edge Function is unavailable.
class InsightService {
  InsightService();

  /// Generate a natural language insight from structured data
  Future<String> generateInsight(InsightData data) async {
    try {
      final response = await SupabaseService.client.functions.invoke(
        'generate-insight',
        body: data.toJson(),
      );

      if (response.status == 200 && response.data != null) {
        final result = response.data as Map<String, dynamic>;
        final insight = result['insight'] as String?;
        if (insight != null && insight.isNotEmpty) return insight;
      }
    } catch (e) {
      debugPrint('InsightService Edge Function error: $e');
    }

    // Fallback to rule-based insight
    return _getRuleBasedInsight(data);
  }

  /// Rule-based fallback for when server-side AI is unavailable
  String _getRuleBasedInsight(InsightData data) {
    final trend = data.trend;
    final change = data.changePercent;
    
    if (trend == 'down' && change < -10) {
      return 'Sales dropped significantly. Investigate external factors and consider running a targeted promotion.';
    }
    
    if (trend == 'down' && change >= -10) {
      return 'Sales are slightly below last period. Monitor closely.';
    }
    
    if (trend == 'up' && change > 10) {
      return "Strong performance this period. Identify what's driving growth and replicate it.";
    }
    
    return 'Performance is stable compared to the previous period.';
  }
}
