#include "rar.hpp"
#include "rarbridge.h"
#include <string.h>

namespace {

struct BridgeState {
  pledo_rar_progress_cb progress;
  void *ctx;
  const char *password;
  long long processed;
  long long total;
  const char *current;
  bool cancelled;
  bool passwordRequested;
};

int CALLBACK bridgeCallback(UINT msg, LPARAM userData, LPARAM p1, LPARAM p2) {
  BridgeState *s = (BridgeState *)userData;
  switch (msg) {
    case UCM_PROCESSDATA:
      s->processed += (long long)p2;
      if (s->progress && !s->progress(s->ctx, s->processed, s->total, s->current)) {
        s->cancelled = true;
        return -1;
      }
      return 1;
    case UCM_NEEDPASSWORD: {
      s->passwordRequested = true;
      if (s->password == NULL || s->password[0] == 0) return -1;
      char *buf = (char *)p1;
      size_t size = (size_t)p2;
      if (size == 0) return -1;
      strncpy(buf, s->password, size - 1);
      buf[size - 1] = 0;
      return 1;
    }
    case UCM_NEEDPASSWORDW: {
      s->passwordRequested = true;
      if (s->password == NULL || s->password[0] == 0) return -1;
      wchar_t *buf = (wchar_t *)p1;
      size_t size = (size_t)p2;
      if (size == 0) return -1;
      UtfToWide(s->password, buf, size);
      return 1;
    }
    case UCM_CHANGEVOLUME:
    case UCM_CHANGEVOLUMEW:
      // RAR_VOL_ASK = fehlender Teil -> abbrechen, RAR_VOL_NOTIFY = weiter
      return p2 == RAR_VOL_ASK ? -1 : 1;
    default:
      return 0;
  }
}

long long computeTotal(const char *archivePath, BridgeState *state) {
  RAROpenArchiveDataEx data;
  memset(&data, 0, sizeof(data));
  data.ArcName = (char *)archivePath;
  data.OpenMode = RAR_OM_LIST;
  data.Callback = bridgeCallback;
  data.UserData = (LPARAM)state;
  HANDLE h = RAROpenArchiveEx(&data);
  if (h == NULL || data.OpenResult != ERAR_SUCCESS) {
    if (h) RARCloseArchive(h);
    return 0;
  }
  if (state->password && state->password[0]) RARSetPassword(h, (char *)state->password);
  long long total = 0;
  RARHeaderDataEx header;
  memset(&header, 0, sizeof(header));
  while (RARReadHeaderEx(h, &header) == ERAR_SUCCESS) {
    total += ((long long)header.UnpSizeHigh << 32) | header.UnpSize;
    if (RARProcessFile(h, RAR_SKIP, NULL, NULL) != ERAR_SUCCESS) break;
  }
  RARCloseArchive(h);
  return total;
}

int mapError(int code, BridgeState *s) {
  switch (code) {
    case ERAR_SUCCESS:
    case ERAR_END_ARCHIVE:
      return PLEDO_RAR_OK;
    case ERAR_MISSING_PASSWORD:
      return PLEDO_RAR_NEED_PASSWORD;
    case ERAR_BAD_PASSWORD:
      return PLEDO_RAR_BAD_PASSWORD;
    default:
      if (s->cancelled) return PLEDO_RAR_CANCELLED;
      if (s->passwordRequested && (s->password == NULL || s->password[0] == 0)) return PLEDO_RAR_NEED_PASSWORD;
      if (s->passwordRequested && code == ERAR_BAD_DATA) return PLEDO_RAR_BAD_PASSWORD;
      return PLEDO_RAR_ERROR;
  }
}

} // namespace

extern "C" int pledo_rar_extract(const char *archivePath, const char *destDir, const char *password,
                                 pledo_rar_progress_cb progress, void *ctx, int *errorCode) {
  BridgeState state;
  memset(&state, 0, sizeof(state));
  state.progress = progress;
  state.ctx = ctx;
  state.password = password;
  state.current = "";

  state.total = computeTotal(archivePath, &state);
  state.passwordRequested = false;

  RAROpenArchiveDataEx data;
  memset(&data, 0, sizeof(data));
  data.ArcName = (char *)archivePath;
  data.OpenMode = RAR_OM_EXTRACT;
  data.Callback = bridgeCallback;
  data.UserData = (LPARAM)&state;
  HANDLE h = RAROpenArchiveEx(&data);
  if (h == NULL || data.OpenResult != ERAR_SUCCESS) {
    int code = (int)data.OpenResult;
    if (errorCode) *errorCode = code;
    if (h) RARCloseArchive(h);
    return mapError(code == 0 ? ERAR_EOPEN : code, &state);
  }
  if (password && password[0]) RARSetPassword(h, (char *)password);

  char currentName[1024];
  RARHeaderDataEx header;
  memset(&header, 0, sizeof(header));
  int result = ERAR_SUCCESS;
  while ((result = RARReadHeaderEx(h, &header)) == ERAR_SUCCESS) {
    strncpy(currentName, header.FileName, sizeof(currentName) - 1);
    currentName[sizeof(currentName) - 1] = 0;
    state.current = currentName;
    result = RARProcessFile(h, RAR_EXTRACT, (char *)destDir, NULL);
    if (result != ERAR_SUCCESS) break;
  }
  RARCloseArchive(h);
  if (errorCode) *errorCode = result;
  if (state.cancelled) return PLEDO_RAR_CANCELLED;
  return mapError(result, &state);
}
