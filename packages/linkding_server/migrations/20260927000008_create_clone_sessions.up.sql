-- The one table linkding does not have. Django keeps signed session data in
-- django_session; the clone keeps its own sessions here, so both can run
-- against the same database without reading each other's cookies.
CREATE TABLE clone_session (
    session_key character varying(40) PRIMARY KEY,
    user_id integer NOT NULL REFERENCES auth_user(id) ON DELETE CASCADE,
    expire_date timestamp with time zone NOT NULL
);
CREATE INDEX clone_session_user_id ON clone_session USING btree (user_id);
CREATE INDEX clone_session_expire_date ON clone_session USING btree (expire_date);
