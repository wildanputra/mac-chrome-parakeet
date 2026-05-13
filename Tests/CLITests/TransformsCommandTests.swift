import Foundation
import XCTest
@testable import CLI
@testable import MacParakeetCore

final class TransformsCommandTests: XCTestCase {

    // MARK: - Command parsing

    func testParsesListAsDefaultSubcommand() throws {
        // `macparakeet-cli transforms` (no subcommand) → ListSubcommand.
        let cmd = try TransformsCommand.parseAsRoot([])
        XCTAssertTrue(cmd is TransformsCommand.ListSubcommand,
                      "Bare `transforms` should default to ListSubcommand.")
    }

    func testParsesListWithJSON() throws {
        let cmd = try TransformsCommand.parseAsRoot(["list", "--json"])
        let list = try XCTUnwrap(cmd as? TransformsCommand.ListSubcommand)
        XCTAssertTrue(list.json)
    }

    func testParsesShowWithIdArgument() throws {
        let cmd = try TransformsCommand.parseAsRoot(["show", "Polish"])
        let show = try XCTUnwrap(cmd as? TransformsCommand.ShowSubcommand)
        XCTAssertEqual(show.idOrName, "Polish")
        XCTAssertFalse(show.json)
    }

    func testParsesRunWithFileInput() throws {
        let cmd = try TransformsCommand.parseAsRoot([
            "run", "Polish",
            "--provider", "anthropic", "--api-key", "test",
            "--input", "/tmp/in.txt",
        ])
        let run = try XCTUnwrap(cmd as? TransformsCommand.RunSubcommand)
        XCTAssertEqual(run.idOrName, "Polish")
        XCTAssertEqual(run.input, "/tmp/in.txt")
        XCTAssertFalse(run.stream)
        XCTAssertFalse(run.json)
    }

    func testRunRejectsJSONWithStream() throws {
        // `parseAsRoot` runs `validate()` itself; both --json and --stream
        // present should surface the mutual-exclusivity error at parse time.
        XCTAssertThrowsError(
            try TransformsCommand.parseAsRoot([
                "run", "Polish",
                "--provider", "anthropic", "--api-key", "test",
                "--input", "-",
                "--json", "--stream",
            ])
        ) { error in
            let message = String(describing: error)
            XCTAssertTrue(message.contains("--json with --stream"))
        }
    }

    func testParsesCreateRequiresPromptOrFromFile() throws {
        XCTAssertThrowsError(
            try TransformsCommand.parseAsRoot([
                "create",
                "--name", "Sharpen",
            ]),
            "Either --prompt or --from-file is required."
        ) { error in
            let message = String(describing: error)
            XCTAssertTrue(message.contains("--prompt or --from-file"))
        }
    }

    func testParsesCreateAcceptsShortcut() throws {
        let cmd = try TransformsCommand.parseAsRoot([
            "create",
            "--name", "Sharpen",
            "--prompt", "Make it crisp.",
            "--shortcut", "opt+5",
        ])
        let create = try XCTUnwrap(cmd as? TransformsCommand.CreateSubcommand)
        XCTAssertNoThrow(try create.validate())
        XCTAssertEqual(create.shortcut, "opt+5")
    }

    func testParsesCreateRejectsMutuallyExclusivePromptAndFromFile() throws {
        XCTAssertThrowsError(
            try TransformsCommand.parseAsRoot([
                "create",
                "--name", "Sharpen",
                "--prompt", "Inline",
                "--from-file", "/tmp/x.txt",
            ])
        ) { error in
            let message = String(describing: error)
            XCTAssertTrue(message.contains("mutually exclusive"))
        }
    }

    func testParsesDeleteSubcommand() throws {
        let cmd = try TransformsCommand.parseAsRoot(["delete", "Sharpen"])
        let del = try XCTUnwrap(cmd as? TransformsCommand.DeleteSubcommand)
        XCTAssertEqual(del.idOrName, "Sharpen")
    }

    // MARK: - JSON contract

    func testTransformDTOJSONUsesDocumentedSnakeCaseKeys() throws {
        let shortcut = KeyboardShortcut(
            modifiers: KeyboardShortcut.ModifierFlag.option.rawValue,
            keyCode: 0x12,
            keyLabel: "1"
        )
        let prompt = Prompt(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            name: "Sharpen",
            content: "Make it crisp.",
            category: .transform,
            isBuiltIn: true,
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 1),
            keyboardShortcut: shortcut.encodedString(),
            runningLabel: "Sharpening..."
        )

