import Foundation

/// Store-only ZIP of WordprocessingML. Word, Pages, and Google Docs open it.
enum DOCXWriter {
    enum Block: Equatable {
        case heading(String, level: Int)
        case paragraph(String)
    }

    static func data(blocks: [Block]) -> Data {
        let document = documentXML(blocks: blocks)
        let entries: [(String, Data)] = [
            ("[Content_Types].xml", Data("""
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
            <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
            <Default Extension="xml" ContentType="application/xml"/>
            <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
            <Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>
            </Types>
            """.utf8)),
            ("_rels/.rels", Data("""
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
            <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
            </Relationships>
            """.utf8)),
            ("word/_rels/document.xml.rels", Data("""
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
            <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
            </Relationships>
            """.utf8)),
            ("word/styles.xml", Data(stylesXML.utf8)),
            ("word/document.xml", Data(document.utf8)),
        ]
        return OfficeZip.store(entries)
    }

    private static func documentXML(blocks: [Block]) -> String {
        var body = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body>
        """
        for block in blocks {
            switch block {
            case .heading(let text, let level):
                let style = min(max(level, 1), 3)
                body += "<w:p><w:pPr><w:pStyle w:val=\"Heading\(style)\"/></w:pPr>\(textRun(text))</w:p>"
            case .paragraph(let text):
                body += "<w:p>\(textRun(text))</w:p>"
            }
        }
        body += "</w:body></w:document>"
        return body
    }

    private static func textRun(_ text: String) -> String {
        let cleaned = xmlEscape(stripInvalidXML(text))
        let space = text.first?.isWhitespace == true || text.last?.isWhitespace == true
            ? " xml:space=\"preserve\""
            : ""
        return "<w:r><w:t\(space)>\(cleaned)</w:t></w:r>"
    }

    private static let stylesXML = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
    <w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/></w:style>
    <w:style w:type="paragraph" w:styleId="Heading1"><w:name w:val="heading 1"/><w:basedOn w:val="Normal"/></w:style>
    <w:style w:type="paragraph" w:styleId="Heading2"><w:name w:val="heading 2"/><w:basedOn w:val="Normal"/></w:style>
    <w:style w:type="paragraph" w:styleId="Heading3"><w:name w:val="heading 3"/><w:basedOn w:val="Normal"/></w:style>
    </w:styles>
    """

    private static func xmlEscape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    private static func stripInvalidXML(_ value: String) -> String {
        value.unicodeScalars.filter { scalar in
            switch scalar.value {
            case 0x9, 0xA, 0xD: return true
            case 0x20...0xD7FF, 0xE000...0xFFFD, 0x10000...0x10FFFF: return true
            default: return false
            }
        }.map(String.init).joined()
    }
}

/// ZIP stored (no compression). Shared by .xlsx and .docx writers.
enum OfficeZip {
    static func store(_ files: [(String, Data)]) -> Data {
        var locals = Data()
        var central = Data()
        var offset = 0
        for (name, payload) in files {
            let nameData = Data(name.utf8)
            let crc = crc32(payload)
            var local = Data()
            local.append(contentsOf: [0x50, 0x4b, 0x03, 0x04, 0x14, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00])
            local.append(u32(crc))
            local.append(u32(UInt32(payload.count)))
            local.append(u32(UInt32(payload.count)))
            local.append(u16(UInt16(nameData.count)))
            local.append(u16(0))
            local.append(nameData)
            local.append(payload)
            var cen = Data()
            cen.append(contentsOf: [0x50, 0x4b, 0x01, 0x02, 0x14, 0x00, 0x14, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00])
            cen.append(u32(crc))
            cen.append(u32(UInt32(payload.count)))
            cen.append(u32(UInt32(payload.count)))
            cen.append(u16(UInt16(nameData.count)))
            cen.append(contentsOf: [UInt8](repeating: 0, count: 12))
            cen.append(u32(UInt32(offset)))
            cen.append(nameData)
            central.append(cen)
            locals.append(local)
            offset += local.count
        }
        var end = Data()
        end.append(contentsOf: [0x50, 0x4b, 0x05, 0x06, 0x00, 0x00, 0x00, 0x00])
        end.append(u16(UInt16(files.count)))
        end.append(u16(UInt16(files.count)))
        end.append(u32(UInt32(central.count)))
        end.append(u32(UInt32(locals.count)))
        end.append(u16(0))
        var zip = Data()
        zip.append(locals)
        zip.append(central)
        zip.append(end)
        return zip
    }

    private static func u16(_ v: UInt16) -> Data {
        var le = v.littleEndian
        return Data(bytes: &le, count: 2)
    }

    private static func u32(_ v: UInt32) -> Data {
        var le = v.littleEndian
        return Data(bytes: &le, count: 4)
    }

    private static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        for byte in data {
            let idx = Int((crc ^ UInt32(byte)) & 0xFF)
            crc = crc32Table[idx] ^ (crc >> 8)
        }
        return crc ^ 0xFFFFFFFF
    }

    private static let crc32Table: [UInt32] = {
        (0..<256).map { i -> UInt32 in
            var c = UInt32(i)
            for _ in 0..<8 {
                c = (c & 1) != 0 ? (0xEDB88320 ^ (c >> 1)) : (c >> 1)
            }
            return c
        }
    }()
}
