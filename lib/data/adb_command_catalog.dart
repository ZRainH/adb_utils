import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

class AdbCommandItem {
  const AdbCommandItem({
    required this.command,
    required this.description,
    this.inlineCodes = const [],
  });

  final String command;
  final String description;
  final List<String> inlineCodes;
}

class AdbCommandSection {
  const AdbCommandSection({
    required this.title,
    required this.icon,
    required this.commandColor,
    required this.items,
  });

  final String title;
  final IconData icon;
  final Color commandColor;
  final List<AdbCommandItem> items;
}

/// Comprehensive ADB / shell command handbook used by CommandReferencePage.
List<AdbCommandSection> buildAdbCommandCatalog() {
  const purple = Color(0xFFCEC2DB);
  const green = Color(0xFFA8DAB5);
  const orange = Color(0xFFE6C07B);

  return [
    AdbCommandSection(
      title: '基础与服务',
      icon: Icons.desktop_windows_outlined,
      commandColor: AppColors.accentBright,
      items: [
        AdbCommandItem(command: 'adb version', description: '显示当前 ADB 客户端版本。'),
        AdbCommandItem(command: 'adb help', description: '显示 ADB 帮助与全部子命令说明。'),
        AdbCommandItem(command: 'adb start-server', description: '启动本机 ADB 服务端。'),
        AdbCommandItem(command: 'adb kill-server', description: '停止本机 ADB 服务端。'),
        AdbCommandItem(command: 'adb reconnect', description: '重新连接当前设备的 ADB。'),
        AdbCommandItem(command: 'adb reconnect device', description: '踢掉设备端 adbd 并重新连接。'),
        AdbCommandItem(command: 'adb reconnect offline', description: '重新连接处于 offline 状态的设备。'),
        AdbCommandItem(command: 'adb wait-for-device', description: '阻塞等待直到有设备进入 device 状态。'),
        AdbCommandItem(command: 'adb get-state', description: '获取设备状态（device / offline / bootloader 等）。'),
        AdbCommandItem(command: 'adb get-serialno', description: '获取设备序列号。'),
        AdbCommandItem(command: 'adb get-devpath', description: '获取设备 USB 路径。'),
      ],
    ),
    AdbCommandSection(
      title: '设备列表与目标选择',
      icon: Icons.phone_android,
      commandColor: AppColors.textMuted,
      items: [
        AdbCommandItem(command: 'adb devices', description: '列出已连接设备及其状态。'),
        AdbCommandItem(command: 'adb devices -l', description: '列出设备，并显示 model / product / transport 等信息。'),
        AdbCommandItem(command: 'adb -s <serial> <command>', description: '将后续命令发送到指定序列号的设备。'),
        AdbCommandItem(command: 'adb -d <command>', description: '仅指向唯一 USB 连接的真机。'),
        AdbCommandItem(command: 'adb -e <command>', description: '仅指向唯一正在运行的模拟器。'),
        AdbCommandItem(command: 'adb -t <transport_id> <command>', description: '按 transport id 指定设备。'),
      ],
    ),
    AdbCommandSection(
      title: '无线连接',
      icon: Icons.wifi,
      commandColor: AppColors.textMuted,
      items: [
        AdbCommandItem(command: 'adb tcpip <port>', description: '让设备 adbd 监听指定 TCP 端口（常用 5555）。'),
        AdbCommandItem(command: 'adb usb', description: '切回 USB 模式监听。'),
        AdbCommandItem(command: 'adb connect <ip>:<port>', description: '通过局域网 IP 连接设备。'),
        AdbCommandItem(command: 'adb disconnect [<ip>:<port>]', description: '断开指定无线连接；省略参数则断开全部 TCP 连接。'),
        AdbCommandItem(command: 'adb pair <ip>:<port> [<pairing_code>]', description: '无线调试配对（Android 11+）。'),
        AdbCommandItem(command: 'adb mdns services', description: '列出当前发现的 mDNS ADB 服务。'),
        AdbCommandItem(command: 'adb mdns check', description: '检查 mDNS 后端状态。'),
      ],
    ),
    AdbCommandSection(
      title: '应用安装与卸载',
      icon: Icons.android,
      commandColor: purple,
      items: [
        AdbCommandItem(
          command: 'adb install <path.apk>',
          description: '安装 APK。',
        ),
        AdbCommandItem(
          command: 'adb install -r <path.apk>',
          description: '覆盖安装并保留应用数据。使用 {code}。',
          inlineCodes: ['-r'],
        ),
        AdbCommandItem(
          command: 'adb install -d <path.apk>',
          description: '允许降级安装。使用 {code}。',
          inlineCodes: ['-d'],
        ),
        AdbCommandItem(
          command: 'adb install -g <path.apk>',
          description: '安装时授予清单中声明的全部运行时权限。使用 {code}。',
          inlineCodes: ['-g'],
        ),
        AdbCommandItem(
          command: 'adb install -t <path.apk>',
          description: '允许安装测试包（testOnly）。使用 {code}。',
          inlineCodes: ['-t'],
        ),
        AdbCommandItem(
          command: 'adb install-multiple <base.apk> <split*.apk>',
          description: '安装拆分包（App Bundle 拆出的多个 APK）。',
        ),
        AdbCommandItem(
          command: 'adb install-multi-package <apk1> <apk2> ...',
          description: '一次性安装多个独立包。',
        ),
        AdbCommandItem(
          command: 'adb uninstall <package>',
          description: '卸载应用。',
        ),
        AdbCommandItem(
          command: 'adb uninstall -k <package>',
          description: '卸载应用但保留数据和缓存。使用 {code}。',
          inlineCodes: ['-k'],
        ),
        AdbCommandItem(
          command: 'adb shell cmd package install-existing <package>',
          description: '重新启用设备上已存在但被卸载/禁用的系统应用。',
        ),
      ],
    ),
    AdbCommandSection(
      title: '包管理 (pm / cmd package)',
      icon: Icons.apps,
      commandColor: purple,
      items: [
        AdbCommandItem(command: 'adb shell pm list packages', description: '列出全部包名。'),
        AdbCommandItem(command: 'adb shell pm list packages -3', description: '仅第三方应用。'),
        AdbCommandItem(command: 'adb shell pm list packages -s', description: '仅系统应用。'),
        AdbCommandItem(command: 'adb shell pm list packages -d', description: '已禁用的应用。'),
        AdbCommandItem(command: 'adb shell pm list packages -e', description: '已启用的应用。'),
        AdbCommandItem(command: 'adb shell pm list packages -f', description: '列出包名及其 APK 路径。'),
        AdbCommandItem(command: 'adb shell pm list packages -i', description: '列出安装来源 installer。'),
        AdbCommandItem(command: 'adb shell pm list packages -u', description: '包含已卸载但仍保留数据的包。'),
        AdbCommandItem(command: 'adb shell pm path <package>', description: '显示包对应的 APK / split 路径。'),
        AdbCommandItem(command: 'adb shell pm dump <package>', description: '输出包详细信息。'),
        AdbCommandItem(command: 'adb shell pm clear <package>', description: '清除应用数据。'),
        AdbCommandItem(command: 'adb shell pm enable <package>', description: '启用包或组件。'),
        AdbCommandItem(command: 'adb shell pm disable-user <package>', description: '对当前用户禁用应用。'),
        AdbCommandItem(command: 'adb shell pm hide <package>', description: '隐藏应用（部分 ROM / 用户配置可用）。'),
        AdbCommandItem(command: 'adb shell pm unhide <package>', description: '取消隐藏应用。'),
        AdbCommandItem(command: 'adb shell pm grant <package> <permission>', description: '授予运行时权限。'),
        AdbCommandItem(command: 'adb shell pm revoke <package> <permission>', description: '撤销运行时权限。'),
        AdbCommandItem(command: 'adb shell pm reset-permissions', description: '重置全部应用权限（谨慎）。'),
        AdbCommandItem(command: 'adb shell pm list permissions -d -g', description: '按组列出危险权限。'),
        AdbCommandItem(command: 'adb shell cmd package resolve-activity --brief <intent>', description: '解析可处理该 Intent 的 Activity。'),
        AdbCommandItem(command: 'adb shell cmd package query-activities ...', description: '查询匹配 Intent 的 Activity 列表。'),
      ],
    ),
    AdbCommandSection(
      title: '启动与活动管理 (am)',
      icon: Icons.play_circle_outline,
      commandColor: purple,
      items: [
        AdbCommandItem(
          command: 'adb shell am start -n <pkg>/<activity>',
          description: '启动指定 Activity。',
        ),
        AdbCommandItem(
          command: 'adb shell am start -a android.intent.action.MAIN -c android.intent.category.LAUNCHER <pkg>',
          description: '按启动器方式启动应用。',
        ),
        AdbCommandItem(
          command: 'adb shell am start -a android.intent.action.VIEW -d <url>',
          description: '用 VIEW Intent 打开 URL / deep link。',
        ),
        AdbCommandItem(
          command: 'adb shell am force-stop <package>',
          description: '强制停止应用。',
        ),
        AdbCommandItem(
          command: 'adb shell am kill <package>',
          description: '在安全情况下杀掉后台进程。',
        ),
        AdbCommandItem(
          command: 'adb shell am kill-all',
          description: '杀掉所有后台进程。',
        ),
        AdbCommandItem(
          command: 'adb shell am clear-debug-app',
          description: '清除当前调试应用设置。',
        ),
        AdbCommandItem(
          command: 'adb shell am set-debug-app -w <package>',
          description: '设置等待调试器的调试应用。',
        ),
        AdbCommandItem(
          command: 'adb shell am broadcast -a <action>',
          description: '发送广播。',
        ),
        AdbCommandItem(
          command: 'adb shell am instrument -w <test_package>/<runner>',
          description: '运行 instrumentation 测试。',
        ),
        AdbCommandItem(
          command: 'adb shell am stack list',
          description: '列出当前 Activity 栈。',
        ),
        AdbCommandItem(
          command: 'adb shell am display list',
          description: '列出显示设备信息。',
        ),
      ],
    ),
    AdbCommandSection(
      title: '文件传输',
      icon: Icons.folder_outlined,
      commandColor: AppColors.accentBright,
      items: [
        AdbCommandItem(command: 'adb push <local> <remote>', description: '把本地文件/目录推到设备。'),
        AdbCommandItem(command: 'adb pull <remote> [<local>]', description: '从设备拉取文件/目录到本地。'),
        AdbCommandItem(command: 'adb sync [directory]', description: '同步 host 与设备上的分区内容（开发场景）。'),
        AdbCommandItem(command: 'adb shell ls -la <path>', description: '列出设备目录内容。'),
        AdbCommandItem(command: 'adb shell cd <path>', description: '进入目录（交互 shell 中使用）。'),
        AdbCommandItem(command: 'adb shell pwd', description: '显示当前路径。'),
        AdbCommandItem(command: 'adb shell mkdir -p <path>', description: '创建目录（可递归）。'),
        AdbCommandItem(command: 'adb shell rm [-rf] <path>', description: '删除文件或目录。'),
        AdbCommandItem(command: 'adb shell cp <src> <dst>', description: '复制文件。'),
        AdbCommandItem(command: 'adb shell mv <src> <dst>', description: '移动/重命名。'),
        AdbCommandItem(command: 'adb shell cat <file>', description: '输出文本文件内容。'),
        AdbCommandItem(command: 'adb shell chmod <mode> <path>', description: '修改权限。'),
        AdbCommandItem(command: 'adb shell df -h', description: '查看磁盘空间。'),
        AdbCommandItem(command: 'adb shell du -sh <path>', description: '查看目录占用空间。'),
      ],
    ),
    AdbCommandSection(
      title: '日志与调试',
      icon: Icons.bug_report_outlined,
      commandColor: AppColors.errorLog,
      items: [
        AdbCommandItem(command: 'adb logcat', description: '实时输出系统日志。'),
        AdbCommandItem(command: 'adb logcat -c', description: '清空日志缓冲区。'),
        AdbCommandItem(command: 'adb logcat -d', description: '转储当前缓冲区日志后退出。'),
        AdbCommandItem(command: 'adb logcat -v threadtime', description: '使用 threadtime 格式输出。'),
        AdbCommandItem(command: 'adb logcat -b crash', description: '仅查看 crash 缓冲区。'),
        AdbCommandItem(command: 'adb logcat -b all', description: '查看全部缓冲区。'),
        AdbCommandItem(command: 'adb logcat *:E', description: '仅显示 Error 及以上级别。'),
        AdbCommandItem(command: 'adb logcat <Tag>:D *:S', description: '仅显示指定 Tag，其余静默。'),
        AdbCommandItem(command: 'adb logcat -f /sdcard/log.txt', description: '将日志写入设备文件。'),
        AdbCommandItem(command: 'adb bugreport [<path>]', description: '生成完整 bugreport（zip）。'),
        AdbCommandItem(command: 'adb jdwp', description: '列出支持 JDWP 的进程 PID。'),
        AdbCommandItem(command: 'adb shell dumpsys', description: '转储系统服务状态（可加服务名过滤）。'),
        AdbCommandItem(command: 'adb shell dumpsys activity', description: 'ActivityManager 状态。'),
        AdbCommandItem(command: 'adb shell dumpsys package <package>', description: '包管理器中该应用的详细信息。'),
        AdbCommandItem(command: 'adb shell dumpsys meminfo <package>', description: '应用内存占用。'),
        AdbCommandItem(command: 'adb shell dumpsys cpuinfo', description: 'CPU 使用概况。'),
        AdbCommandItem(command: 'adb shell dumpsys battery', description: '电池状态。'),
        AdbCommandItem(command: 'adb shell dumpsys window', description: '窗口 / 显示相关状态。'),
        AdbCommandItem(command: 'adb shell dumpsys gfxinfo <package>', description: '渲染性能统计。'),
        AdbCommandItem(command: 'adb shell tomestone_provisional', description: '部分设备上的 tombstone 相关入口（视系统而定）。'),
        AdbCommandItem(command: 'adb shell ls /data/tombstones', description: '查看 native crash tombstone（通常需 root）。'),
      ],
    ),
    AdbCommandSection(
      title: '端口转发与网络',
      icon: Icons.settings_ethernet,
      commandColor: green,
      items: [
        AdbCommandItem(command: 'adb forward tcp:<local> tcp:<remote>', description: '将本机端口转发到设备端口。'),
        AdbCommandItem(command: 'adb forward --list', description: '列出当前转发规则。'),
        AdbCommandItem(command: 'adb forward --remove tcp:<local>', description: '删除指定转发。'),
        AdbCommandItem(command: 'adb forward --remove-all', description: '删除全部转发。'),
        AdbCommandItem(command: 'adb reverse tcp:<remote> tcp:<local>', description: '把设备端口反转到本机（设备访问电脑服务）。'),
        AdbCommandItem(command: 'adb reverse --list', description: '列出反向转发。'),
        AdbCommandItem(command: 'adb reverse --remove-all', description: '删除全部反向转发。'),
        AdbCommandItem(command: 'adb shell ifconfig', description: '查看网卡信息（部分设备用 ip addr）。'),
        AdbCommandItem(command: 'adb shell ip addr', description: '查看 IP 地址。'),
        AdbCommandItem(command: 'adb shell netstat', description: '查看网络连接（视 ROM 可用性）。'),
        AdbCommandItem(command: 'adb shell ping -c 4 <host>', description: '网络连通性测试。'),
      ],
    ),
    AdbCommandSection(
      title: '截图与录屏',
      icon: Icons.screenshot_monitor,
      commandColor: orange,
      items: [
        AdbCommandItem(command: 'adb shell screencap -p /sdcard/screen.png', description: '截取屏幕到设备文件。'),
        AdbCommandItem(command: 'adb exec-out screencap -p > screen.png', description: '直接把截图流到本机文件（Windows 注意二进制重定向）。'),
        AdbCommandItem(command: 'adb shell screenrecord /sdcard/demo.mp4', description: '录制屏幕；Ctrl+C 结束。'),
        AdbCommandItem(command: 'adb shell screenrecord --time-limit 30 /sdcard/demo.mp4', description: '限时录制（秒）。'),
        AdbCommandItem(command: 'adb shell screenrecord --size 1280x720 /sdcard/demo.mp4', description: '指定分辨率录制。'),
      ],
    ),
    AdbCommandSection(
      title: '输入模拟',
      icon: Icons.touch_app_outlined,
      commandColor: orange,
      items: [
        AdbCommandItem(command: 'adb shell input tap <x> <y>', description: '点击坐标。'),
        AdbCommandItem(command: 'adb shell input swipe <x1> <y1> <x2> <y2> [<ms>]', description: '滑动手势。'),
        AdbCommandItem(command: 'adb shell input text "hello"', description: '输入文本（空格等需转义）。'),
        AdbCommandItem(command: 'adb shell input keyevent <code>', description: '发送按键事件，如 3=HOME、4=BACK、26=电源。'),
        AdbCommandItem(command: 'adb shell input keyevent KEYCODE_HOME', description: '按 Home。'),
        AdbCommandItem(command: 'adb shell input keyevent KEYCODE_BACK', description: '按返回。'),
        AdbCommandItem(command: 'adb shell input keyevent KEYCODE_POWER', description: '电源键。'),
        AdbCommandItem(command: 'adb shell input keyevent 82', description: '菜单键（KEYCODE_MENU）。'),
        AdbCommandItem(command: 'adb shell input keyevent 24', description: '音量加。'),
        AdbCommandItem(command: 'adb shell input keyevent 25', description: '音量减。'),
        AdbCommandItem(command: 'adb shell input motionevent DOWN <x> <y>', description: '底层触控按下（新版本支持）。'),
      ],
    ),
    AdbCommandSection(
      title: '系统属性与设置',
      icon: Icons.tune,
      commandColor: green,
      items: [
        AdbCommandItem(command: 'adb shell getprop', description: '列出全部系统属性。'),
        AdbCommandItem(command: 'adb shell getprop ro.build.version.release', description: '获取 Android 版本号。'),
        AdbCommandItem(command: 'adb shell getprop ro.product.model', description: '获取设备型号。'),
        AdbCommandItem(command: 'adb shell setprop <key> <value>', description: '设置属性（多数需 root / 调试权限）。'),
        AdbCommandItem(command: 'adb shell settings get system <key>', description: '读取 system 设置项。'),
        AdbCommandItem(command: 'adb shell settings put system <key> <value>', description: '写入 system 设置项。'),
        AdbCommandItem(command: 'adb shell settings put global adb_enabled 1', description: '相关全局开关示例（视 ROM）。'),
        AdbCommandItem(command: 'adb shell settings put global stay_on_while_plugged_in 3', description: '充电时保持唤醒（常用调试项）。'),
        AdbCommandItem(command: 'adb shell settings put system screen_off_timeout 2147483647', description: '拉长熄屏超时。'),
        AdbCommandItem(command: 'adb shell wm size', description: '查看/设置显示分辨率。'),
        AdbCommandItem(command: 'adb shell wm size 1080x1920', description: '临时修改分辨率。'),
        AdbCommandItem(command: 'adb shell wm size reset', description: '恢复默认分辨率。'),
        AdbCommandItem(command: 'adb shell wm density', description: '查看/设置屏幕密度。'),
        AdbCommandItem(command: 'adb shell wm density reset', description: '恢复默认密度。'),
        AdbCommandItem(command: 'adb shell cmd overlay list', description: '列出 RRO / 运行时资源覆盖。'),
        AdbCommandItem(command: 'adb shell cmd uimode night yes', description: '打开深色模式。'),
        AdbCommandItem(command: 'adb shell cmd uimode night no', description: '关闭深色模式。'),
      ],
    ),
    AdbCommandSection(
      title: '电源、重启与引导',
      icon: Icons.power_settings_new,
      commandColor: AppColors.errorLog,
      items: [
        AdbCommandItem(command: 'adb reboot', description: '重启设备。'),
        AdbCommandItem(command: 'adb reboot recovery', description: '重启到 Recovery。'),
        AdbCommandItem(command: 'adb reboot bootloader', description: '重启到 Bootloader / Fastboot。'),
        AdbCommandItem(command: 'adb reboot fastboot', description: '重启到 Fastbootd（新设备）。'),
        AdbCommandItem(command: 'adb reboot sideload', description: '重启到 sideload 模式。'),
        AdbCommandItem(command: 'adb sideload <update.zip>', description: '在 sideload 模式下推送更新包。'),
        AdbCommandItem(command: 'adb root', description: '以 root 重启 adbd（需可 root 的 userdebug/eng）。'),
        AdbCommandItem(command: 'adb unroot', description: '退出 root 的 adbd。'),
        AdbCommandItem(command: 'adb remount', description: '将系统分区重新挂载为可写（需 root）。'),
        AdbCommandItem(command: 'adb disable-verity', description: '关闭 dm-verity（刷机/调试用，需谨慎）。'),
        AdbCommandItem(command: 'adb enable-verity', description: '重新启用 dm-verity。'),
        AdbCommandItem(command: 'adb shell svc power reboot', description: '通过 svc 重启。'),
        AdbCommandItem(command: 'adb shell svc wifi enable', description: '打开 Wi-Fi。'),
        AdbCommandItem(command: 'adb shell svc wifi disable', description: '关闭 Wi-Fi。'),
        AdbCommandItem(command: 'adb shell svc data enable', description: '打开移动数据。'),
        AdbCommandItem(command: 'adb shell svc bluetooth enable', description: '打开蓝牙。'),
      ],
    ),
    AdbCommandSection(
      title: '备份与恢复',
      icon: Icons.backup_outlined,
      commandColor: AppColors.textMuted,
      items: [
        AdbCommandItem(command: 'adb backup -f backup.ab -apk -shared -all', description: '备份应用与共享存储（旧接口，新系统可能受限）。'),
        AdbCommandItem(command: 'adb backup -f backup.ab -apk -noshared -nosystem -all', description: '仅备份第三方应用。'),
        AdbCommandItem(command: 'adb backup -f backup.ab <package>', description: '备份指定包。'),
        AdbCommandItem(command: 'adb restore backup.ab', description: '从备份文件恢复。'),
        AdbCommandItem(command: 'adb shell bmgr list sets', description: '列出 BackupManager 备份集。'),
        AdbCommandItem(command: 'adb shell bmgr backupnow <package>', description: '立即触发指定应用备份。'),
      ],
    ),
    AdbCommandSection(
      title: '进程、性能与追踪',
      icon: Icons.speed,
      commandColor: AppColors.accentBright,
      items: [
        AdbCommandItem(command: 'adb shell ps -A', description: '列出进程。'),
        AdbCommandItem(command: 'adb shell top', description: '实时查看 CPU 占用。'),
        AdbCommandItem(command: 'adb shell pidof <package>', description: '获取应用 PID。'),
        AdbCommandItem(command: 'adb shell kill <pid>', description: '结束进程。'),
        AdbCommandItem(command: 'adb shell cat /proc/meminfo', description: '查看内存信息。'),
        AdbCommandItem(command: 'adb shell cat /proc/cpuinfo', description: '查看 CPU 信息。'),
        AdbCommandItem(command: 'adb shell cmd accessibility', description: '无障碍服务相关命令入口。'),
        AdbCommandItem(command: 'adb shell am profile start <package> <file>', description: '开始 method profiling。'),
        AdbCommandItem(command: 'adb shell am profile stop <package>', description: '停止 profiling。'),
        AdbCommandItem(command: 'adb shell cmd activity start-profiler ...', description: '新版本 Activity 性能分析入口。'),
        AdbCommandItem(command: 'adb shell atrace --async_start -b 8192 gfx input view', description: '启动 atrace（需相应权限）。'),
        AdbCommandItem(command: 'adb shell atrace --async_stop', description: '停止 atrace。'),
        AdbCommandItem(command: 'adb shell cmd package dump-profiles <package>', description: '导出 ART profile。'),
      ],
    ),
    AdbCommandSection(
      title: '用户、账户与多用户',
      icon: Icons.people_outline,
      commandColor: purple,
      items: [
        AdbCommandItem(command: 'adb shell pm list users', description: '列出设备用户。'),
        AdbCommandItem(command: 'adb shell am get-current-user', description: '获取当前用户 ID。'),
        AdbCommandItem(command: 'adb shell am switch-user <userId>', description: '切换用户。'),
        AdbCommandItem(command: 'adb shell pm create-user <name>', description: '创建新用户。'),
        AdbCommandItem(command: 'adb shell pm remove-user <userId>', description: '删除用户。'),
        AdbCommandItem(command: 'adb shell dumpsys account', description: '查看账户服务信息。'),
      ],
    ),
    AdbCommandSection(
      title: '安全、证书与密钥',
      icon: Icons.security,
      commandColor: AppColors.errorLog,
      items: [
        AdbCommandItem(command: 'adb shell settings get global development_settings_enabled', description: '是否开启开发者选项。'),
        AdbCommandItem(command: 'adb shell settings put global verifier_verify_adb_installs 0', description: '关闭 ADB 安装校验（仅调试，慎用）。'),
        AdbCommandItem(command: 'adb shell pm list features', description: '列出系统 Feature。'),
        AdbCommandItem(command: 'adb shell cmd appops get <package>', description: '查看 AppOps。'),
        AdbCommandItem(command: 'adb shell cmd appops set <package> <op> allow', description: '设置 AppOps。'),
        AdbCommandItem(command: 'adb shell content query --uri content://...', description: '查询 ContentProvider。'),
        AdbCommandItem(command: 'adb shell ime list -s', description: '列出输入法。'),
        AdbCommandItem(command: 'adb shell ime set <ime_id>', description: '切换输入法。'),
      ],
    ),
    AdbCommandSection(
      title: '模拟器专用',
      icon: Icons.smartphone,
      commandColor: AppColors.textMuted,
      items: [
        AdbCommandItem(command: 'emulator -list-avds', description: '列出已创建的 AVD（emulator 工具，非 adb）。'),
        AdbCommandItem(command: 'emulator -avd <name>', description: '启动指定 AVD。'),
        AdbCommandItem(command: 'adb emu kill', description: '关闭当前模拟器。'),
        AdbCommandItem(command: 'adb emu geo fix <lon> <lat>', description: '设置模拟器地理位置。'),
        AdbCommandItem(command: 'adb emu sms send <number> <text>', description: '向模拟器发送短信。'),
        AdbCommandItem(command: 'adb emu finger touch <id>', description: '模拟指纹事件。'),
        AdbCommandItem(command: 'adb -e shell', description: '仅进入模拟器 shell。'),
      ],
    ),
    AdbCommandSection(
      title: 'Shell 与常用工具',
      icon: Icons.terminal,
      commandColor: AppColors.accentBright,
      items: [
        AdbCommandItem(command: 'adb shell', description: '进入交互式设备 Shell。'),
        AdbCommandItem(command: 'adb shell <command>', description: '执行单条 shell 命令后退出。'),
        AdbCommandItem(command: 'adb exec-out <command>', description: '以原始二进制方式输出命令结果（适合截图等）。'),
        AdbCommandItem(command: 'adb shell whoami', description: '当前用户。'),
        AdbCommandItem(command: 'adb shell id', description: '查看 uid/gid。'),
        AdbCommandItem(command: 'adb shell uname -a', description: '内核信息。'),
        AdbCommandItem(command: 'adb shell date', description: '设备时间。'),
        AdbCommandItem(command: 'adb shell getenforce', description: 'SELinux 模式。'),
        AdbCommandItem(command: 'adb shell setenforce 0', description: '临时关闭 SELinux enforcing（需权限，慎用）。'),
        AdbCommandItem(command: 'adb shell cmd activity attach-agent ...', description: '附加 JVMTI agent（高级调试）。'),
        AdbCommandItem(command: 'adb shell run-as <package> ...', description: '以可调试应用身份访问其私有目录。'),
        AdbCommandItem(command: 'adb shell cmd statusbar expand-notifications', description: '展开通知栏。'),
        AdbCommandItem(command: 'adb shell cmd statusbar collapse', description: '收起状态栏。'),
      ],
    ),
  ];
}