        let data = try cliJSONEncoder.encode(TransformDTO(prompt: prompt))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(object["running_label"] as? String, "Sharpening...")
        XCTAssertEqual(object["is_built_in"] as? Bool, true)
        XCTAssertNotNil(object["created_at"])
        XCTAssertNotNil(object["updated_at"])
        XCTAssertNil(object["runningLabel"])
        XCTAssertNil(object["isBuiltIn"])
        XCTAssertNil(object["createdAt"])
        XCTAssertNil(object["updatedAt"])
    }

    // MARK: - End-to-end: create + list + show + delete against a real DB

    func testCreateListShowDeleteRoundTrip() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("transforms-cli-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let dbPath = tmp.appendingPathComponent("test.db").path

        let create = try TransformsCommand.CreateSubcommand.parse([
            "--name", "Sharpen",
            "--prompt", "Make it crisp.",
            "--database", dbPath,
        ])
        try create.validate()
        try create.run()

        // After create, the DB should have the three built-ins + Sharpen.
        let db = try DatabaseManager(path: dbPath)
        let repo = PromptRepository(dbQueue: db.dbQueue)
        let all = try repo.fetchVisible(category: .transform)
        XCTAssertEqual(all.count, 4)
        let sharpen = try XCTUnwrap(all.first(where: { $0.name == "Sharpen" }))
        XCTAssertFalse(sharpen.isBuiltIn)
        XCTAssertNil(sharpen.shortcut)

        // Delete by name.
        let del = try TransformsCommand.DeleteSubcommand.parse([
            "Sharpen",
            "--database", dbPath,
        ])
        try del.run()

        let after = try repo.fetchVisible(category: .transform)
        XCTAssertEqual(after.count, 3)
        XCTAssertFalse(after.contains(where: { $0.name == "Sharpen" }))
    }

    func testCreateRejectsBareKeyShortcut() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("transforms-cli-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let dbPath = tmp.appendingPathComponent("test.db").path

        // First seed the built-ins so the DB exists.
        _ = try DatabaseManager(path: dbPath)

        let create = try TransformsCommand.CreateSubcommand.parse([
            "--name", "Bare",
            "--prompt", "Body",
            "--shortcut", "5",  // no modifier
            "--database", dbPath,
        ])
        try create.validate()
        XCTAssertThrowsError(try create.run()) { error in
            // The error should describe an unparseable or modifier-missing
            // shortcut — either branch is acceptable as the user's signal.
            let message = String(describing: error)
            XCTAssertTrue(
                message.contains("modifier") || message.contains("parse"),
                "Expected shortcut-validation error, got: \(message)"
            )
        }
    }

    func testCreateRejectsDuplicateShortcut() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("transforms-cli-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let dbPath = tmp.appendingPathComponent("test.db").path

        _ = try DatabaseManager(path: dbPath)

        let create = try TransformsCommand.CreateSubcommand.parse([
            "--name", "Duplicate Hotkey",
            "--prompt", "Body",
            "--shortcut", "opt+1",
            "--database", dbPath,
        ])
        try create.validate()
        XCTAssertThrowsError(try create.run()) { error in
            let message = String(describing: error)
            XCTAssertTrue(message.contains("already used"), "Expected duplicate-shortcut error, got: \(message)")
            XCTAssertTrue(message.contains("Polish"), "Expected duplicate owner name, got: \(message)")
        }
    }

    func testCreateRejectsMacOSDeadKeyShortcut() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("transforms-cli-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let dbPath = tmp.appendingPathComponent("test.db").path

        _ = try DatabaseManager(path: dbPath)

        let create = try TransformsCommand.CreateSubcommand.parse([
            "--name", "Accent Breaker",
            "--prompt", "Body",
            "--shortcut", "opt+e",
            "--database", dbPath,
        ])
        try create.validate()
        XCTAssertThrowsError(try create.run()) { error in
            let message = String(describing: error)
            XCTAssertTrue(message.contains("special character"), "Expected dead-key error, got: \(message)")
        }
    }

    func testCreateRejectsDuplicateName() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("transforms-cli-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let dbPath = tmp.appendingPathComponent("test.db").path

        // Polish is a built-in — try to create a custom Transform with the
        // same name.
        let create = try TransformsCommand.CreateSubcommand.parse([
            "--name", "Polish",
            "--prompt", "Body",
            "--database", dbPath,
        ])
        try create.validate()
        XCTAssertThrowsError(try create.run()) { error in
            let message = String(describing: error)
            XCTAssertTrue(message.contains("already exists"), "Expected duplicate-name error, got: \(message)")
        }
    }

    func testDeleteRefusesBuiltIn() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("transforms-cli-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let dbPath = tmp.appendingPathComponent("test.db").path
        _ = try DatabaseManager(path: dbPath)

        let del = try TransformsCommand.DeleteSubcommand.parse([
            "Polish",
            "--database", dbPath,
        ])
        XCTAssertThrowsError(try del.run()) { error in
            let message = String(describing: error)
            XCTAssertTrue(message.contains("built-in"), "Expected built-in-protection error, got: \(message)")
        }
    }
}
