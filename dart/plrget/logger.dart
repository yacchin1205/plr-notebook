import 'package:logger/logger.dart';

class DefaultLogFilter extends LogFilter {
  var _verbose = false;

  DefaultLogFilter();

  set verbose(bool value) {
    _verbose = value;
  }

  @override
  bool shouldLog(LogEvent event) {
    if (_verbose) {
      return true;
    }
    return event.level.index >= Level.warning.index;
  }
}

final logFilter = DefaultLogFilter();

final logger = Logger(
  filter: logFilter,
);
