import GRDB

enum Schema {
    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            try db.execute(sql: v1)
            try db.create(virtualTable: "segmentSearch", using: FTS5()) { table in
                table.synchronize(withTable: "segment")
                table.tokenizer = .unicode61(diacritics: .remove)
                table.column("text")
            }
        }
        migrator.registerMigration("v2") { db in
            try db.execute(sql: """
                ALTER TABLE conversation ADD COLUMN captureSource TEXT;
                ALTER TABLE conversation ADD COLUMN lastError TEXT;
                """)
        }
        migrator.registerMigration("v3") { db in
            try db.execute(sql: """
                CREATE TABLE setting (
                  key TEXT PRIMARY KEY NOT NULL,
                  value TEXT NOT NULL
                );
                """)
        }
        return migrator
    }

    private static let v1 = """
    CREATE TABLE conversation (
      id TEXT PRIMARY KEY NOT NULL,
      title TEXT NOT NULL,
      type TEXT NOT NULL,
      state TEXT NOT NULL,
      startedAt DATETIME NOT NULL,
      durationSeconds DOUBLE,
      calendarEventId TEXT,
      importedAt DATETIME,
      createdAt DATETIME NOT NULL,
      updatedAt DATETIME NOT NULL
    );
    CREATE INDEX conversation_startedAt ON conversation(startedAt);

    CREATE TABLE person (
      id TEXT PRIMARY KEY NOT NULL,
      name TEXT NOT NULL,
      organisation TEXT,
      role TEXT,
      notes TEXT
    );

    CREATE TABLE participant (
      id TEXT PRIMARY KEY NOT NULL,
      conversationId TEXT NOT NULL REFERENCES conversation(id) ON DELETE CASCADE,
      personId TEXT REFERENCES person(id) ON DELETE SET NULL,
      name TEXT NOT NULL,
      isUser BOOLEAN NOT NULL DEFAULT 0,
      sourceLabel TEXT
    );
    CREATE INDEX participant_conversation ON participant(conversationId);
    CREATE INDEX participant_person ON participant(personId);

    CREATE TABLE track (
      id TEXT PRIMARY KEY NOT NULL,
      conversationId TEXT NOT NULL REFERENCES conversation(id) ON DELETE CASCADE,
      kind TEXT NOT NULL,
      relativePath TEXT NOT NULL
    );
    CREATE INDEX track_conversation ON track(conversationId);

    CREATE TABLE transcriptVersion (
      id TEXT PRIMARY KEY NOT NULL,
      conversationId TEXT NOT NULL REFERENCES conversation(id) ON DELETE CASCADE,
      engine TEXT NOT NULL,
      modelVersion TEXT,
      settingsJSON TEXT,
      languageHint TEXT,
      isCurrent BOOLEAN NOT NULL,
      createdAt DATETIME NOT NULL
    );
    CREATE UNIQUE INDEX transcriptVersion_current
      ON transcriptVersion(conversationId) WHERE isCurrent = 1;

    CREATE TABLE segment (
      id TEXT PRIMARY KEY NOT NULL,
      transcriptVersionId TEXT NOT NULL REFERENCES transcriptVersion(id) ON DELETE CASCADE,
      participantId TEXT REFERENCES participant(id) ON DELETE SET NULL,
      startMs INTEGER NOT NULL,
      endMs INTEGER NOT NULL,
      text TEXT NOT NULL,
      confidence DOUBLE,
      isEdited BOOLEAN NOT NULL DEFAULT 0
    );
    CREATE INDEX segment_version_start ON segment(transcriptVersionId, startMs);

    CREATE TABLE outcome (
      id TEXT PRIMARY KEY NOT NULL,
      conversationId TEXT NOT NULL REFERENCES conversation(id) ON DELETE CASCADE,
      kind TEXT NOT NULL,
      text TEXT NOT NULL,
      ownerParticipantId TEXT REFERENCES participant(id) ON DELETE SET NULL,
      due DATETIME,
      status TEXT NOT NULL,
      edited BOOLEAN NOT NULL DEFAULT 0,
      source TEXT NOT NULL,
      evidenceSegmentIds TEXT NOT NULL DEFAULT '[]',
      evidenceStartMs INTEGER,
      evidenceEndMs INTEGER,
      createdAt DATETIME NOT NULL
    );
    CREATE INDEX outcome_conversation ON outcome(conversationId);

    CREATE TABLE recordExport (
      conversationId TEXT NOT NULL REFERENCES conversation(id) ON DELETE CASCADE,
      version INTEGER NOT NULL,
      status TEXT NOT NULL,
      approvedAt DATETIME,
      path TEXT NOT NULL,
      PRIMARY KEY (conversationId, version)
    );

    CREATE TABLE consumerCursor (
      consumerName TEXT NOT NULL,
      conversationId TEXT NOT NULL REFERENCES conversation(id) ON DELETE CASCADE,
      recordVersion INTEGER NOT NULL,
      processedAt DATETIME NOT NULL,
      PRIMARY KEY (consumerName, conversationId, recordVersion)
    );
    """
}
