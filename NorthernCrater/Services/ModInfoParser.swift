//
//  ModInfoParser.swift
//  NorthernCrater
//
//  Reads a 7th Heaven mod.xml (`<ModInfo>`): name, author, version, category and the config options the
//  player can set. A `ConfigOption` is `Type` (List or Bool), `Default`, `ID`, `Name`, `Description` and,
//  for lists, `<Option Value="1" Name="..."/>` children.
//

import Foundation

enum ModInfoParser {
    static func parse(_ xml: Data, archiveURL: URL) throws -> ModItem {
        let delegate = Delegate()
        let parser = XMLParser(data: xml)
        parser.delegate = delegate
        guard parser.parse(), delegate.sawModInfo else { throw IROParserError.malformedModXML }
        
        func fallback(_ value: String, _ replacement: String) -> String { value.isEmpty ? replacement : value }
        let fileName = archiveURL.deletingPathExtension().lastPathComponent
        return ModItem(
            id: UUID(),
            name: fallback(delegate.name, fileName),
            author: fallback(delegate.author, "Unknown Author"),
            version: fallback(delegate.version, "1.0"),
            category: fallback(delegate.category, "Uncategorized"),
            archiveURL: archiveURL,
            isEnabled: true,
            options: delegate.options,
            ffnxConfig: delegate.ffnx,
            previewFile: delegate.previewFile.isEmpty ? nil : delegate.previewFile,
            infoVersion: ModItem.currentInfoVersion
        )
    }
    
    private final class Delegate: NSObject, XMLParserDelegate {
        var name = "", author = "", version = "", category = "", previewFile = ""
        var options: [ModOption] = []
        var ffnx: [FFNxEntry] = []
        var sawModInfo = false
        
        private struct OptionBuilder {
            var type = "", defaultValue = "", id = "", name = "", description = ""
            var choices: [ModOptionChoice] = []
        }
        
        private var path: [String] = []
        private var text = ""
        private var option: OptionBuilder?
        private var ffnxWhen: [String: String] = [:]
        private var ffnxItems: [String] = []
        
        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                    qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
            path.append(elementName)
            text = ""
            if path == ["ModInfo"] {
                sawModInfo = true
            } else if path == ["ModInfo", "ConfigOption"] {
                option = OptionBuilder()
            } else if path.count == 3, path[0] == "ModInfo", path[1] == "FFNxConfig" {
                ffnxWhen = attributeDict
                ffnxItems = []
            } else if path.count == 4, path[1] == "FFNxConfig", elementName == "item" {
                // a list value: <item> children
            } else if path == ["ModInfo", "ConfigOption", "Option"], let value = attributeDict["Value"] {
                let preview = attributeDict["PreviewFile"].flatMap { $0.isEmpty ? nil : $0 }
                option?.choices.append(ModOptionChoice(id: value, name: attributeDict["Name"] ?? "Option \(value)",
                                                       previewFile: preview,
                                                       previewAudio: attributeDict["PreviewAudio"].flatMap { $0.isEmpty ? nil : $0 }))
            }
        }
        
        func parser(_ parser: XMLParser, foundCharacters string: String) {
            text += string
        }
        
        func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
                    qualifiedName qName: String?) {
            let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
            switch path {
            case ["ModInfo", "Name"]: name = value
            case ["ModInfo", "Author"]: author = value
            case ["ModInfo", "Version"]: version = value
            case ["ModInfo", "Category"]: category = value
            case ["ModInfo", "PreviewFile"]: previewFile = value
            case ["ModInfo", "ConfigOption", "Type"]: option?.type = value
            case ["ModInfo", "ConfigOption", "Default"]: option?.defaultValue = value
            case ["ModInfo", "ConfigOption", "ID"]: option?.id = value
            case ["ModInfo", "ConfigOption", "Name"]: option?.name = value
            case ["ModInfo", "ConfigOption", "Description"]: option?.description = value
            case ["ModInfo", "ConfigOption"]: finishOption()
            default:
                if path.count == 4, path[1] == "FFNxConfig", elementName == "item" {
                    ffnxItems.append(value)
                } else if path.count == 3, path[1] == "FFNxConfig" {
                    ffnx.append(FFNxEntry(key: elementName,
                                          value: ffnxItems.isEmpty ? value : ffnxItems.joined(separator: ","),
                                          when: ffnxWhen))
                }
            }
            _ = path.popLast()
            text = ""
        }
        
        private func finishOption() {
            guard var o = option, !o.id.isEmpty else { option = nil; return }
            if o.choices.isEmpty {
                // A Bool option has no <Option> children: off (0) and on (1).
                o.choices = o.type.lowercased() == "bool"
                    ? [ModOptionChoice(id: "0", name: "Off"), ModOptionChoice(id: "1", name: "On")]
                    : [ModOptionChoice(id: o.defaultValue.isEmpty ? "0" : o.defaultValue, name: "Default")]
            }
            let selected = o.choices.contains { $0.id == o.defaultValue } ? o.defaultValue : (o.choices.first?.id ?? "0")
            options.append(ModOption(
                id: o.id,
                name: o.name.isEmpty ? o.id : o.name,
                description: o.description,
                choices: o.choices,
                selectedChoiceId: selected))
            option = nil
        }
    }
}
