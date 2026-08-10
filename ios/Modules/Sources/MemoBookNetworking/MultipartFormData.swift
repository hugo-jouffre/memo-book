import Foundation

/// Construction d'un corps `multipart/form-data`.
///
/// Le back-end lit le fichier via `@fastify/multipart` et les champs texte à
/// côté : l'ordre importe peu, mais le fichier doit porter le nom `file`.
struct MultipartFormData {
    let boundary: String
    private var body = Data()

    init(boundary: String = "memobook-\(UUID().uuidString)") {
        self.boundary = boundary
    }

    var contentType: String { "multipart/form-data; boundary=\(boundary)" }

    mutating func addField(name: String, value: String) {
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
        append("\(value)\r\n")
    }

    mutating func addFile(
        name: String,
        filename: String,
        mimeType: String,
        data: Data
    ) {
        append("--\(boundary)\r\n")
        append(
            "Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n"
        )
        append("Content-Type: \(mimeType)\r\n\r\n")
        body.append(data)
        append("\r\n")
    }

    /// Renvoie le corps complet, terminé par sa frontière de fermeture.
    func finalized() -> Data {
        var result = body
        result.append(Data("--\(boundary)--\r\n".utf8))
        return result
    }

    private mutating func append(_ string: String) {
        // Le corps est composé d'en-têtes ASCII et de binaire : l'encodage UTF-8
        // ne peut échouer que sur une chaîne mal formée, impossible ici.
        if let data = string.data(using: .utf8) {
            body.append(data)
        }
    }
}
