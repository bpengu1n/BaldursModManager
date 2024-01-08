//
//  ContentView.swift
//  BaldursModManager
//
//  Created by Justin Bush on 1/5/24.
//

import SwiftUI
import SwiftData

let UIDELAY: CGFloat = 0.01

struct ContentView: View {
  @Environment(\.modelContext) private var modelContext
  @Query(sort: \ModItem.order, order: .forward) private var modItems: [ModItem]
  @State private var selectedModItemOrderNumber: Int?
  @State private var showAlertForModDeletion = false
  @State private var showPermissionsView = false
  // Properties to store deletion details
  @State private var offsetsToDelete: IndexSet?
  @State private var modItemToDelete: ModItem?
  @State private var isFileTransferInProgress = false
  @State private var fileTransferProgress: Double = 0
  
  init() {
    FileUtility.createUserModsFolderIfNeeded()
    
    //FileUtility.moveFilesToSubfolders()
    //FileUtility.moveSwiftDataStoreFiles()
    /*
     if let contents = FileUtility.readFileFromDocumentsFolder(documentsFilePath: Constants.defaultModSettingsFileFromDocumentsRelativePath) {
     Debug.log(contents)
     } else {
     Debug.log("Unable to read file.")
     }
     */
  }
  
  private let modItemManager = ModItemManager.shared
  
