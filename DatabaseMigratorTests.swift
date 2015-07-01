//
//  DatabaseMigratorTests.swift
//  GRDB
//
//  Created by Gwendal Roué on 01/07/2015.
//  Copyright © 2015 Gwendal Roué. All rights reserved.
//

import XCTest
import GRDB

class DatabaseMigratorTests: GRDBTests {
    var databasePath: String!
    var dbQueue: DatabaseQueue!
    
    override func setUp() {
        super.setUp()
        
        self.databasePath = "/tmp/GRDB.sqlite"
        do { try NSFileManager.defaultManager().removeItemAtPath(databasePath) } catch { }
        let configuration = DatabaseConfiguration(verbose: true)
        self.dbQueue = try! DatabaseQueue(path: databasePath, configuration: configuration)
    }
    
    override func tearDown() {
        super.tearDown()
        
        self.dbQueue = nil
        try! NSFileManager.defaultManager().removeItemAtPath(databasePath)
    }

    func testMigrator() {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("createPersons") { db in
            try db.execute("CREATE TABLE persons (id INTEGER PRIMARY KEY, name TEXT)")
        }
        migrator.registerMigration("createPets") { db in
            try db.execute("CREATE TABLE pets (id INTEGER PRIMARY KEY, masterID INTEGER NOT NULL REFERENCES persons(id), name TEXT)")
        }
        
        assertNoError {
            try migrator.migrate(dbQueue)
            try dbQueue.inDatabase { db -> Void in
                XCTAssertTrue(db.tableExists("persons"))
                XCTAssertTrue(db.tableExists("pets"))
            }
        }

        migrator.registerMigration("destroyPersons") { db in
            try db.execute("DROP TABLE pets")
        }

        assertNoError {
            try migrator.migrate(dbQueue)
            try dbQueue.inDatabase { db -> Void in
                XCTAssertTrue(db.tableExists("persons"))
                XCTAssertFalse(db.tableExists("pets"))
            }
        }
    }
    
    func testMigrationFailureTriggersRollback() {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("createPersons") { db in
            try db.execute("CREATE TABLE persons (name TEXT)")
            try db.execute("INSERT INTO persons (name) VALUES ('Arthur')")
        }
        migrator.registerMigration("destroyPersonErroneous") { db in
            try db.execute("DELETE FROM persons")
            try db.execute("I like cookies.")
        }
        
        do {
            try migrator.migrate(dbQueue)
        } catch {
            // The first migration should be committed.
            // The second migration should be rollbacked.
            let names = try! dbQueue.inDatabase { db in
                try db.fetchValues("SELECT * FROM persons", type: String.self).map { $0! }
            }
            XCTAssertEqual(names, ["Arthur"])
        }
    }
}
