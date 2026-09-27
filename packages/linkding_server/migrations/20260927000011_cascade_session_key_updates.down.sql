ALTER TABLE clone_message
    DROP CONSTRAINT clone_message_session_key_fkey,
    ADD CONSTRAINT clone_message_session_key_fkey FOREIGN KEY (session_key)
        REFERENCES clone_session(session_key) ON DELETE CASCADE;
ALTER TABLE clone_session_value
    DROP CONSTRAINT clone_session_value_session_key_fkey,
    ADD CONSTRAINT clone_session_value_session_key_fkey FOREIGN KEY (session_key)
        REFERENCES clone_session(session_key) ON DELETE CASCADE;
