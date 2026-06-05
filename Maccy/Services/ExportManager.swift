import AppKit
import Foundation

final class ExportManager {
  static let shared = ExportManager()

  // MARK: - CSV zip export

  @MainActor
  func exportCSVZip() async throws -> URL {
    let clipboardCSV = buildClipboardCSV()
    var pinboardCSVs: [(String, String)] = []
    for board in PinboardStore.shared.pinboards {
      let entries = PinboardStore.shared.entries(for: board)
      let csv = buildPinboardCSV(entries: entries)
      let safeName = board.name
        .replacingOccurrences(of: "/", with: "-")
        .replacingOccurrences(of: ":", with: "-")
        .replacingOccurrences(of: "\\", with: "-")
      pinboardCSVs.append(("\(safeName).csv", csv))
    }

    let tempDir = FileManager.default.temporaryDirectory
      .appendingPathComponent("CopyCatExport_\(Int(Date().timeIntervalSince1970))", isDirectory: true)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    try clipboardCSV.write(to: tempDir.appendingPathComponent("Clipboard.csv"), atomically: true, encoding: .utf8)
    for (name, content) in pinboardCSVs {
      try content.write(to: tempDir.appendingPathComponent(name), atomically: true, encoding: .utf8)
    }

    let zipURL = FileManager.default.temporaryDirectory.appendingPathComponent("CopyCatExport.zip")
    try? FileManager.default.removeItem(at: zipURL)

    try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
      let process = Process()
      process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
      process.arguments = ["-r", zipURL.path, "."]
      process.currentDirectoryURL = tempDir
      process.terminationHandler = { p in
        p.terminationStatus == 0 ? cont.resume() : cont.resume(throwing: ExportError.zipFailed)
      }
      do { try process.run() } catch { cont.resume(throwing: error) }
    }

