import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var downloads: DownloadManager
    @State private var showLogin = false
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            List {
                if let account = store.account {
                    Section("Konto") {
                        Label {
                            VStack(alignment: .leading) {
                                Text(account.displayName).font(.headline)
                                if let email = account.email {
                                    Text(email).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        } icon: {
                            Image(systemName: "person.crop.circle.fill").font(.title2)
                        }
                    }
                    syncSection
                    Section("Server (\(store.servers.count))") {
                        if store.servers.isEmpty {
                            Text("Noch keine Server gefunden.").foregroundStyle(.secondary)
                        }
                        ForEach(store.servers) { server in
                            ServerRow(server: server)
                        }
                    }
                    Section("Bibliothek") {
                        statRow("Filme", "film", store.movies.count)
                        statRow("Serien", "tv", store.shows.count)
                        statRow("Episoden", "list.number", store.episodes.count)
                        NavigationLink {
                            PlaylistsView()
                        } label: {
                            statRow("Playlists", "music.note.list", store.playlists.count)
                        }
                        NavigationLink {
                            SearchView()
                        } label: {
                            Label("Alles durchsuchen", systemImage: "magnifyingglass")
                        }
                    }
                } else {
                    Section {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Willkommen bei Pledo").font(.title2.bold())
                            Text("Lade Filme, Serien und Playlists von allen Plex-Servern herunter, auf die dein Konto Zugriff hat – direkt auf dein iPhone.")
                                .foregroundStyle(.secondary)
                            Button {
                                showLogin = true
                            } label: {
                                Label("Mit Plex anmelden", systemImage: "person.badge.key.fill")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .padding(.top, 6)
                        }
                        .padding(.vertical, 8)
                    }
                }
            }
            .navigationTitle("Pledo")
            .refreshable { await store.sync(full: false) }
            .sheet(isPresented: $showLogin) { LoginView().environmentObject(store) }
            .sheet(isPresented: $showSettings) {
                SettingsView().environmentObject(store).environmentObject(downloads)
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .mediaDestinations()
        }
    }

    private var syncSection: some View {
        Section {
            if store.isSyncing {
                HStack(spacing: 10) {
                    ProgressView()
                    Text(store.syncStatus.isEmpty ? "Synchronisiere…" : store.syncStatus)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            } else {
                Button {
                    Task { await store.sync(full: true) }
                } label: {
                    Label("Vollständiger Sync", systemImage: "arrow.triangle.2.circlepath")
                }
                Button {
                    Task { await store.sync(full: false) }
                } label: {
                    Label("Nur Verbindungen prüfen", systemImage: "antenna.radiowaves.left.and.right")
                }
            }
            if let error = store.lastError {
                Text(error).font(.caption).foregroundStyle(.red)
            }
        } header: {
            Text("Synchronisierung")
        } footer: {
            if let last = store.lastSync {
                Text("Letzter vollständiger Sync: \(Format.relative(last))")
            } else {
                Text("Noch kein vollständiger Sync durchgeführt.")
            }
        }
    }

    private func statRow(_ title: String, _ icon: String, _ count: Int) -> some View {
        HStack {
            Label(title, systemImage: icon)
            Spacer()
            Text("\(count)").foregroundStyle(.secondary).monospacedDigit()
        }
    }
}

struct ServerRow: View {
    let server: PlexServer

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(server.isOnline ? Color.green : Color.red)
                .frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 2) {
                Text(server.name).font(.headline)
                Text(server.ownerLabel).font(.caption).foregroundStyle(.secondary)
                if server.isOnline {
                    Text(server.connectionLabel).font(.caption2).foregroundStyle(.secondary)
                } else {
                    Text("Offline").font(.caption2).foregroundStyle(.red)
                }
            }
        }
    }
}

struct LoginView: View {
    @EnvironmentObject private var store: LibraryStore
    @Environment(\.dismiss) private var dismiss

    @State private var safari: IdentifiableURL?
    @State private var pollTask: Task<Void, Never>?
    @State private var waiting = false
    @State private var busy = false
    @State private var errorText: String?
    @State private var username = ""
    @State private var password = ""
    @State private var code = ""
    @State private var token = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button {
                        startOAuth()
                    } label: {
                        Label("Über plex.tv anmelden", systemImage: "safari")
                    }
                    .disabled(busy)
                    if waiting {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Warte auf Bestätigung durch plex.tv…").font(.callout)
                        }
                    }
                } footer: {
                    Text("Empfohlen: Die Anmeldung erfolgt auf der Plex-Webseite, dein Passwort wird nicht in dieser App eingegeben.")
                }

                Section {
                    TextField("E-Mail oder Benutzername", text: $username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textContentType(.username)
                    SecureField("Passwort", text: $password)
                        .textContentType(.password)
                    TextField("2FA-Code (optional)", text: $code)
                        .keyboardType(.numberPad)
                    Button("Anmelden") { loginWithPassword() }
                        .disabled(busy || username.isEmpty || password.isEmpty)
                } header: {
                    Text("Benutzername & Passwort")
                }

                Section {
                    TextField("X-Plex-Token", text: $token)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("Mit Token anmelden") { run { try await store.login(token: token.trimmingCharacters(in: .whitespaces)) } }
                        .disabled(busy || token.isEmpty)
                } header: {
                    Text("Plex-Token")
                }

                if let errorText {
                    Section {
                        Text(errorText).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Anmelden")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") {
                        pollTask?.cancel()
                        dismiss()
                    }
                }
            }
            .sheet(item: $safari) { item in
                SafariView(url: item.url).ignoresSafeArea()
            }
        }
        .onDisappear { pollTask?.cancel() }
    }

    private func run(_ action: @escaping () async throws -> Void) {
        errorText = nil
        busy = true
        Task {
            do {
                try await action()
                busy = false
                dismiss()
            } catch {
                busy = false
                errorText = error.localizedDescription
            }
        }
    }

    private func loginWithPassword() {
        let client = store.client
        let u = username, p = password, c = code
        run {
            let t = try await client.signIn(login: u, password: p, verificationCode: c)
            try await store.login(token: t)
        }
    }

    private func startOAuth() {
        errorText = nil
        pollTask?.cancel()
        waiting = true
        let client = store.client
        pollTask = Task {
            do {
                let pin = try await client.createPin()
                safari = IdentifiableURL(url: client.authURL(for: pin))
                let deadline = Date().addingTimeInterval(15 * 60)
                while Date() < deadline {
                    try await Task.sleep(nanoseconds: 2_000_000_000)
                    if let t = try? await client.checkPin(pin) {
                        safari = nil
                        try await store.login(token: t)
                        waiting = false
                        dismiss()
                        return
                    }
                }
                throw PlexError.missingData("Zeitüberschreitung bei der Anmeldung")
            } catch is CancellationError {
                // abgebrochen
            } catch {
                errorText = error.localizedDescription
            }
            waiting = false
        }
    }
}
