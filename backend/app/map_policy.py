"""Only deployer-controlled, keyless raster basemap settings are sent to the app."""
import os
from urllib.parse import urlsplit


def map_config():
    value=os.getenv('MEDAI_TILE_URL','').strip()
    credit=os.getenv('MEDAI_TILE_ATTRIBUTION','').strip()
    try:
        uri=urlsplit(value)
        if (uri.scheme=='https' and uri.hostname and not (uri.query or uri.username or uri.password or uri.fragment)
            and all(k in uri.path for k in ('{z}','{x}','{y}')) and 2<len(credit)<=180):
            return {'tiles':value,'attribution':credit}
    except ValueError:
        pass
    return {'tiles':None,'attribution':None}
