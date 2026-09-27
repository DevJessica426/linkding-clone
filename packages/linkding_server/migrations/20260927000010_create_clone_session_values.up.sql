-- Values a page keeps in the session for the next request, such as a new
-- API token's key, shown once after it is created: what Django keeps in
-- its session data.
CREATE TABLE clone_session_value (
    session_key character varying(40) NOT NULL
        REFERENCES clone_session(session_key) ON DELETE CASCADE,
    name character varying(64) NOT NULL,
    value text NOT NULL,
    PRIMARY KEY (session_key, name)
);
