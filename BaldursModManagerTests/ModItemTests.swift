//
//  ModItemTests.swift
//  BaldursModManagerTests
//
//  Created by BPengu1n on 3/7/24.
//

import XCTest
@testable import BaldursModManager

final class ModItemTests: XCTestCase {
    let testItem = ModItem(order: 1,
                           directoryUrl: URL(fileURLWithPath: "/test/to/data"),
                           directoryPath: "/test/to/data",
                           directoryContents: ["test.pak", "info.json"],
                           pakFileString: "test.pak",
                           name: "Test Mod Name",
                           folder: "",
                           uuid: "00000000-1111-2222-3333-444444444444",
                           md5: "")

    func testAsOrderXML() {
        let orderXml = testItem.asOrderXML()
        XCTAssertEqual(orderXml, try XMLElement(xmlString: "<node id=\"Module\"><attribute id=\"UUID\" type=\"FixedString\" value=\"\(testItem.modUuid)\" /></node>"))
    }
    
    func testAsModuleShortDescXML() {
        let modShortDescXml = testItem.asModuleShortDescXML()
        
        XCTAssertEqual(modShortDescXml, try XMLElement(xmlString: """
<node id="ModuleShortDesc"><attribute id="Folder" type="LSString" value="" />
    <attribute id="Name" type="LSString" value="\(testItem.modName)" />
    <attribute id="UUID" type="FixedString" value="\(testItem.modUuid)" />
    <attribute id="Version64" type="int64" value="" />
</node>
"""))
    }

}
