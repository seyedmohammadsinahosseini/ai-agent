from pydantic import BaseModel, Field
from typing import Literal, Optional

AgentMode = Literal["plan", "build"]
Provider = Literal["openai", "anthropic", "gemini"]


class ChatMessage(BaseModel):
    role: Literal["user", "assistant", "system"]
    content: str


class AttachmentRef(BaseModel):
    id: str
    filename: str
    kind: Literal["context", "workspace"]  # context = just discussed with AI, workspace = copied into the working folder


class ChatRequest(BaseModel):
    messages: list[ChatMessage] = Field(..., min_length=1)
    provider: Provider = "openai"
    model: Optional[str] = None
    mode: AgentMode = "plan"
    working_dir: Optional[str] = None
    attachment_ids: list[str] = Field(default_factory=list)


class SuggestedCommand(BaseModel):
    command: str
    explanation: str  # plain-language explanation for the end user


class ChatResponse(BaseModel):
    reply_text: str
    mode: AgentMode
    suggested_command: Optional[SuggestedCommand] = None
    risk_level: Optional[str] = None
    risk_human_reason: Optional[str] = None
    auto_executed: bool = False
    execution_output: Optional[str] = None
    execution_exit_code: Optional[int] = None
    blocked_reason: Optional[str] = None


class ExecuteRequest(BaseModel):
    command: str
    working_dir: Optional[str] = None
    user_confirmed: bool = False
    confirmation_phrase: Optional[str] = None  # required for DANGEROUS commands


class ExecuteResponse(BaseModel):
    executed: bool
    risk_level: str
    risk_human_reason: str
    output: Optional[str] = None
    exit_code: Optional[int] = None
    message: Optional[str] = None


class SaveApiKeyRequest(BaseModel):
    provider: Provider
    api_key: str


class ModelInfo(BaseModel):
    id: str
    label: str
    provider: Provider
    description: str = ""


class ProviderStatus(BaseModel):
    configured_providers: list[Provider]
    available_models: list[ModelInfo]


class FolderEntry(BaseModel):
    name: str
    path: str
    is_dir: bool


class BrowseFolderResponse(BaseModel):
    current_path: str
    parent_path: Optional[str]
    entries: list[FolderEntry]


class SelectWorkingDirRequest(BaseModel):
    path: str


class SelectWorkingDirResponse(BaseModel):
    path: str
    ok: bool
    message: Optional[str] = None


class UploadResponse(BaseModel):
    id: str
    filename: str
    size_bytes: int
    kind: Literal["context", "workspace"]
    saved_path: Optional[str] = None