  var body: some View {
    NavigationSplitView {
      List(selection: $selectedModItemOrderNumber) {
        ForEach(modItems) { item in
          NavigationLink {
            ModItemDetailView(item: item, deleteAction: deleteItem)
          } label: {
            HStack {
              Image(systemName: item.isEnabled ? "checkmark.circle.fill" : "circle")
              Text(item.modName)
            }
          }
          .tag(item.order)
        }
        .onDelete(perform: deleteItems)
        .onMove(perform: moveItems)
      }
      .navigationSplitViewColumnWidth(min: 200, ideal: 350)
      .toolbar {
        ToolbarItem {
          Button(action: addItem) {
            Label("Add Item", systemImage: "plus")
          }
        }
        ToolbarItemGroup(placement: .navigation) {
          if Debug.isActive {
            Button(action: {
              openUserModsFolder()
            }) {
              Label("Open UserMods", systemImage: "folder")
            }
            Button(action: {
              // preview modsettings.lsx
            }) {
              Label("Preview modsettings.lsx", systemImage: "command")
            }
          }
        }
        ToolbarItem(placement: .principal) {
          if Debug.fileTransferUI || isFileTransferInProgress {
            ProgressView(value: fileTransferProgress, total: 1.0)
              .frame(width: 100)
              .opacity(fileTransferProgress > 0 ? 1 : 0)  // Fade out effect
          }
          
        }
      }
    } detail: {
      WelcomeDetailView()
    }
    .alert(isPresented: $showAlertForModDeletion) {
      Alert(
        title: Text("Remove Mod"),
        message: Text("Are you sure you want to remove this mod? It will be moved to the trash."),
        primaryButton: .destructive(Text("Move to Trash")) {
          deleteModItems(at: offsetsToDelete, itemToDelete: modItemToDelete)
        },
        secondaryButton: .cancel()
      )
    }
    .sheet(isPresented: $showPermissionsView) {
      PermissionsView(onDismiss: {
        self.showPermissionsView = false
      })
    }
    .onAppear {
      if Debug.permissionsView {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
          self.showPermissionsView = true
        }
      }
    }
  }
  
  private func openUserModsFolder() {
    if let appSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
      let userModsURL = appSupportURL.appendingPathComponent(Constants.ApplicationSupportFolderName)
      NSWorkspace.shared.open(userModsURL)
    }
  }
  
  private func addItem() {
    selectFile()
  }
  
  private func moveItems(from source: IndexSet, to destination: Int) {
    var reorderedItems = modItems
    reorderedItems.move(fromOffsets: source, toOffset: destination)
    // Update the 'order' of each 'ModItem' to its new index
    for (index, item) in reorderedItems.enumerated() {
      item.order = index
    }
    // Save the context
    do {
      try modelContext.save()
    } catch {
      Debug.log("Error saving context: \(error)")
    }
  }
  
  private func selectFile() {
    let openPanel = NSOpenPanel()
    openPanel.canChooseFiles = false
    openPanel.canChooseDirectories = true
    openPanel.allowsMultipleSelection = false
    openPanel.begin { response in
      if response == .OK, let selectedDirectory = openPanel.url {
        Debug.log("Selected directory: \(selectedDirectory.path)")
        parseImportedModFolder(at: selectedDirectory)
      }
    }
  }
  
  private func parseImportedModFolder(at url: URL) {
    if let contents = getDirectoryContents(at: url) {
      // Find info.json file
      if let infoJsonUrl = contents.first(where: { $0.caseInsensitiveCompare("info.json") == .orderedSame }) {
        let fullPath = url.appendingPathComponent(infoJsonUrl).path
        
        if let infoDict = parseJsonToDict(atPath: fullPath) {
          Debug.log("JSON contents: \n\(infoDict)")
          createNewModItemFrom(infoDict: infoDict, infoJsonPath: fullPath, directoryContents: contents)
        } else {
          Debug.log("Error parsing JSON content. Bring up manual entry screen.")
        }
      } else {
        Debug.log("Error: Unable to locate info.json file of imported mod")
      }
    }
  }
  
  private func createNewModItemFrom(infoDict: [String:String], infoJsonPath: String, directoryContents: [String]) {
    let directoryURL = URL(fileURLWithPath: infoJsonPath).deletingLastPathComponent()
    
    if let pakFileString = getPakFileString(fromDirectoryContents: directoryContents) {
      // Required
      var name, folder, uuid, md5: String?
      for (key, value) in infoDict {
        switch key.lowercased() {
        case "name": name = value
        case "folder": folder = value
        case "uuid": uuid = value
        case "md5": md5 = value
        default: break
        }
      }
      
      if let name = name, let folder = folder, let uuid = uuid, let md5 = md5 {
        let newOrderNumber = nextOrderValue()
        withAnimation {
          let newModItem = ModItem(order: newOrderNumber, directoryUrl: directoryURL, directoryPath: directoryURL.path, directoryContents: directoryContents, pakFileString: pakFileString, name: name, folder: folder, uuid: uuid, md5: md5)
          // Check for optional keys
          for (key, value) in infoDict {
            switch key.lowercased() {
            case "author": newModItem.modAuthor = value
            case "description": newModItem.modDescription = value
            case "created": newModItem.modCreatedDate = value
            case "group": newModItem.modGroup = value
            case "version": newModItem.modVersion = value
            default: break
            }
          }
          
          addNewModItem(newModItem, orderNumber: newOrderNumber, fromDirectoryUrl: directoryURL)
        }
      }
      
    } else {
      Debug.log("Error: Unable to resolve pakFileString from \(directoryContents)")
    }
  }
  
  private func addNewModItem(_ modItem: ModItem, orderNumber: Int, fromDirectoryUrl directoryUrl: URL) {
    modelContext.insert(modItem)
    
    DispatchQueue.main.asyncAfter(deadline: .now() + UIDELAY) {
      selectedModItemOrderNumber = orderNumber
    }
    
    importModFolderAndUpdateModItemDirectoryPath(at: directoryUrl, modItem: modItem, progress: $fileTransferProgress)
  }
  
  private func getDirectoryContents(at url: URL) -> [String]? {
    do {
      let fileManager = FileManager.default
      let contents = try fileManager.contentsOfDirectory(atPath: url.path)
      Debug.log("Directory contents: \(contents)")
      return contents
    } catch {
      Debug.log("Error listing directory contents: \(error)")
    }
    return nil
  }
  
  private func getPakFileString(fromDirectoryContents directoryContents: [String]) -> String? {
    for file in directoryContents {
      if file.lowercased().hasSuffix(".pak") {
        return file
      }
    }
    return nil
  }
  
  func parseJsonToDict(atPath filePath: String) -> [String: String]? {
    if let data = try? Data(contentsOf: URL(fileURLWithPath: filePath)) {
      do {
        let jsonObject = try JSONSerialization.jsonObject(with: data, options: [])
        if let dict = jsonObject as? [String: Any],
           let mods = dict["Mods"] as? [[String: Any]],
           let firstMod = mods.first {
          
          var result: [String: String] = [:]
          
          // Extract key-value pairs from the "Mods" dictionary
          for (key, value) in firstMod {
            if let stringValue = value as? String {
              result[key] = stringValue
            }
          }
          
          // Extract MD5 from the top-level dictionary
          if let md5 = dict["MD5"] as? String {
            result["MD5"] = md5
          }
          
          return result
        }
      } catch {
        Debug.log("Error parsing JSON: \(error.localizedDescription)")
      }
    }
    
    return nil
  }
  
  // Triggered by UI delete button
  private func deleteItem(item: ModItem) {
    modItemToDelete = item
    offsetsToDelete = nil
    showAlertForModDeletion = true
  }
  
  // Triggered by menu bar item Edit > Delete
  private func deleteItems(offsets: IndexSet) {
    offsetsToDelete = offsets
    modItemToDelete = nil
    showAlertForModDeletion = true
  }
  
  private func deleteModItems(at offsets: IndexSet? = nil, itemToDelete: ModItem? = nil) {
    var indexToSelect: Int?
    
    withAnimation {
      if let offsets = offsets {
        let sortedOffsets = offsets.sorted()
        var adjustment = 0
        
        for index in sortedOffsets {
          let adjustedIndex = index - adjustment
          if adjustedIndex < modItems.count {
            let modItem = modItems[adjustedIndex]
            indexToSelect = adjustedIndex
            modelContext.delete(modItems[adjustedIndex])
            FileUtility.moveModItemToTrash(modItem)
            adjustment += 1
          }
        }
      } else if let item = itemToDelete, let index = modItems.firstIndex(of: item) {
        indexToSelect = index
        modelContext.delete(modItems[index])
        FileUtility.moveModItemToTrash(item)
      }
      try? modelContext.save() // Save the context after deletion
      updateOrderOfModItems()  // Update the order of remaining items
      
      offsetsToDelete = nil
      modItemToDelete = nil
      
      if let index = indexToSelect {
        DispatchQueue.main.asyncAfter(deadline: .now() + UIDELAY) {
          selectedModItemOrderNumber = index - 1
        }
      }
    }
  }
  
  private func updateOrderOfModItems() {
    var updatedOrder = 0
    for item in modItems.sorted(by: { $0.order < $1.order }) {
      item.order = updatedOrder
      updatedOrder += 1
    }
    // Save the context after reordering
    do {
      try modelContext.save()
    } catch {
      Debug.log("Error saving context after reordering: \(error)")
    }
  }
  
  private func nextOrderValue() -> Int {
    if modItems.isEmpty {
      return 0  // If there are no items, start with 0
    } else {
      // Otherwise, find the maximum order and add 1
      return (modItems.max(by: { $0.order < $1.order })?.order ?? 0) + 1
    }
  }
  
  private func importModFolderAndUpdateModItemDirectoryPath(
    at originalPath: URL, modItem: ModItem, progress: Binding<Double>
  ) {
    // Mark transfer as started
    DispatchQueue.main.async {
      self.isFileTransferInProgress = true
    }
    
    importModFolderAndReturnNewDirectoryPath(
      at: originalPath,
      progressHandler: { progressValue in
        DispatchQueue.main.async {
          progress.wrappedValue = progressValue.fractionCompleted
        }
      },
      completionHandler: { directoryPath in
        DispatchQueue.main.async {
          if let directoryPath = directoryPath {
            modItem.directoryUrl = URL(fileURLWithPath: directoryPath)
            modItem.directoryPath = directoryPath
          } else {
            Debug.log("Error: Unable to resolve directoryPath from importModFolderAndReturnNewDirectoryPath(at: \(originalPath))")
          }
          // Mark transfer as finished
          self.isFileTransferInProgress = false
          SoundUtility.play(systemSound: .mount)
          
          // Fade out the ProgressView after 1.5 seconds if fileTransferUI is not active
          if !Debug.fileTransferUI {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
              self.fileTransferProgress = 0
            }
          }
        }
      }
    )
  }
  
  
  private func importModFolderAndReturnNewDirectoryPath(at originalPath: URL, progressHandler: @escaping (Progress) -> Void, completionHandler: @escaping (String?) -> Void) {
    DispatchQueue.global(qos: .userInitiated).async {
      let fileManager = FileManager.default
      guard let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
        completionHandler(nil)
        return
      }
      
      //let destinationURL = appSupportURL.appendingPathComponent("UserMods").appendingPathComponent(originalPath.lastPathComponent)
      let destinationURL = appSupportURL.appendingPathComponent(Constants.ApplicationSupportFolderName).appendingPathComponent("UserMods").appendingPathComponent(originalPath.lastPathComponent)
      let progress = Progress(totalUnitCount: 1)  // You might want to find a better way to estimate progress
      
      do {
        if UserSettings.shared.makeCopyOfModFolderOnImport {
          progressHandler(progress)
          try fileManager.copyItem(at: originalPath, to: destinationURL)
        } else {
          progressHandler(progress)
          try fileManager.moveItem(at: originalPath, to: destinationURL)
        }
        
        progress.completedUnitCount = 1
        DispatchQueue.main.async {
          completionHandler(destinationURL.path)
        }
      } catch {
        DispatchQueue.main.async {
          Debug.log("Error handling mod folder: \(error)")
          completionHandler(nil)
        }
      }
    }
  }
  
}

