import Foundation
import MemoBookCore
import MemoBookNetworking

/// Double de l'API pour les aperçus SwiftUI et les tests d'interface.
///
/// Il garde son état en mémoire : ajouter un souvenir dans un aperçu met
/// vraiment la liste à jour, ce qui rend les aperçus utilisables pour
/// travailler les écrans sans back-end lancé.
public actor PreviewAPI: MemoBookAPI {
    private var memosById: [String: MemoDetail] = [:]
    private var rendersById: [String: Render] = [:]

    public init(seeded: Bool = true) {
        // Le jeu d'essai est construit hors de l'acteur puis affecté : un `init`
        // synchrone d'acteur ne peut pas appeler ses propres méthodes isolées.
        if seeded {
            let seed = Self.seedMemo()
            memosById[seed.id] = seed
        }
    }

    private static func seedMemo() -> MemoDetail {
        let memoId = "preview-memo"
        let now = Date.now

        let entries = [
            Entry(
                id: "entry-1",
                memoId: memoId,
                kind: .audio,
                status: .ready,
                transcript:
                    "On arrive à Bogotá après un vol de nuit. La première claque, c'est l'altitude.",
                capturedAt: now.addingTimeInterval(-86_400 * 2),
                placeLabel: "Bogotá, Colombie",
                error: nil,
                media: nil,
                createdAt: now.addingTimeInterval(-86_400 * 2)
            ),
            Entry(
                id: "entry-2",
                memoId: memoId,
                kind: .audio,
                status: .processing,
                transcript: nil,
                capturedAt: now.addingTimeInterval(-86_400),
                placeLabel: "Monserrate",
                error: nil,
                media: nil,
                createdAt: now.addingTimeInterval(-86_400)
            ),
        ]

        return MemoDetail(
            id: memoId,
            title: "Claire et Gus en Colombie",
            subtitle: "Un carnet de voyage raconté à l'oral",
            authors: "Claire et Augustin",
            theme: "voyage",
            startDate: nil,
            endDate: nil,
            coverPhotoUrl: nil,
            createdAt: now,
            updatedAt: now,
            entries: entries,
            renders: []
        )
    }

    public func ensureDeviceRegistered() async throws {}

    public func memos() async throws -> [MemoSummary] {
        memosById.values
            .sorted { $0.createdAt > $1.createdAt }
            .map { memo in
                MemoSummary(
                    id: memo.id,
                    title: memo.title,
                    subtitle: memo.subtitle,
                    theme: memo.theme,
                    coverPhotoUrl: memo.coverPhotoUrl,
                    createdAt: memo.createdAt,
                    entryCount: memo.entries.count,
                    latestRender: memo.renders.first
                )
            }
    }

    public func createMemo(_ memo: NewMemo) async throws -> Memo {
        let id = UUID().uuidString
        let now = Date.now

        memosById[id] = MemoDetail(
            id: id,
            title: memo.title,
            subtitle: memo.subtitle,
            authors: memo.authors,
            theme: memo.theme,
            startDate: memo.startDate,
            endDate: memo.endDate,
            coverPhotoUrl: nil,
            createdAt: now,
            updatedAt: now,
            entries: [],
            renders: []
        )

        return Memo(
            id: id,
            title: memo.title,
            subtitle: memo.subtitle,
            authors: memo.authors,
            theme: memo.theme,
            startDate: memo.startDate,
            endDate: memo.endDate,
            createdAt: now,
            updatedAt: now
        )
    }

    public func memo(id: String) async throws -> MemoDetail {
        guard let memo = memosById[id] else {
            throw APIError.server(statusCode: 404, code: "not_found", message: "Carnet introuvable.")
        }
        return memo
    }

    public func deleteMemo(id: String) async throws {
        memosById[id] = nil
    }

    public func addTextEntry(memoId: String, entry: NewTextEntry) async throws -> Entry {
        try append(
            to: memoId,
            kind: .text,
            status: .ready,
            transcript: entry.transcript,
            capturedAt: entry.capturedAt,
            placeLabel: entry.placeLabel
        )
    }

    public func uploadAudio(
        memoId: String,
        data: Data,
        filename: String,
        mimeType: String,
        capturedAt: Date,
        placeLabel: String?
    ) async throws -> Entry {
        try append(
            to: memoId,
            kind: .audio,
            status: .pending,
            transcript: nil,
            capturedAt: capturedAt,
            placeLabel: placeLabel
        )
    }

    public func uploadPhoto(
        memoId: String,
        data: Data,
        filename: String,
        mimeType: String,
        capturedAt: Date,
        placeLabel: String?
    ) async throws -> Entry {
        try append(
            to: memoId,
            kind: .photo,
            status: .ready,
            transcript: nil,
            capturedAt: capturedAt,
            placeLabel: placeLabel
        )
    }

    private func append(
        to memoId: String,
        kind: EntryKind,
        status: Status,
        transcript: String?,
        capturedAt: Date,
        placeLabel: String?
    ) throws -> Entry {
        let memo = try existingMemo(memoId)

        let entry = Entry(
            id: UUID().uuidString,
            memoId: memoId,
            kind: kind,
            status: status,
            transcript: transcript,
            capturedAt: capturedAt,
            placeLabel: placeLabel,
            error: nil,
            media: nil,
            createdAt: .now
        )

        memosById[memoId] = memo.appending(entry: entry)
        return entry
    }

    public func entry(id: String) async throws -> Entry {
        for memo in memosById.values {
            if let entry = memo.entries.first(where: { $0.id == id }) { return entry }
        }
        throw APIError.server(statusCode: 404, code: "not_found", message: "Entrée introuvable.")
    }

    public func startRender(memoId: String) async throws -> Render {
        let memo = try existingMemo(memoId)

        let render = Render(
            id: UUID().uuidString,
            memoId: memoId,
            status: .ready,
            pdfUrl: "https://pdf.example.test/preview.pdf",
            error: nil,
            createdAt: .now,
            updatedAt: .now
        )

        rendersById[render.id] = render
        memosById[memoId] = memo.prepending(render: render)
        return render
    }

    public func render(id: String) async throws -> Render {
        guard let render = rendersById[id] else {
            throw APIError.server(
                statusCode: 404,
                code: "not_found",
                message: "Génération introuvable."
            )
        }
        return render
    }

    private func existingMemo(_ id: String) throws -> MemoDetail {
        guard let memo = memosById[id] else {
            throw APIError.server(statusCode: 404, code: "not_found", message: "Carnet introuvable.")
        }
        return memo
    }
}

extension MemoDetail {
    fileprivate func appending(entry: Entry) -> MemoDetail {
        MemoDetail(
            id: id,
            title: title,
            subtitle: subtitle,
            authors: authors,
            theme: theme,
            startDate: startDate,
            endDate: endDate,
            coverPhotoUrl: coverPhotoUrl,
            createdAt: createdAt,
            updatedAt: .now,
            entries: (entries + [entry]).sorted { $0.capturedAt < $1.capturedAt },
            renders: renders
        )
    }

    fileprivate func prepending(render: Render) -> MemoDetail {
        MemoDetail(
            id: id,
            title: title,
            subtitle: subtitle,
            authors: authors,
            theme: theme,
            startDate: startDate,
            endDate: endDate,
            coverPhotoUrl: coverPhotoUrl,
            createdAt: createdAt,
            updatedAt: .now,
            entries: entries,
            renders: [render] + renders
        )
    }
}
