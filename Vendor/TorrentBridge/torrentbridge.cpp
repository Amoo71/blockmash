// Kleine C-Schnittstelle zwischen libtorrent (C++) und Swift.

#include "torrentbridge.h"

#include <libtorrent/session.hpp>
#include <libtorrent/session_params.hpp>
#include <libtorrent/settings_pack.hpp>
#include <libtorrent/add_torrent_params.hpp>
#include <libtorrent/magnet_uri.hpp>
#include <libtorrent/torrent_info.hpp>
#include <libtorrent/torrent_handle.hpp>
#include <libtorrent/torrent_status.hpp>
#include <libtorrent/alert_types.hpp>
#include <libtorrent/read_resume_data.hpp>
#include <libtorrent/write_resume_data.hpp>
#include <libtorrent/peer_info.hpp>
#include <libtorrent/hex.hpp>
#include <libtorrent/error_code.hpp>

#include <ifaddrs.h>
#include <net/if.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <sys/socket.h>

#include <cstring>
#include <fstream>
#include <iterator>
#include <map>
#include <memory>
#include <mutex>
#include <sstream>
#include <string>
#include <vector>
#include <dirent.h>
#include <unistd.h>

namespace lt = libtorrent;

namespace {

struct Session {
    std::unique_ptr<lt::session> ses;
    std::string stateDir;
    std::mutex mutex;
    std::map<std::string, lt::torrent_handle> handles;
};

void copyString(char *dst, size_t dstLen, std::string const &src) {
    if (!dst || dstLen == 0) return;
    size_t n = std::min(dstLen - 1, src.size());
    std::memcpy(dst, src.data(), n);
    dst[n] = 0;
}

std::string idOf(lt::torrent_handle const &h) {
    return lt::aux::to_hex(h.info_hashes().get_best());
}

std::string idOf(lt::info_hash_t const &ih) {
    return lt::aux::to_hex(ih.get_best());
}

lt::settings_pack makeSettings(const char *interfaces, int downLimit, int upLimit, int maxConnections) {
    lt::settings_pack p;
    p.set_int(lt::settings_pack::alert_mask,
              lt::alert_category::error | lt::alert_category::status | lt::alert_category::storage);
    p.set_str(lt::settings_pack::user_agent, "Plexo/1.0 libtorrent/2.0");
    p.set_str(lt::settings_pack::outgoing_interfaces, interfaces ? interfaces : "");
    p.set_int(lt::settings_pack::download_rate_limit, downLimit);
    p.set_int(lt::settings_pack::upload_rate_limit, upLimit);
    if (maxConnections > 0) p.set_int(lt::settings_pack::connections_limit, maxConnections);
    p.set_bool(lt::settings_pack::enable_dht, true);
    p.set_bool(lt::settings_pack::enable_lsd, true);
    p.set_bool(lt::settings_pack::enable_upnp, false);
    p.set_bool(lt::settings_pack::enable_natpmp, false);
    p.set_int(lt::settings_pack::active_downloads, 8);
    p.set_int(lt::settings_pack::active_limit, 16);
    p.set_bool(lt::settings_pack::announce_to_all_trackers, true);
    p.set_bool(lt::settings_pack::announce_to_all_tiers, true);
    return p;
}

std::string readFile(std::string const &path) {
    std::ifstream in(path, std::ios::binary);
    return std::string(std::istreambuf_iterator<char>(in), std::istreambuf_iterator<char>());
}

void writeFile(std::string const &path, std::vector<char> const &buf) {
    std::string tmp = path + ".tmp";
    {
        std::ofstream out(tmp, std::ios::binary | std::ios::trunc);
        out.write(buf.data(), static_cast<std::streamsize>(buf.size()));
    }
    std::rename(tmp.c_str(), path.c_str());
}

lt::torrent_handle find(Session *s, const char *id) {
    std::lock_guard<std::mutex> lock(s->mutex);
    auto it = s->handles.find(id ? id : "");
    if (it == s->handles.end()) return lt::torrent_handle();
    return it->second;
}

int addParams(Session *s, lt::add_torrent_params atp, char *outId, char *err, int errLen) {
    lt::error_code ec;
    lt::torrent_handle h = s->ses->add_torrent(std::move(atp), ec);
    if (ec || !h.is_valid()) {
        copyString(err, static_cast<size_t>(errLen), ec ? ec.message() : std::string("Torrent konnte nicht hinzugefügt werden"));
        return 1;
    }
    std::string id = idOf(h);
    {
        std::lock_guard<std::mutex> lock(s->mutex);
        s->handles[id] = h;
    }
    copyString(outId, 72, id);
    h.save_resume_data(lt::torrent_handle::save_info_dict);
    return 0;
}

/// Lokale IP-Adresse -> Interface-Name (en0, pdp_ip0, …).
std::map<std::string, std::string> interfaceAddresses() {
    std::map<std::string, std::string> result;
    struct ifaddrs *list = nullptr;
    if (getifaddrs(&list) != 0) return result;
    for (struct ifaddrs *i = list; i; i = i->ifa_next) {
        if (!i->ifa_addr || !i->ifa_name) continue;
        char buf[INET6_ADDRSTRLEN] = {0};
        if (i->ifa_addr->sa_family == AF_INET) {
            inet_ntop(AF_INET, &reinterpret_cast<sockaddr_in *>(i->ifa_addr)->sin_addr, buf, sizeof(buf));
        } else if (i->ifa_addr->sa_family == AF_INET6) {
            inet_ntop(AF_INET6, &reinterpret_cast<sockaddr_in6 *>(i->ifa_addr)->sin6_addr, buf, sizeof(buf));
        } else {
            continue;
        }
        result[buf] = i->ifa_name;
    }
    freeifaddrs(list);
    return result;
}

} // namespace

