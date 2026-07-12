"""Shared filesystem paths for nia-todo runtime data."""

import os
from pathlib import Path

APP_DIR = Path(__file__).resolve().parent
DEFAULT_DATA_DIR = APP_DIR / "data"


def _path_from_env(name: str, default: Path | str) -> Path:
    value = os.getenv(name)
    return Path(value).expanduser() if value else Path(default)


DATA_DIR = _path_from_env("NIA_TODO_DATA_DIR", DEFAULT_DATA_DIR)
DB_NAME = os.getenv("NIA_TODO_DB", "nia-todo.db")
DB_PATH = Path(DB_NAME).expanduser()
if not DB_PATH.is_absolute():
    DB_PATH = DATA_DIR / DB_NAME

AVATAR_DIR = _path_from_env("NIA_TODO_AVATAR_DIR", DATA_DIR / "avatars")
VAPID_KEYS_PATH = _path_from_env("NIA_TODO_VAPID_KEYS", DATA_DIR / "vapid_keys.json")
BACKUP_DIR = _path_from_env("NIA_TODO_BACKUP_DIR", DATA_DIR / "backups")
# 管理员可手动放置额外的安装包到此目录（如不同架构的版本），
# 服务器会将其合并到 /downloads/app-downloads.json 中供用户下载。
CUSTOM_DOWNLOADS_DIR = _path_from_env("NIA_TODO_CUSTOM_DOWNLOADS_DIR", DATA_DIR / "custom-downloads")

for directory in (DATA_DIR, DB_PATH.parent, AVATAR_DIR, VAPID_KEYS_PATH.parent, BACKUP_DIR, CUSTOM_DOWNLOADS_DIR):
    directory.mkdir(parents=True, exist_ok=True)
