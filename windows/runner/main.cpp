#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include <string>

#include "flutter_window.h"
#include "utils.h"

namespace {

bool IsUpdaterMode() {
  int argc = 0;
  wchar_t** argv = ::CommandLineToArgvW(::GetCommandLineW(), &argc);
  if (argv == nullptr) {
    return false;
  }
  bool updater = false;
  for (int i = 1; i < argc; i++) {
    if (wcscmp(argv[i], L"--updater") == 0) {
      updater = true;
      break;
    }
  }
  ::LocalFree(argv);
  return updater;
}

}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  const bool updater_mode = IsUpdaterMode();

  FlutterWindow window(project);
  Win32Window::Point origin(updater_mode ? 80 : 10, updater_mode ? 80 : 10);
  Win32Window::Size size(updater_mode ? 520 : 1280,
                         updater_mode ? 280 : 720);
  // Use \u escapes so Chinese is correct regardless of source-file encoding.
  const wchar_t* title = updater_mode
                             ? L"ADB \u684c\u9762\u5de5\u5177 - \u6b63\u5728\u66f4\u65b0"
                             : L"ADB \u684c\u9762\u5de5\u5177";
  if (!window.Create(title, origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  // Updater must show immediately — when launched as a child process the first
  // frame callback can be delayed/missed and the window would stay hidden.
  if (updater_mode) {
    window.Show();
    HWND hwnd = window.GetHandle();
    if (hwnd != nullptr) {
      ::SetForegroundWindow(hwnd);
      ::BringWindowToTop(hwnd);
    }
  }

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
