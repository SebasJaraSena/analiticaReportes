"""
RQ Worker entry point.
Usage (in Docker): python worker_start.py
"""
import logging
import sys

from redis import Redis
from rq import Worker, Queue

from api.config import settings
from api.database import ControlSessionLocal, init_control_db
from api.jobs import cleanup_old_report_files

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
    stream=sys.stdout,
)
logger = logging.getLogger(__name__)


def main() -> None:
    logger.info("Inicializando base de datos de control...")
    init_control_db()

    with ControlSessionLocal() as db:
        cleanup_old_report_files(db)

    logger.info("Conectando a Redis: %s", settings.redis_url)
    conn = Redis.from_url(settings.redis_url)
    conn.ping()

    queues = [Queue("reportes", connection=conn)]
    worker = Worker(queues, connection=conn)

    logger.info("Worker listo. Escuchando cola 'reportes'...")
    worker.work(with_scheduler=False)


if __name__ == "__main__":
    main()
