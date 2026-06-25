import os
from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    # Control DB (Superset's PostgreSQL — stores report requests)
    control_db_host: str = os.getenv("DATABASE_HOST", "db")
    control_db_port: int = int(os.getenv("DATABASE_PORT", "5432"))
    control_db_name: str = os.getenv("DATABASE_DB", "superset")
    control_db_user: str = os.getenv("DATABASE_USER", "superset")
    control_db_password: str = os.getenv("DATABASE_PASSWORD", "superset")

    # Moodle/Zajuna DB (read-only for queries)
    moodle_db_host: str = os.getenv("MOODLE_DB_HOST", "")
    moodle_db_port: int = int(os.getenv("MOODLE_DB_PORT", "5432"))
    moodle_db_name: str = os.getenv("MOODLE_DB_NAME", "moodle")
    moodle_db_user: str = os.getenv("MOODLE_DB_USER", "")
    moodle_db_password: str = os.getenv("MOODLE_DB_PASSWORD", "")

    # Redis
    redis_host: str = os.getenv("REDIS_HOST", "redis")
    redis_port: int = int(os.getenv("REDIS_PORT", "6379"))

    # File storage
    output_dir: str = os.getenv("REPORTES_OUTPUT_DIR", "/app/reportes_generados")
    max_files_per_user: int = int(os.getenv("REPORTES_MAX_FILES_PER_USER", "100"))
    # Per-format split thresholds. XLSX must stay under Excel's hard limit of
    # 1,048,576 rows/sheet — 900k leaves margin for the metadata header rows.
    # CSV has no such limit, so it can hold many more rows per part file.
    xlsx_rows_per_file: int = int(os.getenv("REPORTES_XLSX_ROWS_PER_FILE", "900000"))
    csv_rows_per_file: int = int(os.getenv("REPORTES_CSV_ROWS_PER_FILE", "2000000"))
    # Above this estimated row count, force CSV output even if XLSX was
    # requested: XLSX is ~4x larger and ~10-20x slower to write, and Excel
    # struggles to open 200MB+ files. 0 disables the auto-switch.
    auto_csv_row_threshold: int = int(os.getenv("REPORTES_AUTO_CSV_ROW_THRESHOLD", "500000"))

    # Security: own JWT secret — set REPORTES_SECRET_KEY in docker/.env-local
    secret_key: str = os.getenv("REPORTES_SECRET_KEY", "change-me-in-production")

    # CORS origins (comma-separated)
    cors_origins: str = os.getenv("REPORTES_CORS_ORIGINS", "http://localhost:8088,http://localhost:8089")

    @property
    def control_db_url(self) -> str:
        return (
            f"postgresql+psycopg2://{self.control_db_user}:{self.control_db_password}"
            f"@{self.control_db_host}:{self.control_db_port}/{self.control_db_name}"
        )

    @property
    def moodle_db_dsn(self) -> str:
        return (
            f"host={self.moodle_db_host} port={self.moodle_db_port} "
            f"dbname={self.moodle_db_name} "
            f"user={self.moodle_db_user} password={self.moodle_db_password} "
            f"options='-c statement_timeout=600000'"
        )

    @property
    def redis_url(self) -> str:
        return f"redis://{self.redis_host}:{self.redis_port}/2"

    @property
    def cors_origins_list(self) -> list[str]:
        return [o.strip() for o in self.cors_origins.split(",") if o.strip()]


settings = Settings()
