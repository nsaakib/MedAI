from .manage import load_env
from .main import create_app

load_env()
app = create_app()
