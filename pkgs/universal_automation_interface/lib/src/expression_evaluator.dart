/// Evaluates an expression in the live surface and returns its value.
///
/// The read half of the `evaluate` action: `AutomationDriver.perform`
/// carries the intent, this capability returns the result. The value is
/// JSON-serializable when the surface could serialize it; a value the
/// protocol cannot serialize comes back as a small descriptor (`type`,
/// `description`) instead — evaluation never fails because of
/// serialization. A surface-side exception throws `ProtocolException`
/// (fail loudly); it is never swallowed into a silent `null`.
// Single-method by design: capability granularity lets a tier implement
// exactly the surfaces it has (the OsActivator/OsAppCatalog pattern).
// ignore: one_member_abstracts
abstract interface class ExpressionEvaluator {
  /// Evaluates [expression] and returns the JSON-serializable value —
  /// or the unserializable-value descriptor when the protocol reports
  /// the value's shape instead of its content.
  Future<Object?> evaluateExpression(String expression);
}