    return zipURL
  }

  // MARK: - PDF export (HTML → NSTextView → dataWithPDF)

  @MainActor
  func exportPDF() async throws -> URL {
    let html = buildHTML()
    guard let data = html.data(using: .utf8) else { throw ExportError.encodingFailed }

    var docAttribs: NSDictionary? = nil
    let attrStr = try NSAttributedString(
      data: data,
      options: [
        .documentType: NSAttributedString.DocumentType.html,
        .characterEncoding: String.Encoding.utf8.rawValue
      ],
      documentAttributes: &docAttribs
    )

    // Render into an off-screen NSTextView then capture as PDF
    let pageWidth: CGFloat = 600
    let tv = NSTextView(frame: NSRect(x: 0, y: 0, width: pageWidth, height: 10))
    tv.isVerticallyResizable = true
    tv.maxSize = NSSize(width: pageWidth, height: 1_000_000)
    tv.textContainer?.containerSize = NSSize(width: pageWidth, height: CGFloat.greatestFiniteMagnitude)
    tv.textContainer?.widthTracksTextView = true
    tv.textStorage?.setAttributedString(attrStr)
    tv.sizeToFit()

    let pdfData = tv.dataWithPDF(inside: tv.bounds)
    let pdfURL = FileManager.default.temporaryDirectory.appendingPathComponent("CopyCatExport.pdf")
    try pdfData.write(to: pdfURL)
    return pdfURL
  }

  // MARK: - CSV builders

  @MainActor
  private func buildClipboardCSV() -> String {
    let fmt = ISO8601DateFormatter()
    var rows = ["text,type,application,copied_at,is_pinned"]
    for dec in AppState.shared.history.items {
      let text = csvEscape(dec.item.text ?? "")
      let type = itemType(hasImage: dec.hasImage, text: dec.item.text, fileURLs: dec.item.fileURLs)
      let app = csvEscape(dec.application ?? "")
      let date = fmt.string(from: dec.item.firstCopiedAt)
      rows.append("\(text),\(type),\(app),\(date),\(dec.isPinned)")
    }
    return rows.joined(separator: "\n")
  }

  private func buildPinboardCSV(entries: [PinboardEntry]) -> String {
    let fmt = ISO8601DateFormatter()
    var rows = ["text,type,application,copied_at,is_pinned"]
    for entry in entries {
      let text = csvEscape(entry.text ?? "")
      let type = entryType(entry)
      let app = csvEscape(entry.applicationName ?? "")
      let date = fmt.string(from: entry.copiedAt)
      rows.append("\(text),\(type),\(app),\(date),\(entry.isPinned)")
    }
    return rows.joined(separator: "\n")
  }

  // MARK: - HTML builder for PDF

  @MainActor
  private func buildHTML() -> String {
    let fmt = DateFormatter()
    fmt.dateStyle = .medium
    fmt.timeStyle = .short

    let clipItems = AppState.shared.history.items
    let boards = PinboardStore.shared.pinboards
    let totalPinboard = boards.reduce(0) { $0 + PinboardStore.shared.entries(for: $1).count }

    var html = """
    <html><head><meta charset="utf-8">
    <style>
    body{font-family:-apple-system,'Helvetica Neue',sans-serif;color:#1f2937;margin:24px 28px;}
    .hd{color:#57D559;font-size:26px;font-weight:bold;}
    .hdsub{color:#bfe3ce;font-size:11px;letter-spacing:2px;}
    .meta{color:#9fc7b5;font-size:10px;letter-spacing:1px;}
    .metaval{color:#ffffff;font-weight:bold;font-size:12px;}
    .statn{font-size:23px;font-weight:bold;color:#024E50;}
    .statl{color:#6b7280;font-size:9px;letter-spacing:.5px;}
    .sectitle{color:#024E50;font-size:13px;font-weight:bold;}
    .seccount{color:#6b7280;font-size:11px;}
    th{text-align:left;background-color:#024E50;color:#ffffff;padding:7px 9px;font-size:9px;letter-spacing:.5px;}
    td{padding:8px 9px;font-size:11px;color:#374151;}
    .app{color:#6b7280;font-size:10px;}
    .date{color:#9ca3af;font-size:10px;}
    .pin{background-color:#fde2d6;color:#c2410c;padding:2px 6px;font-size:8px;font-weight:bold;}
    .thumb{max-width:200px;}
    .empty{color:#b6c2b8;font-style:italic;font-size:11px;}
    .foot{color:#9ca3af;font-size:9px;letter-spacing:.5px;}
    </style></head><body>
    <table width="100%" cellspacing="0" cellpadding="0"><tr>
    <td style="background-color:#024E50;padding:20px 24px;"><span class="hd">Copy&nbsp;Cat</span><br><span class="hdsub">CLIPBOARD&nbsp;EXPORT</span></td>
    <td align="right" valign="bottom" style="background-color:#024E50;padding:20px 24px;"><span class="meta">GENERATED</span><br><span class="metaval">\(fmt.string(from: Date()))</span></td>
    </tr></table>
    <br>
    <table width="100%" cellspacing="6" cellpadding="0"><tr>
    \(statCard(clipItems.count, "CLIPBOARD ITEMS"))
    \(statCard(boards.count, "PINBOARDS"))
    \(statCard(totalPinboard, "PINNED ITEMS"))
    </tr></table>
    """

    html += sectionTable(title: "Clipboard History", count: clipItems.count, rows: clipItems.map { dec in
      let type = itemType(hasImage: dec.hasImage, text: dec.item.text, fileURLs: dec.item.fileURLs)
      let content: String
      if type == "IMAGE", let uri = imageThumbnailDataURI(dec.item.imageData) {
        content = "<img class='thumb' src='\(uri)'/>"
      } else {
        content = htmlEscape(String((dec.item.text ?? (dec.hasImage ? "[Image]" : "[File]")).prefix(300)))
      }
      let pin = dec.isPinned ? " <span class='pin'>PINNED</span>" : ""
      return (type, content + pin, htmlEscape(dec.application ?? ""), fmt.string(from: dec.item.lastCopiedAt))
    })

    for board in boards {
      let entries = PinboardStore.shared.entries(for: board)
      html += sectionTable(title: board.name, count: entries.count, rows: entries.map { entry in
        let type = entryType(entry)
        let content: String
        if type == "IMAGE", let uri = imageThumbnailDataURI(entry.imageData) {
          content = "<img class='thumb' src='\(uri)'/>"
        } else {
          content = htmlEscape(String((entry.text ?? (entry.imageData != nil ? "[Image]" : "[File]")).prefix(300)))
        }
        let pin = entry.isPinned ? " <span class='pin'>PINNED</span>" : ""
        return (type, content + pin, htmlEscape(entry.applicationName ?? ""), fmt.string(from: entry.copiedAt))
      })
    }

    html += """
    <br><table width="100%" cellspacing="0" cellpadding="0"><tr>
    <td align="center" style="border-top:2px solid #57D559;padding-top:8px;"><span class="foot">EXPORTED FROM COPY CAT&nbsp;&middot;&nbsp;copycat.app</span></td>
    </tr></table>
    """
    html += "</body></html>"
    return html
  }

  /// A summary stat "card" cell with a tinted background.
  private func statCard(_ n: Int, _ label: String) -> String {
    "<td width=\"33%\" valign=\"top\" style=\"background-color:#f1f7f2;padding:13px 15px;\">"
      + "<span class=\"statn\">\(n)</span><br><span class=\"statl\">\(label)</span></td>"
  }

  /// One decorated section: an accent-striped header bar above a zebra-striped table.
  private func sectionTable(title: String, count: Int, rows: [(String, String, String, String)]) -> String {
    var section = """
    <br><table width="100%" cellspacing="0" cellpadding="0"><tr>
    <td width="4" style="background-color:#57D559;">&nbsp;</td>
    <td style="background-color:#eef4ee;padding:7px 12px;"><span class="sectitle">\(htmlEscape(title))</span> &nbsp;<span class="seccount">\(count) item\(count == 1 ? "" : "s")</span></td>
    </tr></table>
    """
    guard !rows.isEmpty else { return section + "<div class='empty'>No items</div>" }
    section += "<table width=\"100%\" cellspacing=\"0\" cellpadding=\"0\">"
      + "<tr><th width=\"66\">TYPE</th><th>CONTENT</th><th width=\"110\">SOURCE</th><th width=\"96\">DATE</th></tr>"
    for (i, row) in rows.enumerated() {
      let (type, content, app, date) = row
      let bg = i % 2 == 0 ? "#ffffff" : "#f6faf6"
      section += "<tr bgcolor=\"\(bg)\"><td valign=\"top\">\(badge(type))</td>"
        + "<td valign=\"top\">\(content)</td>"
        + "<td class=\"app\" valign=\"top\">\(app)</td>"
        + "<td class=\"date\" valign=\"top\">\(date)</td></tr>"
    }
    return section + "</table>"
  }

  /// A colored badge pill for the item type (green/blue/orange/gray).
  private func badge(_ type: String) -> String {
    let bg: String, fg: String
    switch type {
    case "LINK": bg = "#e3ecfb"; fg = "#1a3a8a"
    case "IMAGE": bg = "#fde8df"; fg = "#a8341a"
    case "FILE": bg = "#eceef0"; fg = "#4b5563"
    default: bg = "#dff3e0"; fg = "#1f7a33"
    }
    return "<span style=\"background-color:\(bg);color:\(fg);padding:2px 7px;font-size:9px;font-weight:bold;\">\(type)</span>"
  }

  /// Downscales clipboard image data to a JPEG thumbnail and returns a base64
  /// data URI so it embeds inline in the PDF while keeping the file small.
  private func imageThumbnailDataURI(_ data: Data?, maxWidth: CGFloat = 240) -> String? {
    guard let data, let image = NSImage(data: data) else { return nil }
    let size = image.size
    guard size.width > 0, size.height > 0 else { return nil }
    let scale = min(1, maxWidth / size.width)
    let target = NSSize(width: max(1, size.width * scale), height: max(1, size.height * scale))
    guard let rep = NSBitmapImageRep(
      bitmapDataPlanes: nil, pixelsWide: Int(target.width), pixelsHigh: Int(target.height),
      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
      colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ) else { return nil }
    rep.size = target
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    image.draw(in: NSRect(origin: .zero, size: target),
               from: NSRect(origin: .zero, size: size), operation: .copy, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()
    guard let jpeg = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.7]) else { return nil }
    return "data:image/jpeg;base64,\(jpeg.base64EncodedString())"
  }

  // MARK: - Helpers

  private func itemType(hasImage: Bool, text: String?, fileURLs: [URL]) -> String {
    if hasImage { return "IMAGE" }
    if !fileURLs.isEmpty { return "FILE" }
    if let t = text, t.hasPrefix("https://") || t.hasPrefix("http://") { return "LINK" }
    return "TEXT"
  }

  private func entryType(_ entry: PinboardEntry) -> String {
    if entry.imageData != nil { return "IMAGE" }
    if !(entry.fileURLStrings ?? []).isEmpty { return "FILE" }
    if let t = entry.text, t.hasPrefix("https://") || t.hasPrefix("http://") { return "LINK" }
    return "TEXT"
  }

  private func csvEscape(_ str: String) -> String {
    let clean = str
      .replacingOccurrences(of: "\"", with: "\"\"")
      .replacingOccurrences(of: "\n", with: " ")
      .replacingOccurrences(of: "\r", with: " ")
    return "\"\(clean)\""
  }

  private func htmlEscape(_ str: String) -> String {
    str
      .replacingOccurrences(of: "&", with: "&amp;")
      .replacingOccurrences(of: "<", with: "&lt;")
      .replacingOccurrences(of: ">", with: "&gt;")
      .replacingOccurrences(of: "\"", with: "&quot;")
  }

  enum ExportError: Error {
    case encodingFailed
    case zipFailed
  }
}
