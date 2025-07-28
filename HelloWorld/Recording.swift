import Foundation

struct Recording: Identifiable, Codable, Equatable {
    let id = UUID()
    let fileName: String
    let url: URL
    let createdAt: Date
    let duration: TimeInterval
    var title: String
    
    init(fileName: String, url: URL, createdAt: Date = Date(), duration: TimeInterval = 0, title: String? = nil) {
        self.fileName = fileName
        self.url = url
        self.createdAt = createdAt
        self.duration = duration
        self.title = title ?? Recording.defaultTitle(for: createdAt)
    }
    
    private static func defaultTitle(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return "Recording \(formatter.string(from: date))"
    }
    
    var fileSizeString: String {
        guard let fileSize = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize else {
            return "Unknown size"
        }
        return ByteCountFormatter.string(fromByteCount: Int64(fileSize), countStyle: .file)
    }
    
    var durationString: String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}