extern "C" {

void *plx_session_create(const char *stateDir, const char *interfaces, int downLimit, int upLimit) {
    auto *s = new Session();
    s->stateDir = stateDir ? stateDir : ".";
    lt::session_params params(makeSettings(interfaces, downLimit, upLimit, 0));
    s->ses = std::make_unique<lt::session>(std::move(params));
    return s;
}

void plx_session_destroy(void *session) {
    auto *s = static_cast<Session *>(session);
    if (!s) return;
    s->ses.reset();
    delete s;
}

void plx_session_apply(void *session, const char *interfaces, int downLimit, int upLimit, int maxConnections) {
    auto *s = static_cast<Session *>(session);
    if (!s) return;
    s->ses->apply_settings(makeSettings(interfaces, downLimit, upLimit, maxConnections));
}

int plx_add_magnet(void *session, const char *magnet, const char *savePath, char *outId, char *err, int errLen) {
    auto *s = static_cast<Session *>(session);
    lt::error_code ec;
    lt::add_torrent_params atp = lt::parse_magnet_uri(magnet ? magnet : "", ec);
    if (ec) {
        copyString(err, static_cast<size_t>(errLen), "Ungültiger Magnet-Link: " + ec.message());
        return 1;
    }
    atp.save_path = savePath ? savePath : ".";
    return addParams(s, std::move(atp), outId, err, errLen);
}

int plx_add_file(void *session, const char *torrentPath, const char *savePath, char *outId, char *err, int errLen) {
    auto *s = static_cast<Session *>(session);
    lt::error_code ec;
    auto ti = std::make_shared<lt::torrent_info>(std::string(torrentPath ? torrentPath : ""), ec);
    if (ec) {
        copyString(err, static_cast<size_t>(errLen), "Ungültige Torrent-Datei: " + ec.message());
        return 1;
    }
    lt::add_torrent_params atp;
    atp.ti = ti;
    atp.save_path = savePath ? savePath : ".";
    return addParams(s, std::move(atp), outId, err, errLen);
}

int plx_load_saved(void *session) {
    auto *s = static_cast<Session *>(session);
    int count = 0;
    DIR *dir = opendir(s->stateDir.c_str());
    if (!dir) return 0;
    std::vector<std::string> files;
    while (struct dirent *e = readdir(dir)) {
        std::string name = e->d_name;
        if (name.size() > 11 && name.substr(name.size() - 11) == ".fastresume") files.push_back(name);
    }
    closedir(dir);
    for (auto const &name : files) {
        std::string data = readFile(s->stateDir + "/" + name);
        if (data.empty()) continue;
        lt::error_code ec;
        lt::add_torrent_params atp = lt::read_resume_data(lt::span<char const>(data.data(), static_cast<std::ptrdiff_t>(data.size())), ec);
        if (ec) continue;
        char id[72] = {0};
        char err[256] = {0};
        if (addParams(s, std::move(atp), id, err, sizeof(err)) == 0) count++;
    }
    return count;
}

void plx_pause(void *session, const char *id) {
    auto h = find(static_cast<Session *>(session), id);
    if (!h.is_valid()) return;
    h.unset_flags(lt::torrent_flags::auto_managed);
    h.pause(lt::torrent_handle::graceful_pause);
    h.save_resume_data(lt::torrent_handle::save_info_dict);
}

void plx_resume(void *session, const char *id) {
    auto h = find(static_cast<Session *>(session), id);
    if (!h.is_valid()) return;
    h.set_flags(lt::torrent_flags::auto_managed);
    h.resume();
}

void plx_remove(void *session, const char *id, int deleteFiles) {
    auto *s = static_cast<Session *>(session);
    auto h = find(s, id);
    if (!h.is_valid()) return;
    {
        std::lock_guard<std::mutex> lock(s->mutex);
        s->handles.erase(id);
    }
    s->ses->remove_torrent(h, deleteFiles ? lt::session_handle::delete_files : lt::remove_flags_t{});
    std::string resume = s->stateDir + "/" + std::string(id) + ".fastresume";
    unlink(resume.c_str());
}

void plx_set_sequential(void *session, const char *id, int on) {
    auto h = find(static_cast<Session *>(session), id);
    if (!h.is_valid()) return;
    if (on) h.set_flags(lt::torrent_flags::sequential_download);
    else h.unset_flags(lt::torrent_flags::sequential_download);
}

void plx_force_recheck(void *session, const char *id) {
    auto h = find(static_cast<Session *>(session), id);
    if (h.is_valid()) h.force_recheck();
}

void plx_force_reannounce(void *session, const char *id) {
    auto h = find(static_cast<Session *>(session), id);
    if (!h.is_valid()) return;
    h.force_reannounce();
    h.force_dht_announce();
}

int plx_status_all(void *session, plx_status *out, int max) {
    auto *s = static_cast<Session *>(session);
    std::vector<lt::torrent_handle> handles;
    {
        std::lock_guard<std::mutex> lock(s->mutex);
        for (auto const &kv : s->handles) handles.push_back(kv.second);
    }
    int n = 0;
    for (auto const &h : handles) {
        if (n >= max) break;
        if (!h.is_valid()) continue;
        lt::torrent_status st = h.status();
        plx_status &o = out[n];
        std::memset(&o, 0, sizeof(o));
        copyString(o.id, sizeof(o.id), idOf(st.info_hashes));
        copyString(o.name, sizeof(o.name), st.name);
        copyString(o.savePath, sizeof(o.savePath), st.save_path);
        if (st.errc) copyString(o.error, sizeof(o.error), st.errc.message());
        switch (st.state) {
            case lt::torrent_status::checking_files: o.state = 0; break;
            case lt::torrent_status::downloading_metadata: o.state = 1; break;
            case lt::torrent_status::downloading: o.state = 2; break;
            case lt::torrent_status::finished: o.state = 3; break;
            case lt::torrent_status::seeding: o.state = 4; break;
            case lt::torrent_status::checking_resume_data: o.state = 5; break;
            default: o.state = 2; break;
        }
        o.paused = (st.flags & lt::torrent_flags::paused) ? 1 : 0;
        o.hasMetadata = st.has_metadata ? 1 : 0;
        o.finished = st.is_finished ? 1 : 0;
        o.progress = st.progress;
        o.totalWanted = st.total_wanted;
        o.totalWantedDone = st.total_wanted_done;
        o.totalSize = st.total;
        o.allTimeDownload = st.all_time_download;
        o.allTimeUpload = st.all_time_upload;
        o.downRate = st.download_payload_rate;
        o.upRate = st.upload_payload_rate;
        o.peers = st.num_peers;
        o.seeds = st.num_seeds;
        o.connectCandidates = st.connect_candidates;
        n++;
    }
    return n;
}

int plx_file_count(void *session, const char *id) {
    auto h = find(static_cast<Session *>(session), id);
    if (!h.is_valid()) return 0;
    auto ti = h.torrent_file();
    if (!ti) return 0;
    return ti->files().num_files();
}

int plx_file_info(void *session, const char *id, int index, char *path, int pathLen,
                  long long *size, long long *done, int *priority) {
    auto h = find(static_cast<Session *>(session), id);
    if (!h.is_valid()) return 1;
    auto ti = h.torrent_file();
    if (!ti) return 1;
    auto const &fs = ti->files();
    if (index < 0 || index >= fs.num_files()) return 1;
    lt::file_index_t fi(index);
    copyString(path, static_cast<size_t>(pathLen), fs.file_path(fi));
    if (size) *size = fs.file_size(fi);
    std::vector<std::int64_t> progress;
    h.file_progress(progress, lt::torrent_handle::piece_granularity);
    if (done) *done = index < static_cast<int>(progress.size()) ? progress[static_cast<size_t>(index)] : 0;
    if (priority) *priority = static_cast<int>(static_cast<std::uint8_t>(h.file_priority(fi)));
    return 0;
}

void plx_set_file_priority(void *session, const char *id, int index, int priority) {
    auto h = find(static_cast<Session *>(session), id);
    if (!h.is_valid()) return;
    h.file_priority(lt::file_index_t(index), lt::download_priority_t(static_cast<std::uint8_t>(priority)));
}

int plx_iface_stats(void *session, plx_iface_stat *out, int max) {
    auto *s = static_cast<Session *>(session);
    std::vector<lt::torrent_handle> handles;
    {
        std::lock_guard<std::mutex> lock(s->mutex);
        for (auto const &kv : s->handles) handles.push_back(kv.second);
    }
    auto addresses = interfaceAddresses();
    std::map<std::string, plx_iface_stat> stats;
    for (auto const &h : handles) {
        if (!h.is_valid()) continue;
        std::vector<lt::peer_info> peers;
        h.get_peer_info(peers);
        for (auto const &p : peers) {
            std::string local = p.local_endpoint.address().to_string();
            auto it = addresses.find(local);
            std::string name = it != addresses.end() ? it->second : "other";
            auto &st = stats[name];
            copyString(st.interfaceName, sizeof(st.interfaceName), name);
            st.peers += 1;
            st.downRate += p.payload_down_speed;
            st.upRate += p.payload_up_speed;
        }
    }
    int n = 0;
    for (auto const &kv : stats) {
        if (n >= max) break;
        out[n++] = kv.second;
    }
    return n;
}

void plx_save_all(void *session) {
    auto *s = static_cast<Session *>(session);
    std::lock_guard<std::mutex> lock(s->mutex);
    for (auto const &kv : s->handles) {
        if (kv.second.is_valid() && kv.second.need_save_resume_data()) {
            kv.second.save_resume_data(lt::torrent_handle::save_info_dict);
        }
    }
}

int plx_pump(void *session, char *finishedIds, int maxFinished) {
    auto *s = static_cast<Session *>(session);
    std::vector<lt::alert *> alerts;
    s->ses->pop_alerts(&alerts);
    int finished = 0;
    for (lt::alert *a : alerts) {
        if (auto *r = lt::alert_cast<lt::save_resume_data_alert>(a)) {
            std::string id = idOf(r->handle);
            bool known;
            {
                std::lock_guard<std::mutex> lock(s->mutex);
                known = s->handles.count(id) > 0;
            }
            if (known) writeFile(s->stateDir + "/" + id + ".fastresume", lt::write_resume_data_buf(r->params));
        } else if (auto *f = lt::alert_cast<lt::torrent_finished_alert>(a)) {
            if (finishedIds && finished < maxFinished) {
                copyString(finishedIds + finished * 72, 72, idOf(f->handle));
                finished++;
            }
            f->handle.save_resume_data(lt::torrent_handle::save_info_dict);
        } else if (auto *m = lt::alert_cast<lt::metadata_received_alert>(a)) {
            m->handle.save_resume_data(lt::torrent_handle::save_info_dict);
        }
    }
    return finished;
}

} // extern "C"
