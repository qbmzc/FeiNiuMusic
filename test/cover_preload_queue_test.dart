import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:feiniu_music/app/utils/cover_preload_queue.dart';

Future<void> flushTasks() => Future<void>.delayed(Duration.zero);

void main() {
  test(
    'limits concurrent loads and deduplicates queued and completed covers',
    () async {
      final started = <String>[];
      final completions = <String, Completer<void>>{};
      final queue = CoverPreloadQueue(
        load: (url) {
          started.add(url);
          return (completions[url] = Completer<void>()).future;
        },
      );
      queue.enqueueAll(['hero', 'first', 'second', 'hero', 'second']);
      expect(started, ['hero', 'first']);
      queue.enqueueAll(['first', 'second']);
      completions['hero']!.complete();
      await flushTasks();
      expect(started, ['hero', 'first', 'second']);
      completions['first']!.complete();
      completions['second']!.complete();
      await flushTasks();
      queue.enqueueAll(['hero', 'first', 'second']);
      expect(started, ['hero', 'first', 'second']);
      queue.dispose();
    },
  );

  test('failed load releases its slot and can be retried', () async {
    var attempts = 0;
    final errors = <Object>[];
    final started = <String>[];
    final queue = CoverPreloadQueue(
      maxConcurrent: 1,
      onError: errors.add,
      load: (url) async {
        started.add(url);
        if (url == 'broken' && attempts++ == 0) throw StateError('offline');
      },
    );
    queue.enqueueAll(['broken', 'next']);
    await flushTasks();
    expect(started, ['broken', 'next']);
    expect(errors, hasLength(1));
    queue.enqueueAll(['broken']);
    await flushTasks();
    expect(started, ['broken', 'next', 'broken']);
    queue.dispose();
  });

  test(
    'disposing stops pending requests even when active loads finish',
    () async {
      final active = Completer<void>();
      final started = <String>[];
      final queue = CoverPreloadQueue(
        maxConcurrent: 1,
        load: (url) {
          started.add(url);
          return active.future;
        },
      );
      queue.enqueueAll(['active', 'pending']);
      queue.dispose();
      active.complete();
      await flushTasks();
      queue.enqueueAll(['new']);
      expect(started, ['active']);
    },
  );

  test('completed URL history is bounded', () async {
    final started = <String>[];
    final queue = CoverPreloadQueue(
      maxRemembered: 2,
      load: (url) async {
        started.add(url);
      },
    );
    queue.enqueueAll(['one', 'two', 'three']);
    await flushTasks();
    queue.enqueueAll(['two', 'three', 'one']);
    await flushTasks();
    expect(started, ['one', 'two', 'three', 'one']);
    queue.dispose();
  });
}