#Preview {
  ContentView()
    .modelContainer(for: ModItem.self, inMemory: true)
}

struct ModItemDetailView: View {
  @Environment(\.modelContext) private var modelContext
  let item: ModItem
  let deleteAction: (ModItem) -> Void
  
  private let modItemManager = ModItemManager.shared
  
  var body: some View {
    VStack {
      HStack {
        Spacer()
        Button(action: { toggleEnabled() }) {
          Label(item.isEnabled ? "Enabled" : "Disabled", systemImage: item.isEnabled ? "checkmark.circle.fill" : "circle")
            .frame(width: 80)
            .padding(6)
        }
        .buttonStyle(.bordered)
        .tint(item.isEnabled ? .green : .gray)
      }
      
      ScrollView {
        HStack {
          VStack(alignment: .leading) {
            Text(item.modName).font(.title)
              .padding(.bottom, 2)
            
            HStack {
              if let author = item.modAuthor {
                Text("by \(author)").font(.footnote)
              }
              if let version = item.modVersion {
                Text("(v\(version))").monoStyle()
              }
            }
            
            if let summary = item.modDescription {
              Divider()
                .padding(.vertical, 10)
              
              Text(summary)
            }
            
            Divider()
              .padding(.vertical, 10)
            
            HStack {
              Text("Load Order Number: \(item.order)").monoStyle()
              if item.order == 0 {
                Text("(top)").monoStyle()
              }
            }
            .padding(.bottom, 10)
            
            if let folder = item.modFolder {
              Text("Folder: \(folder)").monoStyle()
                .padding(.bottom, 10)
            }
            
            Text("UUID: \(item.modUuid)").monoStyle()
            
            if let md5 = item.modMd5 {
              Text("MD5:  \(md5)").monoStyle()
            }
            
            if Debug.isActive {
              Divider()
                .padding(.vertical, 10)
              
              Text("Debug Info").font(.headline)
                .padding(.bottom, 10)
              
              Text("PAK File String: \(item.pakFileString)").monoStyle()
                .padding(.bottom, 5)
              
              Text("Directory Path: \(item.directoryPath)").monoStyle()
                .padding(.bottom, 5)
              
              Text("Directory URL: \(item.directoryUrl.absoluteString)").monoStyle()
                .padding(.bottom, 5)
              
              Text("Directory Contents:\n  \(item.directoryContents[0])\n  \(item.directoryContents[1])").monoStyle()
                .padding(.bottom, 5)
            }
            
            Spacer()
            
          }
          .padding()
          Spacer()
        }
        Spacer()
      }
      
      HStack {
        if Debug.isActive {
          Text(item.isInstalledInModFolder ? "Installed" : "Not Installed")
            .monoStyle()
        }
        Spacer()
        Button(action: { deleteAction(item) }) {
          Label("Remove", systemImage: "trash.circle.fill")
            .padding(6)
        }
        .buttonStyle(.bordered)
        .tint(.red)
        
      }
    }
    .padding()
    
  }
  
  private func toggleEnabled() {
    Debug.log("toggleEnabled()")
    withAnimation {
      item.isEnabled.toggle()
      try? modelContext.save()
    }
    modItemManager.toggleModItem(item)
  }
}

struct WelcomeDetailView: View {
  var body: some View {
    Text("Welcome to BaldursModManager!")
  }
}
