#ifndef PLEDO_RARBRIDGE_H
#define PLEDO_RARBRIDGE_H

#ifdef __cplusplus
extern "C" {
#endif

/// Fortschritt: bisher entpackte Bytes, Gesamtgröße, aktueller Dateiname. Rückgabe 0 = abbrechen.
typedef int (*pledo_rar_progress_cb)(void *ctx, long long processed, long long total, const char *currentName);

/// Rückgabewerte
#define PLEDO_RAR_OK 0
#define PLEDO_RAR_CANCELLED 1
#define PLEDO_RAR_NEED_PASSWORD 2
#define PLEDO_RAR_BAD_PASSWORD 3
#define PLEDO_RAR_ERROR 4

/// Entpackt ein RAR-Archiv (RAR4/RAR5, auch mehrteilig) nach destDir.
/// password darf NULL sein. errorCode erhält den unrar-Fehlercode.
int pledo_rar_extract(const char *archivePath, const char *destDir, const char *password,
                      pledo_rar_progress_cb progress, void *ctx, int *errorCode);

#ifdef __cplusplus
}
#endif

#endif
