from datetime import datetime
from typing import Any

from sqlalchemy import BigInteger, Boolean, DateTime, Integer, String, Text, func
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column
from sqlalchemy import SmallInteger

from api.scheduler import now_bogota


class Base(DeclarativeBase):
    pass


class Solicitud(Base):
    __tablename__ = "reportes_zajuna_solicitudes"

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True)
    reporte_codigo: Mapped[str] = mapped_column(String(100), nullable=False)
    reporte_nombre: Mapped[str] = mapped_column(String(255), nullable=False)
    usuario_id: Mapped[str | None] = mapped_column(String(255))
    usuario_email: Mapped[str | None] = mapped_column(String(255))
    filtros: Mapped[dict[str, Any] | None] = mapped_column(JSONB)
    estado: Mapped[str] = mapped_column(String(30), nullable=False, default="PENDIENTE")
    formato: Mapped[str] = mapped_column(String(20), nullable=False, default="xlsx")
    archivo_nombre: Mapped[str | None] = mapped_column(Text)
    archivo_ruta: Mapped[str | None] = mapped_column(Text)
    archivo_tamano: Mapped[int | None] = mapped_column(BigInteger)
    mensaje_error: Mapped[str | None] = mapped_column(Text)
    filas_procesadas: Mapped[int] = mapped_column(BigInteger, nullable=False, default=0)
    partes_generadas: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    fecha_ultimo_progreso: Mapped[datetime | None] = mapped_column(DateTime(timezone=False))
    mensaje_progreso: Mapped[str | None] = mapped_column(Text)
    fecha_solicitud: Mapped[datetime] = mapped_column(
        DateTime(timezone=False), nullable=False, default=now_bogota, server_default=func.now()
    )
    fecha_inicio: Mapped[datetime | None] = mapped_column(DateTime(timezone=False))
    fecha_fin: Mapped[datetime | None] = mapped_column(DateTime(timezone=False))
    token_descarga: Mapped[str | None] = mapped_column(String(64))

    def to_dict(self) -> dict:
        return {
            "id": self.id,
            "reporte_codigo": self.reporte_codigo,
            "reporte_nombre": self.reporte_nombre,
            "usuario_email": self.usuario_email,
            "filtros": self.filtros,
            "estado": self.estado,
            "formato": self.formato,
            "archivo_nombre": self.archivo_nombre,
            "archivo_tamano": self.archivo_tamano,
            "mensaje_error": self.mensaje_error,
            "filas_procesadas": self.filas_procesadas,
            "partes_generadas": self.partes_generadas,
            "fecha_ultimo_progreso": self.fecha_ultimo_progreso.isoformat() if self.fecha_ultimo_progreso else None,
            "mensaje_progreso": self.mensaje_progreso,
            "fecha_solicitud": self.fecha_solicitud.isoformat() if self.fecha_solicitud else None,
            "fecha_inicio": self.fecha_inicio.isoformat() if self.fecha_inicio else None,
            "fecha_fin": self.fecha_fin.isoformat() if self.fecha_fin else None,
        }


class ReporteProgramado(Base):
    __tablename__ = "reportes_programados"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    usuario_email: Mapped[str] = mapped_column(String(255), nullable=False, index=True)
    nombre: Mapped[str | None] = mapped_column(String(255), nullable=True)
    reporte_codigo: Mapped[str] = mapped_column(String(100), nullable=False)
    reporte_nombre: Mapped[str] = mapped_column(String(255), nullable=False)
    filtros: Mapped[dict[str, Any] | None] = mapped_column(JSONB)
    formato: Mapped[str] = mapped_column(String(20), nullable=False, default="xlsx")
    frecuencia: Mapped[str] = mapped_column(String(20), nullable=False)  # diario/semanal/mensual
    dia_semana: Mapped[int | None] = mapped_column(SmallInteger, nullable=True)  # 0=lunes…6=domingo
    dia_mes: Mapped[int | None] = mapped_column(SmallInteger, nullable=True)  # 1–31
    hora: Mapped[int] = mapped_column(SmallInteger, nullable=False, default=8)
    minuto: Mapped[int] = mapped_column(SmallInteger, nullable=False, default=0)
    activo: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
    ultima_ejecucion: Mapped[datetime | None] = mapped_column(DateTime(timezone=False), nullable=True)
    proxima_ejecucion: Mapped[datetime] = mapped_column(DateTime(timezone=False), nullable=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=False), nullable=False, default=now_bogota
    )


class ReporteUser(Base):
    __tablename__ = "reportes_users"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    email: Mapped[str] = mapped_column(String(255), unique=True, nullable=False, index=True)
    username: Mapped[str] = mapped_column(String(100), unique=True, nullable=False, index=True)
    hashed_password: Mapped[str] = mapped_column(String(255), nullable=False)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)
    is_admin: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=False), nullable=False, default=now_bogota
    )
