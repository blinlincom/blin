package migrations

import (
	"strings"
	"testing"
)

func TestEmbeddedMigrationsAreOrderedAndHaveUpSQL(t *testing.T) {
	items, err := load()
	if err != nil {
		t.Fatal(err)
	}
	if len(items) < 3 {
		t.Fatalf("migration count=%d", len(items))
	}
	for index, item := range items {
		if item.SQL == "" || item.Checksum == "" {
			t.Fatalf("invalid migration: %+v", item)
		}
		if index > 0 && items[index-1].Version >= item.Version {
			t.Fatalf("migrations are not strictly ordered")
		}
	}
}

func TestUniqueRemoteIdentifiersMustBeNullable(t *testing.T) {
	items, err := load()
	if err != nil {
		t.Fatal(err)
	}
	for _, item := range items {
		if item.Name == "000005_messaging.sql" && strings.Contains(item.SQL, "message_id VARCHAR(64) NOT NULL DEFAULT ''") {
			t.Fatal("queued messages would collide on an empty unique remote ID")
		}
	}
}

func TestSplitStatementsSkipsEmptySegments(t *testing.T) {
	statements := splitStatements("CREATE TABLE a(id INT);\n; INSERT INTO a VALUES(1);")
	if len(statements) != 2 {
		t.Fatalf("statements=%v", statements)
	}
}
