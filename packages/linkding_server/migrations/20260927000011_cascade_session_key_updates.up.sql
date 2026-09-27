-- Django gives a session a new key after a password change and keeps its
-- data; the clone's messages and session values follow the key.
ALTER TABLE clone_message
    DROP CONSTRAINT clone_message_session_key_fkey,
    ADD CONSTRAINT clone_message_session_key_fkey FOREIGN KEY (session_key)
        REFERENCES clone_session(session_key) ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE clone_session_value
    DROP CONSTRAINT clone_session_value_session_key_fkey,
    ADD CONSTRAINT clone_session_value_session_key_fkey FOREIGN KEY (session_key)
        REFERENCES clone_session(session_key) ON DELETE CASCADE ON UPDATE CASCADE;
