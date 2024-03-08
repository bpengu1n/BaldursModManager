//
//  XMLBuilder.swift
//  BaldursModManager
//
//  Created by Justin Bush on 1/8/24.
//

import Foundation

/// A class that builds an XML string from given XML attributes and a list of mod items.
class XMLBuilder {
  /// The parsed XML attributes used for building the XML string.
  var xmlAttributes: XMLAttributes
  /// The list of mod items to be included in the XML string.
  var modItems: [ModItem]
  /// Initializes a new XMLBuilder with given XML attributes and mod items.
  ///
  /// - Parameters:
  ///   - xmlAttributes: The XML attributes to be included in the XML string.
  ///   - modItems: The list of mod items to be included in the XML string.
  init(xmlAttributes: XMLAttributes, modItems: [ModItem]) {
    self.xmlAttributes = xmlAttributes
    self.modItems = modItems
  }
  /// Builds and returns an XML string.
  ///
  /// - Returns: A string representing the XML content.
  func buildXMLString() -> String {
      let xmlDoc = try! XMLDocument(xmlString: """
<?xml version="1.0" encoding="UTF-8"?>
<save>
  <region id="ModuleSettings">
    <node id="root">
      <children>
        <node id="ModOrder">
          <children />
        </node>
        <node id="Mods">
          <children />
        </node>
      </children>
    </node>
  </region>
</save>
""")
      
      // Build and add version element
      let xmlVer = XMLElement(name: "version")
      xmlVer.setAttributesWith(["major": xmlAttributes.version.majorString,
                                "minor": xmlAttributes.version.minorString,
                                "revision": xmlAttributes.version.revisionString,
                                "build": xmlAttributes.version.buildString])
      
      xmlDoc.rootElement()?.insertChild(xmlVer, at: 0)
      
      // Add mod XML elements into appropriate nodes
      for mod in modItems {
          for node in xmlDoc.rootElement()?.elements(forName: "node") ?? [] {
              switch node.attribute(forName: "id")?.stringValue {
              case "ModOrder":
                  node.addChild(mod.asOrderXML())
              case "Mods":
                  node.addChild(mod.asModuleShortDescXML())
              default:
                  continue
              }
          }
      }
    
      return xmlDoc.xmlString(options: XMLNode.Options.nodeCompactEmptyElement)
  }

  /// Builds the GustavDev header UUID string for the XML.
  ///
  /// - Parameter moduleShortDesc: The module short description to be used.
  /// - Returns: A string representing the GustavDev header UUID XML element.
  private func buildGustavDevHeaderUUIDString(moduleShortDesc: XMLAttributes.ModuleShortDesc) -> String {
    "            <node id=\"Module\">\n              <attribute id=\"UUID\" type=\"FixedString\" value=\"\(moduleShortDesc.uuid.valueString)\" />\n            </node>"
  }
}

extension String {
  /// A computed property that attempts to convert the string to an integer. If the string is a valid integer or floating-point number, it is converted to an integer and returned as a string. Otherwise, it returns an empty string.
  var forceStringValueAsInt: String {
    if let intValue = Int(self) {
      return String(intValue)
    } else if let floatValue = Float(self) {
      return String(Int(floatValue))
    } else {
      return ""
    }
  }
}
