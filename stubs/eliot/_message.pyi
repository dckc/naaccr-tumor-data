# Stubs for eliot._message (Python 3)
#
# NOTE: This dynamically typed stub was automatically generated by stubgen.

from ._action import TaskLevel, current_action
from pyrsistent import PClass
from typing import Any, Optional

MESSAGE_TYPE_FIELD: str
TASK_UUID_FIELD: str
TASK_LEVEL_FIELD: str
TIMESTAMP_FIELD: str
EXCEPTION_FIELD: str
REASON_FIELD: str

class Message:
    @classmethod
    def new(_class: Any, _serializer: Optional[Any] = ..., **fields: Any): ...
    @classmethod
    def log(_class: Any, **fields: Any) -> None: ...
    def __init__(self, contents: Any, serializer: Optional[Any] = ...) -> None: ...
    def bind(self, **fields: Any): ...
    def contents(self): ...
    def write(self, logger: Optional[Any] = ..., action: Optional[Any] = ...) -> None: ...

class WrittenMessage(PClass):
    @property
    def timestamp(self): ...
    @property
    def task_uuid(self): ...
    @property
    def task_level(self): ...
    @property
    def contents(self): ...
    @classmethod
    def from_dict(cls, logged_dictionary: Any): ...
    def as_dict(self): ...
