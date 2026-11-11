import os
import sys

MIN_SYNC_INTERVAL_SECONDS = 5
DEFAULT_SYNC_INTERVAL_SECONDS = 300


def application_dir():
    """Folder that holds the program and the editable .env file."""
    if getattr(sys, "frozen", False):
        return os.path.dirname(sys.executable)
    return os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def env_file_path():
    """
    Prefer .env beside the exe (or project root when running from source).
    A Windows service's working directory is often System32, so cwd is only a fallback.
    """
    preferred = os.path.join(application_dir(), ".env")
    if os.path.isfile(preferred):
        return preferred
    cwd_env = os.path.join(os.getcwd(), ".env")
    if os.path.isfile(cwd_env):
        return cwd_env
    return preferred


def parse_sync_interval(raw, fallback=DEFAULT_SYNC_INTERVAL_SECONDS):
    try:
        seconds = int(str(raw).strip())
    except (TypeError, ValueError):
        return fallback
    if seconds < MIN_SYNC_INTERVAL_SECONDS:
        return MIN_SYNC_INTERVAL_SECONDS
    return seconds


def load_config():
    """
    Re-read .env on every call (override=True) so edits like SYNC_INTERVAL_SECONDS
    apply to the running service. No reinstall or restart is required.
    """
    from dotenv import load_dotenv

    path = env_file_path()
    if os.path.isfile(path):
        load_dotenv(path, override=True, encoding="utf-8-sig")
    else:
        load_dotenv(override=True, encoding="utf-8-sig")

    supabase_url = os.environ.get("SUPABASE_URL")
    supabase_key = os.environ.get("SUPABASE_KEY")
    if not supabase_url or not supabase_key:
        raise RuntimeError(
            "Missing SUPABASE_URL / SUPABASE_KEY. Copy .env next to the exe "
            f"(looked in: {application_dir()})"
        )

    return {
        "tally_port": int(os.environ.get("TALLY_PORT", 9000)),
        "supabase_url": supabase_url,
        "supabase_key": supabase_key,
        "sync_interval_seconds": parse_sync_interval(os.environ.get("SYNC_INTERVAL_SECONDS")),
        "target_company_name": os.environ.get("TARGET_COMPANY_NAME", "").strip(),
        "env_path": path,
    }


if __name__ == "__main__":
    config = load_config()
