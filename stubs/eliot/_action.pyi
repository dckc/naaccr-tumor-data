# Stubs for eliot._action (Python 3)
#
# NOTE: This dynamically typed stub was automatically generated by stubgen.

from ._errors import _error_extraction
from ._message import EXCEPTION_FIELD, Message, REASON_FIELD, TASK_UUID_FIELD, WrittenMessage
from ._util import safeunicode
from pyrsistent import PClass
from typing import Any, Callable, Optional, TypeVar, overload

Func = Callable[..., Any]
F = TypeVar('F', bound=TaskMethod)

ACTION_STATUS_FIELD: str
ACTION_TYPE_FIELD: str
STARTED_STATUS: str
SUCCEEDED_STATUS: str
FAILED_STATUS: str
VALID_STATUSES: Any

def current_action(): ...

class TaskLevel:
    def __init__(self, level: Any) -> None: ...
    def as_list(self): ...
    @property
    def level(self): ...
    def __lt__(self, other: Any): ...
    def __le__(self, other: Any): ...
    def __gt__(self, other: Any): ...
    def __ge__(self, other: Any): ...
    def __eq__(self, other: Any): ...
    def __ne__(self, other: Any): ...
    def __hash__(self): ...
    @classmethod
    def fromString(cls, string: Any): ...
    def toString(self): ...
    def next_sibling(self): ...
    def child(self): ...
    def parent(self): ...
    def is_sibling_of(self, task_level: Any): ...
    from_string: Any = ...
    to_string: Any = ...

class Action:
    def __init__(self, logger: Any, task_uuid: Any, task_level: Any, action_type: Any, serializers: Optional[Any] = ...) -> None: ...
    @property
    def task_uuid(self): ...
    def serialize_task_id(self): ...
    @classmethod
    def continue_task(cls, logger: Optional[Any] = ..., task_id: Any = ...): ...
    serializeTaskId: Any = ...
    continueTask: Any = ...
    def finish(self, exception: Optional[Any] = ...) -> None: ...
    def child(self, logger: Any, action_type: Any, serializers: Optional[Any] = ...): ...
    def run(self, f: Any, *args: Any, **kwargs: Any): ...
    def addSuccessFields(self, **fields: Any) -> None: ...
    add_success_fields: Any = ...
    def context(self) -> None: ...
    def __enter__(self): ...
    def __exit__(self, type: Any, exception: Any, traceback: Any) -> None: ...

class WrongTask(Exception):
    def __init__(self, action: Any, message: Any) -> None: ...

class WrongTaskLevel(Exception):
    def __init__(self, action: Any, message: Any) -> None: ...

class WrongActionType(Exception):
    def __init__(self, action: Any, message: Any) -> None: ...

class InvalidStatus(Exception):
    def __init__(self, action: Any, message: Any) -> None: ...

class DuplicateChild(Exception):
    def __init__(self, action: Any, message: Any) -> None: ...

class InvalidStartMessage(Exception):
    def __init__(self, message: Any, reason: Any) -> None: ...
    @classmethod
    def wrong_status(cls, message: Any): ...
    @classmethod
    def wrong_task_level(cls, message: Any): ...

class WrittenAction(PClass):
    start_message: Any = ...
    end_message: Any = ...
    task_level: Any = ...
    task_uuid: Any = ...
    @classmethod
    def from_messages(cls, start_message: Optional[Any] = ..., children: Any = ..., end_message: Optional[Any] = ...): ...
    @property
    def action_type(self): ...
    @property
    def status(self): ...
    @property
    def start_time(self): ...
    @property
    def end_time(self): ...
    @property
    def exception(self): ...
    @property
    def reason(self): ...
    @property
    def children(self): ...

def start_action(logger: Optional[Any] = ..., action_type: str = ..., _serializers: Optional[Any] = ..., **fields: Any): ...
def startTask(logger: Optional[Any] = ..., action_type: str = ..., _serializers: Optional[Any] = ..., **fields: Any): ...

class TooManyCalls(Exception): ...

def preserve_context(f: Any): ...

@overload
def log_call(wrapped_function: F) -> F: ...
@overload
def log_call(action_type: Optional[str] = ..., include_args: Optional[List[str]] = ..., include_result: Optional[bool] = false) -> Callable[[F], F]: ...
