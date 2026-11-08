#ifndef PLEXO_TORRENTBRIDGE_H
#define PLEXO_TORRENTBRIDGE_H

#ifdef __cplusplus
extern "C" {
#endif

/// Status eines Torrents (Felder werden von plx_status_all befüllt).
typedef struct {
    char id[72];            // Info-Hash (hex)
    char name[512];
    char savePath[1024];
    char error[256];
    int state;              // 0 prüfen, 1 Metadaten, 2 lädt, 3 fertig, 4 seedet, 5 prüft Resume
    int paused;
    int hasMetadata;
    int finished;
    float progress;
    long long totalWanted;
    long long totalWantedDone;
    long long totalSize;
    long long allTimeDownload;
    long long allTimeUpload;
    int downRate;
    int upRate;
    int peers;
    int seeds;
    int connectCandidates;
} plx_status;

/// Peer-Statistik pro Netzwerk-Interface (z. B. en0 = WLAN, pdp_ip0 = Mobilfunk).
typedef struct {
    char interfaceName[32];
    int peers;
    int downRate;
    int upRate;
} plx_iface_stat;

void *plx_session_create(const char *stateDir, const char *interfaces, int downLimit, int upLimit);
void plx_session_destroy(void *session);
/// interfaces: kommagetrennt, z. B. "en0,pdp_ip0"; leer = Standardroute.
void plx_session_apply(void *session, const char *interfaces, int downLimit, int upLimit, int maxConnections);

/// Gibt 0 bei Erfolg zurück und schreibt die ID nach outId (72 Bytes).
int plx_add_magnet(void *session, const char *magnet, const char *savePath, char *outId, char *err, int errLen);
int plx_add_file(void *session, const char *torrentPath, const char *savePath, char *outId, char *err, int errLen);
/// Lädt alle gespeicherten Resume-Dateien aus stateDir. Gibt die Anzahl zurück.
int plx_load_saved(void *session);

void plx_pause(void *session, const char *id);
void plx_resume(void *session, const char *id);
void plx_remove(void *session, const char *id, int deleteFiles);
void plx_set_sequential(void *session, const char *id, int on);
void plx_force_recheck(void *session, const char *id);
void plx_force_reannounce(void *session, const char *id);

int plx_status_all(void *session, plx_status *out, int max);

int plx_file_count(void *session, const char *id);
/// priority: 0 = nicht laden, 4 = normal, 7 = hoch.
int plx_file_info(void *session, const char *id, int index, char *path, int pathLen,
                  long long *size, long long *done, int *priority);
void plx_set_file_priority(void *session, const char *id, int index, int priority);

/// Download-/Upload-Rate der Peers, aufgeteilt nach lokalem Interface (alle Torrents).
int plx_iface_stats(void *session, plx_iface_stat *out, int max);

/// Resume-Daten aller Torrents anfordern (werden beim nächsten plx_pump gespeichert).
void plx_save_all(void *session);
/// Verarbeitet Alerts. finishedIds erhält bis zu maxFinished IDs fertig gewordener Torrents (je 72 Bytes).
int plx_pump(void *session, char *finishedIds, int maxFinished);

#ifdef __cplusplus
}
#endif

#endif
