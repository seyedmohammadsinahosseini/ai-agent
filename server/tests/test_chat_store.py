from app import chat_store


def test_streamed_execution_output_is_merged_into_assistant_turn():
    chat = chat_store.create_chat("Persistence test")
    try:
        message = chat_store.add_message(
            chat["id"], "assistant", "Running it",
            extra={
                "risk_level": "CONFIRM",
                "working_dir": "C:/workspace",
                "suggested_command": {"command": "tool", "explanation": "test"},
            },
        )
        assert chat_store.message_belongs_to_chat(message["id"], chat["id"])
        assert chat_store.message_command_matches(message["id"], chat["id"], "tool")
        assert not chat_store.message_command_matches(message["id"], chat["id"], "other-tool")

        assert chat_store.update_message_execution(
            message["id"], chat["id"], "streamed output", 0, was_stopped=False
        )
        saved = chat_store.get_chat(chat["id"])["messages"][0]
        assert saved["execution_output"] == "streamed output"
        assert saved["execution_exit_code"] == 0
        assert saved["execution_was_stopped"] is False
        assert saved["risk_level"] == "CONFIRM"
        assert saved["working_dir"] == "C:/workspace"
    finally:
        chat_store.delete_chat(chat["id"])
