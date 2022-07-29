.PHONY: build proto
#!/usr/bin/make -f

PACKAGES_SIMTEST=$(shell go list ./... | grep '/simulation')
VERSION := $(shell echo $(shell git describe --tags) | sed 's/^v//')
COMMIT := $(shell git log -1 --format='%H')
LEDGER_ENABLED ?= true
SDK_PACK := $(shell go list -m github.com/cosmos/cosmos-sdk | sed  's/ /\@/g')
TM_VERSION := $(shell go list -m github.com/tendermint/tendermint | sed 's:.* ::')
BUILDDIR ?= $(CURDIR)/build
DOCKER := $(shell which docker)
POST_ID ?= 1
STAKE_DENOM ?= ustarx

export GO111MODULE = on

# process build tags
build_tags = netgo
ifeq ($(LEDGER_ENABLED),true)
  ifeq ($(OS),Windows_NT)
    GCCEXE = $(shell where gcc.exe 2> NUL)
    ifeq ($(GCCEXE),)
      $(error gcc.exe not installed for ledger support, please install or set LEDGER_ENABLED=false)
    else
      build_tags += ledger
    endif
  else
    UNAME_S = $(shell uname -s)
    ifeq ($(UNAME_S),OpenBSD)
      $(warning OpenBSD detected, disabling ledger support (https://github.com/cosmos/cosmos-sdk/issues/1988))
    else
      GCC = $(shell command -v gcc 2> /dev/null)
      ifeq ($(GCC),)
        $(error gcc not installed for ledger support, please install or set LEDGER_ENABLED=false)
      else
        build_tags += ledger
      endif
    endif
  endif
endif

ifeq (cleveldb,$(findstring cleveldb,$(STARGAZE_BUILD_OPTIONS)))
  build_tags += gcc
else ifeq (rocksdb,$(findstring rocksdb,$(STARGAZE_BUILD_OPTIONS)))
  build_tags += gcc
endif
build_tags += $(BUILD_TAGS)
build_tags := $(strip $(build_tags))

whitespace :=
whitespace += $(whitespace)
comma := ,
build_tags_comma_sep := $(subst $(whitespace),$(comma),$(build_tags))

# process linker flags

ldflags = -X github.com/cosmos/cosmos-sdk/version.Name=stargaze \
		  -X github.com/cosmos/cosmos-sdk/version.AppName=starsd \
		  -X github.com/cosmos/cosmos-sdk/version.Version=$(VERSION) \
		  -X github.com/cosmos/cosmos-sdk/version.Commit=$(COMMIT) \
		  -X "github.com/cosmos/cosmos-sdk/version.BuildTags=$(build_tags_comma_sep)" \
		  -X github.com/tendermint/tendermint/version.TMCoreSemVer=$(TM_VERSION)

ifeq (cleveldb,$(findstring cleveldb,$(STARGAZE_BUILD_OPTIONS)))
  ldflags += -X github.com/cosmos/cosmos-sdk/types.DBBackend=cleveldb
else ifeq (rocksdb,$(findstring rocksdb,$(STARGAZE_BUILD_OPTIONS)))
  ldflags += -X github.com/cosmos/cosmos-sdk/types.DBBackend=rocksdb
endif
ifeq (,$(findstring nostrip,$(STARGAZE_BUILD_OPTIONS)))
  ldflags += -w -s
endif
ifeq ($(LINK_STATICALLY),true)
	ldflags += -linkmode=external -extldflags "-Wl,-z,muldefs -static"
endif
ldflags += $(LDFLAGS)
ldflags := $(strip $(ldflags))

BUILD_FLAGS := -tags "$(build_tags)" -ldflags '$(ldflags)'
# check for nostrip option
ifeq (,$(findstring nostrip,$(STARGAZE_BUILD_OPTIONS)))
  BUILD_FLAGS += -trimpath
endif


all: install

install:
	go install -mod=readonly $(BUILD_FLAGS) ./cmd/starsd

build:
	go build $(BUILD_FLAGS) -o bin/starsd ./cmd/starsd

go.sum: go.mod
	@echo "--> Ensure dependencies have not been modified"
	GO111MODULE=on go mod verify

# look into .golangci.yml for enabling / disabling linters
lint:
	@echo "--> Running linter"
	@golangci-lint run --tests=false --skip-dirs="simapp"
	@go mod verify


build-linux: 
	CGO_ENABLED=0 GOARCH=amd64 GOOS=linux go build $(BUILD_FLAGS) -o bin/starsd github.com/public-awesome/stargaze/cmd/starsd

build-docker:
	docker build -t publicawesome/stargaze:local-dev .

docker-test: build-linux
	docker build -f docker/Dockerfile.test -t rocketprotocol/stargaze-relayer-test:latest .


test:
	go test -v -race github.com/public-awesome/stargaze/v6/x/...

.PHONY: test build-linux docker-test lint build install

###############################################################################
###                                Protobuf                                 ###
###############################################################################
proto-gen:
	starport generate proto-go
	go mod tidy

ci-sign: 
	drone sign public-awesome/stargaze --save

.PHONY: build-readiness-checker

build-readiness-checker:
	CGO_ENABLED=0 GOARCH=amd64 GOOS=linux go build -o bin/readiness-checker github.com/public-awesome/stargaze/testutil/readiness-checker
	docker build -t publicawesome/stargaze-readiness-checker -f docker/Dockerfile.readiness .
