import logging
from contextlib import contextmanager
from typing import Generator

import psycopg2
import psycopg2.extras
from sqlalchemy import create_engine, text
from sqlalchemy.orm import sessionmaker, Session

from api.config import settings

logger = logging.getLogger(__name__)

# ── Control DB (SQLAlchemy) ──────────────────────────────────────────────────

_control_engine = create_engine(
    settings.control_db_url,
    pool_size=5,
    max_overflow=10,
    pool_pre_ping=True,
)

ControlSessionLocal = sessionmaker(bind=_control_engine, autocommit=False, autoflush=False)


def get_control_session() -> Generator[Session, None, None]:
    session = ControlSessionLocal()
    try:
        yield session
    finally:
        session.close()


def init_control_db() -> None:
    """Create reportes_zajuna_solicitudes table and indexes if not present."""
    ddl = """
    CREATE TABLE IF NOT EXISTS reportes_zajuna_solicitudes (
        id             BIGSERIAL PRIMARY KEY,
        reporte_codigo VARCHAR(100)  NOT NULL,
        reporte_nombre VARCHAR(255)  NOT NULL,
        usuario_id     VARCHAR(255),
        usuario_email  VARCHAR(255),
        filtros        JSONB,
        estado         VARCHAR(30)   NOT NULL DEFAULT 'PENDIENTE',
        formato        VARCHAR(20)   NOT NULL DEFAULT 'xlsx',
        archivo_nombre TEXT,
        archivo_ruta   TEXT,
        archivo_tamano BIGINT,
        mensaje_error  TEXT,
        filas_procesadas BIGINT NOT NULL DEFAULT 0,
        partes_generadas INTEGER NOT NULL DEFAULT 0,
        fecha_ultimo_progreso TIMESTAMP,
        mensaje_progreso TEXT,
        fecha_solicitud  TIMESTAMP NOT NULL DEFAULT NOW(),
        fecha_inicio     TIMESTAMP,
        fecha_fin        TIMESTAMP,
        token_descarga   VARCHAR(64)
    );

    CREATE INDEX IF NOT EXISTS idx_rzs_estado
        ON reportes_zajuna_solicitudes (estado);
    CREATE INDEX IF NOT EXISTS idx_rzs_usuario_email
        ON reportes_zajuna_solicitudes (usuario_email);
    CREATE INDEX IF NOT EXISTS idx_rzs_fecha_solicitud
        ON reportes_zajuna_solicitudes (fecha_solicitud DESC);
    CREATE INDEX IF NOT EXISTS idx_rzs_reporte_codigo
        ON reportes_zajuna_solicitudes (reporte_codigo);

    CREATE TABLE IF NOT EXISTS reportes_users (
        id               SERIAL PRIMARY KEY,
        email            VARCHAR(255) NOT NULL UNIQUE,
        username         VARCHAR(100) NOT NULL UNIQUE,
        hashed_password  VARCHAR(255) NOT NULL,
        is_active        BOOLEAN NOT NULL DEFAULT TRUE,
        created_at       TIMESTAMP NOT NULL DEFAULT NOW()
    );

    CREATE INDEX IF NOT EXISTS idx_ru_email    ON reportes_users (email);
    CREATE INDEX IF NOT EXISTS idx_ru_username ON reportes_users (username);

    CREATE TABLE IF NOT EXISTS reportes_programados (
        id               SERIAL PRIMARY KEY,
        usuario_email    VARCHAR(255) NOT NULL,
        nombre           VARCHAR(255),
        reporte_codigo   VARCHAR(100) NOT NULL,
        reporte_nombre   VARCHAR(255) NOT NULL,
        filtros          JSONB,
        formato          VARCHAR(20)  NOT NULL DEFAULT 'xlsx',
        frecuencia       VARCHAR(20)  NOT NULL,
        dia_semana       SMALLINT,
        dia_mes          SMALLINT,
        hora             SMALLINT     NOT NULL DEFAULT 8,
        minuto           SMALLINT     NOT NULL DEFAULT 0,
        activo           BOOLEAN      NOT NULL DEFAULT TRUE,
        ultima_ejecucion TIMESTAMP,
        proxima_ejecucion TIMESTAMP   NOT NULL,
        created_at       TIMESTAMP    NOT NULL DEFAULT NOW()
    );

    CREATE INDEX IF NOT EXISTS idx_rp_usuario_email ON reportes_programados (usuario_email);
    CREATE INDEX IF NOT EXISTS idx_rp_activo_proxima ON reportes_programados (activo, proxima_ejecucion);
    """
    migrate_ddl = """
    ALTER TABLE reportes_users
        ADD COLUMN IF NOT EXISTS is_admin BOOLEAN NOT NULL DEFAULT FALSE;
    ALTER TABLE reportes_zajuna_solicitudes
        ADD COLUMN IF NOT EXISTS filas_procesadas BIGINT NOT NULL DEFAULT 0,
        ADD COLUMN IF NOT EXISTS partes_generadas INTEGER NOT NULL DEFAULT 0,
        ADD COLUMN IF NOT EXISTS fecha_ultimo_progreso TIMESTAMP,
        ADD COLUMN IF NOT EXISTS mensaje_progreso TEXT;
    """
    with _control_engine.connect() as conn:
        # Advisory lock prevents deadlock when multiple workers start simultaneously
        conn.execute(text("SELECT pg_advisory_xact_lock(7261836450)"))
        conn.execute(text(ddl))
        conn.execute(text(migrate_ddl))
        conn.commit()
    logger.info("Control DB inicializado.")


# ── Moodle DB (psycopg2 server-side cursor for streaming) ───────────────────

@contextmanager
def get_moodle_conn():
    """psycopg2 connection to Moodle DB (read-only, server-side cursor support)."""
    if not settings.moodle_db_host:
        raise RuntimeError(
            "MOODLE_DB_HOST no configurado. "
            "Agrega las variables MOODLE_DB_* al archivo docker/.env-local."
        )
    conn = psycopg2.connect(
        settings.moodle_db_dsn,
        cursor_factory=psycopg2.extras.RealDictCursor,
    )
    conn.set_session(readonly=True)
    try:
        yield conn
    finally:
        conn.close()
