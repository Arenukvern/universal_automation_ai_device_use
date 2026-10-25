import 'package:meta/meta.dart';

import 'automation_exceptions_export.dart';
import 'cdp_discovery.dart';

/// A target selector matched no surface, or more than one.
///
/// Distinct from [EndpointUnreachableException]: the endpoint answered
/// and listed its targets — the *choice* among them was ambiguous or
/// impossible. The remedy is in the message: narrow the selector.
@immutable
class TargetSelectionException extends AutomationException {
  /// Creates the exception for a selector that matched [matches] targets.
  TargetSelectionException(
    this.selector,
    this.matches, {
    required String message,
  }) : super(
         message,
         details: {
           'selector': selector.describe(),
           'matches': matches.length,
           if (matches.isNotEmpty)
             'candidates': [
               for (final target in matches)
                 {'id': target.id, 'type': target.type, 'url': target.url},
             ],
         },
       );

  /// The selector that was asked for.
  final CdpTargetSelector selector;

  /// The targets that matched it.
  final List<CdpTargetInfo> matches;

  @override
  String get kind => 'targetSelection';
}
