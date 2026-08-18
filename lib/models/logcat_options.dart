/// Logcat buffer, aligned with `adb logcat -b`.
enum LogcatBuffer {
  main('main', 'Main'),
  system('system', 'System'),
  crash('crash', 'Crash'),
  radio('radio', 'Radio'),
  events('events', 'Events'),
  all('all', 'All');

  const LogcatBuffer(this.id, this.label);

  final String id;
  final String label;
}
