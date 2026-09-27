/// Current time as a UTC ISO-8601 string, used for every `creation_date`
/// sent to the backend.
///
/// The backend runs with `USE_TZ = True`, so it stores and compares these as
/// UTC. Sending a local-clock timestamp (which is what
/// `DateTime.now().toIso8601String()` produces, because `DateTime.now()`
/// returns a *local* DateTime) shifts every stored record by the device's
/// UTC offset. That corrupts receipt timestamps and breaks any time-window
/// query the server runs against them.
///
/// Always use this instead of `DateTime.now().toIso8601String()`.
String utcNowIso() => DateTime.now().toUtc().toIso8601String();
