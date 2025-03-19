CREATE TABLE posts (
    Id SERIAL PRIMARY KEY,
    PostTypeId SMALLINT CHECK (PostTypeId BETWEEN 1 AND 8),  -- Enforcing range instead of ENUM
    AcceptedAnswerId INTEGER,
    CreationDate TIMESTAMP(3) WITH TIME ZONE NOT NULL,
    Score INTEGER,
    ViewCount INTEGER,
    Body TEXT,
    OwnerUserId INTEGER NOT NULL,
    OwnerDisplayName TEXT,
    LastEditorUserId INTEGER,
    LastEditorDisplayName TEXT,
    LastEditDate TIMESTAMP(3) WITH TIME ZONE,
    LastActivityDate TIMESTAMP(3) WITH TIME ZONE,
    Title TEXT,
    Tags TEXT,
    AnswerCount SMALLINT DEFAULT 0,
    CommentCount SMALLINT DEFAULT 0,
    FavoriteCount SMALLINT DEFAULT 0,
    ContentLicense TEXT,
    ParentId TEXT,
    CommunityOwnedDate TIMESTAMP(3) WITH TIME ZONE,
    ClosedDate TIMESTAMP(3) WITH TIME ZONE
);

CREATE TABLE votes (
    Id SERIAL PRIMARY KEY,
    PostId INTEGER ,
    VoteTypeId SMALLINT NOT NULL,
    CreationDate TIMESTAMP(3) WITH TIME ZONE NOT NULL,
    UserId INTEGER,
    BountyAmount SMALLINT DEFAULT 0
);

CREATE TABLE comments (
    Id SERIAL PRIMARY KEY,
    PostId INTEGER ,
    Score SMALLINT DEFAULT 0,
    Text TEXT NOT NULL,
    CreationDate TIMESTAMP(3) WITH TIME ZONE NOT NULL,
    UserId INTEGER,
    UserDisplayName TEXT
);

CREATE TABLE users (
    Id SERIAL PRIMARY KEY,
    Reputation TEXT,
    CreationDate TIMESTAMP(3) WITH TIME ZONE NOT NULL,
    DisplayName TEXT NOT NULL,
    LastAccessDate TIMESTAMP(3) WITH TIME ZONE,
    AboutMe TEXT,
    Views INTEGER DEFAULT 0,
    UpVotes INTEGER DEFAULT 0,
    DownVotes INTEGER DEFAULT 0,
    WebsiteUrl TEXT,
    Location TEXT,
    AccountId INTEGER
);
