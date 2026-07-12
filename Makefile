.PHONY: go-fmt go-test go-build admin-install admin-check admin-build check

go-fmt:
	cd server && test -z "$$(gofmt -l .)"

go-test:
	cd server && go test ./...

go-build:
	cd server && go build ./cmd/bim-server

admin-install:
	cd admin-web && npm ci

admin-check:
	cd admin-web && npm run typecheck && npm run test

admin-build:
	cd admin-web && npm run build

check: go-fmt go-test go-build admin-check admin-build
