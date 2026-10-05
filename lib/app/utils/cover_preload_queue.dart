import 'dart:async';
import 'dart:collection';

/// Keeps speculative cover requests behind a small concurrency budget.
class CoverPreloadQueue {
  CoverPreloadQueue({
    required this.load,
    this.maxConcurrent = 2,
    this.maxRemembered = 128,
    this.onError,
  }) : assert(maxConcurrent > 0),
       assert(maxRemembered > 0);

  final Future<void> Function(String url) load;
  final int maxConcurrent;
  final int maxRemembered;
  final void Function(Object error)? onError;
  final Queue<String> _pending = Queue();
  final Set<String> _scheduled = {};
  final LinkedHashSet<String> _completed = LinkedHashSet();
  int _running = 0;
  bool _disposed = false;

  void enqueueAll(Iterable<String> urls) {
    if (_disposed) return;
    for (final url in urls) {
      if (_completed.contains(url) || !_scheduled.add(url)) continue;
      _pending.add(url);
    }
    _drain();
  }

  void _drain() {
    while (!_disposed && _running < maxConcurrent && _pending.isNotEmpty) {
      final url = _pending.removeFirst();
      _running++;
      unawaited(_run(url));
    }
  }

  Future<void> _run(String url) async {
    try {
      await load(url);
      if (!_disposed) {
        _completed.add(url);
        while (_completed.length > maxRemembered) {
          _completed.remove(_completed.first);
        }
      }
    } catch (error) {
      onError?.call(error);
    } finally {
      _scheduled.remove(url);
      _running--;
      _drain();
    }
  }

  void dispose() {
    _disposed = true;
    _pending.clear();
    _completed.clear();
    _scheduled.clear();
  }
}
