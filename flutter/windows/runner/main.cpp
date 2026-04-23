#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include <string>
#include <vector>

#include "flutter_window.h"
#include "utils.h"

namespace {

bool HasArgument(const std::vector<std::string>& args, const std::string& value) {
  for (const auto& arg : args) {
    if (arg == value) {
      return true;
    }
  }
  return false;
}

struct MonitorBounds {
  LONG left;
  LONG top;
  LONG width;
  LONG height;
  bool found;
};

BOOL CALLBACK MonitorEnumProc(HMONITOR monitor, HDC, LPRECT, LPARAM data) {
  auto* result = reinterpret_cast<MonitorBounds*>(data);
  MONITORINFO info;
  info.cbSize = sizeof(MONITORINFO);
  if (GetMonitorInfo(monitor, &info)) {
    if ((info.dwFlags & MONITORINFOF_PRIMARY) == 0) {
      result->left = info.rcMonitor.left;
      result->top = info.rcMonitor.top;
      result->width = info.rcMonitor.right - info.rcMonitor.left;
      result->height = info.rcMonitor.bottom - info.rcMonitor.top;
      result->found = true;
      return FALSE;
    }
  }
  return TRUE;
}

MonitorBounds ResolveWindowBounds(bool customer_display_mode, bool preview_mode) {
  if (!customer_display_mode || preview_mode) {
    POINT origin{0, 0};
    HMONITOR primary_monitor = MonitorFromPoint(origin, MONITOR_DEFAULTTOPRIMARY);
    MONITORINFO info;
    info.cbSize = sizeof(MONITORINFO);
    if (GetMonitorInfo(primary_monitor, &info)) {
      return {
          info.rcMonitor.left,
          info.rcMonitor.top,
          info.rcMonitor.right - info.rcMonitor.left,
          info.rcMonitor.bottom - info.rcMonitor.top,
          true};
    }
    return {0, 0, 1280, 720, true};
  }

  MonitorBounds bounds{0, 0, 1280, 720, false};
  EnumDisplayMonitors(nullptr, nullptr, MonitorEnumProc, reinterpret_cast<LPARAM>(&bounds));
  return bounds;
}

void EnterFullscreen(HWND hwnd, const MonitorBounds& bounds) {
  SetWindowLongPtr(hwnd, GWL_STYLE, WS_POPUP | WS_VISIBLE);
  SetWindowLongPtr(hwnd, GWL_EXSTYLE, WS_EX_APPWINDOW);
  SetWindowPos(
      hwnd,
      HWND_TOP,
      bounds.left,
      bounds.top,
      bounds.width,
      bounds.height,
      SWP_FRAMECHANGED | SWP_SHOWWINDOW);
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
  const bool customer_display_preview =
      HasArgument(command_line_arguments, "--customer-display-preview");
  const bool customer_display_mode =
      HasArgument(command_line_arguments, "--customer-display") ||
      customer_display_preview;

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  const auto bounds = ResolveWindowBounds(
      customer_display_mode, customer_display_preview);
  if (customer_display_mode && !bounds.found) {
    return EXIT_SUCCESS;
  }
  Win32Window::Point origin(bounds.left, bounds.top);
  Win32Window::Size size(bounds.width, bounds.height);
  const wchar_t* title =
      customer_display_mode ? L"KIYIM DOKON - Mijoz ekrani" : L"KIYIM DOKON POS";
  if (!window.Create(title, origin, size)) {
    return EXIT_FAILURE;
  }
  EnterFullscreen(window.GetHandle(), bounds);
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
