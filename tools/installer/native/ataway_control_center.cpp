#include <winsock2.h>
#include <ws2tcpip.h>
#include <iphlpapi.h>
#include <windows.h>
#include <shellapi.h>
#include <winsvc.h>

#include <string>
#include <vector>
#include <fstream>
#include <sstream>

#pragma comment(lib, "Advapi32.lib")
#pragma comment(lib, "Shell32.lib")
#pragma comment(lib, "Ws2_32.lib")
#pragma comment(lib, "Iphlpapi.lib")

namespace {

constexpr wchar_t kClassName[] = L"ATAWAYControlCenterWindow";
constexpr wchar_t kTitle[] = L"ATAWAY Backend Control Center";
constexpr UINT_PTR kRefreshTimerId = 1;
constexpr UINT kRefreshIntervalMs = 3000;

constexpr int IDC_STATUS = 1001;
constexpr int IDC_URLS = 1002;
constexpr int IDC_START = 1003;
constexpr int IDC_STOP = 1004;
constexpr int IDC_RESTART = 1005;
constexpr int IDC_REFRESH = 1006;
constexpr int IDC_LOGS = 1007;
constexpr int IDC_COMPASS = 1008;

constexpr wchar_t kBackendServiceName[] = L"ATAWAYLocalBackend";
constexpr wchar_t kMongoServiceName[] = L"ATAWAYMongoDB";

HWND gStatusLabel = nullptr;
HWND gUrlLabel = nullptr;
std::wstring gInstallRoot = L"C:\\Program Files\\ATAWAY Local Backend";

std::wstring ReadPortFromEnv() {
  std::wstring envPath = gInstallRoot + L"\\backend\\.env";
  std::ifstream file(envPath);
  if (!file) return L"4000";

  std::string line;
  while (std::getline(file, line)) {
    if (line.rfind("PORT=", 0) == 0) {
      std::string value = line.substr(5);
      if (!value.empty()) {
        return std::wstring(value.begin(), value.end());
      }
    }
  }
  return L"4000";
}

std::wstring ServiceStateText(DWORD state) {
  switch (state) {
    case SERVICE_RUNNING: return L"RUNNING";
    case SERVICE_STOPPED: return L"STOPPED";
    case SERVICE_START_PENDING: return L"STARTING";
    case SERVICE_STOP_PENDING: return L"STOPPING";
    default: return L"UNKNOWN";
  }
}

DWORD QueryServiceState(const wchar_t* serviceName) {
  SC_HANDLE scm = OpenSCManagerW(nullptr, nullptr, SC_MANAGER_CONNECT);
  if (!scm) return SERVICE_STOPPED;

  SC_HANDLE service = OpenServiceW(scm, serviceName, SERVICE_QUERY_STATUS);
  if (!service) {
    CloseServiceHandle(scm);
    return SERVICE_STOPPED;
  }

  SERVICE_STATUS_PROCESS status{};
  DWORD bytesNeeded = 0;
  DWORD state = SERVICE_STOPPED;
  if (QueryServiceStatusEx(
          service,
          SC_STATUS_PROCESS_INFO,
          reinterpret_cast<LPBYTE>(&status),
          sizeof(status),
          &bytesNeeded)) {
    state = status.dwCurrentState;
  }

  CloseServiceHandle(service);
  CloseServiceHandle(scm);
  return state;
}

bool WaitForState(const wchar_t* serviceName, DWORD desiredState, DWORD timeoutMs) {
  DWORD start = GetTickCount();
  while ((GetTickCount() - start) < timeoutMs) {
    if (QueryServiceState(serviceName) == desiredState) {
      return true;
    }
    Sleep(500);
  }
  return QueryServiceState(serviceName) == desiredState;
}

bool StartNamedService(const wchar_t* serviceName) {
  SC_HANDLE scm = OpenSCManagerW(nullptr, nullptr, SC_MANAGER_CONNECT);
  if (!scm) return false;

  SC_HANDLE service = OpenServiceW(scm, serviceName, SERVICE_START | SERVICE_QUERY_STATUS);
  if (!service) {
    CloseServiceHandle(scm);
    return false;
  }

  bool ok = true;
  DWORD state = QueryServiceState(serviceName);
  if (state != SERVICE_RUNNING && state != SERVICE_START_PENDING) {
    ok = StartServiceW(service, 0, nullptr) != FALSE;
  }

  CloseServiceHandle(service);
  CloseServiceHandle(scm);
  return ok && WaitForState(serviceName, SERVICE_RUNNING, 15000);
}

bool StopNamedService(const wchar_t* serviceName) {
  SC_HANDLE scm = OpenSCManagerW(nullptr, nullptr, SC_MANAGER_CONNECT);
  if (!scm) return false;

  SC_HANDLE service = OpenServiceW(scm, serviceName, SERVICE_STOP | SERVICE_QUERY_STATUS);
  if (!service) {
    CloseServiceHandle(scm);
    return false;
  }

  bool ok = true;
  DWORD state = QueryServiceState(serviceName);
  if (state != SERVICE_STOPPED && state != SERVICE_STOP_PENDING) {
    SERVICE_STATUS status{};
    ok = ControlService(service, SERVICE_CONTROL_STOP, &status) != FALSE;
  }

  CloseServiceHandle(service);
  CloseServiceHandle(scm);
  return ok && WaitForState(serviceName, SERVICE_STOPPED, 15000);
}

std::vector<std::wstring> GetLanUrls() {
  std::vector<std::wstring> urls;
  ULONG size = 0;
  GetAdaptersAddresses(AF_INET, GAA_FLAG_SKIP_ANYCAST | GAA_FLAG_SKIP_MULTICAST | GAA_FLAG_SKIP_DNS_SERVER, nullptr, nullptr, &size);
  std::vector<BYTE> buffer(size);
  auto* addresses = reinterpret_cast<IP_ADAPTER_ADDRESSES*>(buffer.data());
  if (GetAdaptersAddresses(AF_INET, GAA_FLAG_SKIP_ANYCAST | GAA_FLAG_SKIP_MULTICAST | GAA_FLAG_SKIP_DNS_SERVER, nullptr, addresses, &size) != NO_ERROR) {
    return urls;
  }

  std::wstring port = ReadPortFromEnv();
  for (auto* adapter = addresses; adapter != nullptr; adapter = adapter->Next) {
    if (adapter->OperStatus != IfOperStatusUp) continue;
    if (adapter->IfType == IF_TYPE_SOFTWARE_LOOPBACK) continue;

    for (auto* ua = adapter->FirstUnicastAddress; ua != nullptr; ua = ua->Next) {
      wchar_t host[64] = {};
      auto* addr = reinterpret_cast<sockaddr_in*>(ua->Address.lpSockaddr);
      if (addr != nullptr && addr->sin_family == AF_INET &&
          InetNtopW(AF_INET, &addr->sin_addr, host, 64) != nullptr) {
        std::wstring ip = host;
        if (ip != L"127.0.0.1") {
          urls.push_back(L"http://" + ip + L":" + port + L"/api");
        }
      }
    }
  }
  return urls;
}

void RefreshUi() {
  DWORD mongoState = QueryServiceState(kMongoServiceName);
  DWORD backendState = QueryServiceState(kBackendServiceName);
  std::wstring health = (backendState == SERVICE_RUNNING) ? L"LIKELY OK" : L"FAILED";

  std::wstring status =
      L"MongoDB: " + ServiceStateText(mongoState) +
      L"    Backend: " + ServiceStateText(backendState) +
      L"    Health: " + health;
  SetWindowTextW(gStatusLabel, status.c_str());

  std::wstring port = ReadPortFromEnv();
  std::wstring urls = L"Local: http://127.0.0.1:" + port + L"/api\r\n";
  auto lanUrls = GetLanUrls();
  if (lanUrls.empty()) {
    urls += L"LAN: topilmadi";
  } else {
    urls += L"LAN: " + lanUrls.front();
  }
  SetWindowTextW(gUrlLabel, urls.c_str());
}

void ShowMessage(const wchar_t* text, const wchar_t* caption = L"ATAWAY") {
  MessageBoxW(nullptr, text, caption, MB_OK | MB_ICONINFORMATION);
}

void OpenLogsFolder() {
  std::wstring path = gInstallRoot + L"\\logs";
  ShellExecuteW(nullptr, L"open", path.c_str(), nullptr, nullptr, SW_SHOWNORMAL);
}

void OpenCompass() {
  wchar_t localAppData[MAX_PATH] = {};
  DWORD length = GetEnvironmentVariableW(L"LOCALAPPDATA", localAppData, MAX_PATH);
  if (length == 0 || length >= MAX_PATH) {
    ShowMessage(L"LOCALAPPDATA topilmadi, Compass'ni ochib bo'lmadi.", L"Xato");
    return;
  }

  std::wstring updateExe = std::wstring(localAppData) + L"\\MongoDBCompass\\Update.exe";
  if (GetFileAttributesW(updateExe.c_str()) == INVALID_FILE_ATTRIBUTES) {
    ShowMessage(L"MongoDB Compass topilmadi. Installer orqali qayta o'rnatib ko'ring.", L"Xato");
    return;
  }

  ShellExecuteW(
      nullptr,
      L"open",
      updateExe.c_str(),
      L"--processStart MongoDBCompass.exe",
      nullptr,
      SW_SHOWNORMAL);
}

LRESULT CALLBACK WindowProc(HWND hwnd, UINT message, WPARAM wParam, LPARAM lParam) {
  switch (message) {
    case WM_CREATE: {
      CreateWindowW(L"STATIC", L"Server holati", WS_CHILD | WS_VISIBLE,
                    20, 20, 120, 20, hwnd, nullptr, nullptr, nullptr);

      gStatusLabel = CreateWindowW(L"STATIC", L"...", WS_CHILD | WS_VISIBLE,
                                   20, 45, 720, 24, hwnd, reinterpret_cast<HMENU>(static_cast<INT_PTR>(IDC_STATUS)), nullptr, nullptr);

      CreateWindowW(L"STATIC", L"API URL'lar", WS_CHILD | WS_VISIBLE,
                    20, 90, 120, 20, hwnd, nullptr, nullptr, nullptr);

      gUrlLabel = CreateWindowW(L"STATIC", L"...", WS_CHILD | WS_VISIBLE,
                                20, 115, 720, 50, hwnd, reinterpret_cast<HMENU>(static_cast<INT_PTR>(IDC_URLS)), nullptr, nullptr);

      CreateWindowW(L"BUTTON", L"Start", WS_TABSTOP | WS_VISIBLE | WS_CHILD | BS_DEFPUSHBUTTON,
                    20, 190, 100, 34, hwnd, reinterpret_cast<HMENU>(static_cast<INT_PTR>(IDC_START)), nullptr, nullptr);
      CreateWindowW(L"BUTTON", L"Stop", WS_TABSTOP | WS_VISIBLE | WS_CHILD,
                    130, 190, 100, 34, hwnd, reinterpret_cast<HMENU>(static_cast<INT_PTR>(IDC_STOP)), nullptr, nullptr);
      CreateWindowW(L"BUTTON", L"Restart", WS_TABSTOP | WS_VISIBLE | WS_CHILD,
                    240, 190, 100, 34, hwnd, reinterpret_cast<HMENU>(static_cast<INT_PTR>(IDC_RESTART)), nullptr, nullptr);
      CreateWindowW(L"BUTTON", L"Refresh", WS_TABSTOP | WS_VISIBLE | WS_CHILD,
                    350, 190, 100, 34, hwnd, reinterpret_cast<HMENU>(static_cast<INT_PTR>(IDC_REFRESH)), nullptr, nullptr);
      CreateWindowW(L"BUTTON", L"Loglar", WS_TABSTOP | WS_VISIBLE | WS_CHILD,
                    460, 190, 100, 34, hwnd, reinterpret_cast<HMENU>(static_cast<INT_PTR>(IDC_LOGS)), nullptr, nullptr);
      CreateWindowW(L"BUTTON", L"Compass", WS_TABSTOP | WS_VISIBLE | WS_CHILD,
                    570, 190, 100, 34, hwnd, reinterpret_cast<HMENU>(static_cast<INT_PTR>(IDC_COMPASS)), nullptr, nullptr);

      SetTimer(hwnd, kRefreshTimerId, kRefreshIntervalMs, nullptr);
      RefreshUi();
      return 0;
    }
    case WM_TIMER:
      if (wParam == kRefreshTimerId) {
        RefreshUi();
      }
      return 0;
    case WM_COMMAND: {
      switch (LOWORD(wParam)) {
        case IDC_START:
          if (!StartNamedService(kMongoServiceName) || !StartNamedService(kBackendServiceName)) {
            ShowMessage(L"Service'larni ishga tushirib bo'lmadi.", L"Xato");
          }
          RefreshUi();
          return 0;
        case IDC_STOP:
          if (!StopNamedService(kBackendServiceName)) {
            ShowMessage(L"Backend service'ni to'xtatib bo'lmadi.", L"Xato");
          }
          RefreshUi();
          return 0;
        case IDC_RESTART:
          StopNamedService(kBackendServiceName);
          Sleep(1000);
          if (!StartNamedService(kBackendServiceName)) {
            ShowMessage(L"Backend service'ni qayta ishga tushirib bo'lmadi.", L"Xato");
          }
          RefreshUi();
          return 0;
        case IDC_REFRESH:
          RefreshUi();
          return 0;
        case IDC_LOGS:
          OpenLogsFolder();
          return 0;
        case IDC_COMPASS:
          OpenCompass();
          return 0;
      }
      break;
    }
    case WM_DESTROY:
      KillTimer(hwnd, kRefreshTimerId);
      PostQuitMessage(0);
      return 0;
  }
  return DefWindowProcW(hwnd, message, wParam, lParam);
}

}  // namespace

int WINAPI wWinMain(HINSTANCE instance, HINSTANCE, PWSTR, int showCommand) {
  WNDCLASSW wc{};
  wc.lpfnWndProc = WindowProc;
  wc.hInstance = instance;
  wc.lpszClassName = kClassName;
  wc.hCursor = LoadCursor(nullptr, IDC_ARROW);
  wc.hbrBackground = reinterpret_cast<HBRUSH>(COLOR_WINDOW + 1);

  RegisterClassW(&wc);

  HWND window = CreateWindowExW(
      0, kClassName, kTitle,
      WS_OVERLAPPED | WS_CAPTION | WS_SYSMENU | WS_MINIMIZEBOX,
      CW_USEDEFAULT, CW_USEDEFAULT, 780, 290,
      nullptr, nullptr, instance, nullptr);

  if (!window) return 0;

  ShowWindow(window, showCommand);
  UpdateWindow(window);

  MSG msg{};
  while (GetMessageW(&msg, nullptr, 0, 0)) {
    TranslateMessage(&msg);
    DispatchMessageW(&msg);
  }

  return 0;
}
